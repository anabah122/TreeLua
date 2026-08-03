-- math/sphere.lua — bounding sphere
--
--   local s = geometry:computeBoundingSphere()
--   s:applyMatrix4(mesh.matrixWorld)
--
-- An empty sphere is radius < 0, so a fresh one grows correctly under
-- expandByPoint without a separate flag.

local Vector3 = require "engine.math.vec3"

local Sphere = {}
Sphere.__index = Sphere

function Sphere:new(center, radius)
    return setmetatable({
        type   = "Sphere",
        center = center and center:clone() or Vector3:new(),
        radius = radius or -1,
    }, Sphere)
end

function Sphere:isSphere()
    return true
end

function Sphere:set(center, radius)
    self.center:copy(center)
    self.radius = radius
    return self
end

function Sphere:clone()
    return Sphere:new(self.center, self.radius)
end

function Sphere:copy(sphere)
    return self:set(sphere.center, sphere.radius)
end

function Sphere:isEmpty()
    return self.radius < 0
end

function Sphere:makeEmpty()
    self.center:set(0, 0, 0)
    self.radius = -1
    return self
end

function Sphere:containsPoint(point)
    return point:distanceToSquared(self.center) <= self.radius * self.radius
end

function Sphere:distanceToPoint(point)
    return point:distanceTo(self.center) - self.radius
end

function Sphere:intersectsSphere(sphere)
    local r = self.radius + sphere.radius
    return sphere.center:distanceToSquared(self.center) <= r * r
end

function Sphere:intersectsBox(box)
    return box:clampPoint(self.center, Vector3:new())
              :distanceToSquared(self.center) <= self.radius * self.radius
end

function Sphere:expandByPoint(point)
    if self:isEmpty() then
        self.center:copy(point)
        self.radius = 0
        return self
    end

    local d = self.center:distanceTo(point)
    if d > self.radius then
        -- grow just enough to swallow the point, recentring so the far side
        -- does not balloon: the new sphere spans the old one plus the point
        local grow = (d - self.radius) / 2
        self.center:lerpVectors(self.center, point, grow / d)
        self.radius = self.radius + grow
    end

    return self
end

function Sphere:getBoundingBox(target)
    local Box3 = require "engine.math.box3"
    target = target or Box3:new()

    if self:isEmpty() then return target:makeEmpty() end

    target:set(self.center, self.center)
    return target:expandByScalar(self.radius)
end

function Sphere:setFromPoints(points, optionalCenter)
    if optionalCenter then
        self.center:copy(optionalCenter)
    else
        local Box3 = require "engine.math.box3"
        Box3:new():setFromPoints(points):getCenter(self.center)
    end

    local maxSq = 0
    for _, p in ipairs(points) do
        maxSq = math.max(maxSq, self.center:distanceToSquared(p))
    end

    self.radius = math.sqrt(maxSq)
    return self
end

-- Transform into another space. A non-uniform scale cannot stay a sphere, so
-- the largest axis scale is used: the result encloses the true shape.
function Sphere:applyMatrix4(m)
    self.center:applyMatrix4(m)

    local e = m:elements()
    local sx = e[1] * e[1] + e[2]  * e[2]  + e[3]  * e[3]
    local sy = e[5] * e[5] + e[6]  * e[6]  + e[7]  * e[7]
    local sz = e[9] * e[9] + e[10] * e[10] + e[11] * e[11]

    self.radius = self.radius * math.sqrt(math.max(sx, sy, sz))
    return self
end

function Sphere:translate(offset)
    self.center:addSelf(offset)
    return self
end

function Sphere:equals(sphere)
    return self.center:equals(sphere.center) and self.radius == sphere.radius
end

function Sphere:__tostring()
    return string.format("Sphere(%s, r=%.4f)", tostring(self.center), self.radius)
end

return Sphere
