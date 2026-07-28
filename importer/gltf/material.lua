-- gltf/material.lua — material metadata + texture loading
--
-- material.build(j, buffers, mat_idx, ctx) -> {
--   name, baseColor, metallic, roughness, emissive, alphaMode, alphaCutoff,
--   doubleSided, texture, texturePath, normalTexture, ...
-- }
--
-- ctx = { path = <gltf path>, withTex = bool, anisotropy = n }

local binary = require "importer.gltf.binary"

local material = {}

local function dirname(path)
    return path:match("(.*[/\\])") or ""
end

-- load one glTF texture index -> love.Image (or nil)
local function load_texture(j, buffers, tex_idx, ctx)
    if tex_idx == nil then return nil, nil end

    local tex_json = (j.textures or {})[tex_idx + 1]
    if not (tex_json and tex_json.source ~= nil) then return nil, nil end

    local img_json = (j.images or {})[tex_json.source + 1]
    if not img_json then return nil, nil end

    local image, src_path

    if img_json.uri then
        if img_json.uri:sub(1,5) == "data:" then
            -- embedded base64 image
            local b64 = img_json.uri:match("base64,(.+)$")
            if not b64 then return nil, nil end
            local bytes = love.data.decode("string", "base64", b64)
            local fd = love.filesystem.newFileData(bytes, img_json.name or "tex")
            image = love.graphics.newImage(love.image.newImageData(fd), { mipmaps = true })
        else
            src_path = dirname(ctx.path) .. img_json.uri
            image = love.graphics.newImage(src_path, { mipmaps = true })
        end
    elseif img_json.bufferView ~= nil then
        local bytes = binary.bufferview_bytes(j, buffers, img_json.bufferView)
        if not bytes then return nil, nil end
        local fd = love.filesystem.newFileData(bytes, img_json.name or "tex")
        image = love.graphics.newImage(love.image.newImageData(fd), { mipmaps = true })
    end

    if image then
        image:setFilter("linear", "linear", ctx.anisotropy or 1)
    end
    return image, src_path
end

function material.build(j, buffers, mat_idx, ctx)
    if mat_idx == nil then return nil end
    local mat = (j.materials or {})[mat_idx + 1]
    if not mat then return nil end

    local pbr = mat.pbrMetallicRoughness or {}

    -- metallic/roughness stay nil when the file omits them, so the facade can
    -- tell an unauthored material from one that states a value. Substituting
    -- the spec default here would erase that distinction.
    local out = {
        name        = mat.name,
        baseColor   = pbr.baseColorFactor or {1,1,1,1},
        metallic    = pbr.metallicFactor,
        roughness   = pbr.roughnessFactor,
        emissive    = mat.emissiveFactor  or {0,0,0},
        alphaMode   = mat.alphaMode       or "OPAQUE",
        alphaCutoff = mat.alphaCutoff     or 0.5,
        doubleSided = mat.doubleSided     or false,
    }

    -- OPAQUE ignores alpha entirely (glTF spec). Exporters sometimes write a
    -- zero there anyway, and multiplying by it would erase the whole surface.
    if out.alphaMode == "OPAQUE" then
        out.baseColor[4] = 1
    end

    if not ctx.withTex then return out end

    -- base color
    if pbr.baseColorTexture then
        out.texture, out.texturePath =
            load_texture(j, buffers, pbr.baseColorTexture.index, ctx)
        out.textureUV = pbr.baseColorTexture.texCoord or 0
    end

    -- metallic/roughness packed map
    if pbr.metallicRoughnessTexture then
        out.metallicRoughnessTexture =
            load_texture(j, buffers, pbr.metallicRoughnessTexture.index, ctx)
    end

    -- normal map
    if mat.normalTexture then
        out.normalTexture = load_texture(j, buffers, mat.normalTexture.index, ctx)
        out.normalScale   = mat.normalTexture.scale or 1
    end

    -- occlusion
    if mat.occlusionTexture then
        out.occlusionTexture  = load_texture(j, buffers, mat.occlusionTexture.index, ctx)
        out.occlusionStrength = mat.occlusionTexture.strength or 1
    end

    -- emissive
    if mat.emissiveTexture then
        out.emissiveTexture = load_texture(j, buffers, mat.emissiveTexture.index, ctx)
    end

    return out
end

return material
