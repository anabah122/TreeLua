local function lerp(a, b, t)
    return a + (b - a) * t
end

local function clamp(v, lo, hi)
    return math.min(math.max(v, lo), hi)
end

local function frac(x)
    return x - math.floor(x)
end



-- Vector3
local Vector3 = {}
Vector3.__index = Vector3

function Vector3:new(x, y, z)
    x = x or 0 
    y = y or x 
    z = z or x 
    return setmetatable({x = x, y = y, z = z, type = 'vec3'}, Vector3)
end


function Vector3:clone()
    return Vector3:new(self.x, self.y, self.z)
end

function Vector3:asLinearArray()
    return {self.x, self.y, self.z}
end

function Vector3:__add( val ) return self:add( val ) end 
function Vector3:add(val)
    if type(val) == "number" then
        return Vector3:new(self.x + val, self.y + val, self.z + val)
    else
        return Vector3:new(self.x + val.x, self.y + val.y, self.z + val.z)
    end
end

function Vector3:__sub( val ) return self:sub( val ) end 
function Vector3:sub(val)
    if type(val) == "number" then
        return Vector3:new(self.x - val, self.y - val, self.z - val)
    else
        return Vector3:new(self.x - val.x, self.y - val.y, self.z - val.z)
    end
end

function Vector3:__mul( val ) return self:mul( val ) end
function Vector3:mul(val)
    if type(val) == "number" then
        return Vector3:new(self.x * val, self.y * val, self.z * val)
    else
        return Vector3:new(self.x * val.x, self.y * val.y, self.z * val.z)
    end
end

function Vector3:__div( val ) return self:div( val ) end
function Vector3:div(val)
    if type(val) == "number" then
        return Vector3:new(self.x / val, self.y / val, self.z / val)
    else
        return Vector3:new(self.x / val.x, self.y / val.y, self.z / val.z)
    end
end

function Vector3:magnitude()
    return math.sqrt(self.x^2 + self.y^2 + self.z^2)
end

function Vector3:distanceTo(v)
    local dx = self.x - v.x
    local dy = self.y - v.y
    local dz = self.z - v.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

function Vector3:dot(v)
    return self.x * v.x + self.y * v.y + self.z * v.z
end

function Vector3:cross(v)
    return Vector3:new(
        self.y * v.z - v.y * self.z,
        self.z * v.x - v.z * self.x,
        self.x * v.y - v.x * self.y
    )
end

function Vector3:equals(v)
    return self.x == v.x and self.y == v.y and self.z == v.z
end

function Vector3:normalize()
    local mag = self:magnitude()
    if mag == 0 then return Vector3:new(0, 0, 0) end
    return Vector3:new(self.x / mag, self.y / mag, self.z / mag)
end

function Vector3:clamp(a, b)
    if type(a) == "table" then
        return Vector3:new(
            clamp(self.x, a.x, b.x),
            clamp(self.y, a.y, b.y),
            clamp(self.z, a.z, b.z)
        )
    else
        return Vector3:new(
            clamp(self.x, a, b),
            clamp(self.y, a, b),
            clamp(self.z, a, b)
        )
    end
end

function Vector3:clampMagnitude(maxMag)
    local mag = self:magnitude()
    if mag <= maxMag then return self:clone() end
    return self:normalize():mul(maxMag)
end

function Vector3:abs()
    return Vector3:new(math.abs(self.x), math.abs(self.y), math.abs(self.z))
end

function Vector3:frac()
    return Vector3:new(frac(self.x), frac(self.y), frac(self.z))
end

function Vector3:project(dir)
    local dot = self:dot(dir)
    local len2 = dir:dot(dir)
    if len2 == 0 then return Vector3:new(0, 0, 0) end
    local f = dot / len2
    return dir:mul(f)
end

function Vector3:min(val)
    if type(val) == "number" then
        return Vector3:new(math.min(self.x, val), math.min(self.y, val), math.min(self.z, val))
    else
        return Vector3:new(math.min(self.x, val.x), math.min(self.y, val.y), math.min(self.z, val.z))
    end
end

function Vector3:max(val)
    if type(val) == "number" then
        return Vector3:new(math.max(self.x, val), math.max(self.y, val), math.max(self.z, val))
    else
        return Vector3:new(math.max(self.x, val.x), math.max(self.y, val.y), math.max(self.z, val.z))
    end
end

function Vector3:floor()
    return Vector3:new(math.floor(self.x), math.floor(self.y), math.floor(self.z))
end

function Vector3:ceil()
    return Vector3:new(math.ceil(self.x), math.ceil(self.y), math.ceil(self.z))
end

function Vector3:round()
    return Vector3:new(math.floor(self.x + 0.5), math.floor(self.y + 0.5), math.floor(self.z + 0.5))
end

function Vector3:lerp(target, amount)
    return Vector3:new(
        lerp(self.x, target.x, amount),
        lerp(self.y, target.y, amount),
        lerp(self.z, target.z, amount)
    )
end

function Vector3:angle(v)
    local dot = self:dot(v)
    local mag1 = self:magnitude()
    local mag2 = v:magnitude()
    if mag1 == 0 or mag2 == 0 then return 0 end
    local cosang = dot / (mag1 * mag2)
    cosang = math.max(-1, math.min(1, cosang)) -- clamp to avoid NaN
    return math.acos(cosang)
end

function Vector3:approach(target, amount)
    local dist = self:distanceTo(target)
    if dist <= amount then return target:clone() end
    local dir = target:sub(self):normalize()
    return self:add(dir:mul(amount))
end

function Vector3:__tostring()
    return string.format("(%g, %g, %g)", self.x, self.y, self.z)
end

function Vector3:get()
    return {self.x,self.y,self.z}
end

return Vector3