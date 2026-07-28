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

--------------------------------------------------------------------------
-- three.js-compatible surface
--
-- The methods above are the engine's original immutable ones: `a:add(b)`
-- returns a new vector and leaves `a` alone. three.js is the opposite --
-- `a.add(b)` mutates `a` and returns it so calls chain.
--
-- Both live here rather than in a wrapper: a wrapper would allocate on every
-- vector op, and skinning runs thousands per frame. The rule for telling them
-- apart is the name. Anything below mutates `self` and returns `self`; the
-- immutable originals keep the names they always had (add/sub/mul/div and the
-- operators built on them), so existing engine code is untouched.
--
-- Where three.js and the original agree on both name and behaviour -- dot,
-- cross, distanceTo, clone, equals, angle -- there is nothing to add.
--------------------------------------------------------------------------

function Vector3:set(x, y, z)
    self.x, self.y, self.z = x or 0, y or 0, z or 0
    return self
end

function Vector3:setScalar(s)
    return self:set(s, s, s)
end

function Vector3:setX(x) self.x = x return self end
function Vector3:setY(y) self.y = y return self end
function Vector3:setZ(z) self.z = z return self end

function Vector3:copy(v)
    return self:set(v.x, v.y, v.z)
end

-- three.js calls the magnitude `length`; `lengthSq` skips the square root for
-- comparisons, which is what most callers actually want.
function Vector3:length()
    return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end

function Vector3:lengthSq()
    return self.x * self.x + self.y * self.y + self.z * self.z
end

function Vector3:distanceToSquared(v)
    local dx, dy, dz = self.x - v.x, self.y - v.y, self.z - v.z
    return dx * dx + dy * dy + dz * dz
end

function Vector3:addV(v)
    self.x, self.y, self.z = self.x + v.x, self.y + v.y, self.z + v.z
    return self
end

function Vector3:addScalar(s)
    return self:set(self.x + s, self.y + s, self.z + s)
end

function Vector3:addScaledVector(v, s)
    return self:set(self.x + v.x * s, self.y + v.y * s, self.z + v.z * s)
end

function Vector3:addVectors(a, b)
    return self:set(a.x + b.x, a.y + b.y, a.z + b.z)
end

function Vector3:subV(v)
    return self:set(self.x - v.x, self.y - v.y, self.z - v.z)
end

function Vector3:subScalar(s)
    return self:set(self.x - s, self.y - s, self.z - s)
end

function Vector3:subVectors(a, b)
    return self:set(a.x - b.x, a.y - b.y, a.z - b.z)
end

function Vector3:multiply(v)
    return self:set(self.x * v.x, self.y * v.y, self.z * v.z)
end

function Vector3:multiplyScalar(s)
    return self:set(self.x * s, self.y * s, self.z * s)
end

function Vector3:multiplyVectors(a, b)
    return self:set(a.x * b.x, a.y * b.y, a.z * b.z)
end

function Vector3:divide(v)
    return self:set(self.x / v.x, self.y / v.y, self.z / v.z)
end

function Vector3:divideScalar(s)
    return self:multiplyScalar(s == 0 and 0 or 1 / s)
end

function Vector3:negate()
    return self:set(-self.x, -self.y, -self.z)
end

function Vector3:normalizeSelf()
    return self:divideScalar(self:length())
end

function Vector3:setLength(len)
    return self:normalizeSelf():multiplyScalar(len)
end

function Vector3:crossVectors(a, b)
    return self:set(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

function Vector3:lerpSelf(v, alpha)
    return self:set(
        lerp(self.x, v.x, alpha),
        lerp(self.y, v.y, alpha),
        lerp(self.z, v.z, alpha)
    )
end

function Vector3:lerpVectors(a, b, alpha)
    return self:set(
        lerp(a.x, b.x, alpha),
        lerp(a.y, b.y, alpha),
        lerp(a.z, b.z, alpha)
    )
end

function Vector3:clampSelf(minV, maxV)
    return self:set(
        clamp(self.x, minV.x, maxV.x),
        clamp(self.y, minV.y, maxV.y),
        clamp(self.z, minV.z, maxV.z)
    )
end

function Vector3:clampScalar(minVal, maxVal)
    return self:set(
        clamp(self.x, minVal, maxVal),
        clamp(self.y, minVal, maxVal),
        clamp(self.z, minVal, maxVal)
    )
end

function Vector3:clampLength(minVal, maxVal)
    local len = self:length()
    return self:divideScalar(len == 0 and 1 or len)
               :multiplyScalar(clamp(len, minVal, maxVal))
end

function Vector3:minSelf(v)
    return self:set(math.min(self.x, v.x), math.min(self.y, v.y), math.min(self.z, v.z))
end

function Vector3:maxSelf(v)
    return self:set(math.max(self.x, v.x), math.max(self.y, v.y), math.max(self.z, v.z))
end

function Vector3:floorSelf()
    return self:set(math.floor(self.x), math.floor(self.y), math.floor(self.z))
end

function Vector3:ceilSelf()
    return self:set(math.ceil(self.x), math.ceil(self.y), math.ceil(self.z))
end

function Vector3:roundSelf()
    return self:set(math.floor(self.x + 0.5), math.floor(self.y + 0.5), math.floor(self.z + 0.5))
end

function Vector3:projectOnVector(v)
    local denom = v:lengthSq()
    if denom == 0 then return self:set(0, 0, 0) end
    return self:copy(v):multiplyScalar(v:dot(self) / denom)
end

-- Reflect off the plane with this normal, i.e. remove twice the component
-- pointing into it. `n` is assumed unit length, as in three.js.
function Vector3:projectOnPlane(n)
    local d = self:dot(n)
    return self:set(self.x - n.x * d, self.y - n.y * d, self.z - n.z * d)
end

function Vector3:reflect(n)
    local d = 2 * self:dot(n)
    return self:set(self.x - n.x * d, self.y - n.y * d, self.z - n.z * d)
end

-- Rotate by a quaternion: v' = q * v * conj(q), expanded to avoid building the
-- intermediate quaternion. Kept here rather than on Quaternion so that
-- `Object3D` can push a local offset into world space in one call.
function Vector3:applyQuaternion(q)
    local x,  y,  z  = self.x, self.y, self.z
    local qx, qy, qz, qw = q.x, q.y, q.z, q.w

    local ix =  qw * x + qy * z - qz * y
    local iy =  qw * y + qz * x - qx * z
    local iz =  qw * z + qx * y - qy * x
    local iw = -qx * x - qy * y - qz * z

    return self:set(
        ix * qw + iw * -qx + iy * -qz - iz * -qy,
        iy * qw + iw * -qy + iz * -qx - ix * -qz,
        iz * qw + iw * -qz + ix * -qy - iy * -qx
    )
end

-- Full transform including translation, with the perspective divide applied so
-- projection matrices behave as three.js users expect.
function Vector3:applyMatrix4(m)
    local x, y, z = self.x, self.y, self.z
    local e = m:asLinearArray()

    local w = e[4] * x + e[8] * y + e[12] * z + e[16]
    if w == 0 then w = 1 end

    return self:set(
        (e[1] * x + e[5] * y + e[ 9] * z + e[13]) / w,
        (e[2] * x + e[6] * y + e[10] * z + e[14]) / w,
        (e[3] * x + e[7] * y + e[11] * z + e[15]) / w
    )
end

-- Read a column of translation/position straight out of a world matrix, which
-- is how three.js gets an object's world position.
function Vector3:setFromMatrixPosition(m)
    local e = m:asLinearArray()
    return self:set(e[13], e[14], e[15])
end

function Vector3:setFromMatrixScale(m)
    local e = m:asLinearArray()
    return self:set(
        math.sqrt(e[1] * e[1] + e[2] * e[2] + e[ 3] * e[ 3]),
        math.sqrt(e[5] * e[5] + e[6] * e[6] + e[ 7] * e[ 7]),
        math.sqrt(e[9] * e[9] + e[10] * e[10] + e[11] * e[11])
    )
end

function Vector3:angleTo(v)
    return self:angle(v)
end

function Vector3:toArray()
    return { self.x, self.y, self.z }
end

function Vector3:fromArray(a, offset)
    offset = offset or 0
    return self:set(a[offset + 1], a[offset + 2], a[offset + 3])
end

return Vector3