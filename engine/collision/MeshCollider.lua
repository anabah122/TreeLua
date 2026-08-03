-- engine/collision/MeshCollider.lua — static triangle-soup collider
--
--   local collider = MeshCollider:new(mesh)   -- mesh: TL.Mesh, world-space triangles baked once
--   collider:getBoundingBox()
--   collider:intersectsCapsule(capsule)       -- first hit, or nil
--
-- Triangles are baked from geometry.vertices/indices at construction time
-- (matrixWorld applied once) -- fine for static level geometry; a moving mesh
-- needs a new MeshCollider or an explicit :rebuild().

local Vector3  = require "engine.math.vec3"
local Box3     = require "engine.math.box3"
local Triangle = require "engine.math.triangle"

local MeshCollider = {}
MeshCollider.__index = MeshCollider

function MeshCollider:new(mesh)
    local self = setmetatable({
        type       = "MeshCollider",
        triangles  = {},
        bounds     = Box3:new(),
    }, MeshCollider)

    self:rebuild(mesh)
    return self
end

function MeshCollider:rebuild(mesh)
    mesh:updateWorldMatrix(false, false)

    local geometry = mesh.geometry
    local vertices, indices = geometry.vertices, geometry.indices

    local positions = {}
    for i, v in ipairs(vertices) do
        positions[i] = Vector3:new(v[1], v[2], v[3]):applyMatrix4(mesh.matrixWorld)
    end

    self.triangles = {}
    self.bounds:makeEmpty()

    for i = 1, #indices, 3 do
        local a = positions[indices[i]]
        local b = positions[indices[i + 1]]
        local c = positions[indices[i + 2]]
        self.triangles[#self.triangles + 1] = Triangle:new(a, b, c)
        self.bounds:expandByPoint(a)
        self.bounds:expandByPoint(b)
        self.bounds:expandByPoint(c)
    end

    return self
end

function MeshCollider:getBoundingBox(target)
    target = target or Box3:new()
    return target:copy(self.bounds)
end

-- three.js-style dispatch name so World's testShapes(a, b) can call
-- capsule:intersectsMeshCollider or fall back to this side.
function MeshCollider:intersectsCapsule(capsule)
    if not capsule:getBoundingBox():intersectsBox(self.bounds) then return nil end

    for _, triangle in ipairs(self.triangles) do
        local hit = capsule:intersectsTriangle(triangle)
        if hit then return hit end
    end
    return nil
end

return MeshCollider
