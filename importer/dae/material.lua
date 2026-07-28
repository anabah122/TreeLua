-- dae/material.lua — <material>/<effect> -> the same table glTF produces
--
--   material.build(root, target_url, ctx) -> { name, baseColor, texture, ... }
--
-- Collada splits this in two: <material> is a thin pointer to an <effect>,
-- which holds the actual phong/lambert/blinn parameters. Texture lookups go
-- through <newparam> sampler -> surface -> <image> indirection.

local xml = require "importer.dae.xml"

local material = {}

local function dirname(path)
    return path:match("(.*[/\\])") or ""
end

-- <color>0.8 0.8 0.8 1</color> or a <texture> reference
local function read_slot(effect, profile, slot_name, root, ctx)
    local slot = xml.deep(profile, slot_name)
    if not slot then return nil, nil end

    local color = xml.find(slot, "color")
    if color then
        local c = xml.numbers(color.text)
        return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }, nil
    end

    local tex = xml.find(slot, "texture")
    if tex and ctx.withTex then
        local image = material.resolve_texture(root, profile, tex.attr.texture, ctx)
        return nil, image
    end

    return nil, nil
end

-- sampler2D -> surface -> image, resolved through <newparam> sids
function material.resolve_texture(root, profile, sampler_sid, ctx)
    if not sampler_sid then return nil end

    local image_id = sampler_sid

    -- sampler param -> surface param
    for _, np in ipairs(xml.deepall(profile, "newparam")) do
        if np.attr.sid == sampler_sid then
            local sampler = xml.find(np, "sampler2D")
            local src = sampler and xml.find(sampler, "source")
            if src and src.text then
                image_id = src.text:match("%S+")
            end
            break
        end
    end

    -- surface param -> image id
    for _, np in ipairs(xml.deepall(profile, "newparam")) do
        if np.attr.sid == image_id then
            local surface = xml.find(np, "surface")
            local init = surface and xml.find(surface, "init_from")
            if init and init.text then
                image_id = init.text:match("%S+")
            end
            break
        end
    end

    local img_el = xml.byid(root, image_id)
    if not img_el then return nil end

    local init = xml.find(img_el, "init_from")
    if not (init and init.text) then return nil end

    local uri = init.text:match("%S+")
    if not uri then return nil end

    -- some exporters wrap the path in <ref>
    local ref = xml.find(init, "ref")
    if ref and ref.text then uri = ref.text:match("%S+") end

    uri = uri:gsub("^file://", ""):gsub("%%20", " ")

    local path = uri
    if not uri:match("^%a:[/\\]") and not uri:match("^/") then
        path = dirname(ctx.path) .. uri
    end

    local ok, image = pcall(love.graphics.newImage, path, { mipmaps = true })
    if not ok then
        -- texture paths in DAE are frequently absolute paths from the authoring
        -- machine; fall back to the basename next to the model
        local base = uri:match("([^/\\]+)$")
        if base then
            ok, image = pcall(love.graphics.newImage, dirname(ctx.path) .. base, { mipmaps = true })
        end
    end
    if not ok then return nil end

    image:setFilter("linear", "linear", ctx.anisotropy or 1)
    return image
end

function material.build(root, target_url, ctx)
    if not target_url then return nil end

    local mat_el = xml.byid(root, target_url)
    if not mat_el then return nil end

    local out = {
        name      = mat_el.attr.name or mat_el.attr.id,
        baseColor = {1, 1, 1, 1},
        metallic  = 0,
        roughness = 1,
        emissive  = {0, 0, 0},
        alphaMode = "OPAQUE",
    }

    local inst = xml.find(mat_el, "instance_effect")
    local effect = inst and xml.byid(root, inst.attr.url)
    if not effect then return out end

    local profile = xml.find(effect, "profile_COMMON")
    if not profile then return out end

    local color, tex = read_slot(effect, profile, "diffuse", root, ctx)
    if color then out.baseColor = color end
    if tex then out.texture = tex end

    local ecolor = read_slot(effect, profile, "emission", root, ctx)
    if ecolor then out.emissive = { ecolor[1], ecolor[2], ecolor[3] } end

    -- shininess maps loosely onto roughness; collada has no PBR in profile_COMMON
    local shin = xml.deep(profile, "shininess")
    local sf = shin and xml.find(shin, "float")
    if sf then
        local s = tonumber(sf.text and sf.text:match("%S+")) or 0
        out.roughness = math.max(0, math.min(1, 1 - (s / 128)))
    end

    local trans = xml.deep(profile, "transparency")
    local tf = trans and xml.find(trans, "float")
    if tf then
        local a = tonumber(tf.text and tf.text:match("%S+"))
        if a and a < 1 then out.alphaMode = "BLEND" end
    end

    -- normal maps live in an extra profile, not profile_COMMON
    if ctx.withTex then
        local bump = xml.deep(effect, "bump")
        local btex = bump and xml.find(bump, "texture")
        if btex then
            out.normalTexture = material.resolve_texture(root, profile, btex.attr.texture, ctx)
        end
    end

    return out
end

return material
