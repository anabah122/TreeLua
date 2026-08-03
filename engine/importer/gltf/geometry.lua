-- gltf/geometry.lua — primitive attributes -> vertex/index arrays -> love.Mesh
--
-- geometry.build(j, buffers, prim) -> entry | nil
--   entry.vertices   : { {x,y,z, nx,ny,nz, u,v[, j1,j2,j3,j4, w1,w2,w3,w4]} }
--   entry.indices    : { int, 1-based } | nil
--   entry.attributes : presence flags
--   entry.skinned    : true when JOINTS_0 + WEIGHTS_0 present
--
-- geometry.to_mesh(entry, usage) -> love.Mesh

local binary = require "engine.importer.gltf.binary"
local common = require "engine.importer.common"

local geometry = {}

-- shared with the DAE importer so both formats feed the same shaders
geometry.FORMAT         = common.FORMAT
geometry.FORMAT_SKINNED = common.FORMAT_SKINNED

-- read an optional vec-N attribute, nil when absent
local function attr(j, buffers, attribs, name)
    local idx = attribs[name]
    if idx == nil then return nil end
    local raw, elems, ctype, count = binary.accessor(j, buffers, idx)
    if not raw then return nil end
    return binary.read(raw, ctype, count * elems), elems, count
end

function geometry.build(j, buffers, prim)
    local attribs = prim.attributes or {}

    -- positions are required; primitives without them are not geometry
    local positions, _, pos_count = attr(j, buffers, attribs, "POSITION")
    if not positions then return nil end

    local entry = {
        vertices   = {},
        indices    = nil,
        attributes = { position = true },
    }

    local normals = attr(j, buffers, attribs, "NORMAL")
    if normals then entry.attributes.normal = true end

    local uvs = attr(j, buffers, attribs, "TEXCOORD_0")
    if uvs then entry.attributes.texcoord = true end

    -- skinning attributes travel as a pair; one without the other is useless
    local joints  = attr(j, buffers, attribs, "JOINTS_0")
    local weights = attr(j, buffers, attribs, "WEIGHTS_0")
    local skinned = (joints ~= nil and weights ~= nil)
    if skinned then
        entry.attributes.joints  = true
        entry.attributes.weights = true
        entry.skinned = true
    end

    for vi = 0, pos_count - 1 do
        local px = positions[vi*3+1] or 0
        local py = positions[vi*3+2] or 0
        local pz = positions[vi*3+3] or 0
        local nx = normals and normals[vi*3+1] or 0
        local ny = normals and normals[vi*3+2] or 0
        local nz = normals and normals[vi*3+3] or 0
        local u  = uvs and uvs[vi*2+1] or 0
        local v  = uvs and uvs[vi*2+2] or 0

        if skinned then
            -- joint indices stay 0-based: the shader indexes a uniform array
            local j1 = joints[vi*4+1] or 0
            local j2 = joints[vi*4+2] or 0
            local j3 = joints[vi*4+3] or 0
            local j4 = joints[vi*4+4] or 0
            local w1 = weights[vi*4+1] or 0
            local w2 = weights[vi*4+2] or 0
            local w3 = weights[vi*4+3] or 0
            local w4 = weights[vi*4+4] or 0
            -- weights must sum to 1 or the mesh visibly shrinks toward origin
            local sum = w1 + w2 + w3 + w4
            if sum > 0 then
                w1, w2, w3, w4 = w1/sum, w2/sum, w3/sum, w4/sum
            end
            -- component order must match common.FORMAT_SKINNED: pos, uv, normal
            entry.vertices[vi+1] = { px,py,pz, u,v, nx,ny,nz, j1,j2,j3,j4, w1,w2,w3,w4 }
        else
            entry.vertices[vi+1] = { px,py,pz, u,v, nx,ny,nz }
        end
    end

    if prim.indices ~= nil then
        local raw, _, ctype, count = binary.accessor(j, buffers, prim.indices)
        if raw then
            entry.indices = binary.read_indices(raw, ctype, count)
        end
    end

    return entry
end

function geometry.to_mesh(entry, usage)
    usage = usage or "static"
    local fmt = entry.skinned and common.FORMAT_SKINNED or common.FORMAT
    local m = love.graphics.newMesh(fmt, entry.vertices, "triangles", usage)
    if entry.indices then
        m:setVertexMap(entry.indices)
    end
    return m
end

return geometry
