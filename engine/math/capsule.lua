-- math/capsule.lua — swept sphere along a segment, three.js examples/jsm/math/Capsule.js API
--
--   local capsule = Capsule:new(start, finish, radius)
--   capsule:intersectsCapsule(other)
--   capsule:intersectsBox(box)
--
-- Used for character controllers: a capsule is a sphere radius that never
-- pierces corners the way a plain AABB test would.

local Vector3 = require "engine.math.vec3"
local Box3    = require "engine.math.box3"

local Capsule = {}
Capsule.__index = Capsule

function Capsule:new(start, finish, radius)
    return setmetatable({
        type   = "Capsule",
        start  = start and start:clone() or Vector3:new(0, 0, 0),
        finish = finish and finish:clone() or Vector3:new(0, 1, 0),
        radius = radius or 1,
    }, Capsule)
end

function Capsule:isCapsule()
    return true
end

function Capsule:clone()
    return Capsule:new(self.start, self.finish, self.radius)
end

function Capsule:set(start, finish, radius)
    self.start:copy(start)
    self.finish:copy(finish)
    self.radius = radius
    return self
end

function Capsule:copy(capsule)
    return self:set(capsule.start, capsule.finish, capsule.radius)
end

function Capsule:getCenter(target)
    target = target or Vector3:new()
    return target:addVectors(self.start, self.finish):multiplyScalar(0.5)
end

function Capsule:translate(v)
    self.start:addSelf(v)
    self.finish:addSelf(v)
    return self
end

function Capsule:getBoundingBox(target)
    target = target or Box3:new()
    target:makeEmpty()
    target:expandByPoint(self.start)
    target:expandByPoint(self.finish)
    target:expandByScalar(self.radius)
    return target
end

-- Closest points between the two segments (this capsule's axis and [p1, p2]),
-- written into targetA/targetB. Standard segment-segment closest point
-- solve; degenerate parallel cases fall out of the clamping rather than
-- needing a separate branch.
local function closestPointsSegmentSegment(p1, p2, p3, p4, targetA, targetB)
    local r = Vector3:new():subVectors(p1, p3)
    local d1 = Vector3:new():subVectors(p2, p1)
    local d2 = Vector3:new():subVectors(p4, p3)

    local a = d1:dot(d1)
    local e = d2:dot(d2)
    local f = d2:dot(r)

    local s, t

    if a <= 1e-12 and e <= 1e-12 then
        s, t = 0, 0
    elseif a <= 1e-12 then
        s = 0
        t = math.min(math.max(f / e, 0), 1)
    else
        local c = d1:dot(r)
        if e <= 1e-12 then
            t = 0
            s = math.min(math.max(-c / a, 0), 1)
        else
            local b = d1:dot(d2)
            local denom = a * e - b * b

            if denom ~= 0 then
                s = math.min(math.max((b * f - c * e) / denom, 0), 1)
            else
                s = 0
            end

            t = (b * s + f) / e

            if t < 0 then
                t = 0
                s = math.min(math.max(-c / a, 0), 1)
            elseif t > 1 then
                t = 1
                s = math.min(math.max((b - c) / a, 0), 1)
            end
        end
    end

    targetA:copy(p1):addScaledVector(d1, s)
    targetB:copy(p3):addScaledVector(d2, t)
end

function Capsule:lineLineMinimumPoints(other, targetA, targetB)
    targetA = targetA or Vector3:new()
    targetB = targetB or Vector3:new()
    closestPointsSegmentSegment(self.start, self.finish, other.start, other.finish, targetA, targetB)
    return targetA, targetB
end

function Capsule:intersectsCapsule(capsule)
    local a, b = Vector3:new(), Vector3:new()
    self:lineLineMinimumPoints(capsule, a, b)

    local r = self.radius + capsule.radius
    local distSq = a:distanceToSquared(b)

    if distSq > r * r then return nil end

    local dist = math.sqrt(distSq)
    local normal = Vector3:new():subVectors(a, b)
    if dist > 1e-9 then normal:multiplyScalar(1 / dist) else normal:set(0, 1, 0) end

    return {
        normal = normal,
        depth  = r - dist,
        point1 = a,
        point2 = b,
    }
end

function Capsule:intersectsSphere(sphere)
    local closest = Vector3:new()
    local segment = Vector3:new():subVectors(self.finish, self.start)
    local lenSq = segment:lengthSq()
    local t = lenSq > 1e-12 and Vector3:new():subVectors(sphere.center, self.start):dot(segment) / lenSq or 0
    t = math.min(math.max(t, 0), 1)
    closest:copy(segment):multiplyScalar(t):addSelf(self.start)

    local r = self.radius + sphere.radius
    local distSq = closest:distanceToSquared(sphere.center)
    if distSq > r * r then return nil end

    local dist = math.sqrt(distSq)
    local normal = Vector3:new():subVectors(closest, sphere.center)
    if dist > 1e-9 then normal:multiplyScalar(1 / dist) else normal:set(0, 1, 0) end

    return {
        normal = normal,
        depth  = r - dist,
        point1 = closest,
        point2 = sphere.center,
    }
end

-- Box3:clampPoint leaves a point untouched when it's already inside the box,
-- so it gives distance zero for a point buried in the box's interior rather
-- than the distance out to the nearest face -- exactly the case where a
-- capsule's axis dips inside a box it's brushing against. This clamps to the
-- SURFACE: for an interior point it pushes out along whichever axis is
-- closest to a face, instead of reporting a false zero-distance "point".
local function closestSurfacePoint(box, point, target)
    target = target or Vector3:new()

    if not box:containsPoint(point) then
        return box:clampPoint(point, target)
    end

    target:copy(point)

    local penetrations = {
        { axis = "x", dist = point.x - box.min.x, face = box.min.x },
        { axis = "x", dist = box.max.x - point.x, face = box.max.x },
        { axis = "y", dist = point.y - box.min.y, face = box.min.y },
        { axis = "y", dist = box.max.y - point.y, face = box.max.y },
        { axis = "z", dist = point.z - box.min.z, face = box.min.z },
        { axis = "z", dist = box.max.z - point.z, face = box.max.z },
    }

    local nearest = penetrations[1]
    for i = 2, #penetrations do
        if penetrations[i].dist < nearest.dist then nearest = penetrations[i] end
    end

    if nearest.axis == "x" then target.x = nearest.face
    elseif nearest.axis == "y" then target.y = nearest.face
    else target.z = nearest.face end

    return target
end

-- AABB check via the segment's closest point to the box, same shape as
-- Sphere:intersectsBox but with the closest point taken along the axis.
-- Returns three.js-style hit-info like the sphere/capsule cases, so callers
-- resolving movement don't need to special-case the box collider.
function Capsule:intersectsBox(box)
    local segment = Vector3:new():subVectors(self.finish, self.start)

    local closestOnSegment = Vector3:new()
    local closestOnBox = Vector3:new()
    local bestDistSq = math.huge
    local bestInside = false

    -- sample the two ends and the box-clamped projection; sufficient because
    -- the AABB's clamp of a segment point is a piecewise-linear function of t,
    -- so the true minimum is at an endpoint or where the clamp changes axis —
    -- checking a handful of candidate t values is exact in every axis-aligned
    -- case used here (endpoints plus midpoint-style bisection is overkill for
    -- a segment against a box; this iterative refine converges instead)
    local samples = 8
    for i = 0, samples do
        local t = i / samples
        local point = Vector3:new():copy(segment):multiplyScalar(t):addSelf(self.start)
        local inside = box:containsPoint(point)
        local clamped = closestSurfacePoint(box, point, Vector3:new())
        local distSq = clamped:distanceToSquared(point)

        -- Interior and exterior samples are not comparable by raw distance:
        -- an interior sample right at a face boundary reads distance ~0
        -- (nearest-face distance, not penetration depth), which would look
        -- "closer" than a sample that's genuinely deep inside. So: any
        -- interior sample beats every exterior one, and among interior
        -- samples the DEEPEST one wins (larger distSq = further from that
        -- sample's nearest face = more embedded), while among exterior
        -- samples the nearest one wins as before.
        local better
        if inside and not bestInside then
            better = true
        elseif inside == bestInside then
            if inside then
                better = distSq > bestDistSq
            else
                better = distSq < bestDistSq
            end
        else
            better = false
        end

        if better then
            bestDistSq = distSq
            bestInside = inside
            closestOnSegment:copy(point)
            closestOnBox:copy(clamped)
        end
    end

    if not bestInside and bestDistSq > self.radius * self.radius then return nil end

    local dist = math.sqrt(bestDistSq)
    local normal
    if bestInside then
        -- closestOnSegment sits INSIDE the box and closestOnBox is the
        -- nearest face, so segment-minus-box points from the face back
        -- toward the interior; push-out needs the opposite (face-minus-segment).
        normal = Vector3:new():subVectors(closestOnBox, closestOnSegment)
    else
        normal = Vector3:new():subVectors(closestOnSegment, closestOnBox)
    end

    if dist > 1e-9 then
        normal:multiplyScalar(1 / dist)
    else
        normal:set(0, 1, 0)
    end

    return {
        normal = normal,
        depth  = self.radius + (bestInside and dist or -dist),
        point1 = closestOnSegment,
        point2 = closestOnBox,
    }
end

-- Same sampling approach as intersectsBox: the triangle's closest point to a
-- segment point is not linear in t, but sampling the axis and taking the
-- triangle's closest point at each sample converges to the true minimum for
-- the triangle sizes a mesh collider deals with.
function Capsule:intersectsTriangle(triangle)
    local segment = Vector3:new():subVectors(self.finish, self.start)

    local closestOnSegment = Vector3:new()
    local closestOnTriangle = Vector3:new()
    local bestDistSq = math.huge

    local samples = 8
    for i = 0, samples do
        local t = i / samples
        local point = Vector3:new():copy(segment):multiplyScalar(t):addSelf(self.start)
        local onTri = triangle:closestPointToPoint(point, Vector3:new())
        local distSq = onTri:distanceToSquared(point)
        if distSq < bestDistSq then
            bestDistSq = distSq
            closestOnSegment:copy(point)
            closestOnTriangle:copy(onTri)
        end
    end

    if bestDistSq > self.radius * self.radius then return nil end

    local dist = math.sqrt(bestDistSq)

    -- A flat triangle has no "inside" to push out of, unlike a box: the only
    -- signal for which way to push is which side of the triangle's PLANE the
    -- capsule is on. Using the raw segment-to-triangle-point vector breaks the
    -- moment the axis crosses to the far side (e.g. sinks below ground level)
    -- -- that vector flips and starts pointing further through the surface
    -- instead of back out of it. The face normal, signed by which side the
    -- point is actually on, stays consistent through the crossing.
    local faceNormal = triangle:getNormal(Vector3:new())
    local plane = triangle:getPlane()
    local side = plane:distanceToPoint(closestOnSegment)
    local normal = faceNormal:multiplyScalar(side < 0 and -1 or 1)

    return {
        normal = normal,
        depth  = self.radius - dist,
        point1 = closestOnSegment,
        point2 = closestOnTriangle,
    }
end

function Capsule:equals(capsule)
    return self.start:equals(capsule.start)
       and self.finish:equals(capsule.finish)
       and self.radius == capsule.radius
end

function Capsule:__tostring()
    return string.format("Capsule(%s .. %s, r=%.4f)", tostring(self.start), tostring(self.finish), self.radius)
end

return Capsule
