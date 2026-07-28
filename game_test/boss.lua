-- Босс: анимированная glTF-модель (LOD "high") + примитивный заменитель
-- ("low"), переключаемые вручную через LOD:update(camera), как требует README.
local cfg = require "game_test.config"
local Vector3 = require "math.vec3"
local Quaternion = require "math.quat"

local FORWARD = Vector3:new(0, 0, 1)
local scratchQ = Quaternion:new()
local scratchDir = Vector3:new()

local Boss = {}
Boss.__index = Boss

local bossCfg = {
    speed        = 1.1,
    radius       = 0.9,
    hp           = 12,
    contactDmg   = 1,
    touchCooldown = 0.8,
    scale        = 0.9,
    lowDistance  = 12, -- за этой дистанцией камера видит только box-заменитель
}

function Boss:new(TL, scene)
    local self = setmetatable({}, Boss)
    self.TL = TL
    self.scene = scene

    local gltf = TL.GLTFLoader:new():load("assets/model/model3dtest.glb")
    self.highDetail = gltf.scene
    self.highDetail.scale:set(bossCfg.scale, bossCfg.scale, bossCfg.scale)

    local lowMat = TL.MeshStandardMaterial:new{ color = 0x8a2a6b, metalness = 0, roughness = 0.9 }
    self.lowDetail = TL.Mesh:new(TL.BoxGeometry:new(1, 1.8, 1), lowMat)
    self.lowDetail.position.y = 0.9

    self.lod = TL.LOD:new()
    self.lod:addLevel(self.highDetail, 0)
    self.lod:addLevel(self.lowDetail, bossCfg.lowDistance)
    scene:add(self.lod)

    self.mixer = TL.AnimationMixer:new(self.highDetail)
    if gltf.animations[1] then
        self.mixer:clipAction(gltf.animations[1]):play()
    end

    self.x, self.z = 0, -4.5
    self.lod.position:set(self.x, 0, self.z)

    self.hp = bossCfg.hp
    self.maxHp = bossCfg.hp
    self.touchCooldown = 0
    self.alive = true

    return self
end

function Boss:update(dt, room, player, camera)
    if not self.alive then return end

    self.mixer:update(dt)
    if self.touchCooldown > 0 then self.touchCooldown = self.touchCooldown - dt end

    local dx, dz = player.x - self.x, player.z - self.z
    local len = math.sqrt(dx * dx + dz * dz)
    if len > 1e-4 then
        dx, dz = dx / len, dz / len
        self.x = self.x + dx * bossCfg.speed * dt
        self.z = self.z + dz * bossCfg.speed * dt
    end
    self.x, self.z = room:resolveCircle(self.x, self.z, bossCfg.radius)

    self.lod.position.x = self.x
    self.lod.position.z = self.z
    -- Кватернион кратчайшего поворота FORWARD -> направление к игроку, а не
    -- rotation.y = atan2(...): atan2 перескакивает через ±π при обходе цели
    -- вокруг босса, и запись Euler-угла с разрывом даёт мгновенный разворот
    -- на кадре разрыва -- выглядит как "дёрганье".
    if len > 1e-4 then
        scratchDir:set(dx, 0, dz)
        scratchQ:setFromUnitVectors(FORWARD, scratchDir)
        self.highDetail:setRotationFromQuaternion(scratchQ)
    end

    self.lod:update(camera)

    if len < bossCfg.radius + cfg.playerRadius and self.touchCooldown <= 0 then
        player:takeDamage(bossCfg.contactDmg)
        self.touchCooldown = bossCfg.touchCooldown
    end
end

function Boss:damageAt(x, z, radius)
    if not self.alive then return false end
    local dx, dz = x - self.x, z - self.z
    local rr = radius + bossCfg.radius
    if dx * dx + dz * dz < rr * rr then
        self.hp = self.hp - 1
        if self.hp <= 0 then
            self.hp = 0
            self.alive = false
            self.scene:remove(self.lod)
        end
        return true
    end
    return false
end

return Boss
