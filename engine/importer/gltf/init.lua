-- gltf/init.lua — glTF 2.0 / GLB loader (entry point)
--
--   local gltf = require "engine.importer.gltf"
--   local model = gltf:load{ path = "assets/hero.glb", mesh = true, tex = true }
--
-- Public API is always called with ':' so a method reads differently from a
-- field at the callsite. Module-level entry points ignore the self they get.
--
-- args:
--   path        : file path (.gltf or .glb)
--   mesh        : build love.Mesh objects            (default false)
--   tex         : load textures                      (default false)
--   transform   : bake node TRS into entry.transform (default true)
--   anisotropy  : texture anisotropy                 (default 1)
--
-- returns a flat array of primitives, plus model-level fields:
--   model.nodes      : node hierarchy (see skeleton.lua)
--   model.skins      : skin definitions
--   model.animations : animation clips
--   model.scene      : root node indices
--
-- each entry:
--   name, vertices, indices, attributes, trs, transform,
--   mesh, material, skinned, skin, node

local json     = require "engine.importer.gltf.json"
local binary   = require "engine.importer.gltf.binary"
local geometry = require "engine.importer.gltf.geometry"
local material = require "engine.importer.gltf.material"
local skeleton = require "engine.importer.gltf.skeleton"
local animation= require "engine.importer.gltf.animation"

local gltf = {}

-- re-export submodules so callers can reach the pieces directly
gltf.json      = json
gltf.binary    = binary
gltf.geometry  = geometry
gltf.material  = material
gltf.skeleton  = skeleton
gltf.animation = animation

function gltf:load(args)
    assert(args and args.path, "gltf:load requires args.path")

    local path       = args.path
    local withMesh   = args.mesh or false
    local withTex    = args.tex  or false
    local anisotropy = args.anisotropy or 1
    local withTransform = args.transform ~= false  -- default true

    local data = binary.read_file(path)

    local json_str, bin_embedded
    if data:sub(1,4) == "glTF" then
        json_str, bin_embedded = binary.parse_glb(data)
    else
        json_str = data
    end

    local j = json.decode(json_str)
    assert(j and j.asset and j.asset.version == "2.0", "not a glTF 2.0 file")

    local buffers = binary.load_buffers(j, path, bin_embedded)
    local ctx = { path = path, withTex = withTex, anisotropy = anisotropy }

    -- ── hierarchy ────────────────────────────────────────────────────────────
    local nodes = skeleton.build_nodes(j)
    skeleton.update_world(nodes)

    -- mesh index -> node that instantiates it (first wins; glTF allows reuse)
    local mesh_node = {}
    for i, node in ipairs(nodes) do
        if node.mesh and not mesh_node[node.mesh] then
            mesh_node[node.mesh] = i
        end
    end

    -- ── skins ────────────────────────────────────────────────────────────────
    local skins = {}
    for si = 1, #(j.skins or {}) do
        skins[si] = skeleton.build_skin(j, buffers, si)
    end

    -- ── primitives ───────────────────────────────────────────────────────────
    local result = {}

    for mesh_i, mesh_json in ipairs(j.meshes or {}) do
        local node_idx = mesh_node[mesh_i]
        local node     = node_idx and nodes[node_idx]

        for _, prim in ipairs(mesh_json.primitives or {}) do
            local entry = geometry.build(j, buffers, prim)

            -- primitives without POSITION are not drawable geometry
            if entry then
                entry.name = mesh_json.name or ("mesh_"..mesh_i)
                entry.node = node_idx

                if node then
                    entry.trs = node.hasMatrix
                        and { matrix = node.localMatrix }
                        or  { t = node.translation, r = node.rotation, s = node.scale }
                    if node.skin then
                        entry.skin = skins[node.skin]
                    end
                else
                    entry.trs = { t = {0,0,0}, r = {0,0,0,1}, s = {1,1,1} }
                end

                if withTransform then
                    entry.transform = node and node.worldMatrix
                        or skeleton.compose(entry.trs.t, entry.trs.r, entry.trs.s)
                end

                entry.material = material.build(j, buffers, prim.material, ctx)

                if withMesh then
                    entry.mesh = geometry.to_mesh(entry)
                    local tex = entry.material and entry.material.texture
                    if tex then entry.mesh:setTexture(tex) end
                end

                result[#result+1] = entry
            end
        end
    end

    -- ── model-level data ─────────────────────────────────────────────────────
    result.nodes      = nodes
    result.skins      = skins
    result.animations = animation.build(j, buffers)
    result.json       = j

    local scene = (j.scenes or {})[(j.scene or 0) + 1]
    if scene then
        result.scene = {}
        for _, n in ipairs(scene.nodes or {}) do
            result.scene[#result.scene+1] = n + 1
        end
    end

    return result
end

-- convenience passthrough, kept for compatibility with the old flat module
function gltf:toMesh(entry, usage)
    return geometry.to_mesh(entry, usage)
end

return gltf
