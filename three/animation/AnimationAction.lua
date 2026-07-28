-- three/animation/AnimationAction.lua — one clip's playback state
--
--   local action = mixer:clipAction(clip)
--   action:setLoop("repeat"):setEffectiveTimeScale(1):play()
--
-- Holds time, weight and rate for a single clip. The mixer owns the set of
-- actions and decides which one actually writes the pose.
--
-- BLENDING IS NOT SUPPORTED. three.js evaluates every active action into an
-- accumulator and blends by weight; that requires the sampler to return values
-- rather than write them, and both importers' samplers write TRS straight into
-- the shared node list. So `weight` is respected only as a chooser -- the
-- highest-weight running action wins outright -- and crossFadeTo ramps weights
-- so the switch happens at the midpoint. See AnimationMixer:update.

local AnimationAction = {}
AnimationAction.__index = AnimationAction

function AnimationAction:new(mixer, clip, root)
    return setmetatable({
        type = "AnimationAction",

        _mixer = mixer,
        _clip  = clip,
        _root  = root,

        time            = 0,
        timeScale       = 1,
        weight          = 1,
        enabled         = true,
        paused          = false,
        clampWhenFinished = false,

        loop            = "repeat",   -- "repeat" | "once" | "pingpong"
        repetitions     = math.huge,

        _isRunning      = false,
        _loopCount      = 0,
        _direction      = 1,

        -- crossfade state, driven by the mixer
        _fadeFrom       = nil,
        _fadeTo         = nil,
        _fadeDuration   = 0,
        _fadeElapsed    = 0,
    }, AnimationAction)
end

function AnimationAction:isAnimationAction()
    return true
end

function AnimationAction:getClip() return self._clip end
function AnimationAction:getMixer() return self._mixer end
function AnimationAction:getRoot() return self._root end

-- ── transport ────────────────────────────────────────────────────────────────

function AnimationAction:play()
    self._isRunning = true
    self.enabled    = true
    self.paused     = false
    self._mixer:_activate(self)
    return self
end

function AnimationAction:stop()
    self._isRunning = false
    self._loopCount = 0
    self.time       = 0
    self._mixer:_deactivate(self)
    return self
end

function AnimationAction:reset()
    self.time       = 0
    self._loopCount = 0
    self._direction = 1
    self.paused     = false
    self.enabled    = true
    return self
end

function AnimationAction:isRunning()
    return self._isRunning and self.enabled and not self.paused
end

function AnimationAction:isScheduled()
    return self._isRunning
end

-- ── settings ─────────────────────────────────────────────────────────────────

function AnimationAction:setLoop(mode, repetitions)
    self.loop = mode or "repeat"
    self.repetitions = repetitions or math.huge
    return self
end

function AnimationAction:setEffectiveWeight(weight)
    self.weight = weight
    return self
end

function AnimationAction:getEffectiveWeight()
    return self.enabled and self.weight or 0
end

function AnimationAction:setEffectiveTimeScale(scale)
    self.timeScale = scale
    return self
end

function AnimationAction:getEffectiveTimeScale()
    return self.paused and 0 or self.timeScale
end

-- three.js stretches a clip onto a wall-clock duration here. The engine needed
-- this before the facade existed: the same motion exported twice rarely lands
-- on the same length -- Blender's glTF at 24fps and Mixamo's Collada at 30fps
-- differ by 17ms, enough to visibly drift apart after a few loops.
function AnimationAction:setDuration(duration)
    if duration and duration > 0 and self._clip.duration > 0 then
        self.timeScale = self._clip.duration / duration
    end
    return self
end

function AnimationAction:startAt(time)
    self.time = time or 0
    return self
end

function AnimationAction:syncWith(other)
    self.time      = other.time
    self.timeScale = other.timeScale
    return self
end

-- ── fading ───────────────────────────────────────────────────────────────────

function AnimationAction:fadeIn(duration)
    return self:_scheduleFade(0, 1, duration)
end

function AnimationAction:fadeOut(duration)
    return self:_scheduleFade(self.weight, 0, duration)
end

function AnimationAction:_scheduleFade(from, to, duration)
    self._fadeFrom     = from
    self._fadeTo       = to
    self._fadeDuration = duration or 0
    self._fadeElapsed  = 0
    self.weight        = from
    return self
end

-- Ramps this action in while `other` ramps out. Because the samplers cannot
-- blend, the visible switch is a cut at the crossover point rather than a
-- true blend -- the weights still ramp, so timing code behaves the same.
function AnimationAction:crossFadeFrom(other, duration, warp)
    other:fadeOut(duration)
    self:fadeIn(duration)
    if warp then self:syncWith(other) end
    return self:play()
end

function AnimationAction:crossFadeTo(other, duration, warp)
    return other:crossFadeFrom(self, duration, warp)
end

-- ── stepping ─────────────────────────────────────────────────────────────────

-- Advance this action's clock. Returns true while it should still be sampled;
-- a "once" action that has run out returns false so the mixer can retire it.
function AnimationAction:_advance(dt)
    if not self:isRunning() then return false end

    if self._fadeDuration > 0 then
        self._fadeElapsed = self._fadeElapsed + dt
        local t = math.min(1, self._fadeElapsed / self._fadeDuration)
        self.weight = self._fadeFrom + (self._fadeTo - self._fadeFrom) * t
        if t >= 1 then
            self._fadeDuration = 0
            -- a completed fade-out means this action is done contributing
            if self.weight <= 0 then
                self._isRunning = false
                return false
            end
        end
    end

    local duration = self._clip.duration
    self.time = self.time + dt * self.timeScale * self._direction

    if duration <= 0 then return true end

    if self.loop == "once" then
        if self.time >= duration then
            self.time = self.clampWhenFinished and duration or 0
            self._isRunning = false
            self._mixer:_dispatchFinished(self)
            return self.clampWhenFinished
        end

    elseif self.loop == "pingpong" then
        if self.time > duration then
            self.time = duration - (self.time - duration)
            self._direction = -1
            self._loopCount = self._loopCount + 1
        elseif self.time < 0 then
            self.time = -self.time
            self._direction = 1
            self._loopCount = self._loopCount + 1
        end

    else -- "repeat"
        if self.time >= duration then
            self._loopCount = self._loopCount + math.floor(self.time / duration)
            self.time = self.time % duration
            if self._loopCount >= self.repetitions then
                self._isRunning = false
                self._mixer:_dispatchFinished(self)
                return false
            end
        elseif self.time < 0 then
            self.time = self.time % duration
        end
    end

    return true
end

return AnimationAction
