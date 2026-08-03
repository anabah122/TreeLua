-- dae/xml.lua — minimal XML parser (no deps)
--
--   local root = xml.parse(str)
--
-- node = {
--   name     = "geometry",
--   attr     = { id = "Cube-mesh", name = "Cube" },
--   children = { node, ... },
--   text     = "1.0 2.0 3.0",   -- only when the element has character data
-- }
--
-- helpers:
--   xml.find(node, "mesh")            -> first direct child by tag
--   xml.findall(node, "source")       -> all direct children by tag
--   xml.deep(node, "float_array")     -> first descendant at any depth
--   xml.byid(root, "Cube-mesh")       -> element whose id attribute matches
--   xml.numbers(str)                  -> flat array of numbers
--   xml.words(str)                    -> flat array of whitespace-split strings

local xml = {}

local ENTITIES = {
    lt = "<", gt = ">", amp = "&", quot = '"', apos = "'",
}

local function unescape(s)
    if not s:find("&", 1, true) then return s end
    return (s:gsub("&(#?%w+);", function(e)
        if ENTITIES[e] then return ENTITIES[e] end
        local num = e:match("^#(%d+)$")
        if num then
            local c = tonumber(num)
            return (utf8 and utf8.char(c)) or string.char(c % 256)
        end
        local hex = e:match("^#[xX](%x+)$")
        if hex then
            local c = tonumber(hex, 16)
            return (utf8 and utf8.char(c)) or string.char(c % 256)
        end
        return "&" .. e .. ";"
    end))
end

-- parse attributes out of a tag body
local function parse_attrs(s)
    local attr = {}
    for k, q, v in s:gmatch("([%w_:%-%.]+)%s*=%s*(['\"])(.-)%2") do
        attr[k] = unescape(v)
    end
    return attr
end

function xml.parse(data)
    -- strip declaration, comments, CDATA markers, processing instructions
    data = data:gsub("<%?.-%?>", "")
    data = data:gsub("<!%-%-.-%-%->", "")
    data = data:gsub("<!%[CDATA%[(.-)%]%]>", function(c) return c end)
    data = data:gsub("<!DOCTYPE.->", "")

    local root = { name = "#root", attr = {}, children = {} }
    local stack = { root }
    local pos = 1

    while true do
        local s, e = data:find("<", pos, true)
        if not s then break end

        -- character data preceding this tag belongs to the open element
        if s > pos then
            local text = data:sub(pos, s - 1)
            if text:find("%S") then
                local top = stack[#stack]
                top.text = (top.text or "") .. text
            end
        end

        local close, tag_end = data:find(">", s, true)
        if not close then break end

        local body = data:sub(s + 1, close - 1)
        pos = close + 1

        if body:sub(1, 1) == "/" then
            -- closing tag
            if #stack > 1 then table.remove(stack) end
        else
            local self_closing = body:sub(-1) == "/"
            if self_closing then body = body:sub(1, -2) end

            local name = body:match("^([%w_:%-%.]+)")
            if name then
                local node = {
                    name     = name,
                    attr     = parse_attrs(body:sub(#name + 1)),
                    children = {},
                }
                local top = stack[#stack]
                top.children[#top.children + 1] = node
                if not self_closing then
                    stack[#stack + 1] = node
                end
            end
        end
    end

    -- collada files have a single <COLLADA> root
    return root.children[1] or root
end

-- ── navigation ───────────────────────────────────────────────────────────────
function xml.find(node, tag)
    if not node then return nil end
    for _, c in ipairs(node.children) do
        if c.name == tag then return c end
    end
    return nil
end

function xml.findall(node, tag)
    local out = {}
    if not node then return out end
    for _, c in ipairs(node.children) do
        if c.name == tag then out[#out + 1] = c end
    end
    return out
end

-- first descendant with this tag, searched depth-first
function xml.deep(node, tag)
    if not node then return nil end
    for _, c in ipairs(node.children) do
        if c.name == tag then return c end
        local found = xml.deep(c, tag)
        if found then return found end
    end
    return nil
end

function xml.deepall(node, tag, out)
    out = out or {}
    if not node then return out end
    for _, c in ipairs(node.children) do
        if c.name == tag then out[#out + 1] = c end
        xml.deepall(c, tag, out)
    end
    return out
end

-- resolve "#Cube-mesh" style references
function xml.byid(root, id)
    if not id then return nil end
    id = id:gsub("^#", "")
    local found
    local function walk(node)
        if found then return end
        for _, c in ipairs(node.children) do
            if c.attr.id == id then found = c; return end
            walk(c)
        end
    end
    walk(root)
    return found
end

-- find by sid within a subtree (collada bones are addressed this way)
function xml.bysid(node, sid)
    if not node then return nil end
    for _, c in ipairs(node.children) do
        if c.attr.sid == sid then return c end
        local found = xml.bysid(c, sid)
        if found then return found end
    end
    return nil
end

-- ── text payloads ────────────────────────────────────────────────────────────
function xml.numbers(s)
    local out = {}
    if not s then return out end
    local n = 0
    for tok in s:gmatch("%S+") do
        n = n + 1
        out[n] = tonumber(tok) or 0
    end
    return out
end

function xml.words(s)
    local out = {}
    if not s then return out end
    local n = 0
    for tok in s:gmatch("%S+") do
        n = n + 1
        out[n] = tok
    end
    return out
end

return xml
