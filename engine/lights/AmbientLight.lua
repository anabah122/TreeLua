-- three/lights/AmbientLight.lua — uniform light from every direction
--
--   scene:add(AmbientLight:new(0x404050, 1))
--
-- Has no position or direction: only its colour and intensity are read, and
-- they land in the shader's u_ambient. Several ambient lights in one scene sum
-- together, as in three.js.

local Light = require "engine.lights.Light"

local AmbientLight = Light:extend("AmbientLight")

function AmbientLight:new(color, intensity)
    local l = Light.new(self, color, intensity)
    l.type = "AmbientLight"
    return l
end

function AmbientLight:isAmbientLight()
    return true
end

return AmbientLight
