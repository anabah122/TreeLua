-- math/plane.lua — infinite plane in Hessian normal form
--
--   local p = Plane:new(Vector3:new(0, 1, 0), 0)   -- the ground
--   p:distanceToPoint(v)                           -- signed, + on the normal side
--
-- `constant` is the signed distance from the origin to the plane along the
-- NEGATED normal, matching three.js: the plane is the set of points where
-- dot(normal, point) + constant == 0.

local Vector3 = require "math.vec3"

local Plane = {}
Plane.__index = Plane

function Plane:new(normal, constant)
    return setmetatable({
        type     = "Plane",
        normal   = normal and normal:clone() or Vector3:new(1, 0, 0),
        constant = constant or 0,
    }, Plane)
end

function Plane:isPlane()
    return true
end

function Plane:set(normal, constant)
    self.normal:copy(normal)
    self.constant = constant
    return self
end

function Plane:setComponents(x, y, z, w)
    self.normal:set(x, y, z)
    self.constant = w
    return self
end

function Plane:clone()
    return Plane:new(self.normal, self.constant)
end

function Plane:copy(plane)
    return self:set(plane.normal, plane.constant)
end

function Plane:setFromNormalAndCoplanarPoint(normal, point)
    self.normal:copy(normal)
    self.constant = -point:dot(self.normal)
    return self
end

function Plane:setFromCoplanarPoints(a, b, c)
    local normal = Vector3:new():crossVectors(
        Vector3:new():subVectors(c, b),
        Vector3:new():subVectors(a, b)
    ):normalizeSelf()
    return self:setFromNormalAndCoplanarPoint(normal, a)
end

-- Scale the equation so the normal is unit length, which is what makes
-- distanceToPoint a true distance rather than a proportional value.
function Plane:normalizeSelf()
    local len = self.normal:length()
    if len == 0 then return self end

    local inv = 1 / len
    self.normal:multiplyScalar(inv)
    self.constant = self.constant * inv
    return self
end

function Plane:negate()
    self.normal:negate()
    self.constant = -self.constant
    return self
end

function Plane:distanceToPoint(point)
    return self.normal:dot(point) + self.constant
end

function Plane:distanceToSphere(sphere)
    return self:distanceToPoint(sphere.center) - sphere.radius
end

function Plane:projectPoint(point, target)
    target = target or Vector3:new()
    return target:copy(self.normal)
                 :multiplyScalar(-self:distanceToPoint(point))
                 :addV(point)
end

function Plane:coplanarPoint(target)
    target = target or Vector3:new()
    return target:copy(self.normal):multiplyScalar(-self.constant)
end

function Plane:translate(offset)
    self.constant = self.constant - offset:dot(self.normal)
    return self
end

function Plane:equals(plane)
    return self.normal:equals(plane.normal) and self.constant == plane.constant
end

function Plane:__tostring()
    return string.format("Plane(%s, %.4f)", tostring(self.normal), self.constant)
end

return Plane
