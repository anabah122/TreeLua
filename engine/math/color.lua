-- math/color.lua — RGB colour
--
-- Three components only, no alpha: three.js keeps transparency on the material
-- as `opacity`, and so does this engine's facade. The importers store material
-- tint as a flat {r,g,b,a} array, which `toArray`/`fromArray` bridge.
--
-- Values are unclamped floats in 0..1 -- LÖVE 11 uses the same range, so
-- colours pass to love.graphics.setColor untouched, and values above 1 stay
-- usable for emissive.

local Color = {}
Color.__index = Color

local function clamp(v, lo, hi)
    return math.min(math.max(v, lo), hi)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- three.js's named colours, trimmed to the ones worth typing. Anything else is
-- a hex literal, which `set` handles.
Color.NAMES = {
    black = 0x000000, white   = 0xffffff, red     = 0xff0000,
    green = 0x00ff00, blue    = 0x0000ff, yellow  = 0xffff00,
    cyan  = 0x00ffff, magenta = 0xff00ff, gray    = 0x808080,
    grey  = 0x808080, orange  = 0xffa500, purple  = 0x800080,
}

-- Color:new()               -> white
-- Color:new(0xff8800)       -> hex
-- Color:new("red")          -> name
-- Color:new(1, 0.5, 0)      -> components
function Color:new(r, g, b)
    local c = setmetatable({ r = 1, g = 1, b = 1, type = 'color' }, Color)
    if r ~= nil then c:set(r, g, b) end
    return c
end

function Color:set(r, g, b)
    if type(r) == "string" then
        return self:setStyle(r)
    elseif type(r) == "table" then
        return self:setRGB(r.r or r[1], r.g or r[2], r.b or r[3])
    elseif g == nil then
        return self:setHex(r)
    end
    return self:setRGB(r, g, b)
end

function Color:setRGB(r, g, b)
    self.r, self.g, self.b = r, g, b
    return self
end

function Color:setScalar(s)
    return self:setRGB(s, s, s)
end

function Color:setHex(hex)
    hex = math.floor(hex)
    return self:setRGB(
        (math.floor(hex / 0x10000) % 0x100) / 255,
        (math.floor(hex / 0x100)   % 0x100) / 255,
        (hex % 0x100) / 255
    )
end

-- Accepts "red", "#ff8800" and "#f80"; anything unrecognised stays put rather
-- than silently turning black.
function Color:setStyle(style)
    local named = Color.NAMES[style:lower()]
    if named then return self:setHex(named) end

    local hex = style:match("^#?(%x%x%x%x%x%x)$")
    if hex then return self:setHex(tonumber(hex, 16)) end

    local short = style:match("^#?(%x%x%x)$")
    if short then
        local r, g, b = short:sub(1,1), short:sub(2,2), short:sub(3,3)
        return self:setHex(tonumber(r..r..g..g..b..b, 16))
    end

    return self
end

-- three.js `setHSL`: hue/saturation/lightness, all 0..1.
function Color:setHSL(h, s, l)
    h = h % 1
    if s == 0 then return self:setScalar(l) end

    local function hue2rgb(p, q, t)
        if t < 0 then t = t + 1 end
        if t > 1 then t = t - 1 end
        if t < 1/6 then return p + (q - p) * 6 * t end
        if t < 1/2 then return q end
        if t < 2/3 then return p + (q - p) * 6 * (2/3 - t) end
        return p
    end

    local q = l <= 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q

    return self:setRGB(hue2rgb(p, q, h + 1/3),
                       hue2rgb(p, q, h),
                       hue2rgb(p, q, h - 1/3))
end

function Color:getHex()
    return math.floor(clamp(self.r, 0, 1) * 255 + 0.5) * 0x10000
         + math.floor(clamp(self.g, 0, 1) * 255 + 0.5) * 0x100
         + math.floor(clamp(self.b, 0, 1) * 255 + 0.5)
end

function Color:getHexString()
    return string.format("%06x", self:getHex())
end

function Color:getHSL()
    local r, g, b = self.r, self.g, self.b
    local maxc = math.max(r, g, b)
    local minc = math.min(r, g, b)

    local l = (minc + maxc) / 2
    if minc == maxc then return 0, 0, l end

    local d = maxc - minc
    local s = l <= 0.5 and d / (maxc + minc) or d / (2 - maxc - minc)

    local h
    if maxc == r then
        h = (g - b) / d + (g < b and 6 or 0)
    elseif maxc == g then
        h = (b - r) / d + 2
    else
        h = (r - g) / d + 4
    end

    return h / 6, s, l
end

function Color:clone()
    return Color:new(self.r, self.g, self.b)
end

function Color:copy(c)
    return self:setRGB(c.r, c.g, c.b)
end

function Color:add(c)
    return self:setRGB(self.r + c.r, self.g + c.g, self.b + c.b)
end

function Color:sub(c)
    return self:setRGB(math.max(0, self.r - c.r),
                       math.max(0, self.g - c.g),
                       math.max(0, self.b - c.b))
end

function Color:multiply(c)
    return self:setRGB(self.r * c.r, self.g * c.g, self.b * c.b)
end

function Color:multiplyScalar(s)
    return self:setRGB(self.r * s, self.g * s, self.b * s)
end

function Color:lerp(c, alpha)
    return self:setRGB(lerp(self.r, c.r, alpha),
                       lerp(self.g, c.g, alpha),
                       lerp(self.b, c.b, alpha))
end

function Color:equals(c)
    return self.r == c.r and self.g == c.g and self.b == c.b
end

function Color:toArray(alpha)
    return { self.r, self.g, self.b, alpha or 1 }
end

function Color:fromArray(a, offset)
    offset = offset or 0
    return self:setRGB(a[offset + 1], a[offset + 2], a[offset + 3])
end

function Color:__tostring()
    return "#" .. self:getHexString()
end

return Color
