-- three/lights/DirectionalLight.lua — parallel rays, like the sun
--
--   local sun = DirectionalLight:new(0xfff5ec, 1)
--   sun.position:set(-0.4, 1.0, 0.6)
--   scene:add(sun)
--
-- The direction is NOT a field: three.js derives it from the light's position
-- relative to `target`, whose default sits at the origin. So moving the light
-- aims it, and only the direction matters -- distance does nothing, since the
-- rays are parallel.

local Light   = require "three.lights.Light"
local Object3D = require "three.core.Object3D"
local Vector3 = require "math.vec3"

local DirectionalLight = Light:extend("DirectionalLight")

function DirectionalLight:new(color, intensity)
    local l = Light.new(self, color, intensity)
    l.type = "DirectionalLight"

    -- three.js defaults the light to (0,1,0) looking at the origin
    l.position:set(0, 1, 0)
    l.target = Object3D:new()

    return l
end

function DirectionalLight:isDirectionalLight()
    return true
end

-- Unit vector along which the light TRAVELS: from the light toward its target,
-- which is what the shader's u_lightDir expects. three.js computes the same
-- vector internally when it fills its light uniforms.
function DirectionalLight:direction(target)
    target = target or Vector3:new()

    self:updateWorldMatrix(true, false)
    local from = Vector3:new():setFromMatrixPosition(self.matrixWorld)

    self.target:updateWorldMatrix(true, false)
    local to = Vector3:new():setFromMatrixPosition(self.target.matrixWorld)

    target:subVectors(to, from)

    -- a light sitting exactly on its target has no direction; point it down
    -- rather than handing the shader a zero vector
    if target:lengthSq() == 0 then return target:set(0, -1, 0) end

    return target:normalizeSelf()
end

function DirectionalLight:copy(source, recursive)
    Light.copy(self, source, recursive)
    self.target = source.target:clone(false)
    return self
end

return DirectionalLight
