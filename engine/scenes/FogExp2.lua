-- three/scenes/FogExp2.lua — exponential-squared distance fog
--
--   scene.fog = FogExp2:new(0x808080, 0.01)
--
-- Density-based falloff, thicker with distance rather than fading linearly
-- between two planes. Read by shader/parts/fog.lua via u_fogDensity.

local Color = require "engine.math.color"

local FogExp2 = {}
FogExp2.__index = FogExp2

function FogExp2:new(color, density)
    local f = setmetatable({}, self)
    f.type    = "FogExp2"
    f.color   = Color:new(color == nil and 0xffffff or color)
    f.density = density or 0.00025
    return f
end

function FogExp2:isFogExp2()
    return true
end

return FogExp2
