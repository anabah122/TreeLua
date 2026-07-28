-- Игрок от первого лица: своей видимой модели нет (камера сидит в глазах,
-- см. fpscontrols.lua), тут только HP/урон и точка выстрела.
local cfg = require "demos.isaac.config"

local Player = {}
Player.__index = Player

function Player:new(TL, scene)
    local self = setmetatable({}, Player)
    self.TL = TL

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

function Player:update(dt)
    if self.invuln > 0 then self.invuln = self.invuln - dt end
    if self.fireCooldown > 0 then self.fireCooldown = self.fireCooldown - dt end
end

function Player:canFire()
    return self.alive and self.fireCooldown <= 0
end

function Player:fire()
    self.fireCooldown = cfg.playerFireRate
    return self.x, self.z, self.aimX, self.aimZ
end

return Player
