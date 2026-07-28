-- class/camera.lua — LEGACY, superseded by the public API
--
-- Replaced by three.cameras.PerspectiveCamera (the camera) plus
-- three.controls.FlyControls (the input handling this file actually is).
-- Kept because it predates the facade and nothing in the library depends on
-- it; new code should not use it.
--
-- It reads the globals `LK` and `LG`, so it only works after
-- `require "lib.util"`. FlyControls reads love.keyboard directly instead.

local mat4 = require 'math.mat4'
local vec3 = require 'math.vec3'

local UP = vec3:new(0, 1, 0)

local Camera = {}
Camera.__index = Camera

function Camera:new(opts)
    opts = opts or {}
    local c = setmetatable({}, Camera)

    c.pos   = vec3:new(opts.x or 0, opts.y or 2, opts.z or 6)
    c.yaw   = opts.yaw   or math.pi
    c.pitch = opts.pitch or 0

    c.speed     = opts.speed     or 5
    c.speedMin  = 0.1
    c.speedMax  = 500
    c.lookSpeed = opts.lookSpeed or 0.002
    c.fov       = opts.fov       or math.rad(60)
    c.near      = opts.near      or 0.1
    c.far       = opts.far       or 1024

    love.mouse.setRelativeMode(true)
    return c
end

function Camera:forward()
    local cp = math.cos(self.pitch)
    return vec3:new(cp * math.sin(self.yaw), math.sin(self.pitch), cp * math.cos(self.yaw))
end

function Camera:right()
    return self:forward():cross(UP):normalize()
end

-- Forward with the pitch flattened out, so walking never drifts up or down:
-- looking at the floor and pressing S must pull the camera back, not sink it.
function Camera:forwardFlat()
    return vec3:new(math.sin(self.yaw), 0, math.cos(self.yaw))
end

function Camera:wheelmoved(dy)
    self.speed = math.max(self.speedMin, math.min(self.speedMax, self.speed * (dy > 0 and 1.2 or 1/1.2)))
end

function Camera:mousemoved(dx, dy)
    self.yaw   = self.yaw - dx * self.lookSpeed
    self.pitch = math.max(-math.pi * 0.499,
                 math.min( math.pi * 0.499, self.pitch - dy * self.lookSpeed))
end

function Camera:update(dt)
    local move = vec3:new(0, 0, 0)

    if LK.isDown('w') then move = move + self:forwardFlat() end
    if LK.isDown('s') then move = move - self:forwardFlat() end
    if LK.isDown('d') then move = move + self:right()       end
    if LK.isDown('a') then move = move - self:right()       end
    if LK.isDown('q') then move = move + UP                 end
    if LK.isDown('e') then move = move - UP                 end
    
    if move:magnitude() > 0 then
        local shift = LK.isDown('lshift', 'rshift')
        local spd   = self.speed * (shift and 0.2 or 1)
        self.pos = self.pos + move:normalize() * (spd * dt)
    end
end

function Camera:viewproj()
    local eye    = self.pos
    local target = self.pos + self:forward()
    local w, h   = LG.getWidth(), LG.getHeight()

    local proj = mat4:new():setProjectionMatrix(self.fov, self.near, self.far, w / h)
    local view = mat4:new():setViewMatrix(
        { eye.x,    eye.y,    eye.z    },
        { target.x, target.y, target.z },
        { UP.x,     UP.y,     UP.z     }
    )
    return mat4:new():mul(proj, view)
end

return Camera
