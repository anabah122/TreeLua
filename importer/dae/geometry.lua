-- dae/geometry.lua — <mesh> primitives -> de-indexed vertex/index arrays
--
--   geometry.build(root, geom_node, ctx, skin) -> { entry, ... }
--
-- The hard part is de-indexing. Collada addresses each attribute with its own
-- index, so one triangle corner may reference position 5, normal 12 and uv 3.
-- GPUs take a single index per vertex, so unique (p,n,uv) tuples are hashed
-- into fresh vertices and the triangle list is rewritten against them.

local xml     = require "importer.dae.xml"
local sources = require "importer.dae.sources"
local common  = require "importer.common"

local geometry = {}

geometry.FORMAT         = common.FORMAT
geometry.FORMAT_SKINNED = common.FORMAT_SKINNED

-- <polylist>/<polygons> may carry n-gons; fan-triangulate them
local function triangulate(p, stride, vcounts)
    local tris = {}
    if not vcounts then
        -- <triangles>: already 3 corners per face
        local corners = #p / stride
        for i = 0, corners - 1 do tris[#tris+1] = i end
        return tris
    end

    local corner = 0
    for _, n in ipairs(vcounts) do
        for k = 1, n - 2 do
            tris[#tris+1] = corner
            tris[#tris+1] = corner + k
            tris[#tris+1] = corner + k + 1
        end
        corner = corner + n
    end
    return tris
end

-- Build one drawable entry from a <triangles>/<polylist>/<polygons> element.
local function build_primitive(root, prim, ctx, skin, vertex_joints)
    local inputs, index_stride = sources.inputs(prim)
    if not inputs.VERTEX then return nil end

    local p_node = xml.find(prim, "p")
    if not p_node then return nil end
    local p = xml.numbers(p_node.text)
    if #p == 0 then return nil end

    local vcount_node = xml.find(prim, "vcount")
    local vcounts = vcount_node and xml.numbers(vcount_node.text) or nil
    local corners = triangulate(p, index_stride, vcounts)

    local pos_src = sources.read(root, inputs.VERTEX.source)
    if not pos_src then return nil end
    local nrm_src = inputs.NORMAL   and sources.read(root, inputs.NORMAL.source)
    local uv_src  = inputs.TEXCOORD and sources.read(root, inputs.TEXCOORD.source)

    local up = ctx.up_axis

    local entry = {
        vertices   = {},
        indices    = {},
        attributes = { position = true },
    }
    if nrm_src then entry.attributes.normal   = true end
    if uv_src  then entry.attributes.texcoord = true end

    local skinned = (skin ~= nil and vertex_joints ~= nil)
    if skinned then
        entry.skinned = true
        entry.attributes.joints  = true
        entry.attributes.weights = true
    end

    local pos_off = inputs.VERTEX.offset
    local nrm_off = inputs.NORMAL   and inputs.NORMAL.offset
    local uv_off  = inputs.TEXCOORD and inputs.TEXCOORD.offset

    local seen = {}      -- "pi/ni/ui" -> vertex number
    local nverts = 0

    for _, corner in ipairs(corners) do
        local base = corner * index_stride
        local pi = p[base + pos_off + 1] or 0
        local ni = nrm_off and (p[base + nrm_off + 1] or 0) or -1
        local ui = uv_off  and (p[base + uv_off  + 1] or 0) or -1

        local key = pi .. "/" .. ni .. "/" .. ui
        local vi = seen[key]

        if not vi then
            local ps = pos_src.stride
            local px = pos_src.data[pi*ps + 1] or 0
            local py = pos_src.data[pi*ps + 2] or 0
            local pz = pos_src.data[pi*ps + 3] or 0
            px, py, pz = sources.convert_up(up, px, py, pz)

            local nx, ny, nz = 0, 0, 0
            if nrm_src and ni >= 0 then
                local ns = nrm_src.stride
                nx = nrm_src.data[ni*ns + 1] or 0
                ny = nrm_src.data[ni*ns + 2] or 0
                nz = nrm_src.data[ni*ns + 3] or 0
                nx, ny, nz = sources.convert_up(up, nx, ny, nz)
            end

            local u, v = 0, 0
            if uv_src and ui >= 0 then
                local us = uv_src.stride
                u = uv_src.data[ui*us + 1] or 0
                v = uv_src.data[ui*us + 2] or 0
                -- collada's V runs bottom-up, love samples top-down
                v = 1 - v
            end

            nverts = nverts + 1
            vi = nverts

            if skinned then
                -- weights are indexed by the ORIGINAL position index, not the
                -- de-indexed vertex, so several vertices can share influences
                local inf = vertex_joints[pi + 1]
                local j, w
                if inf then
                    j, w = common.top4_weights(inf)
                else
                    j, w = {0,0,0,0}, {1,0,0,0}
                end
                -- component order must match common.FORMAT_SKINNED: pos, uv, normal
                entry.vertices[vi] = { px,py,pz, u,v, nx,ny,nz,
                                       j[1],j[2],j[3],j[4], w[1],w[2],w[3],w[4] }
            else
                entry.vertices[vi] = { px,py,pz, u,v, nx,ny,nz }
            end

            seen[key] = vi
        end

        entry.indices[#entry.indices + 1] = vi
    end

    entry.material_symbol = prim.attr.material
    return entry
end

function geometry.build(root, geom_node, ctx, skin, vertex_joints)
    local mesh = xml.find(geom_node, "mesh")
    if not mesh then return {} end

    local out = {}
    for _, tag in ipairs({ "triangles", "polylist", "polygons", "tristrips", "trifans" }) do
        for _, prim in ipairs(xml.findall(mesh, tag)) do
            -- strips/fans are rare; treated as triangle soup, which is correct
            -- only when the exporter wrote them as such. Blender never does.
            local entry = build_primitive(root, prim, ctx, skin, vertex_joints)
            if entry then
                entry.name = geom_node.attr.name or geom_node.attr.id or "mesh"
                out[#out + 1] = entry
            end
        end
    end
    return out
end

function geometry.to_mesh(entry, usage)
    usage = usage or "static"
    local fmt = entry.skinned and common.FORMAT_SKINNED or common.FORMAT
    local m = love.graphics.newMesh(fmt, entry.vertices, "triangles", usage)
    if entry.indices and #entry.indices > 0 then
        m:setVertexMap(entry.indices)
    end
    return m
end

return geometry
