-- three/scenes/Fog.lua — linear distance fog
--
--   scene.fog = Fog:new(0x808080, 1, 50)
--
-- Blends every fragment toward `color` between `near` and `far`, in world
-- units from the camera. Read by shader/parts/fog.lua via u_fogNear/u_fogFar.

local Color = require "engine.math.color"

local Fog = {}
Fog.__index = Fog

function Fog:new(color, near, far)
    local f = setmetatable({}, self)
    f.type  = "Fog"
    f.color = Color:new(color == nil and 0xffffff or color)
    f.near  = near or 1
    f.far   = far or 1000
    return f
end

function Fog:isFog()
    return true
end

return Fog
