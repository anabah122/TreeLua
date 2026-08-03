-- three/lights/Light.lua — base light
--
-- Lights are Object3Ds, so they sit in the graph and inherit a transform. That
-- matters for DirectionalLight, whose direction is derived from where it sits
-- relative to its target rather than stored as a vector.
--
-- The bundled shader takes up to WebGLRenderer.MAX_LIGHTS directional/point/
-- spot lights (see shader/parts/pbr.lua) plus one ambient term. A scene with
-- more gets the brightest MAX_LIGHTS, picked by the renderer, which says so
-- rather than silently dropping the rest.

local Object3D = require "engine.core.Object3D"
local Color    = require "engine.math.color"

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
