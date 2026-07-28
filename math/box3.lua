-- math/box3.lua — axis-aligned bounding box
--
--   local box = Box3:new():setFromObject(model)
--   local size = box:getSize()
--
-- Mutating throughout, like the rest of the three.js-facing surface. An empty
-- box is min = +inf, max = -inf, so `expandByPoint` on a fresh box just works
-- and `isEmpty` is a plain comparison rather than a flag to keep in sync.

local Vector3 = require "math.vec3"

local Box3 = {}
Box3.__index = Box3

function Box3:new(min, max)
    return setmetatable({
        type = "Box3",
        min = min and min:clone() or Vector3:new( math.huge,  math.huge,  math.huge),
        max = max and max:clone() or Vector3:new(-math.huge, -math.huge, -math.huge),
    }, Box3)
end

function Box3:isBox3()
    return true
end

function Box3:set(min, max)
    self.min:copy(min)
    self.max:copy(max)
    return self
end

function Box3:clone()
    return Box3:new(self.min, self.max)
end

function Box3:copy(box)
    return self:set(box.min, box.max)
end

function Box3:makeEmpty()
    self.min:set( math.huge,  math.huge,  math.huge)
    self.max:set(-math.huge, -math.huge, -math.huge)
    return self
end

function Box3:isEmpty()
    return self.max.x < self.min.x
        or self.max.y < self.min.y
        or self.max.z < self.min.z
end

function Box3:getCenter(target)
    target = target or Vector3:new()
    if self:isEmpty() then return target:set(0, 0, 0) end
    return target:addVectors(self.min, self.max):multiplyScalar(0.5)
end

function Box3:getSize(target)
    target = target or Vector3:new()
    if self:isEmpty() then return target:set(0, 0, 0) end
    return target:subVectors(self.max, self.min)
end

function Box3:expandByPoint(point)
    self.min:minSelf(point)
    self.max:maxSelf(point)
    return self
end

function Box3:expandByScalar(scalar)
    self.min:addScalar(-scalar)
    self.max:addScalar(scalar)
    return self
end

function Box3:expandByVector(v)
    self.min:subV(v)
    self.max:addV(v)
    return self
end

function Box3:union(box)
    self.min:minSelf(box.min)
    self.max:maxSelf(box.max)
    return self
end

function Box3:containsPoint(point)
    return point.x >= self.min.x and point.x <= self.max.x
       and point.y >= self.min.y and point.y <= self.max.y
       and point.z >= self.min.z and point.z <= self.max.z
end

function Box3:containsBox(box)
    return self.min.x <= box.min.x and box.max.x <= self.max.x
       and self.min.y <= box.min.y and box.max.y <= self.max.y
       and self.min.z <= box.min.z and box.max.z <= self.max.z
end

function Box3:intersectsBox(box)
    return box.max.x >= self.min.x and box.min.x <= self.max.x
       and box.max.y >= self.min.y and box.min.y <= self.max.y
       and box.max.z >= self.min.z and box.min.z <= self.max.z
end

function Box3:clampPoint(point, target)
    target = target or Vector3:new()
    return target:copy(point):clampSelf(self.min, self.max)
end

function Box3:distanceToPoint(point)
    local clamped = self:clampPoint(point, Vector3:new())
    return clamped:subV(point):length()
end

function Box3:setFromPoints(points)
    self:makeEmpty()
    for _, p in ipairs(points) do self:expandByPoint(p) end
    return self
end

-- Build from raw vertex tables, which is how the geometry generators and the
-- importers both store positions: { x, y, z, u, v, nx, ny, nz }.
function Box3:setFromVertices(vertices)
    self:makeEmpty()
    for _, v in ipairs(vertices) do
        if v[1] < self.min.x then self.min.x = v[1] end
        if v[2] < self.min.y then self.min.y = v[2] end
        if v[3] < self.min.z then self.min.z = v[3] end
        if v[1] > self.max.x then self.max.x = v[1] end
        if v[2] > self.max.y then self.max.y = v[2] end
        if v[3] > self.max.z then self.max.z = v[3] end
    end
    return self
end

-- Bounds of an object and everything under it, in world space.
--
-- Every corner of each mesh's local box is transformed rather than the box
-- itself: a rotated box's transformed min/max is NOT the min/max of the
-- transformed corners, and using it would undersize the result.
function Box3:setFromObject(object)
    self:makeEmpty()

    object:updateWorldMatrix(false, true)

    local corner = Vector3:new()

    object:traverse(function(node)
        local geometry = node.geometry
        if not geometry then return end

        local box = geometry.boundingBox or geometry:computeBoundingBox()
        if not box then return end

        for i = 0, 7 do
            corner:set(
                (i % 2 < 1) and box.min.x or box.max.x,
                (i % 4 < 2) and box.min.y or box.max.y,
                (i % 8 < 4) and box.min.z or box.max.z
            )
            corner:applyMatrix4(node.matrixWorld)
            self:expandByPoint(corner)
        end
    end)

    return self
end

function Box3:equals(box)
    return self.min:equals(box.min) and self.max:equals(box.max)
end

function Box3:__tostring()
    return string.format("Box3(%s .. %s)", tostring(self.min), tostring(self.max))
end

return Box3
