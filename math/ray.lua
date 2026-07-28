-- math/ray.lua — origin plus a unit direction
--
--   local ray = Ray:new(origin, direction)
--   local hit = ray:intersectTriangle(a, b, c, false, Vector3:new())
--
-- The direction is assumed normalised; the intersection routines return a
-- distance along it, so a non-unit direction silently rescales every result.

local Vector3 = require "math.vec3"

local Ray = {}
Ray.__index = Ray

function Ray:new(origin, direction)
    return setmetatable({
        type      = "Ray",
        origin    = origin and origin:clone() or Vector3:new(),
        direction = direction and direction:clone() or Vector3:new(0, 0, -1),
    }, Ray)
end

function Ray:isRay()
    return true
end

function Ray:set(origin, direction)
    self.origin:copy(origin)
    self.direction:copy(direction)
    return self
end

function Ray:clone()
    return Ray:new(self.origin, self.direction)
end

function Ray:copy(ray)
    return self:set(ray.origin, ray.direction)
end

function Ray:at(t, target)
    target = target or Vector3:new()
    return target:copy(self.direction):multiplyScalar(t):addSelf(self.origin)
end

function Ray:lookAt(v)
    self.direction:copy(v):subSelf(self.origin):normalizeSelf()
    return self
end

function Ray:recast(t)
    self.origin:copy(self:at(t, Vector3:new()))
    return self
end

-- Nearest point on the ray to an arbitrary point. Clamped at the origin: a
-- point behind the ray projects to a negative t, which is not on the ray.
function Ray:closestPointToPoint(point, target)
    target = target or Vector3:new()
    target:subVectors(point, self.origin)

    local t = target:dot(self.direction)
    if t < 0 then return target:copy(self.origin) end

    return target:copy(self.direction):multiplyScalar(t):addSelf(self.origin)
end

function Ray:distanceToPoint(point)
    return math.sqrt(self:distanceSqToPoint(point))
end

function Ray:distanceSqToPoint(point)
    return self:closestPointToPoint(point, Vector3:new()):distanceToSquared(point)
end

-- The tip is transformed as a point and the direction rebuilt from it, so
-- translation cancels in the subtraction and any scale is renormalised away.
-- Order matters: the tip must be taken before the origin moves.
function Ray:applyMatrix4(m)
    local tip = Vector3:new():addVectors(self.origin, self.direction):applyMatrix4(m)

    self.origin:applyMatrix4(m)
    self.direction:subVectors(tip, self.origin):normalizeSelf()

    return self
end

function Ray:intersectSphere(sphere, target)
    local oc = Vector3:new():subVectors(sphere.center, self.origin)
    local tca = oc:dot(self.direction)
    local d2 = oc:lengthSq() - tca * tca
    local r2 = sphere.radius * sphere.radius

    if d2 > r2 then return nil end

    local thc = math.sqrt(r2 - d2)
    local t0, t1 = tca - thc, tca + thc

    -- both behind the origin means the sphere is entirely behind the ray
    if t1 < 0 then return nil end

    return self:at(t0 < 0 and t1 or t0, target or Vector3:new())
end

function Ray:intersectsSphere(sphere)
    return sphere.center:distanceToSquared(self.origin) <= sphere.radius * sphere.radius
        or self:distanceSqToPoint(sphere.center) <= sphere.radius * sphere.radius
end

function Ray:distanceToPlane(plane)
    local denom = plane.normal:dot(self.direction)

    if denom == 0 then
        -- parallel; only a hit if the origin already lies in the plane, and
        -- then the whole ray does, so distance zero is the useful answer
        if plane:distanceToPoint(self.origin) == 0 then return 0 end
        return nil
    end

    local t = -(self.origin:dot(plane.normal) + plane.constant) / denom
    if t < 0 then return nil end
    return t
end

function Ray:intersectPlane(plane, target)
    local t = self:distanceToPlane(plane)
    if t == nil then return nil end
    return self:at(t, target or Vector3:new())
end

function Ray:intersectsPlane(plane)
    return self:distanceToPlane(plane) ~= nil
end

-- Slab test: clip the ray against each pair of parallel box faces in turn and
-- keep the surviving interval.
function Ray:intersectBox(box, target)
    local o, d = self.origin, self.direction
    local tmin, tmax = -math.huge, math.huge

    local mins = { box.min.x, box.min.y, box.min.z }
    local maxs = { box.max.x, box.max.y, box.max.z }
    local os   = { o.x, o.y, o.z }
    local ds   = { d.x, d.y, d.z }

    for i = 1, 3 do
        if ds[i] == 0 then
            -- parallel to this slab: a miss unless the origin is between it
            if os[i] < mins[i] or os[i] > maxs[i] then return nil end
        else
            local inv = 1 / ds[i]
            local t1 = (mins[i] - os[i]) * inv
            local t2 = (maxs[i] - os[i]) * inv
            if t1 > t2 then t1, t2 = t2, t1 end

            if t1 > tmin then tmin = t1 end
            if t2 < tmax then tmax = t2 end
            if tmax < tmin then return nil end
        end
    end

    if tmax < 0 then return nil end

    return self:at(tmin >= 0 and tmin or tmax, target or Vector3:new())
end

function Ray:intersectsBox(box)
    return self:intersectBox(box, Vector3:new()) ~= nil
end

-- Moeller-Trumbore. `backfaceCulling` drops triangles whose winding faces away,
-- which is what a pick against solid geometry usually wants.
function Ray:intersectTriangle(a, b, c, backfaceCulling, target)
    local edge1 = Vector3:new():subVectors(b, a)
    local edge2 = Vector3:new():subVectors(c, a)
    local pvec  = Vector3:new():crossVectors(self.direction, edge2)

    local det = edge1:dot(pvec)

    if backfaceCulling then
        if det < 1e-12 then return nil end
    elseif math.abs(det) < 1e-12 then
        return nil
    end

    local invDet = 1 / det
    local tvec = Vector3:new():subVectors(self.origin, a)

    local u = tvec:dot(pvec) * invDet
    if u < 0 or u > 1 then return nil end

    local qvec = Vector3:new():crossVectors(tvec, edge1)
    local v = self.direction:dot(qvec) * invDet
    if v < 0 or u + v > 1 then return nil end

    local t = edge2:dot(qvec) * invDet
    if t < 0 then return nil end

    return self:at(t, target or Vector3:new())
end

function Ray:equals(ray)
    return self.origin:equals(ray.origin) and self.direction:equals(ray.direction)
end

function Ray:__tostring()
    return string.format("Ray(%s -> %s)", tostring(self.origin), tostring(self.direction))
end

return Ray
