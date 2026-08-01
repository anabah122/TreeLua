-- math/quat.lua — rotation quaternion
--
-- Written against the three.js `Quaternion` docs from the start, so unlike
-- vec3/mat4 there is no older immutable surface underneath: every method here
-- mutates `self` and returns it, and calls chain.
--
-- The importers already speak raw {x,y,z,w} arrays for node rotations, and
-- `common.slerp` interpolates them by component. This class is the typed face
-- of the same data -- `fromArray`/`toArray` cross that boundary.

local Quaternion = {}
Quaternion.__index = Quaternion

local function clamp(v, lo, hi)
    return math.min(math.max(v, lo), hi)
end

-- Identity by default: no rotation, which is what an unset node carries.
function Quaternion:new(x, y, z, w)
    return setmetatable({
        x = x or 0,
        y = y or 0,
        z = z or 0,
        w = w == nil and 1 or w,
        type = 'quat',
    }, Quaternion)
end

function Quaternion:set(x, y, z, w)
    self.x, self.y, self.z, self.w = x, y, z, w
    return self
end

function Quaternion:clone()
    return Quaternion:new(self.x, self.y, self.z, self.w)
end

function Quaternion:copy(q)
    return self:set(q.x, q.y, q.z, q.w)
end

function Quaternion:identity()
    return self:set(0, 0, 0, 1)
end

function Quaternion:equals(q)
    return self.x == q.x and self.y == q.y and self.z == q.z and self.w == q.w
end

function Quaternion:length()
    return math.sqrt(self.x * self.x + self.y * self.y +
                     self.z * self.z + self.w * self.w)
end

function Quaternion:lengthSq()
    return self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w
end

function Quaternion:normalize()
    local len = self:length()
    if len == 0 then return self:identity() end
    return self:set(self.x / len, self.y / len, self.z / len, self.w / len)
end

-- Conjugate is the inverse for unit quaternions, which is all this engine
-- produces; three.js documents `invert` as exactly that.
function Quaternion:conjugate()
    return self:set(-self.x, -self.y, -self.z, self.w)
end

function Quaternion:invert()
    return self:conjugate()
end

function Quaternion:dot(q)
    return self.x * q.x + self.y * q.y + self.z * q.z + self.w * q.w
end

function Quaternion:setFromAxisAngle(axis, angle)
    local half = angle / 2
    local s    = math.sin(half)
    local ax   = axis.x or axis[1]
    local ay   = axis.y or axis[2]
    local az   = axis.z or axis[3]
    return self:set(ax * s, ay * s, az * s, math.cos(half))
end

-- three.js supports six Euler orders; XYZ and YXZ cover everything this engine
-- actually emits (importers give quaternions directly, and the camera is
-- yaw/pitch), so the rest fall back to XYZ rather than silently misrotating.
function Quaternion:setFromEuler(euler)
    local x, y, z = euler.x or euler[1], euler.y or euler[2], euler.z or euler[3]
    local order   = euler.order or "XYZ"

    local c1, c2, c3 = math.cos(x / 2), math.cos(y / 2), math.cos(z / 2)
    local s1, s2, s3 = math.sin(x / 2), math.sin(y / 2), math.sin(z / 2)

    if order == "YXZ" then
        return self:set(
            s1 * c2 * c3 + c1 * s2 * s3,
            c1 * s2 * c3 - s1 * c2 * s3,
            c1 * c2 * s3 - s1 * s2 * c3,
            c1 * c2 * c3 + s1 * s2 * s3
        )
    elseif order == "ZXY" then
        return self:set(
            s1 * c2 * c3 - c1 * s2 * s3,
            c1 * s2 * c3 + s1 * c2 * s3,
            c1 * c2 * s3 + s1 * s2 * c3,
            c1 * c2 * c3 - s1 * s2 * s3
        )
    elseif order == "ZYX" then
        return self:set(
            s1 * c2 * c3 - c1 * s2 * s3,
            c1 * s2 * c3 + s1 * c2 * s3,
            c1 * c2 * s3 - s1 * s2 * c3,
            c1 * c2 * c3 + s1 * s2 * s3
        )
    elseif order == "YZX" then
        return self:set(
            s1 * c2 * c3 + c1 * s2 * s3,
            c1 * s2 * c3 + s1 * c2 * s3,
            c1 * c2 * s3 - s1 * s2 * c3,
            c1 * c2 * c3 - s1 * s2 * s3
        )
    elseif order == "XZY" then
        return self:set(
            s1 * c2 * c3 - c1 * s2 * s3,
            c1 * s2 * c3 - s1 * c2 * s3,
            c1 * c2 * s3 + s1 * s2 * c3,
            c1 * c2 * c3 + s1 * s2 * s3
        )
    end

    -- XYZ
    return self:set(
        s1 * c2 * c3 + c1 * s2 * s3,
        c1 * s2 * c3 - s1 * c2 * s3,
        c1 * c2 * s3 + s1 * s2 * c3,
        c1 * c2 * c3 - s1 * s2 * s3
    )
end

-- Reads the rotation out of a matrix, ignoring its scale. Delegates to
-- mat4:decompose so there is one trace-based extraction, not two.
function Quaternion:setFromRotationMatrix(m)
    local vec3 = require "math.vec3"
    m:decompose(vec3:new(0, 0, 0), self, vec3:new(1, 1, 1))
    return self
end

-- Shortest rotation carrying `from` onto `to`; both are assumed unit length.
function Quaternion:setFromUnitVectors(from, to)
    local r = from:dot(to) + 1

    if r < 1e-6 then
        -- opposite vectors: no unique arc, so spin about any perpendicular axis
        if math.abs(from.x) > math.abs(from.z) then
            return self:set(-from.y, from.x, 0, 0):normalize()
        end
        return self:set(0, -from.z, from.y, 0):normalize()
    end

    return self:set(
        from.y * to.z - from.z * to.y,
        from.z * to.x - from.x * to.z,
        from.x * to.y - from.y * to.x,
        r
    ):normalize()
end

function Quaternion:multiplyQuaternions(a, b)
    return self:set(
        a.x * b.w + a.w * b.x + a.y * b.z - a.z * b.y,
        a.y * b.w + a.w * b.y + a.z * b.x - a.x * b.z,
        a.z * b.w + a.w * b.z + a.x * b.y - a.y * b.x,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
    )
end

function Quaternion:multiply(q)
    return self:multiplyQuaternions(self:clone(), q)
end

function Quaternion:premultiply(q)
    return self:multiplyQuaternions(q, self:clone())
end

-- Spherical interpolation. Falls back to a plain lerp when the two are nearly
-- parallel, where sin(theta) underflows and the general form blows up.
function Quaternion:slerp(q, t)
    if t == 0 then return self end
    if t == 1 then return self:copy(q) end

    local x, y, z, w = self.x, self.y, self.z, self.w
    local cosHalf = w * q.w + x * q.x + y * q.y + z * q.z

    -- take the short way round
    local qx, qy, qz, qw = q.x, q.y, q.z, q.w
    if cosHalf < 0 then
        cosHalf = -cosHalf
        qx, qy, qz, qw = -qx, -qy, -qz, -qw
    end

    if cosHalf >= 1.0 then
        return self:set(x, y, z, w)
    end

    local sinHalfSq = 1.0 - cosHalf * cosHalf
    if sinHalfSq <= 1e-6 then
        local s = 1 - t
        return self:set(s * x + t * qx,
                        s * y + t * qy,
                        s * z + t * qz,
                        s * w + t * qw):normalize()
    end

    local sinHalf = math.sqrt(sinHalfSq)
    local halfAng = math.atan2(sinHalf, cosHalf)
    local ratioA  = math.sin((1 - t) * halfAng) / sinHalf
    local ratioB  = math.sin(t * halfAng) / sinHalf

    return self:set(x * ratioA + qx * ratioB,
                    y * ratioA + qy * ratioB,
                    z * ratioA + qz * ratioB,
                    w * ratioA + qw * ratioB)
end

function Quaternion:slerpQuaternions(a, b, t)
    return self:copy(a):slerp(b, t)
end

function Quaternion:angleTo(q)
    return 2 * math.acos(clamp(math.abs(self:dot(q)), -1, 1))
end

function Quaternion:rotateTowards(q, step)
    local angle = self:angleTo(q)
    if angle == 0 then return self end
    return self:slerp(q, math.min(1, step / angle))
end

function Quaternion:toArray()
    return { self.x, self.y, self.z, self.w }
end

function Quaternion:fromArray(a, offset)
    offset = offset or 0
    return self:set(a[offset + 1], a[offset + 2],
                    a[offset + 3], a[offset + 4])
end

function Quaternion:__tostring()
    return string.format("(%g, %g, %g, %g)", self.x, self.y, self.z, self.w)
end

return Quaternion
