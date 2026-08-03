-- three/lights/HemisphereLight.lua — cheap sky/ground ambient, no shadows
--
--   scene:add(HemisphereLight:new(0x88ccff, 0x554433, 1))
--
-- Two ambient terms blended by surface normal instead of one flat colour:
-- `color` (sky) lights faces pointing up, `groundColor` lights faces pointing
-- down, `up` (Object3D's own field) is the sky direction, defaulting to +Y.
-- Unlike DirectionalLight this never casts a shadow -- three.js's doesn't
-- either, since a hemisphere has no single ray to occlude.

local Light = require "engine.lights.Light"

local HemisphereLight = Light:extend("HemisphereLight")

function HemisphereLight:new(skyColor, groundColor, intensity)
    local l = Light.new(self, skyColor, intensity)
    l.type = "HemisphereLight"

    -- reuses Light's `color` field as the sky colour, matching three.js
    l.groundColor = require("engine.math.color"):new(groundColor == nil and 0xffffff or groundColor)

    -- three.js reads the sky direction off the light's own +Y in world space;
    -- default position gives that a non-zero vector to normalize
    l.position:set(0, 1, 0)

    return l
end

function HemisphereLight:isHemisphereLight()
    return true
end

function HemisphereLight:copy(source, recursive)
    Light.copy(self, source, recursive)
    self.groundColor:copy(source.groundColor)
    return self
end

return HemisphereLight
