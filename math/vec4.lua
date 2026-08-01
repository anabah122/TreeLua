local function lerp(a, b, t)
    return a + (b - a) * t
end

local function clamp(v, lo, hi)
    return math.min(math.max(v, lo), hi)
end

local function frac(x)
    return x - math.floor(x)
end




-- Vector4
local Vector4 = {}
Vector4.__index = Vector4

function Vector4:new(x, y, z, w)
    x = x or 0 
    y = y or x 
    z = z or x 
    w = w or x 
    return setmetatable({x = x, y = y, z = z, w = w, type = 'vec4'}, Vector4)
end

function Vector4:clone()
    return Vector4:new(self.x, self.y, self.z, self.w)
end

function Vector4:asLinearArray()
    return {self.x, self.y, self.z, self.w}
end

function Vector4:add(val)
    if type(val) == "number" then
        return Vector4:new(self.x + val, self.y + val, self.z + val, self.w + val)
    else
        return Vector4:new(self.x + val.x, self.y + val.y, self.z + val.z, self.w + val.w)
    end
end

function Vector4:sub(val)
    if type(val) == "number" then
        return Vector4:new(self.x - val, self.y - val, self.z - val, self.w - val)
    else
        return Vector4:new(self.x - val.x, self.y - val.y, self.z - val.z, self.w - val.w)
    end
end

function Vector4:mul(val)
    if type(val) == "number" then
        return Vector4:new(self.x * val, self.y * val, self.z * val, self.w * val)
    else
        return Vector4:new(self.x * val.x, self.y * val.y, self.z * val.z, self.w * val.w)
    end
end

function Vector4:div(val)
    if type(val) == "number" then
        return Vector4:new(self.x / val, self.y / val, self.z / val, self.w / val)
    else
        return Vector4:new(self.x / val.x, self.y / val.y, self.z / val.z, self.w / val.w)
    end
end

function Vector4:magnitude()
    return math.sqrt(self.x^2 + self.y^2 + self.z^2 + self.w^2)
end

function Vector4:distanceTo(v)
    local dx = self.x - v.x
    local dy = self.y - v.y
    local dz = self.z - v.z
    local dw = self.w - v.w
    return math.sqrt(dx*dx + dy*dy + dz*dz + dw*dw)
end

function Vector4:dot(v)
    return self.x * v.x + self.y * v.y + self.z * v.z + self.w * v.w
end

function Vector4:equals(v)
    return self.x == v.x and self.y == v.y and self.z == v.z and self.w == v.w
end

function Vector4:normalize()
    local mag = self:magnitude()
    if mag == 0 then return Vector4:new(0, 0, 0, 0) end
    return Vector4:new(self.x / mag, self.y / mag, self.z / mag, self.w / mag)
end

function Vector4:clamp(a, b)
    if type(a) == "table" then
        return Vector4:new(
            clamp(self.x, a.x, b.x),
            clamp(self.y, a.y, b.y),
            clamp(self.z, a.z, b.z),
            clamp(self.w, a.w, b.w)
        )
    else
        return Vector4:new(
            clamp(self.x, a, b),
            clamp(self.y, a, b),
            clamp(self.z, a, b),
            clamp(self.w, a, b)
        )
    end
end

function Vector4:clampMagnitude(maxMag)
    local mag = self:magnitude()
    if mag <= maxMag then return self:clone() end
    return self:normalize():mul(maxMag)
end

function Vector4:abs()
    return Vector4:new(math.abs(self.x), math.abs(self.y), math.abs(self.z), math.abs(self.w))
end

function Vector4:frac()
    return Vector4:new(frac(self.x), frac(self.y), frac(self.z), frac(self.w))
end

function Vector4:project(dir)
    local dot = self:dot(dir)
    local len2 = dir:dot(dir)
    if len2 == 0 then return Vector4:new(0, 0, 0, 0) end
    local f = dot / len2
    return dir:mul(f)
end

function Vector4:min(val)
    if type(val) == "number" then
        return Vector4:new(math.min(self.x, val), math.min(self.y, val), math.min(self.z, val), math.min(self.w, val))
    else
        return Vector4:new(math.min(self.x, val.x), math.min(self.y, val.y), math.min(self.z, val.z), math.min(self.w, val.w))
    end
end

function Vector4:max(val)
    if type(val) == "number" then
        return Vector4:new(math.max(self.x, val), math.max(self.y, val), math.max(self.z, val), math.max(self.w, val))
    else
        return Vector4:new(math.max(self.x, val.x), math.max(self.y, val.y), math.max(self.z, val.z), math.max(self.w, val.w))
    end
end

function Vector4:floor()
    return Vector4:new(math.floor(self.x), math.floor(self.y), math.floor(self.z), math.floor(self.w))
end

function Vector4:ceil()
    return Vector4:new(math.ceil(self.x), math.ceil(self.y), math.ceil(self.z), math.ceil(self.w))
end

function Vector4:round()
    return Vector4:new(
        math.floor(self.x + 0.5),
        math.floor(self.y + 0.5),
        math.floor(self.z + 0.5),
        math.floor(self.w + 0.5)
    )
end

function Vector4:lerp(target, amount)
    return Vector4:new(
        lerp(self.x, target.x, amount),
        lerp(self.y, target.y, amount),
        lerp(self.z, target.z, amount),
        lerp(self.w, target.w, amount)
    )
end

function Vector4:angle(v)
    local dot = self:dot(v)
    local mag1 = self:magnitude()
    local mag2 = v:magnitude()
    if mag1 == 0 or mag2 == 0 then return 0 end
    local cosang = dot / (mag1 * mag2)
    cosang = math.max(-1, math.min(1, cosang))
    return math.acos(cosang)
end

function Vector4:approach(target, amount)
    local dist = self:distanceTo(target)
    if dist <= amount then return target:clone() end
    local dir = target:sub(self):normalize()
    return self:add(dir:mul(amount))
end

function Vector4:__tostring()
    return string.format("(%g, %g, %g, %g)", self.x, self.y, self.z, self.w)
end


return Vector4