-- three/controls/FlyControls.lua — free-look camera input
--
--   local controls = FlyControls:new(camera)
--   function love.update(dt)          controls:update(dt) end
--   function love.mousemoved(x,y,dx,dy) controls:mousemoved(dx, dy) end
--   function love.wheelmoved(dx,dy)   controls:wheelmoved(dy) end
--
-- This is what class/camera.lua always was: input handling, not a camera. It
-- drives a PerspectiveCamera rather than owning a view matrix, so the camera
-- stays a normal Object3D that can be parented, animated or replaced.
--
-- Unlike the original it reads love.keyboard directly instead of the global
-- `LK` that lib/util installs -- a library must not require its host to have
-- set up globals first.

local Vector3    = require "math.vec3"
local Quaternion = require "math.quat"

local FlyControls = {}
FlyControls.__index = FlyControls

local UP = Vector3:new(0, 1, 0)

function FlyControls:new(camera, params)
    params = params or {}

    local c = setmetatable({}, FlyControls)
    c.type   = "FlyControls"
    c.object = camera
    c.enabled = params.enabled ~= false

    -- Yaw/pitch are kept here rather than read back from the camera's
    -- quaternion: extracting euler angles every frame would drift, and pitch
    -- has to be clamped anyway.
    c.yaw   = params.yaw   or math.pi
    c.pitch = params.pitch or 0

    c.movementSpeed = params.movementSpeed or 5
    c.speedMin      = params.speedMin or 0.1
    c.speedMax      = params.speedMax or 500
    c.lookSpeed     = params.lookSpeed or 0.002

    c.slowModifier  = params.slowModifier or 0.2

    c.keys = params.keys or {
        forward = "w", back = "s", left = "a", right = "d",
        up = "q", down = "e", slow = { "lshift", "rshift" },
    }

    c.lockMouse = params.lockMouse ~= false
    if c.lockMouse then love.mouse.setRelativeMode(true) end

    c:_applyRotation()
    return c
end

function FlyControls:isFlyControls()
    return true
end

-- ── orientation ──────────────────────────────────────────────────────────────

-- Where the camera looks. Note the +Z in the yaw terms: the camera faces -Z in
-- three.js, and the default yaw of pi turns it around to look up +Z, which is
-- what the original camera did.
function FlyControls:forward()
    local cp = math.cos(self.pitch)
    return Vector3:new(cp * math.sin(self.yaw), math.sin(self.pitch), cp * math.cos(self.yaw))
end

function FlyControls:right()
    return self:forward():cross(UP):normalize()
end

-- Forward with the pitch flattened out, so walking never drifts up or down:
-- looking at the floor and pressing back must pull the camera away, not sink it.
function FlyControls:forwardFlat()
    return Vector3:new(math.sin(self.yaw), 0, math.cos(self.yaw))
end

-- Push yaw/pitch onto the camera. Built as a lookAt at a point one unit ahead
-- so the roll stays zero without composing euler angles by hand.
function FlyControls:_applyRotation()
    local cam = self.object
    local f   = self:forward()
    cam:lookAt(cam.position.x + f.x, cam.position.y + f.y, cam.position.z + f.z)
    return self
end

-- ── input ────────────────────────────────────────────────────────────────────

function FlyControls:mousemoved(dx, dy)
    if not self.enabled then return self end

    self.yaw = self.yaw - dx * self.lookSpeed

    -- just short of straight up/down: at exactly +-pi/2 the forward vector goes
    -- parallel to UP and the right vector collapses
    local limit = math.pi * 0.499
    self.pitch = math.max(-limit, math.min(limit, self.pitch - dy * self.lookSpeed))

    return self:_applyRotation()
end

function FlyControls:wheelmoved(dy)
    if not self.enabled then return self end
    local factor = dy > 0 and 1.2 or 1 / 1.2
    self.movementSpeed = math.max(self.speedMin,
                         math.min(self.speedMax, self.movementSpeed * factor))
    return self
end

local function isDown(key)
    if type(key) == "table" then
        return love.keyboard.isDown(unpack(key))
    end
    return love.keyboard.isDown(key)
end

function FlyControls:update(dt)
    if not self.enabled then return self end

    local k    = self.keys
    local move = Vector3:new(0, 0, 0)

    if isDown(k.forward) then move:addV(self:forwardFlat()) end
    if isDown(k.back)    then move:subV(self:forwardFlat()) end
    if isDown(k.right)   then move:addV(self:right())       end
    if isDown(k.left)    then move:subV(self:right())       end
    if isDown(k.up)      then move:addV(UP)                 end
    if isDown(k.down)    then move:subV(UP)                 end

    if move:lengthSq() > 0 then
        local speed = self.movementSpeed
        if k.slow and isDown(k.slow) then speed = speed * self.slowModifier end
        self.object.position:addScaledVector(move:normalizeSelf(), speed * dt)
        self:_applyRotation()
    end

    return self
end

function FlyControls:dispose()
    if self.lockMouse then love.mouse.setRelativeMode(false) end
    self.enabled = false
    return self
end

return FlyControls
