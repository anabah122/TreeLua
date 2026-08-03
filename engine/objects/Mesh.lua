-- three/objects/Mesh.lua — drawable geometry plus a material
--
--   local mesh = Mesh:new(geometry, material)
--   scene:add(mesh)
--
-- The importers already produce a `love.Mesh` per primitive, so geometry here
-- is a thin holder around that object rather than a vertex-buffer abstraction:
-- the engine's job is to hand it to love.graphics.draw with the right uniforms
-- set, which is what the renderer does by reading the fields below.
--
-- `skin` and `bindShapeMatrix` come straight off the importer entry. A mesh
-- carrying a skin is drawn with the bone palette; one without is drawn rigid.

local Object3D = require "engine.core.Object3D"

local Mesh = Object3D:extend("Mesh")

function Mesh:new(geometry, material)
    local m = Object3D.new(self)
    m.type = "Mesh"

    m.geometry = geometry
    m.material = material

    -- set by the loaders for skinned primitives; see SkinnedMesh
    m.skin            = nil
    m.bindShapeMatrix = nil

    return m
end

function Mesh:isMesh()
    return true
end

function Mesh:copy(source, recursive)
    Object3D.copy(self, source, recursive)
    -- geometry and material are shared, as in three.js: cloning a mesh gives a
    -- second transform over the same buffers, not a second copy of the data
    self.geometry        = source.geometry
    self.material        = source.material
    self.skin            = source.skin
    self.bindShapeMatrix = source.bindShapeMatrix
    return self
end

return Mesh
