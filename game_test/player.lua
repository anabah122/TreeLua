-- Игрок: движение WASD, прицел мышью по полу, стрельба слезами (tears).
local cfg = require "game_test.config"

local Player = {}
Player.__index = Player

function Player:new(TL, scene)
    local self = setmetatable({}, Player)
    self.TL = TL

    local mat = TL.MeshStandardMaterial:new{ color = 0xf2d9b0, metalness = 0, roughness = 0.6 }
    self.mesh = TL.Mesh:new(TL.BoxGeometry:new(0.6, 0.6, 0.6), mat)
    self.mesh.position.y = 0.3
    scene:add(self.mesh)

    self.x, self.z = 0, 0
    self.hp = cfg.playerHp
    self.fireCooldown = 0
    self.invuln = 0
    self.aimX, self.aimZ = 0, 1
    self.alive = true

    return self
end

function Player:takeDamage(amount)
    if self.invuln > 0 or not self.alive then return end
    self.hp = self.hp - amount
    self.invuln = cfg.playerInvuln
    if self.hp <= 0 then
        self.hp = 0
        self.alive = false
    end
end

function Player:update(dt, room, keys)
    if self.invuln > 0 then self.invuln = self.invuln - dt end
    if self.fireCooldown > 0 then self.fireCooldown = self.fireCooldown - dt end
    if not self.alive then return end

    local dx, dz = 0, 0
    if keys.up    then dz = dz - 1 end
    if keys.down  then dz = dz + 1 end
    if keys.left  then dx = dx - 1 end
    if keys.right then dx = dx + 1 end

    if dx ~= 0 or dz ~= 0 then
        local len = math.sqrt(dx * dx + dz * dz)
        dx, dz = dx / len, dz / len
        self.x = self.x + dx * cfg.playerSpeed * dt
        self.z = self.z + dz * cfg.playerSpeed * dt
    end

    self.x, self.z = room:clampToBounds(self.x, self.z, cfg.playerRadius)
    self.x, self.z = room:resolveCircle(self.x, self.z, cfg.playerRadius)

    self.mesh.position.x = self.x
    self.mesh.position.z = self.z

    -- flash while invulnerable
    self.mesh.visible = self.invuln <= 0 or math.floor(self.invuln * 12) % 2 == 0
end

-- Обновляет прицел по точке на полу (Y=0), куда целится мышь.
function Player:aimAt(worldX, worldZ)
    local dx, dz = worldX - self.x, worldZ - self.z
    local len = math.sqrt(dx * dx + dz * dz)
    if len > 1e-4 then
        self.aimX, self.aimZ = dx / len, dz / len
    end
end

function Player:canFire()
    return self.alive and self.fireCooldown <= 0
end

function Player:fire()
    self.fireCooldown = cfg.playerFireRate
    return self.x, self.z, self.aimX, self.aimZ
end

return Player
