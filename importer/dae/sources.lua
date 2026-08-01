-- dae/sources.lua — <source> / <accessor> decoding and up-axis handling
--
--   sources.read(root, "#Cube-mesh-positions") -> { data, stride, count, kind }
--
-- A collada <source> wraps a raw array plus an <accessor> describing how to
-- read it (stride, offset, which params are meaningful). Sources are shared
-- between geometry, skinning and animation, so this is the single decoder.

local xml = require "importer.dae.xml"

local sources = {}

-- ── source decoding ──────────────────────────────────────────────────────────
-- Returns { data = {...}, stride = n, count = n, kind = "float"|"name" }
function sources.read(root, url)
    local node = xml.byid(root, url)
    if not node then return nil end

    -- an <input> may point at <vertices>, which forwards to a real source
    if node.name == "vertices" then
        local input = xml.find(node, "input")
        if input then return sources.read(root, input.attr.source) end
        return nil
    end

    local technique = xml.find(node, "technique_common")
    local accessor  = technique and xml.find(technique, "accessor")

    local float_array = xml.find(node, "float_array")
    local name_array  = xml.find(node, "Name_array") or xml.find(node, "IDREF_array")

    local data, kind
    if float_array then
        data, kind = xml.numbers(float_array.text), "float"
    elseif name_array then
        data, kind = xml.words(name_array.text), "name"
    else
        return nil
    end

    local stride = 1
    local count  = #data
    local offset = 0

    if accessor then
        stride = tonumber(accessor.attr.stride) or 1
        count  = tonumber(accessor.attr.count)  or math.floor(#data / stride)
        offset = tonumber(accessor.attr.offset) or 0
    end

    -- honour the accessor's offset by dropping the skipped head
    if offset > 0 then
        local shifted = {}
        for i = offset + 1, #data do shifted[i - offset] = data[i] end
        data = shifted
    end

    return { data = data, stride = stride, count = count, kind = kind }
end

-- ── inputs ───────────────────────────────────────────────────────────────────
-- Collect <input> elements into { [SEMANTIC] = { source, offset, set } }.
-- Shared inputs carry an offset into the interleaved <p> index stream.
function sources.inputs(node)
    local out, max_offset = {}, 0
    for _, inp in ipairs(xml.findall(node, "input")) do
        local sem = inp.attr.semantic
        local off = tonumber(inp.attr.offset) or 0
        local set = tonumber(inp.attr.set) or 0
        -- TEXCOORD set=0 wins; higher sets are secondary UVs we ignore for now
        if not out[sem] or set < (out[sem].set or 0) then
            out[sem] = { source = inp.attr.source, offset = off, set = set }
        end
        if off > max_offset then max_offset = off end
    end
    return out, max_offset + 1   -- stride of the index stream
end

-- ── up axis ──────────────────────────────────────────────────────────────────
-- Blender and 3ds Max export Z_UP; the engine works in Y_UP, so vectors are
-- rotated on load rather than at draw time.
function sources.up_axis(root)
    local asset = xml.find(root, "asset")
    local up    = asset and xml.find(asset, "up_axis")
    return (up and up.text and up.text:match("%S+")) or "Y_UP"
end

-- <unit meter="0.01"/> declares how many metres one file unit is worth.
-- Mixamo exports Collada in centimetres, so without this a character loads
-- 100x too big while the glTF of the same rig comes in at human scale.
function sources.unit_scale(root)
    local asset = xml.find(root, "asset")
    local unit  = asset and xml.find(asset, "unit")
    local meter = unit and tonumber(unit.attr.meter)
    return (meter and meter > 0) and meter or 1
end

-- Convert a position/normal triple from the file's up-axis into Y_UP.
function sources.convert_up(up, x, y, z)
    if up == "Z_UP" then
        -- (x, y, z) -> (x, z, -y)
        return x, z, -y
    elseif up == "X_UP" then
        return y, -x, z
    end
    return x, y, z
end

-- Same rotation expressed as a matrix, for baking into node transforms.
-- `scale` folds in <unit meter=...> so the whole scene arrives in metres.
function sources.up_matrix(up, scale)
    local matClass = require "math.mat4"
    local m = matClass:new()
    if up == "Z_UP" then
        m[1],  m[2],  m[3],  m[4]  = 1, 0,  0, 0
        m[5],  m[6],  m[7],  m[8]  = 0, 0,  1, 0
        m[9],  m[10], m[11], m[12] = 0, -1, 0, 0
        m[13], m[14], m[15], m[16] = 0, 0,  0, 1
    elseif up == "X_UP" then
        m[1],  m[2],  m[3],  m[4]  = 0,  1, 0, 0
        m[5],  m[6],  m[7],  m[8]  = -1, 0, 0, 0
        m[9],  m[10], m[11], m[12] = 0,  0, 1, 0
        m[13], m[14], m[15], m[16] = 0,  0, 0, 1
    end

    if scale and scale ~= 1 then
        for i = 1, 12 do m[i] = m[i] * scale end
    end

    return m
end

-- ── matrices ─────────────────────────────────────────────────────────────────
-- Collada writes matrices row-major in text, which matches math/mat4.lua, so
-- the 16 numbers map straight across with no transpose.
function sources.matrix(nums, offset)
    local matClass = require "math.mat4"
    offset = offset or 0
    local m = matClass:new()
    for i = 1, 16 do m[i] = nums[offset + i] or 0 end
    return m
end

return sources
