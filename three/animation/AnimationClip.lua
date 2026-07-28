-- three/animation/AnimationClip.lua — one named animation
--
-- A thin, typed face over the importer's clip record:
--
--   { name, duration, tracks = { {node, path, times, values, interp} }, fps }
--
-- The clip keeps a reference to the module that can SAMPLE it, because glTF
-- and Collada animate different things -- glTF writes TRS channels per node,
-- Collada bakes whole matrices -- and each importer ships the sampler that
-- understands its own tracks. The mixer therefore never branches on format.

local AnimationClip = {}
AnimationClip.__index = AnimationClip

function AnimationClip:new(name, duration, tracks)
    return setmetatable({
        type     = "AnimationClip",
        name     = name or "",
        duration = duration or 0,
        tracks   = tracks or {},
        -- filled by fromImporter
        _sampler = nil,
        _nodes   = nil,
        _raw     = nil,
    }, AnimationClip)
end

function AnimationClip:isAnimationClip()
    return true
end

-- Wrap an importer clip. `sampler` is importer.gltf.animation or
-- importer.dae.animation; `nodes` is the flat node list its sample() writes to.
function AnimationClip:fromImporter(clip, sampler, nodes)
    local c = AnimationClip:new(clip.name, clip.duration, clip.tracks)
    c._sampler = sampler
    c._nodes   = nodes
    c._raw     = clip
    c.fps      = clip.fps
    c.frames   = clip.frames
    return c
end

-- Write this clip's pose at `time` into the node list. `loop` false clamps at
-- the ends instead of wrapping.
function AnimationClip:sample(time, loop)
    if not self._sampler then return self end
    self._sampler.sample(self._raw, time, self._nodes, loop)
    return self
end

local PATH_SIZE = { translation = 3, rotation = 4, scale = 3 }

-- Wrap `time` the way the samplers do, so a blended clip and a directly
-- sampled one agree on where in the clip they are.
function AnimationClip:_wrapTime(time, loop)
    if loop ~= false and self.duration > 0 then
        return (time % self.duration) + (self._raw and self._raw.startTime or 0)
    end
    return time
end

-- Evaluate every track at `time` and hand the values to `accumulator` scaled by
-- `weight`, instead of writing them into the nodes.
--
-- This is what makes blending possible without touching the importers: both
-- already expose evaluate(track, time), which returns values, and both split a
-- clip into per-node TRS tracks -- Collada's baked matrices are decomposed on
-- load. Only their `sample` writes, and the mixer calls this instead.
function AnimationClip:accumulate(accumulator, time, loop, weight)
    if not self._sampler or not self._sampler.evaluate then return self end

    time = self:_wrapTime(time, loop)

    for _, track in ipairs(self.tracks) do
        if PATH_SIZE[track.path] then
            local v = self._sampler.evaluate(track, time)
            if v then
                if track.path == "translation" then
                    accumulator:addTranslation(track.node, v, weight)
                elseif track.path == "rotation" then
                    accumulator:addRotation(track.node, v, weight)
                elseif track.path == "scale" then
                    accumulator:addScale(track.node, v, weight)
                end
            end
        end
    end

    return self
end

function AnimationClip:resetDuration()
    local longest = 0
    for _, track in ipairs(self.tracks) do
        local last = track.times and track.times[#track.times]
        if last and last > longest then longest = last end
    end
    self.duration = longest
    if self._raw then self._raw.duration = longest end
    return self
end

-- three.js's static lookup helpers, as methods per this engine's convention.
function AnimationClip:findByName(clips, name)
    for _, c in ipairs(clips) do
        if c.name == name then return c end
    end
    return nil
end

function AnimationClip:clone()
    local c = AnimationClip:new(self.name, self.duration, self.tracks)
    c._sampler, c._nodes, c._raw = self._sampler, self._nodes, self._raw
    c.fps, c.frames = self.fps, self.frames
    return c
end

-- Same clip data (tracks/sampler are read-only, shared), retargeted to write
-- into a different instance's node list -- what a Model's clips need after
-- Model:createInstance() gives that instance its own cloned Skeleton nodes.
function AnimationClip:withNodes(nodes)
    local c = self:clone()
    c._nodes = nodes
    return c
end

function AnimationClip:__tostring()
    return string.format("AnimationClip(%s, %.3fs, %d tracks)",
        self.name, self.duration, #self.tracks)
end

return AnimationClip
