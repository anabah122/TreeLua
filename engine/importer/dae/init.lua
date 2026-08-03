-- dae/init.lua — Collada (.dae) loader (entry point)
--
--   local dae = require "engine.importer.dae"
--   local model = dae:load{ path = "assets/hero.dae", mesh = true, tex = true }
--
-- Public API is always called with ':' so a method reads differently from a
-- field at the callsite. Module-level entry points ignore the self they get.
--
-- args match the glTF loader exactly:
--   path, mesh, tex, transform, anisotropy
--
-- The returned structure is identical to importer.gltf, so both formats feed
-- the same rendering and animation code:
--   model[i]         : primitives (vertices, indices, material, mesh, skin...)
--   model.nodes      : node hierarchy
--   model.skins      : skin definitions
--   model.animations : clips
--   model.scene      : root node indices

local xml      = require "engine.importer.dae.xml"
local sources  = require "engine.importer.dae.sources"
local geometry = require "engine.importer.dae.geometry"
local material = require "engine.importer.dae.material"
local skeleton = require "engine.importer.dae.skeleton"
local animation= require "engine.importer.dae.animation"
local common   = require "engine.importer.common"

local dae = {}

dae.xml       = xml
dae.sources   = sources
dae.geometry  = geometry
dae.material  = material
dae.skeleton  = skeleton
dae.animation = animation

local function read_file(path)
    local data = love.filesystem.read(path)
    if data then return data end
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

function dae:load(args)
    assert(args and args.path, "dae:load requires args.path")

    local path       = args.path
    local withMesh   = args.mesh or false
    local withTex    = args.tex  or false
    local anisotropy = args.anisotropy or 1
    local withTransform = args.transform ~= false

    local root = xml.parse(read_file(path))
    assert(root and root.name == "COLLADA", "not a COLLADA file")

    local ctx = {
        path       = path,
        withTex    = withTex,
        anisotropy = anisotropy,
        up_axis    = sources.up_axis(root),
        unit_scale = sources.unit_scale(root),
    }

    -- ── hierarchy ────────────────────────────────────────────────────────────
    local nodes = skeleton.build_nodes(root, ctx)
    common.update_world(nodes, nodes.rootMatrix)

    -- ── geometry + controllers ───────────────────────────────────────────────
    local controllers = skeleton.controllers(root)
    local geom_lib = xml.deep(root, "library_geometries")

    local by_geom_id = {}
    for _, g in ipairs(geom_lib and xml.findall(geom_lib, "geometry") or {}) do
        if g.attr.id then by_geom_id[g.attr.id] = g end
    end

    local result = {}
    local skins  = {}

    -- Each node that instantiates geometry (directly or through a controller)
    -- becomes one or more drawable entries.
    for node_idx, node in ipairs(nodes) do
        local geom_url, skin, vertex_joints

        if node.controller then
            local ctrl = controllers[node.controller:gsub("^#", "")]
            if ctrl then
                skin, vertex_joints = skeleton.build_skin(root, ctrl, nodes)
                if skin then
                    geom_url = skin.source
                    skins[#skins + 1] = skin
                    skin.index = #skins
                end
            end
        elseif node.geometry then
            geom_url = node.geometry
        end

        if geom_url then
            local geom_node = by_geom_id[geom_url:gsub("^#", "")]
            if geom_node then
                local entries = geometry.build(root, geom_node, ctx, skin, vertex_joints)

                for _, entry in ipairs(entries) do
                    entry.node = node_idx
                    entry.skin = skin

                    if withTransform then
                        entry.transform = node.worldMatrix
                        -- bind_shape_matrix belongs between the mesh and the
                        -- skeleton; only skinned meshes carry one
                        if skin and skin.bindShapeMatrix then
                            entry.bindShapeMatrix = skin.bindShapeMatrix
                        end
                    end

                    -- resolve the primitive's material symbol via bind_material
                    local target = node.materialBindings
                        and entry.material_symbol
                        and node.materialBindings[entry.material_symbol]
                    if target then
                        entry.material = material.build(root, target, ctx)
                    end

                    if withMesh then
                        entry.mesh = geometry.to_mesh(entry)
                        local tex = entry.material and entry.material.texture
                        if tex then entry.mesh:setTexture(tex) end
                    end

                    result[#result + 1] = entry
                end
            end
        end
    end

    -- ── model-level data ─────────────────────────────────────────────────────
    result.nodes      = nodes
    result.skins      = skins
    result.animations = animation.build(root, nodes)
    result.upAxis     = ctx.up_axis
    result.xml        = root

    result.scene = {}
    for i, node in ipairs(nodes) do
        if node.parent == nil then result.scene[#result.scene + 1] = i end
    end

    return result
end

function dae:toMesh(entry, usage)
    return geometry.to_mesh(entry, usage)
end

return dae
