-- three/materials/MeshStandardMaterial.lua — PBR material
--
-- Named for the three.js class the glTF importer's output maps onto: glTF
-- materials are metallic-roughness, and so is this field set. The bundled
-- shader is Cook-Torrance, so every field here reaches it.

local Material = require "three.materials.Material"

local MeshStandardMaterial = Material:extend("MeshStandardMaterial")

function MeshStandardMaterial:new(params)
    params = params or {}
    local m = Material.new(self, params)
    m.type = "MeshStandardMaterial"

    m.roughnessMap = params.roughnessMap or nil
    m.metalnessMap = params.metalnessMap or nil
    m.emissiveMap  = params.emissiveMap or nil

    return m
end

function MeshStandardMaterial:copy(source)
    Material.copy(self, source)
    self.roughnessMap = source.roughnessMap
    self.metalnessMap = source.metalnessMap
    self.emissiveMap  = source.emissiveMap
    return self
end

-- Build one from an importer material record. Both importers emit the same
-- shape: { name, baseColor = {r,g,b,a}, texture, metallic, roughness, ... }.
function MeshStandardMaterial:fromImporter(mat)
    if not mat then return MeshStandardMaterial:new() end

    local bc = mat.baseColor or { 1, 1, 1, 1 }
    local mrMap = mat.metallicRoughnessTexture

    -- The factors only mean anything alongside a metallic-roughness map. With
    -- no map the surface is a plain matte dielectric, whatever numbers the
    -- exporter happened to leave behind -- Mixamo writes 0.5/0.5 into every
    -- material it touches, which would otherwise make skin half metal.
    local m = MeshStandardMaterial:new{
        name      = mat.name,
        opacity   = bc[4] or 1,
        map       = mat.texture,
        metalness = mrMap and mat.metallic or 0,
        roughness = mrMap and mat.roughness or 1,
    }
    m.color:setRGB(bc[1], bc[2], bc[3])

    if mat.emissive then
        m.emissive:setRGB(mat.emissive[1], mat.emissive[2], mat.emissive[3])
    end

    -- glTF packs metalness and roughness into one texture, so both fields
    -- point at it; the shader reads B and G respectively.
    m.metalnessMap = mrMap
    m.roughnessMap = mrMap
    m.emissiveMap  = mat.emissiveTexture

    m.normalMap   = mat.normalTexture
    m.normalScale = mat.normalScale or 1

    m.aoMap          = mat.occlusionTexture
    m.aoMapIntensity = mat.occlusionStrength or 1

    -- glTF alphaMode: BLEND means read opacity, MASK means cut out
    if mat.alphaMode == "BLEND" then
        m.transparent = true
    elseif mat.alphaMode == "MASK" then
        m.alphaTest = mat.alphaCutoff or 0.5
    end

    if mat.doubleSided then m.side = "double" end

    return m
end

return MeshStandardMaterial
