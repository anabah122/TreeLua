-- engine/collision/World.lua — collision world, delegates broadphase by composition
--
--   local world = World:new()                          -- flat list (default)
--   local world = World:new{ broadphase = Octree:new(bounds) }
--
--   world:add(capsule)
--   local hit = world:testCapsule(playerCapsule)        -- first hit or nil
--   world:testCapsuleAll(playerCapsule, function(hit, collider) ... end)
--
-- Collider objects are anything with :getBoundingBox() and :intersects*(other)
-- -- Box3/Sphere/Capsule all already qualify. World does no resolution
-- (sliding, depenetration); it only answers "what do I overlap."

local FlatBroadphase = require "engine.collision.FlatBroadphase"

local World = {}
World.__index = World

function World:new(opts)
    opts = opts or {}
    return setmetatable({
        broadphase = opts.broadphase or FlatBroadphase:new(),
    }, World)
end

function World:add(collider)
    self.broadphase:add(collider)
    return self
end

function World:remove(collider)
    self.broadphase:remove(collider)
    return self
end

-- Dispatches to whichever intersects* method the shapes share, three.js-style
-- (Capsule:intersectsBox, Capsule:intersectsSphere, Capsule:intersectsCapsule,
-- Box3:intersectsSphere, ...). `.type` is "Box3"/"Sphere"/"Capsule" but the
-- method name three.js uses for the box case is just "Box", not "Box3".
local SHAPE_NAME = {
    Box3 = "Box", Sphere = "Sphere", Capsule = "Capsule",
    MeshCollider = "MeshCollider", Heightfield = "Heightfield",
}

local function testShapes(a, b)
    local method = "intersects" .. SHAPE_NAME[b.type]
    if a[method] then return a[method](a, b) end

    method = "intersects" .. SHAPE_NAME[a.type]
    if b[method] then
        return b[method](b, a)
    end

    error(("no intersects test between %s and %s"):format(a.type, b.type))
end

-- First overlapping collider, or nil. Returns the hit-info table (or `true`
-- for boolean-only tests) plus the collider it came from.
function World:testCapsule(capsule)
    local box = capsule:getBoundingBox()
    for _, collider in ipairs(self.broadphase:query(box)) do
        local hit = testShapes(capsule, collider)
        if hit then return hit, collider end
    end
    return nil
end

-- Every overlap, calling `callback(hit, collider)` for each.
function World:testCapsuleAll(capsule, callback)
    local box = capsule:getBoundingBox()
    for _, collider in ipairs(self.broadphase:query(box)) do
        local hit = testShapes(capsule, collider)
        if hit then callback(hit, collider) end
    end
end

return World
