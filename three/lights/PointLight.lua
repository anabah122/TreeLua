-- three/lights/PointLight.lua — omnidirectional light with falloff
--
--   local lamp = PointLight:new(0xffeecc, 2, 10)
--   lamp.position:set(0, 3, 0)
--   scene:add(lamp)
--
-- Constructor and fields follow three.js: color, intensity, distance, decay.
-- `distance` of 0 means the light never cuts off; `decay` of 2 is the physical
-- inverse-square falloff and three.js's default.
--
-- The bundled shader takes one directional light plus ambient, so this is not
-- sampled yet -- it sits in the graph, reports its world position and waits for
-- the shader to grow a point-light slot. Added now so scene code written
-- against three.js loads rather than erroring on a missing class.

local Light   = require "three.lights.Light"
local Vector3 = require "math.vec3"

local PointLight = Light:extend("PointLight")

function PointLight:new(color, intensity, distance, decay)
    local l = Light.new(self, color, intensity)
    l.type = "PointLight"

    l.distance = distance or 0
    l.decay    = decay == nil and 2 or decay

    return l
end

function PointLight:isPointLight()
    return true
end

-- three.js's accessor pair: intensity expressed in candela.
function PointLight:getPower()
    return self.intensity * 4 * math.pi
end

function PointLight:setPower(power)
    self.intensity = power / (4 * math.pi)
    return self
end

function PointLight:worldPosition(target)
    target = target or Vector3:new()
    self:updateWorldMatrix(true, false)
    return target:setFromMatrixPosition(self.matrixWorld)
end

function PointLight:copy(source, recursive)
    Light.copy(self, source, recursive)
    self.distance = source.distance
    self.decay    = source.decay
    return self
end

return PointLight
