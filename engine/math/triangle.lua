-- math/triangle.lua — three vertices, three.js Triangle API
--
--   local tri = Triangle:new(a, b, c)
--   tri:closestPointToPoint(point, target)
--
-- Used by mesh collision: a capsule against a triangle soup tests each
-- triangle's closest point, same shape as Capsule:intersectsBox against a
-- box's clamped point.

local Vector3 = require "engine.math.vec3"
local Plane   = require "engine.math.plane"

local Triangle = {}
Triangle.__index = Triangle

function Triangle:new(a, b, c)
    return setmetatable({
        type = "Triangle",
        a = a and a:clone() or Vector3:new(),
        b = b and b:clone() or Vector3:new(),
        c = c and c:clone() or Vector3:new(),
    }, Triangle)
end

function Triangle:isTriangle()
    return true
end

function Triangle:set(a, b, c)
    self.a:copy(a)
    self.b:copy(b)
    self.c:copy(c)
    return self
end

function Triangle:clone()
    return Triangle:new(self.a, self.b, self.c)
end

function Triangle:getNormal(target)
    target = target or Vector3:new()
    return target:crossVectors(
        Vector3:new():subVectors(self.c, self.b),
        Vector3:new():subVectors(self.a, self.b)
    ):normalizeSelf()
end

function Triangle:getPlane(target)
    target = target or Plane:new()
    return target:setFromCoplanarPoints(self.a, self.b, self.c)
end

-- Barycentric coordinates of `point` projected onto the triangle's plane.
function Triangle:getBarycoord(point, target)
    local v0 = Vector3:new():subVectors(self.c, self.a)
    local v1 = Vector3:new():subVectors(self.b, self.a)
    local v2 = Vector3:new():subVectors(point, self.a)

    local dot00 = v0:dot(v0)
    local dot01 = v0:dot(v1)
    local dot02 = v0:dot(v2)
    local dot11 = v1:dot(v1)
    local dot12 = v1:dot(v2)

    local denom = dot00 * dot11 - dot01 * dot01
    target = target or Vector3:new()

    if denom == 0 then return target:set(-2, -1, -1) end

    local invDenom = 1 / denom
    local u = (dot11 * dot02 - dot01 * dot12) * invDenom
    local v = (dot00 * dot12 - dot01 * dot02) * invDenom

    return target:set(1 - u - v, v, u)
end

function Triangle:containsPoint(point)
    local bary = self:getBarycoord(point, Vector3:new())
    return bary.x >= 0 and bary.y >= 0 and (bary.x + bary.y) <= 1
end

-- Nearest point on the (finite, filled) triangle to an arbitrary point:
-- project onto the plane, and if that lands outside the triangle, clamp to
-- the nearest edge.
function Triangle:closestPointToPoint(point, target)
    target = target or Vector3:new()

    local plane = self:getPlane(Plane:new())
    local projected = plane:projectPoint(point, Vector3:new())

    if self:containsPoint(projected) then
        return target:copy(projected)
    end

    local function closestOnSegment(p, a, b)
        local ab = Vector3:new():subVectors(b, a)
        local lenSq = ab:lengthSq()
        local t = lenSq > 1e-12 and Vector3:new():subVectors(p, a):dot(ab) / lenSq or 0
        t = math.min(math.max(t, 0), 1)
        return Vector3:new():copy(ab):multiplyScalar(t):addSelf(a)
    end

    local candidates = {
        closestOnSegment(projected, self.a, self.b),
        closestOnSegment(projected, self.b, self.c),
        closestOnSegment(projected, self.c, self.a),
    }

    local best, bestDistSq = candidates[1], candidates[1]:distanceToSquared(point)
    for i = 2, 3 do
        local distSq = candidates[i]:distanceToSquared(point)
        if distSq < bestDistSq then best, bestDistSq = candidates[i], distSq end
    end

    return target:copy(best)
end

function Triangle:equals(triangle)
    return self.a:equals(triangle.a) and self.b:equals(triangle.b) and self.c:equals(triangle.c)
end

function Triangle:__tostring()
    return string.format("Triangle(%s, %s, %s)", tostring(self.a), tostring(self.b), tostring(self.c))
end

return Triangle
