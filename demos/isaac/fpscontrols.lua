-- Управление от первого лица: mouselook (yaw/pitch) + WASD по полу с
-- коллизией стен room:resolveCircle. В отличие от three.controls.FlyControls
-- (noclip-полёт для дебага) камера всегда стоит на игроке на фиксированной
-- высоте -- это ходьба, а не свободный полёт.
local cfg = require "demos.isaac.config"

local LOOK_SPEED = 0.0025
local PITCH_LIMIT = math.pi * 0.49

local FpsControls = {}
FpsControls.__index = FpsControls

function FpsControls:new(camera)
    local self = setmetatable({}, FpsControls)
    self.camera = camera
    self.yaw = math.pi
    self.pitch = 0
    love.mouse.setRelativeMode(true)
    return self
end

function FpsControls:mousemoved(dx, dy)
    self.yaw = self.yaw - dx * LOOK_SPEED
    self.pitch = math.max(-PITCH_LIMIT, math.min(PITCH_LIMIT, self.pitch - dy * LOOK_SPEED))
end

-- Направление взгляда по полу (Y=0), нормализовано -- то, куда стреляет игрок.
function FpsControls:forwardFlat()
    return math.sin(self.yaw), math.cos(self.yaw)
end

function FpsControls:update(dt, room, player, keys)
    local fx, fz = self:forwardFlat()
    local rx, rz = fz, -fx -- вправо = forward, повёрнутый на -90°

    local dx, dz = 0, 0
    if keys.up    then dx, dz = dx + fx, dz + fz end
    if keys.down  then dx, dz = dx - fx, dz - fz end
    if keys.right then dx, dz = dx + rx, dz + rz end
    if keys.left  then dx, dz = dx - rx, dz - rz end

    if dx ~= 0 or dz ~= 0 then
        local len = math.sqrt(dx * dx + dz * dz)
        dx, dz = dx / len, dz / len
        player.x = player.x + dx * cfg.playerSpeed * dt
        player.z = player.z + dz * cfg.playerSpeed * dt
    end

    player.x, player.z = room:clampToBounds(player.x, player.z, cfg.playerRadius)
    player.x, player.z = room:resolveCircle(player.x, player.z, cfg.playerRadius)

    player.aimX, player.aimZ = fx, fz

    self.camera.position:set(player.x, cfg.eyeHeight, player.z)
    self.camera:lookAt(player.x + fx, cfg.eyeHeight + math.sin(self.pitch), player.z + fz)
end

function FpsControls:dispose()
    love.mouse.setRelativeMode(false)
end

return FpsControls
