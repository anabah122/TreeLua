-- gltf/skeleton.lua — node hierarchy, skins, bind matrices
--
-- skeleton.build_nodes(j)            -> flat node list with parent/children wired
-- skeleton.build_skin(j, bufs, idx)  -> { joints, inverseBind, skeletonRoot }
-- skeleton.compose(t, r, s)          -> mat4  (quaternion-aware TRS)
--
-- Node indices are kept 1-based internally; glTF's 0-based indices are
-- converted on entry so nothing downstream has to remember the offset.

local binary   = require "importer.gltf.binary"
local common   = require "importer.common"
local matClass = require "math.mat4"

local skeleton = {}

-- Quaternion-aware TRS composition, shared with the DAE importer.
-- (mat4:setTransformationMatrix() takes euler angles; glTF stores quaternions,
-- so composing through that path would silently produce wrong orientations.)
skeleton.compose = common.compose

-- ── nodes ────────────────────────────────────────────────────────────────────
-- Returns a flat array of nodes (1-based) with:
--   name, parent (index|nil), children {indices}, mesh, skin,
--   translation/rotation/scale, matrix (local), localMatrix
function skeleton.build_nodes(j)
    local nodes = {}

    for i, n in ipairs(j.nodes or {}) do
        local node = {
            index    = i,
            name     = n.name or ("node_"..i),
            children = {},
            parent   = nil,
            mesh     = n.mesh ~= nil and (n.mesh + 1) or nil,
            skin     = n.skin ~= nil and (n.skin + 1) or nil,
        }

        if n.matrix then
            -- glTF matrices are column-major; mat4.lua is row-major -> transpose
            local c = n.matrix
            local m = matClass:new()
            m[1],  m[2],  m[3],  m[4]  = c[1], c[5], c[9],  c[13]
            m[5],  m[6],  m[7],  m[8]  = c[2], c[6], c[10], c[14]
            m[9],  m[10], m[11], m[12] = c[3], c[7], c[11], c[15]
            m[13], m[14], m[15], m[16] = c[4], c[8], c[12], c[16]
            node.localMatrix = m
            node.hasMatrix   = true
        else
            node.translation = n.translation or {0,0,0}
            node.rotation    = n.rotation    or {0,0,0,1}
            node.scale       = n.scale       or {1,1,1}
            node.localMatrix = skeleton.compose(node.translation, node.rotation, node.scale)
        end

        nodes[i] = node
    end

    -- wire hierarchy (glTF child indices are 0-based)
    for i, n in ipairs(j.nodes or {}) do
        for _, c in ipairs(n.children or {}) do
            local child = nodes[c + 1]
            if child then
                child.parent = i
                table.insert(nodes[i].children, c + 1)
            end
        end
    end

    return nodes
end

-- Walk the hierarchy and fill node.worldMatrix.
-- Roots are seeded with `root` (or identity) so a model transform can be baked in.
skeleton.update_world = common.update_world

-- ── skins ────────────────────────────────────────────────────────────────────
-- skin.joints        : node indices (1-based), in bind order
-- skin.inverseBind   : mat4 per joint
-- skin.skeletonRoot  : node index (1-based) or nil
function skeleton.build_skin(j, buffers, skin_idx)
    local skin = (j.skins or {})[skin_idx]
    if not skin then return nil end

    local out = {
        name        = skin.name,
        joints      = {},
        inverseBind = {},
    }

    for k, node_idx in ipairs(skin.joints or {}) do
        out.joints[k] = node_idx + 1
    end

    if skin.skeleton ~= nil then
        out.skeletonRoot = skin.skeleton + 1
    end

    if skin.inverseBindMatrices ~= nil then
        local vals = binary.accessor_values(j, buffers, skin.inverseBindMatrices)
        for k = 1, #out.joints do
            local o = (k-1) * 16
            -- glTF stores these column-major -> transpose into row-major
            local m = matClass:new()
            m[1],  m[2],  m[3],  m[4]  = vals[o+1], vals[o+5], vals[o+9],  vals[o+13]
            m[5],  m[6],  m[7],  m[8]  = vals[o+2], vals[o+6], vals[o+10], vals[o+14]
            m[9],  m[10], m[11], m[12] = vals[o+3], vals[o+7], vals[o+11], vals[o+15]
            m[13], m[14], m[15], m[16] = vals[o+4], vals[o+8], vals[o+12], vals[o+16]
            out.inverseBind[k] = m
        end
    else
        -- spec allows omitting them; identity means bind pose is model space
        for k = 1, #out.joints do out.inverseBind[k] = matClass:new() end
    end

    return out
end

-- Per-frame skinning palette:  skinMatrix = jointWorld * inverseBind
-- Pass `meshWorldInverse` to cancel the mesh node's own transform (glTF requires
-- this when the skinned mesh node is not at the scene root).
skeleton.palette = common.palette

return skeleton
