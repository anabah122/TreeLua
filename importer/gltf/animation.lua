-- gltf/animation.lua — animation clips, keyframe tracks, sampling
--
-- animation.build(j, buffers) -> { [i] = clip }
--   clip = { name, duration, tracks = { {node, path, times, values, interp} } }
--
-- animation.sample(clip, time, nodes)  -- writes TRS into nodes, marks dirty
--
-- path is one of: "translation" | "rotation" | "scale" | "weights"
-- interp is one of: "LINEAR" | "STEP" | "CUBICSPLINE"

local binary   = require "importer.gltf.binary"
local common   = require "importer.common"
local skeleton = require "importer.gltf.skeleton"

local animation = {}

local PATH_SIZE = { translation = 3, rotation = 4, scale = 3 }

-- ── building ─────────────────────────────────────────────────────────────────
function animation.build(j, buffers)
    local clips = {}

    for ai, anim in ipairs(j.animations or {}) do
        local clip = {
            name     = anim.name or ("clip_"..ai),
            tracks   = {},
            duration = 0,
        }

        for _, chan in ipairs(anim.channels or {}) do
            local target = chan.target
            if target and target.node ~= nil then
                local sampler = (anim.samplers or {})[chan.sampler + 1]
                if sampler then
                    local times  = binary.accessor_values(j, buffers, sampler.input)
                    local values = binary.accessor_values(j, buffers, sampler.output)

                    local track = {
                        node   = target.node + 1,   -- 1-based
                        path   = target.path,
                        times  = times,
                        values = values,
                        interp = sampler.interpolation or "LINEAR",
                    }
                    clip.tracks[#clip.tracks+1] = track

                    local last = times[#times]
                    if last and last > clip.duration then clip.duration = last end
                end
            end
        end

        clips[#clips+1] = common.clip_rate(clip)
    end

    return clips
end

-- ── interpolation helpers ────────────────────────────────────────────────────
-- lerp / slerp / keyframe search live in importer.common, shared with DAE
local lerp     = common.lerp
local slerp    = common.slerp
local find_key = common.find_key

-- Evaluate one track at `time`, returning n components.
function animation.evaluate(track, time)
    local times  = track.times
    local values = track.values
    local n = PATH_SIZE[track.path]
    if not n or #times == 0 then return nil end

    local i = find_key(times, time)
    if not i then return nil end

    local cubic = (track.interp == "CUBICSPLINE")
    -- cubic packs (inTangent, value, outTangent) per key, so stride is 3n
    local stride = cubic and (n * 3) or n
    local voff   = cubic and n or 0   -- value sits in the middle

    -- clamped at either end, or STEP: return the key as-is
    if i >= #times or track.interp == "STEP" then
        local o = (i-1) * stride + voff
        local out = {}
        for k = 1, n do out[k] = values[o+k] end
        return out
    end

    local t0, t1 = times[i], times[i+1]
    local span = t1 - t0
    local f = span > 0 and ((time - t0) / span) or 0

    local o0 = (i-1) * stride + voff
    local o1 = i     * stride + voff

    if cubic then
        -- Hermite basis over the packed tangents
        local f2, f3 = f*f, f*f*f
        local h00 =  2*f3 - 3*f2 + 1
        local h10 =      f3 - 2*f2 + f
        local h01 = -2*f3 + 3*f2
        local h11 =      f3 -   f2

        local out = {}
        for k = 1, n do
            local p0 = values[o0 + k]
            local p1 = values[o1 + k]
            -- outTangent of key i, inTangent of key i+1
            local m0 = values[(i-1)*stride + n*2 + k] * span
            local m1 = values[ i   *stride           + k] * span
            out[k] = h00*p0 + h10*m0 + h01*p1 + h11*m1
        end
        if track.path == "rotation" then
            local x,y,z,w = out[1], out[2], out[3], out[4]
            local len = math.sqrt(x*x + y*y + z*z + w*w)
            if len > 0 then out[1],out[2],out[3],out[4] = x/len, y/len, z/len, w/len end
        end
        return out
    end

    if track.path == "rotation" then
        local x,y,z,w = slerp(
            values[o0+1], values[o0+2], values[o0+3], values[o0+4],
            values[o1+1], values[o1+2], values[o1+3], values[o1+4], f)
        return { x, y, z, w }
    end

    local out = {}
    for k = 1, n do out[k] = lerp(values[o0+k], values[o1+k], f) end
    return out
end

-- ── playback ─────────────────────────────────────────────────────────────────
-- Applies every track of `clip` at `time` onto `nodes`, then rebuilds the
-- affected local matrices. Caller runs skeleton.update_world() afterwards.
function animation.sample(clip, time, nodes, loop)
    if loop ~= false and clip.duration > 0 then
        time = time % clip.duration
    end

    local touched = {}

    for _, track in ipairs(clip.tracks) do
        local node = nodes[track.node]
        if node and PATH_SIZE[track.path] then
            local v = animation.evaluate(track, time)
            if v then
                if track.path == "translation" then
                    node.translation = v
                elseif track.path == "rotation" then
                    node.rotation = v
                elseif track.path == "scale" then
                    node.scale = v
                end
                touched[track.node] = true
            end
        end
    end

    -- an animated node's baked matrix is stale; rebuild from its TRS
    for idx in pairs(touched) do
        local node = nodes[idx]
        node.localMatrix = skeleton.compose(node.translation, node.rotation, node.scale)
        node.hasMatrix = false
    end

    return nodes
end

-- find a clip by name
function animation.find(clips, name)
    for _, c in ipairs(clips) do
        if c.name == name then return c end
    end
    return nil
end

return animation
