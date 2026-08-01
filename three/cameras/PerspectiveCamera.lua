-- three/cameras/PerspectiveCamera.lua
--
--   local camera = PerspectiveCamera:new(60, w / h, 0.1, 1000)
--   camera.position:set(0, 1.2, 3.5)
--   camera:lookAt(0, 1, 0)
--
-- Constructor argument order and defaults follow three.js exactly, including
-- `fov` in DEGREES -- the one place this engine's radians-everywhere rule is
-- broken on purpose, because every three.js example passes degrees. The value
-- is converted when the projection matrix is built.

local Camera = require "three.cameras.Camera"

local PerspectiveCamera = Camera:extend("PerspectiveCamera")

function PerspectiveCamera:new(fov, aspect, near, far)
    local c = Camera.new(self)
    c.type = "PerspectiveCamera"

    c.fov    = fov    or 50
    c.aspect = aspect or 1
    c.near   = near   or 0.1
    c.far    = far    or 2000

    c.zoom   = 1
    c.filmGauge  = 35
    c.filmOffset = 0

    c:updateProjectionMatrix()
    return c
end

function PerspectiveCamera:isPerspectiveCamera()
    return true
end

function PerspectiveCamera:updateProjectionMatrix()
    -- zoom widens or narrows the vertical field, as in three.js
    local vFov = 2 * math.atan(math.tan(math.rad(self.fov) / 2) / self.zoom)

    self.projectionMatrix:makePerspective(vFov, self.aspect, self.near, self.far)
    self.projectionMatrixInverse:copy(self.projectionMatrix):invert()
    return self
end

-- three.js's helper for matching a real lens; kept because examples use it.
function PerspectiveCamera:setFocalLength(focalLength)
    local vExtentSlope = 0.5 * self:getFilmHeight() / focalLength
    self.fov = math.deg(2 * math.atan(vExtentSlope))
    return self:updateProjectionMatrix()
end

function PerspectiveCamera:getFocalLength()
    local vExtentSlope = math.tan(math.rad(self.fov) / 2)
    return 0.5 * self:getFilmHeight() / vExtentSlope
end

function PerspectiveCamera:getFilmWidth()
    return self.filmGauge * math.min(self.aspect, 1)
end

function PerspectiveCamera:getFilmHeight()
    return self.filmGauge / math.max(self.aspect, 1)
end

function PerspectiveCamera:getEffectiveFOV()
    return math.deg(2 * math.atan(math.tan(math.rad(self.fov) / 2) / self.zoom))
end

-- Convenience the renderer calls when the window resizes.
function PerspectiveCamera:setAspect(aspect)
    if self.aspect ~= aspect then
        self.aspect = aspect
        self:updateProjectionMatrix()
    end
    return self
end

function PerspectiveCamera:copy(source, recursive)
    Camera.copy(self, source, recursive)
    self.fov, self.aspect, self.near, self.far =
        source.fov, source.aspect, source.near, source.far
    self.zoom, self.filmGauge, self.filmOffset =
        source.zoom, source.filmGauge, source.filmOffset
    return self
end

return PerspectiveCamera
