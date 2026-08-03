-- gltf/binary.lua — GLB container, buffer loading, accessor decoding
--
-- binary.parse_glb(data)              -> json_str, bin_data
-- binary.load_buffers(j, path, bin)   -> { [i] = string }
-- binary.accessor(j, buffers, idx)    -> raw, elem_count, ctype, count
-- binary.read(raw, ctype, n)          -> lua array of numbers (1-based)
-- binary.read_floats(raw, elems, n)   -> flat lua array
-- binary.read_indices(raw, ctype, n)  -> lua array, 1-based
-- binary.bufferview_bytes(j, bufs, i) -> string

local ffi = require "ffi"

local binary = {}

local COMPONENT_BYTES = { [5120]=1,[5121]=1,[5122]=2,[5123]=2,[5125]=4,[5126]=4 }
local COMPONENT_TYPE  = {
    [5120]="int8_t", [5121]="uint8_t", [5122]="int16_t",
    [5123]="uint16_t",[5125]="uint32_t",[5126]="float",
}
local TYPE_COUNT = { SCALAR=1,VEC2=2,VEC3=3,VEC4=4,MAT2=4,MAT3=9,MAT4=16 }

binary.COMPONENT_BYTES = COMPONENT_BYTES
binary.COMPONENT_TYPE  = COMPONENT_TYPE
binary.TYPE_COUNT      = TYPE_COUNT

-- ── file io ──────────────────────────────────────────────────────────────────
function binary.read_file(path)
    -- try love.filesystem first (relative paths inside game dir)
    local data, err = love.filesystem.read(path)
    if data then return data end
    -- fallback to io for absolute paths
    local f = assert(io.open(path, "rb"), "cannot open "..path..": "..tostring(err or ""))
    local s = f:read("*a")
    f:close()
    return s
end

-- decode little-endian uint32 from string at byte offset (1-based)
local function u32(s, pos)
    local a,b,c,d = s:byte(pos, pos+3)
    return a + b*256 + c*65536 + d*16777216
end
binary.u32 = u32

-- ── GLB container ────────────────────────────────────────────────────────────
function binary.parse_glb(data)
    -- header: magic(4) version(4) length(4)
    local version = u32(data, 5)
    assert(version == 2, "only glTF 2.0 GLB supported")

    local json_str, bin_data
    local pos = 13  -- first chunk starts here
    while pos <= #data do
        local chunk_len  = u32(data, pos)
        local chunk_type = u32(data, pos+4)
        local chunk_data = data:sub(pos+8, pos+8+chunk_len-1)
        if chunk_type == 0x4E4F534A then      -- JSON
            json_str = chunk_data
        elseif chunk_type == 0x004E4942 then  -- BIN
            bin_data = chunk_data
        end
        pos = pos + 8 + chunk_len
    end

    assert(json_str, "no JSON chunk in GLB")
    return json_str, bin_data
end

-- ── buffers ──────────────────────────────────────────────────────────────────
function binary.load_buffers(j, path, bin_embedded)
    local buffers = {}
    for i, buf in ipairs(j.buffers or {}) do
        if buf.uri == nil then
            -- GLB embedded binary
            buffers[i] = assert(bin_embedded, "GLB has no BIN chunk")
        elseif buf.uri:sub(1,5) == "data:" then
            -- data URI  base64
            local b64 = buf.uri:match("base64,(.+)$")
            assert(b64, "unrecognised data URI")
            buffers[i] = love.data.decode("string", "base64", b64)
        else
            -- external file
            local dir = path:match("(.*[/\\])") or ""
            buffers[i] = binary.read_file(dir .. buf.uri)
        end
    end
    return buffers
end

-- raw bytes of a bufferView (used for embedded images)
function binary.bufferview_bytes(j, buffers, bv_idx)
    local bv  = j.bufferViews[bv_idx + 1]
    if not bv then return nil end
    local buf = buffers[bv.buffer + 1]
    local off = bv.byteOffset or 0
    return buf:sub(off + 1, off + bv.byteLength)
end

-- ── accessors ────────────────────────────────────────────────────────────────
-- returns: raw byte string (de-strided), elems per item, ctype name, item count
function binary.accessor(j, buffers, acc_idx)
    local acc = j.accessors[acc_idx + 1]
    assert(acc, "accessor "..tostring(acc_idx).." missing")

    local elem_count  = TYPE_COUNT[acc.type]
    local comp_bytes  = COMPONENT_BYTES[acc.componentType]
    local ctype       = COMPONENT_TYPE[acc.componentType]
    local total_count = acc.count  -- number of elements (vertices or indices)

    local bv_idx = acc.bufferView
    if bv_idx == nil then
        -- no backing view: all zeros (sparse base)
        return nil, elem_count, ctype, total_count
    end

    local bv   = j.bufferViews[bv_idx + 1]
    local buf  = buffers[bv.buffer + 1]
    local bv_offset  = bv.byteOffset or 0
    local acc_offset = acc.byteOffset or 0
    local stride = bv.byteStride or (comp_bytes * elem_count)

    local elem_bytes = comp_bytes * elem_count
    local result
    if stride == elem_bytes then
        local start = bv_offset + acc_offset + 1
        result = buf:sub(start, start + elem_bytes * total_count - 1)
    else
        -- de-stride into a packed copy
        local parts = {}
        local base = bv_offset + acc_offset
        for i = 0, total_count - 1 do
            local s = base + i * stride + 1
            parts[i+1] = buf:sub(s, s + elem_bytes - 1)
        end
        result = table.concat(parts)
    end

    return result, elem_count, ctype, total_count
end

-- ── typed reads ──────────────────────────────────────────────────────────────
-- generic: decode `n` values of `ctype` into a flat 1-based lua array
function binary.read(raw, ctype, n)
    if not raw then
        local out = {}
        for i = 1, n do out[i] = 0 end
        return out
    end
    local ptr = ffi.cast(ctype .. "*", ffi.cast("const char*", raw))
    local out = {}
    for i = 0, n - 1 do out[i+1] = ptr[i] end
    return out
end

function binary.read_floats(raw, elem_count, count)
    return binary.read(raw, "float", count * elem_count)
end

-- indices come back 1-based, ready for love's setVertexMap
function binary.read_indices(raw, ctype, count)
    if ctype ~= "uint8_t" and ctype ~= "uint16_t" and ctype ~= "uint32_t" then
        error("unsupported index type: "..tostring(ctype))
    end
    local ptr = ffi.cast(ctype .. "*", ffi.cast("const char*", raw))
    local out = {}
    for i = 0, count - 1 do
        out[i+1] = ptr[i] + 1  -- convert to 1-based
    end
    return out
end

-- read an accessor straight into a lua array (convenience for skin/animation)
function binary.accessor_values(j, buffers, acc_idx)
    local raw, elems, ctype, count = binary.accessor(j, buffers, acc_idx)
    return binary.read(raw, ctype, count * elems), elems, count
end

return binary
