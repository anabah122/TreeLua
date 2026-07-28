-- three/animation/AnimationMixer.lua — drives a model's animations
--
--   local mixer = AnimationMixer:new(gltf.scene)
--   mixer:clipAction(gltf.animations[1]):play()
--   function love.update(dt) mixer:update(dt) end
--
-- Owns the actions for one root object, steps their clocks, samples the
-- winning one into the node hierarchy and refreshes world matrices so the
-- skinning palette is current.
--
-- ONE ACTION WRITES THE POSE. three.js accumulates every running action and
-- blends by weight; that needs samplers that RETURN a pose, and both importers
-- write TRS directly into the shared node list instead. Rather than fake it,
-- the mixer picks the highest-weight running action and samples only that.
-- Crossfades still ramp weights, so the switch lands at the crossover point.

local AnimationAction = require "three.animation.AnimationAction"
local common          = require "importer.common"

local AnimationMixer = {}
AnimationMixer.__index = AnimationMixer

function AnimationMixer:new(root)
    return setmetatable({
        type = "AnimationMixer",

        _root    = root,
        _actions = {},        -- clip -> action
        _active  = {},        -- ordered list of running actions
        _listeners = {},

        time      = 0,
        timeScale = 1,
    }, AnimationMixer)
end

function AnimationMixer:isAnimationMixer()
    return true
end

function AnimationMixer:getRoot()
    return self._root
end

-- Returns the action for `clip`, creating it on first ask. three.js caches the
-- same way, so calling this every frame is safe.
function AnimationMixer:clipAction(clip, root)
    local existing = self._actions[clip]
    if existing then return existing end

    local action = AnimationAction:new(self, clip, root or self._root)
    self._actions[clip] = action
    return action
end

function AnimationMixer:existingAction(clip)
    return self._actions[clip]
end

function AnimationMixer:_activate(action)
    for _, a in ipairs(self._active) do
        if a == action then return end
    end
    self._active[#self._active + 1] = action
end

function AnimationMixer:_deactivate(action)
    for i, a in ipairs(self._active) do
        if a == action then
            table.remove(self._active, i)
            return
        end
    end
end

function AnimationMixer:stopAllAction()
    for i = #self._active, 1, -1 do
        self._active[i]:stop()
    end
    self._active = {}
    return self
end

function AnimationMixer:uncacheClip(clip)
    local action = self._actions[clip]
    if action then
        action:stop()
        self._actions[clip] = nil
    end
    return self
end

-- ── events ───────────────────────────────────────────────────────────────────
-- three.js mixers are EventDispatchers and fire "finished" and "loop".

function AnimationMixer:addEventListener(kind, fn)
    self._listeners[kind] = self._listeners[kind] or {}
    table.insert(self._listeners[kind], fn)
    return self
end

function AnimationMixer:removeEventListener(kind, fn)
    for i, f in ipairs(self._listeners[kind] or {}) do
        if f == fn then
            table.remove(self._listeners[kind], i)
            return self
        end
    end
    return self
end

function AnimationMixer:_dispatchFinished(action)
    for _, fn in ipairs(self._listeners.finished or {}) do
        fn({ type = "finished", action = action, target = self })
    end
end

-- ── stepping ─────────────────────────────────────────────────────────────────

-- Which action gets to write the pose: highest effective weight, ties going to
-- whichever started first, so the choice never flickers frame to frame.
function AnimationMixer:_dominant()
    local best, bestWeight = nil, -1
    for _, action in ipairs(self._active) do
        if action:isRunning() then
            local w = action:getEffectiveWeight()
            if w > bestWeight then best, bestWeight = action, w end
        end
    end
    return best
end

function AnimationMixer:update(dt)
    local step = dt * self.timeScale
    self.time = self.time + step

    -- advance every clock first, so weights and crossfades resolve before the
    -- winner is chosen
    for i = #self._active, 1, -1 do
        local action = self._active[i]
        if not action:_advance(step) then
            table.remove(self._active, i)
        end
    end

    local action = self:_dominant()
    if not action then return self end

    local clip = action:getClip()
    clip:sample(action.time, action.loop ~= "once")

    -- the sampler wrote local TRS; world matrices have to follow or the
    -- skinning palette reads last frame's pose
    local nodes = clip._nodes
    if nodes then
        common.update_world(nodes, nodes.rootMatrix)
    end

    return self
end

-- three.js exposes this for scrubbing; here it also re-poses immediately so a
-- paused caller sees the result without waiting for the next update.
function AnimationMixer:setTime(time)
    self.time = time
    for _, action in ipairs(self._active) do
        action.time = time
    end
    return self:update(0)
end

return AnimationMixer
