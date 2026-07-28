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

function Camera:copy(source, recursive)
    Object3D.copy(self, source, recursive)
    self.matrixWorldInverse:copy(source.matrixWorldInverse)
    self.projectionMatrix:copy(source.projectionMatrix)
    self.projectionMatrixInverse:copy(source.projectionMatrixInverse)
    return self
end

return Camera
