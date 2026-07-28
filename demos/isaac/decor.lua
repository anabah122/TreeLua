-- Декоративные камни по периметру комнаты, отрисованные одним InstancedMesh.
local cfg     = require "demos.isaac.config"
local Matrix4 = require "math.mat4"
local Quaternion = require "math.quat"
local Vector3 = require "math.vec3"

local Decor = {}

local UP = Vector3:new(0, 1, 0)

function Decor:spawn(TL, scene)
    local positions = {}
    local w, d = cfg.roomHalfW - 0.8, cfg.roomHalfD - 0.8
    local n = 14
    for i = 1, n do
        local t = (i - 1) / n * math.pi * 2
        local x = math.cos(t) * w
        local z = math.sin(t) * d
        positions[#positions + 1] = { x = x, z = z }
    end

    local geometry = TL.SphereGeometry:new(0.35, 8, 6)
    local material = TL.MeshStandardMaterial:new{ color = 0x6b6357, metalness = 0, roughness = 1 }
    local field = TL.InstancedMesh:new(geometry, material, #positions)

    local m = Matrix4:new()
    local q = Quaternion:new()
    for i, p in ipairs(positions) do
        q:setFromAxisAngle(UP, math.random() * math.pi * 2)
        local s = 0.7 + math.random() * 0.6
        m:compose({ x = p.x, y = 0.35, z = p.z }, q, { x = s, y = s, z = s })
        field:setMatrixAt(i, m)
    end

    scene:add(field)
    return field
end

return Decor
