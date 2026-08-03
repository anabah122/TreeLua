-- math/frustum.lua — the six planes bounding a camera's view
--
--   local f = Frustum:new():setFromProjectionMatrix(viewProj)
--   if f:intersectsObject(mesh) then ... end
--
-- Planes face inward, so a point inside has a positive distance to all six and
-- a single negative distance is enough to reject.

local Plane   = require "engine.math.plane"
local Vector3 = require "engine.math.vec3"
local Sphere  = require "engine.math.sphere"

local Frustum = {}
Frustum.__index = Frustum

function Frustum:new(...)
    local planes = { ... }
    for i = 1, 6 do planes[i] = planes[i] or Plane:new() end
    return setmetatable({ type = "Frustum", planes = planes }, Frustum)
end

function Frustum:isFrustum()
    return true
end

function Frustum:set(p0, p1, p2, p3, p4, p5)
    local p = { p0, p1, p2, p3, p4, p5 }
    for i = 1, 6 do self.planes[i]:copy(p[i]) end
    return self
end

function Frustum:clone()
    return Frustum:new():copy(self)
end

function Frustum:copy(frustum)
    for i = 1, 6 do self.planes[i]:copy(frustum.planes[i]) end
    return self
end

-- Gribb-Hartmann: each plane is a sum or difference of two rows of the
-- view-projection matrix, normalised so the plane equation gives a true signed
-- distance rather than one proportional to it.
--
-- The engine's Matrix4 is row-major, so m[1..4] is row 1 and m[13..16] row 4.
function Frustum:setFromProjectionMatrix(m)
    local r1 = { m[1],  m[2],  m[3],  m[4]  }
    local r2 = { m[5],  m[6],  m[7],  m[8]  }
    local r3 = { m[9],  m[10], m[11], m[12] }
    local r4 = { m[13], m[14], m[15], m[16] }

    local function setPlane(idx, a, b, sign)
        self.planes[idx]:setComponents(
            a[1] + sign * b[1],
            a[2] + sign * b[2],
            a[3] + sign * b[3],
            a[4] + sign * b[4]
        ):normalizeSelf()
    end

    setPlane(1, r4, r1,  1)   -- left
    setPlane(2, r4, r1, -1)   -- right
    setPlane(3, r4, r2,  1)   -- bottom
    setPlane(4, r4, r2, -1)   -- top
    setPlane(5, r4, r3,  1)   -- near
    setPlane(6, r4, r3, -1)   -- far

    return self
end

function Frustum:containsPoint(point)
    for i = 1, 6 do
        if self.planes[i]:distanceToPoint(point) < 0 then return false end
    end
    return true
end

function Frustum:intersectsSphere(sphere)
    local r = -sphere.radius
    for i = 1, 6 do
        if self.planes[i]:distanceToPoint(sphere.center) < r then return false end
    end
    return true
end

-- Test the box corner furthest along each plane's normal: if even that one is
-- outside, the whole box is.
function Frustum:intersectsBox(box)
    local v = Vector3:new()

    for i = 1, 6 do
        local n = self.planes[i].normal
        v:set(
            n.x > 0 and box.max.x or box.min.x,
            n.y > 0 and box.max.y or box.min.y,
            n.z > 0 and box.max.z or box.min.z
        )
        if self.planes[i]:distanceToPoint(v) < 0 then return false end
    end

    return true
end

-- A mesh's bounding sphere pushed into world space -- one dot product per
-- plane. A sphere is a loose fit for a long thin mesh, so this errs toward
-- accepting: a false positive costs a draw call, a false negative pops
-- geometry out of view.
function Frustum:intersectsObject(object)
    local geometry = object.geometry
    if not geometry then return false end

    local sphere = geometry.boundingSphere or geometry:computeBoundingSphere()
    if not sphere then return true end

    local world = Sphere:new(sphere.center, sphere.radius):applyMatrix4(object.matrixWorld)
    return self:intersectsSphere(world)
end

return Frustum
