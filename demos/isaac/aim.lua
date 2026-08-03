-- Прицеливание мышью: луч камеры пересекается с плоскостью пола (Y=0).
local Raycaster = require "engine.core.Raycaster"
local Plane     = require "engine.math.plane"
local Vector3   = require "engine.math.vec3"

local Aim = {}
Aim.__index = Aim

function Aim:new()
    local self = setmetatable({}, Aim)
    self.caster = Raycaster:new()
    self.ground = Plane:new(Vector3:new(0, 1, 0), 0)
    return self
end

-- Возвращает x, z точки на полу под курсором, либо nil, если луч уходит от пола.
function Aim:groundPointUnderCursor(camera)
    local mx, my = love.mouse.getPosition()
    self.caster:setFromScreen(mx, my, camera)

    local hit = self.caster.ray:intersectPlane(self.ground, Vector3:new())
    if not hit then return nil end
    return hit.x, hit.z
end

return Aim
