-- three/cameras/OrthographicCamera.lua
--
--   local d = 5
--   local camera = OrthographicCamera:new(-d * aspect, d * aspect, d, -d, 1, 100)
--
-- Argument order is three.js's: left, right, top, bottom, near, far. Note that
-- `top` comes before `bottom` and is the larger value, which reads backwards
-- but matches the docs.

local Camera = require "engine.cameras.Camera"

local OrthographicCamera = Camera:extend("OrthographicCamera")

function OrthographicCamera:new(left, right, top, bottom, near, far)
    local c = Camera.new(self)
    c.type = "OrthographicCamera"

    c.left   = left   or -1
    c.right  = right  or  1
    c.top    = top    or  1
    c.bottom = bottom or -1
    c.near   = near   or  0.1
    c.far    = far    or  2000

    c.zoom = 1

    c:updateProjectionMatrix()
    return c
end

function OrthographicCamera:isOrthographicCamera()
    return true
end

function OrthographicCamera:updateProjectionMatrix()
    local dx = (self.right - self.left) / (2 * self.zoom)
    local dy = (self.top - self.bottom) / (2 * self.zoom)
    local cx = (self.right + self.left) / 2
    local cy = (self.top + self.bottom) / 2

    self.projectionMatrix:makeOrthographic(
        cx - dx, cx + dx, cy + dy, cy - dy, self.near, self.far)
    self.projectionMatrixInverse:copy(self.projectionMatrix):invert()
    return self
end

function OrthographicCamera:copy(source, recursive)
    Camera.copy(self, source, recursive)
    self.left, self.right  = source.left, source.right
    self.top,  self.bottom = source.top,  source.bottom
    self.near, self.far    = source.near, source.far
    self.zoom = source.zoom
    return self
end

return OrthographicCamera
