-- three/objects/Skeleton.lua — joints plus their inverse bind matrices
--
-- In three.js a Skeleton holds an array of Bone objects. Here it wraps the
-- importer's flat node list and skin record instead, because that is what the
-- animation sampler writes into and what importer.common.palette reads. The
-- shape is:
--
--   nodes = { [i] = { name, parent, children, localMatrix, worldMatrix, ... } }
--   skin  = { joints = {node indices}, inverseBind = {mat4}, skeletonRoot }
--
-- Wrapping rather than converting keeps one source of truth: animation writes
-- to nodes, the palette reads from nodes, no copy in between to fall stale.

local Skeleton = {}
Skeleton.__index = Skeleton

function Skeleton:new(nodes, skin)
    return setmetatable({
        type  = "Skeleton",
        nodes = nodes,
        skin  = skin,
    }, Skeleton)
end

function Skeleton:isSkeleton()
    return true
end

function Skeleton:getBoneCount()
    return self.skin and #self.skin.joints or 0
end

-- three.js exposes bones by name; the node list is flat, so this is a scan.
function Skeleton:getBoneByName(name)
    for _, node in ipairs(self.nodes) do
        if node.name == name then return node end
    end
    return nil
end

-- Recompute every node's world matrix from its local one. The mixer calls this
-- after sampling; `root` seeds the roots so a model transform can be baked in.
function Skeleton:update(root)
    local common = require "engine.importer.common"
    common.update_world(self.nodes, root or self.nodes.rootMatrix)
    return self
end

function Skeleton:computeBoneMatrices()
    local common = require "engine.importer.common"
    if not self.skin then return nil end
    return common.palette(self.nodes, self.skin)
end

-- Deep-copy the "live" half only: node transforms/hierarchy, which is what an
-- AnimationMixer writes into every frame. `skin.inverseBind`/joints and the
-- mesh's geometry/material stay shared by reference, exactly like three.js's
-- SkeletonUtils.clone shares geometry while giving each instance its own
-- Bone objects. That split is what lets N animated instances of one model
-- exist without N re-parses of the source file.
function Skeleton:clone()
    local cloned = {}
    cloned.rootMatrix = self.nodes.rootMatrix

    for i, node in ipairs(self.nodes) do
        cloned[i] = {
            index       = node.index,
            name        = node.name,
            parent      = node.parent,
            children    = node.children,   -- hierarchy shape is static, shared
            mesh        = node.mesh,
            skin        = node.skin,
            hasMatrix   = node.hasMatrix,
            translation = node.translation and { node.translation[1], node.translation[2], node.translation[3] },
            rotation    = node.rotation    and { node.rotation[1], node.rotation[2], node.rotation[3], node.rotation[4] },
            scale       = node.scale       and { node.scale[1], node.scale[2], node.scale[3] },
            localMatrix = node.localMatrix and node.localMatrix:clone(),
            worldMatrix = node.worldMatrix and node.worldMatrix:clone(),
        }
    end

    return Skeleton:new(cloned, self.skin)
end

return Skeleton
