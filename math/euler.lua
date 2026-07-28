-- math/euler.lua — three axis angles plus the order they apply in
--
-- Exists because three.js users reach for `object.rotation.x = ...` far more
-- often than they build quaternions by hand. Nothing in the engine consumes an
-- Euler directly: `Object3D` converts to a quaternion, which is what the
-- importers, the skinning palette and mat4:compose all speak.
--
-- Angles are radians, matching three.js and the rest of this engine.

local Euler = {}
Euler.__index = Euler

Euler.DEFAULT_ORDER = "XYZ"

local function clamp(v, lo, hi)
    return math.min(math.max(v, lo), hi)
end

function Euler:new(x, y, z, order)
    return setmetatable({
        x = x or 0,
        y = y or 0,
        z = z or 0,
        order = order or Euler.DEFAULT_ORDER,
        type = 'euler',
    }, Euler)
end

function Euler:set(x, y, z, order)
    self.x, self.y, self.z = x, y, z
    self.order = order or self.order
    return self
end

function Euler:clone()
    return Euler:new(self.x, self.y, self.z, self.order)
end

function Euler:copy(e)
    return self:set(e.x, e.y, e.z, e.order)
end

function Euler:equals(e)
    return self.x == e.x and self.y == e.y
       and self.z == e.z and self.order == e.order
end

-- Extract angles from a pure rotation matrix. The matrix is row-major here, so
-- the element picks differ from three.js even though the algebra matches.
--
-- Each branch clamps its asin argument: a matrix that has been through a few
-- multiplies can land a hair outside [-1,1] and asin would return NaN, which
-- then poisons every transform downstream.
function Euler:setFromRotationMatrix(m, order)
    order = order or self.order

    local m11, m12, m13 = m[1],  m[2],  m[3]
    local m21, m22, m23 = m[5],  m[6],  m[7]
    local m31, m32, m33 = m[9],  m[10], m[11]

    if order == "XYZ" then
        self.y = math.asin(clamp(m13, -1, 1))
        if math.abs(m13) < 0.9999999 then
            self.x = math.atan2(-m23, m33)
            self.z = math.atan2(-m12, m11)
        else
            -- gimbal lock: x and z spin about the same axis, pin z at 0
            self.x = math.atan2(m32, m22)
            self.z = 0
        end
    elseif order == "YXZ" then
        self.x = math.asin(-clamp(m23, -1, 1))
        if math.abs(m23) < 0.9999999 then
            self.y = math.atan2(m13, m33)
            self.z = math.atan2(m21, m22)
        else
            self.y = math.atan2(-m31, m11)
            self.z = 0
        end
    elseif order == "ZXY" then
        self.x = math.asin(clamp(m32, -1, 1))
        if math.abs(m32) < 0.9999999 then
            self.y = math.atan2(-m31, m33)
            self.z = math.atan2(-m12, m22)
        else
            self.y = 0
            self.z = math.atan2(m21, m11)
        end
    elseif order == "ZYX" then
        self.y = math.asin(-clamp(m31, -1, 1))
        if math.abs(m31) < 0.9999999 then
            self.x = math.atan2(m32, m33)
            self.z = math.atan2(m21, m11)
        else
            self.x = 0
            self.z = math.atan2(-m12, m22)
        end
    elseif order == "YZX" then
        self.z = math.asin(clamp(m21, -1, 1))
        if math.abs(m21) < 0.9999999 then
            self.x = math.atan2(-m23, m22)
            self.y = math.atan2(-m31, m11)
        else
            self.x = 0
            self.y = math.atan2(m13, m33)
        end
    elseif order == "XZY" then
        self.z = math.asin(-clamp(m12, -1, 1))
        if math.abs(m12) < 0.9999999 then
            self.x = math.atan2(m32, m22)
            self.y = math.atan2(m13, m11)
        else
            self.x = math.atan2(-m23, m33)
            self.y = 0
        end
    end

    self.order = order
    return self
end

function Euler:setFromQuaternion(q, order)
    local mat4 = require "math.mat4"
    return self:setFromRotationMatrix(
        mat4:new():makeRotationFromQuaternion(q), order or self.order)
end

function Euler:setFromVector3(v, order)
    return self:set(v.x, v.y, v.z, order or self.order)
end

-- Re-derive the angles for a different order, keeping the same rotation.
function Euler:reorder(newOrder)
    local Quaternion = require "math.quat"
    return self:setFromQuaternion(Quaternion:new():setFromEuler(self), newOrder)
end

function Euler:toArray()
    return { self.x, self.y, self.z, self.order }
end

function Euler:fromArray(a, offset)
    offset = offset or 0
    return self:set(a[offset + 1], a[offset + 2], a[offset + 3],
                    a[offset + 4] or self.order)
end

function Euler:__tostring()
    return string.format("(%g, %g, %g, %s)", self.x, self.y, self.z, self.order)
end

return Euler
