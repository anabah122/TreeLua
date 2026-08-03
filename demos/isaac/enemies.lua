-- Враги-преследователи с анимированной glTF-моделью.
-- Модель (geometry/material/скелет/клипы) грузится с диска РОВНО ОДИН РАЗ в
-- Model-синглтон; каждый враг -- это Model:createInstance(), лёгкая обёртка
-- со своим transform, своим (склонированным) скелетом-позой и своим
-- AnimationMixer. Скелет/скиннинг у инстансов независимы, поэтому миксеры не
-- конкурируют за одни и те же кости, а сама модель при этом не парсится
-- заново на каждого врага.
local cfg = require "demos.isaac.config"
local Vector3 = require "engine.math.vec3"
local Quaternion = require "engine.math.quat"

local MODEL_PATH = "assets/model/model3dtest.glb"
local ENEMY_SCALE = 0.55
local FORWARD = Vector3:new(0, 0, 1)
local scratchQ = Quaternion:new()
local scratchDir = Vector3:new()

local Enemies = {}
Enemies.__index = Enemies

function Enemies:new(TL, scene)
    local self = setmetatable({}, Enemies)
    self.TL = TL
    self.scene = scene
    self.list = {}
    self.model = TL.Model:fromLoaderResult(TL.GLTFLoader:new():load(MODEL_PATH))
    return self
end

function Enemies:spawn(x, z)
    local instance = self.model:createInstance()
    local model = instance.scene
    model.scale:set(ENEMY_SCALE, ENEMY_SCALE, ENEMY_SCALE)
    model.position:set(x, 0, z)
    self.scene:add(model)

    local mixer = instance.mixer
    if instance.animations[1] then
        mixer:clipAction(instance.animations[1]):play()
    end

    self.list[#self.list + 1] = {
        model = model, mixer = mixer,
        x = x, z = z, hp = cfg.enemyHp, maxHp = cfg.enemyHp, touchCooldown = 0,
    }
end

function Enemies:count()
    return #self.list
end

function Enemies:update(dt, room, player)
    for i = #self.list, 1, -1 do
        local e = self.list[i]
        e.mixer:update(dt)
        if e.touchCooldown > 0 then e.touchCooldown = e.touchCooldown - dt end

        local dx, dz = player.x - e.x, player.z - e.z
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 1e-4 then
            dx, dz = dx / len, dz / len
            e.x = e.x + dx * cfg.enemySpeed * dt
            e.z = e.z + dz * cfg.enemySpeed * dt
            -- Кватернион кратчайшего поворота вместо rotation.y = atan2(...):
            -- избегает разрыва Euler-угла на +-pi, из-за которого поворот дёргался.
            scratchDir:set(dx, 0, dz)
            scratchQ:setFromUnitVectors(FORWARD, scratchDir)
            e.model:setRotationFromQuaternion(scratchQ)
        end
        e.x, e.z = room:resolveCircle(e.x, e.z, cfg.enemyRadius)
        e.model.position.x = e.x
        e.model.position.z = e.z

        if len < cfg.enemyRadius + cfg.playerRadius and e.touchCooldown <= 0 then
            player:takeDamage(cfg.enemyContactDmg)
            e.touchCooldown = cfg.enemyTouchCooldown
        end
    end
end

-- Наносит урон первому врагу, чей круг пересекает (x,z,radius); возвращает true при попадании.
-- onDeath(x, z), если задан, вызывается с координатами врага в момент смерти.
function Enemies:damageAt(x, z, radius, onDeath)
    for i = #self.list, 1, -1 do
        local e = self.list[i]
        local dx, dz = x - e.x, z - e.z
        local rr = radius + cfg.enemyRadius
        if dx * dx + dz * dz < rr * rr then
            e.hp = e.hp - 1
            if e.hp <= 0 then
                self.scene:remove(e.model)
                table.remove(self.list, i)
                if onDeath then onDeath(e.x, e.z) end
            end
            return true
        end
    end
    return false
end

return Enemies
