-- three/lights/Light.lua — base light
--
-- Lights are Object3Ds, so they sit in the graph and inherit a transform. That
-- matters for DirectionalLight, whose direction is derived from where it sits
-- relative to its target rather than stored as a vector.
--
-- The bundled shader takes exactly one directional light plus one ambient
-- term. The scene may hold more; the renderer picks (see WebGLRenderer) and
-- says so rather than silently dropping them.

local Object3D = require "three.core.Object3D"
local Color    = require "math.color"

local Light = Object3D:extend("Light")

function Light:new(color, intensity)
    local l = Object3D.new(self)
    l.type = "Light"

    l.color     = Color:new(color == nil and 0xffffff or color)
    l.intensity = intensity == nil and 1 or intensity

    return l
end

function Light:isLight()
    return true
end

-- Colour scaled by intensity, which is what a shader uniform wants.
function Light:effectiveColor(target)
    target = target or Color:new()
    return target:copy(self.color):multiplyScalar(self.intensity)
end

function Light:copy(source, recursive)
    Object3D.copy(self, source, recursive)
    self.color:copy(source.color)
    self.intensity = source.intensity
    return self
end

function Light:dispose()
    return self
end

return Light
