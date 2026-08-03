-- engine/collision/FlatBroadphase.lua — no spatial structure, just a list
--
-- Default World broadphase: correct for small collider counts, O(n) per
-- query. Same interface as Octree so World can hold either behind one field.

local FlatBroadphase = {}
FlatBroadphase.__index = FlatBroadphase

function FlatBroadphase:new()
    return setmetatable({ colliders = {} }, FlatBroadphase)
end

function FlatBroadphase:add(collider)
    self.colliders[#self.colliders + 1] = collider
    return self
end

function FlatBroadphase:remove(collider)
    for i, c in ipairs(self.colliders) do
        if c == collider then
            table.remove(self.colliders, i)
            return self
        end
    end
    return self
end

-- Every collider whose bounding box overlaps `box`. No structure to prune
-- with, so this is just the whole list.
function FlatBroadphase:query(box)
    return self.colliders
end

return FlatBroadphase
