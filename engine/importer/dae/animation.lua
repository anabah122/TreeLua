-- dae/animation.lua — <library_animations> -> clips/tracks
--
--   animation.build(root, nodes) -> { clip, ... }
--   animation.sample(clip, time, nodes, loop)
--
-- Collada usually animates a node's whole <matrix> rather than separate TRS
-- channels, so matrix tracks are decomposed into translation/rotation/scale on
-- load. That keeps playback identical to the glTF path and lets rotations be
-- slerped instead of blended element-wise (which would skew them).

local xml     = require "engine.importer.dae.xml"
local sources = require "engine.importer.dae.sources"
local common  = require "engine.importer.common"

local animation = {}

local PATH_SIZE = { translation = 3, rotation = 4, scale = 3 }

-- ── target resolution ────────────────────────────────────────────────────────
-- targets look like "Bone_001/matrix" or "Cube/location.X"
local function resolve_target(target, nodes)
    if not target then return nil, nil end
    local id, rest = target:match("^([^/]+)/?(.*)$")
    if not id then return nil, nil end

    local idx = nodes.by_id[id] or nodes.by_sid[id] or nodes.by_name[id]
    if not idx then
        -- some exporters append the sid path; retry on the bare head
        local head = id:match("^([^%.]+)")
        idx = head and (nodes.by_id[head] or nodes.by_sid[head] or nodes.by_name[head])
    end
    return idx, rest
end

-- which TRS channel a collada sid maps to
local function channel_of(sid)
    if not sid or sid == "" then return nil end
    local base = sid:match("^([^%.%(]+)")
    if base == "matrix" or base == "transform" then return "matrix" end
    if base == "location" or base == "translate" then return "translation" end
    if base == "scale" then return "scale" end
    if base and base:match("^rotate") then return "rotate_axis" end
    return nil
end

-- ── building ─────────────────────────────────────────────────────────────────
local function build_channel(root, chan, nodes, tracks)
    local sampler = xml.byid(root, chan.attr.source)
    if not sampler then return end

    local inputs = sources.inputs(sampler)
    local time_src   = inputs.INPUT  and sources.read(root, inputs.INPUT.source)
    local value_src  = inputs.OUTPUT and sources.read(root, inputs.OUTPUT.source)
    if not (time_src and value_src) then return end

    local interp_src = inputs.INTERPOLATION and sources.read(root, inputs.INTERPOLATION.source)
    local interp = "LINEAR"
    if interp_src and interp_src.data[1] == "STEP" then interp = "STEP" end

    local node_idx, sid = resolve_target(chan.attr.target, nodes)
    if not node_idx then return end

    local kind = channel_of(sid)
    local times = time_src.data

    if kind == "matrix" or value_src.stride == 16 then
        -- one 4x4 per key: decompose into three parallel tracks
        local tpos, trot, tscl = {}, {}, {}
        for k = 1, #times do
            local m = sources.matrix(value_src.data, (k-1) * 16)
            local t, r, s = common.decompose(m)
            tpos[(k-1)*3+1], tpos[(k-1)*3+2], tpos[(k-1)*3+3] = t[1], t[2], t[3]
            trot[(k-1)*4+1], trot[(k-1)*4+2], trot[(k-1)*4+3], trot[(k-1)*4+4] = r[1], r[2], r[3], r[4]
            tscl[(k-1)*3+1], tscl[(k-1)*3+2], tscl[(k-1)*3+3] = s[1], s[2], s[3]
        end
        tracks[#tracks+1] = { node = node_idx, path = "translation", times = times, values = tpos, interp = interp }
        tracks[#tracks+1] = { node = node_idx, path = "rotation",    times = times, values = trot, interp = interp }
        tracks[#tracks+1] = { node = node_idx, path = "scale",       times = times, values = tscl, interp = interp }

    elseif kind == "translation" and value_src.stride >= 3 then
        tracks[#tracks+1] = { node = node_idx, path = "translation",
                              times = times, values = value_src.data, interp = interp }

    elseif kind == "scale" and value_src.stride >= 3 then
        tracks[#tracks+1] = { node = node_idx, path = "scale",
                              times = times, values = value_src.data, interp = interp }
    end
    -- single-component channels (location.X, rotateZ.ANGLE) are skipped:
    -- they need the node's other channels to reconstruct a full transform,
    -- and every exporter worth supporting writes full matrices.
end

function animation.build(root, nodes)
    local lib = xml.deep(root, "library_animations")
    if not lib then return {} end

    local clips = {}

    -- <animation> elements may nest; each leaf holds channels
    local function collect(anim_el, name)
        local tracks = {}
        for _, chan in ipairs(xml.deepall(anim_el, "channel")) do
            build_channel(root, chan, nodes, tracks)
        end
        if #tracks > 0 then
            local duration = 0
            for _, t in ipairs(tracks) do
                local last = t.times[#t.times]
                if last and last > duration then duration = last end
            end
            clips[#clips+1] = common.clip_rate{
                name = name or anim_el.attr.name or anim_el.attr.id or ("clip_" .. (#clips+1)),
                tracks = tracks,
                duration = duration,
            }
        end
    end

    -- <animation_clip> groups animations into named clips when present
    local clip_lib = xml.deep(root, "library_animation_clips")
    if clip_lib then
        for _, clip_el in ipairs(xml.findall(clip_lib, "animation_clip")) do
            local tracks = {}
            for _, inst in ipairs(xml.findall(clip_el, "instance_animation")) do
                local anim_el = xml.byid(root, inst.attr.url)
                if anim_el then
                    for _, chan in ipairs(xml.deepall(anim_el, "channel")) do
                        build_channel(root, chan, nodes, tracks)
                    end
                end
            end
            if #tracks > 0 then
                local start_t = tonumber(clip_el.attr.start) or 0
                local end_t   = tonumber(clip_el.attr["end"]) or 0
                clips[#clips+1] = common.clip_rate{
                    name     = clip_el.attr.name or clip_el.attr.id or ("clip_" .. (#clips+1)),
                    tracks   = tracks,
                    duration = end_t > start_t and (end_t - start_t) or 0,
                    startTime = start_t,
                }
            end
        end
        if #clips > 0 then return clips end
    end

    -- no clip library: treat the whole animation library as one clip
    collect(lib, "default")
    return clips
end

-- ── evaluation ───────────────────────────────────────────────────────────────
-- Shared with the glTF path in spirit; DAE has no CUBICSPLINE so this is the
-- LINEAR/STEP subset plus slerp for rotations.
function animation.evaluate(track, time)
    local times, values = track.times, track.values
    local n = PATH_SIZE[track.path]
    if not n or #times == 0 then return nil end

    local i = common.find_key(times, time)
    if not i then return nil end

    if i >= #times or track.interp == "STEP" then
        local o = (i-1) * n
        local out = {}
        for k = 1, n do out[k] = values[o+k] end
        return out
    end

    local t0, t1 = times[i], times[i+1]
    local span = t1 - t0
    local f = span > 0 and ((time - t0) / span) or 0

    local o0, o1 = (i-1) * n, i * n

    if track.path == "rotation" then
        local x,y,z,w = common.slerp(
            values[o0+1], values[o0+2], values[o0+3], values[o0+4],
            values[o1+1], values[o1+2], values[o1+3], values[o1+4], f)
        return { x, y, z, w }
    end

    local out = {}
    for k = 1, n do out[k] = common.lerp(values[o0+k], values[o1+k], f) end
    return out
end

function animation.sample(clip, time, nodes, loop)
    if loop ~= false and clip.duration > 0 then
        time = (time % clip.duration) + (clip.startTime or 0)
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

    for idx in pairs(touched) do
        local node = nodes[idx]
        node.localMatrix = common.compose(
            node.translation or {0,0,0},
            node.rotation    or {0,0,0,1},
            node.scale       or {1,1,1})
    end

    return nodes
end

function animation.find(clips, name)
    for _, c in ipairs(clips) do
        if c.name == name then return c end
    end
    return nil
end

return animation
