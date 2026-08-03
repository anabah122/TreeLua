-- engine/collision/Octree.lua — static spatial hash broadphase
--
--   local octree = Octree:new(Box3:new(min, max), 4)  -- bounds, max depth
--   octree:add(collider)
--   local candidates = octree:query(box)
--
-- Same interface as FlatBroadphase, so World holds either behind one field
-- (composition, chosen at construction). Colliders are stored by bounding
-- box in the smallest node that fully contains them -- no rebalancing, so
-- this fits static/rarely-moving world geometry rather than a bag of
-- constantly-moving dynamic bodies.

local Box3 = require "engine.math.box3"

local Octree = {}
Octree.__index = Octree

local MAX_PER_LEAF = 8

function Octree:new(bounds, maxDepth, depth)
    return setmetatable({
        bounds     = bounds,
        maxDepth   = maxDepth or 4,
        depth      = depth or 0,
        colliders  = {},
        children   = nil,
    }, Octree)
end

function Octree:_split()
    local min, max = self.bounds.min, self.bounds.max
    local center = self.bounds:getCenter(require("engine.math.vec3"):new())

    self.children = {}
    for i = 0, 7 do
        local childMin = require("engine.math.vec3"):new(
            (i % 2 < 1) and min.x or center.x,
            (i % 4 < 2) and min.y or center.y,
            (i % 8 < 4) and min.z or center.z
        )
        local childMax = require("engine.math.vec3"):new(
            (i % 2 < 1) and center.x or max.x,
            (i % 4 < 2) and center.y or max.y,
            (i % 8 < 4) and center.z or max.z
        )
        self.children[i + 1] = Octree:new(Box3:new(childMin, childMax), self.maxDepth, self.depth + 1)
    end

    -- push existing colliders down where they fit
    local moved = self.colliders
    self.colliders = {}
    for _, collider in ipairs(moved) do
        self:add(collider)
    end
end

-- Child that fully contains the box, or nil if it straddles a boundary (or
-- there are no children yet).
function Octree:_childFor(box)
    if not self.children then return nil end
    for _, child in ipairs(self.children) do
        if child.bounds:containsBox(box) then return child end
    end
    return nil
end

function Octree:add(collider)
    local box = collider.getBoundingBox and collider:getBoundingBox() or collider

    if not self.children and self.depth < self.maxDepth and #self.colliders >= MAX_PER_LEAF then
        self:_split()
    end

    local child = self:_childFor(box)
    if child then
        child:add(collider)
    else
        self.colliders[#self.colliders + 1] = collider
    end
    return self
end

function Octree:remove(collider)
    for i, c in ipairs(self.colliders) do
        if c == collider then
            table.remove(self.colliders, i)
            return true
        end
    end
    if self.children then
        for _, child in ipairs(self.children) do
            if child:remove(collider) then return true end
        end
    end
    return false
end

function Octree:query(box, results)
    results = results or {}

    for _, collider in ipairs(self.colliders) do
        results[#results + 1] = collider
    end

    if self.children then
        for _, child in ipairs(self.children) do
            if child.bounds:intersectsBox(box) then
                child:query(box, results)
            end
        end
    end

    return results
end

return Octree
