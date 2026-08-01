-- three/objects/SkinnedMesh.lua — a Mesh deformed by a skeleton
--
--   local mesh = SkinnedMesh:new(geometry, material)
--   mesh:bind(skeleton)
--
-- The palette maths lives in importer.common and is shared with the raw
-- importer path; this class only decides WHICH nodes to read and caches the
-- resulting matrices for the renderer.
--
-- One trap is baked into the engine and repeated here: the mesh node's own
-- transform is NOT cancelled out of the palette. Skinned vertices already sit
-- in skeleton space, so jointWorld * inverseBind places them correctly, and
-- folding in inverse(meshWorld) applies the node's scale a second time.

local Mesh    = require "three.objects.Mesh"
local common  = require "importer.common"
local Matrix4 = require "math.mat4"

local SkinnedMesh = Mesh:extend("SkinnedMesh")

function SkinnedMesh:new(geometry, material)
    local m = Mesh.new(self, geometry, material)
    m.type = "SkinnedMesh"

    m.skeleton        = nil
    m.bindMatrix      = nil
    m.bindMatrixInverse = nil

    return m
end

function SkinnedMesh:isSkinnedMesh()
    return true
end

function SkinnedMesh:bind(skeleton, bindMatrix)
    self.skeleton = skeleton
    if bindMatrix then
        self.bindMatrix        = bindMatrix
        self.bindMatrixInverse = bindMatrix:clone():invert()
    end
    return self
end

-- Bone matrices for this frame, or nil if the mesh turns out not to be skinned
-- after all. The skeleton owns the node list, so the palette follows whatever
-- the animation mixer last wrote into it.
function SkinnedMesh:palette()
    local sk = self.skeleton
    if not sk or not sk.skin then return nil end

    local pal = common.palette(sk.nodes, sk.skin)

    -- Collada puts the mesh into bind space with a separate matrix, which has
    -- to multiply on the right of every bone
    local bsm = self.bindShapeMatrix
    if bsm then
        for i, m in ipairs(pal) do
            pal[i] = Matrix4:new():mul(m, bsm)
        end
    end

    return pal
end

-- Cloning gives this mesh its OWN skeleton (deep-copied nodes), not a
-- reference to the source's -- otherwise every clone's AnimationMixer would
-- write into the same node list and their poses would fight each other.
-- Geometry/material/skin stay shared via Mesh.copy, as in three.js.
function SkinnedMesh:copy(source, recursive)
    Mesh.copy(self, source, recursive)
    self.skeleton          = source.skeleton and source.skeleton:clone()
    self.bindMatrix        = source.bindMatrix
    self.bindMatrixInverse = source.bindMatrixInverse
    return self
end

return SkinnedMesh
