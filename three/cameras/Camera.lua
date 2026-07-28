-- three/cameras/Camera.lua — base camera
--
-- An Object3D that additionally carries the two matrices the renderer needs:
-- `projectionMatrix`, set by the subclass, and `matrixWorldInverse`, which is
-- the view matrix -- the inverse of where the camera sits.
--
-- Note the name collision with class/camera.lua, the engine's existing
-- free-look controller. That one is not a camera in the three.js sense: it is
-- input handling. It survives as three.controls.FlyControls, which drives an
-- instance of this class.

local Object3D = require "three.core.Object3D"
local Matrix4  = require "math.mat4"

local Camera = Object3D:extend("Camera")

function Camera:new()
    local c = Object3D.new(self)
    c.type = "Camera"

    c.matrixWorldInverse       = Matrix4:new()
    c.projectionMatrix         = Matrix4:new()
    c.projectionMatrixInverse  = Matrix4:new()

    return c
end

function Camera:isCamera()
    return true
end

function Camera:updateMatrixWorld(force)
    Object3D.updateMatrixWorld(self, force)
    self.matrixWorldInverse:copy(self.matrixWorld):invert()
    return self
end

function Camera:updateWorldMatrix(updateParents, updateChildren)
    Object3D.updateWorldMatrix(self, updateParents, updateChildren)
    self.matrixWorldInverse:copy(self.matrixWorld):invert()
    return self
end

-- Where the camera looks: down its own -Z, in world space.
function Camera:getWorldDirection(target)
    return Object3D.getWorldDirection(self, target)
end

-- projection * view, which is the single matrix the shader takes as
-- u_viewProj. three.js has no such accessor -- it sends the two separately --
-- but the bundled shader wants them premultiplied.
function Camera:viewProjectionMatrix(target)
    target = target or Matrix4:new()
    return target:multiplyMatrices(self.projectionMatrix, self.matrixWorldInverse)
end

-- World point -> pixel coords for a `width`x`height` viewport (defaults to the
-- LÖVE window). Third return is visible: false when the point is behind the
-- camera (NDC z outside [-1,1]), same test as three.js's frustum check.
function Camera:worldToScreen(v, width, height)
    if not width then width, height = love.graphics.getDimensions() end

    local ndc = v:clone():project(self)
    local sx = (ndc.x * 0.5 + 0.5) * width
    local sy = (1 - (ndc.y * 0.5 + 0.5)) * height
    return sx, sy, ndc.z > -1 and ndc.z < 1
end

-- Pixel coords (+ NDC depth, default mid-frustum) -> world point.
function Camera:screenToWorld(x, y, width, height, ndcZ)
    if not width then width, height = love.graphics.getDimensions() end
    ndcZ = ndcZ or 0

    local Vector3 = require "math.vec3"
    local ndcX = (x / width) * 2 - 1
    local ndcY = 1 - (y / height) * 2
    return Vector3:new(ndcX, ndcY, ndcZ):unproject(self)
end

function Camera:copy(source, recursive)
    Object3D.copy(self, source, recursive)
    self.matrixWorldInverse:copy(source.matrixWorldInverse)
    self.projectionMatrix:copy(source.projectionMatrix)
    self.projectionMatrixInverse:copy(source.projectionMatrixInverse)
    return self
end

return Camera
