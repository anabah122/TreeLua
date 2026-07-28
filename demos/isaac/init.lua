-- Тестовая игра на TreeEngine: минималистичный клон Айзека с 3D-визуализацией.
-- Движок используется только как библиотека (require "init"), файлы движка не меняются.
local TL = require "init"

local cfg         = require "demos.isaac.config"
local Room        = require "demos.isaac.room"
local Player      = require "demos.isaac.player"
local Tears       = require "demos.isaac.tears"
local Enemies     = require "demos.isaac.enemies"
local HpBar       = require "demos.isaac.hpbar"
local Boss        = require "demos.isaac.boss"
local Decor       = require "demos.isaac.decor"
local Pickups     = require "demos.isaac.pickups"
local FpsControls = require "demos.isaac.fpscontrols"

local M = {}

local scene, camera, renderer
local room, player, tears, enemies, boss, pickups, controls
local keys = { up = false, down = false, left = false, right = false }
local roomCleared = false
local gameOver = false

local function spawnWave()
    enemies:spawn(-4, -3)
    enemies:spawn(4, -3)
    enemies:spawn(0, 4)
    enemies:spawn(-5, 2)
end

function M.init()
    love.window.setTitle("TreeEngine test game — FPS maze")

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x0e1016)

    camera = TL.PerspectiveCamera:new(70, w / h, 0.1, 100)

    renderer = TL.WebGLRenderer:new()

    local sun = TL.DirectionalLight:new(0xfff3e0, 1)
    sun.position:set(0.4, 1.0, 0.3)
    scene:add(sun)
    scene:add(TL.AmbientLight:new(0x4a4f5c, 1))

    room = Room:new(TL, scene)
    local startX, startZ = room:buildMaze(TL, scene, 2)

    player  = Player:new(TL, scene)
    player.x, player.z = startX, startZ

    tears   = Tears:new(TL, scene)
    enemies = Enemies:new(TL, scene)
    boss    = Boss:new(TL, scene)
    pickups = Pickups:new(TL, scene)
    Decor:spawn(TL, scene)

    controls = FpsControls:new(camera)
    controls.camera.position:set(player.x, cfg.eyeHeight, player.z)

    spawnWave()
end

local function restart()
    -- simplest reset: rebuild scene from scratch
    M.init()
    roomCleared = false
    gameOver = false
end

function M.update(dt)
    if gameOver then return end

    player:update(dt)
    if not player.alive then
        gameOver = true
        return
    end

    controls:update(dt, room, player, keys)

    enemies:update(dt, room, player)
    boss:update(dt, room, player, camera)
    pickups:update(dt, player)
    tears:update(dt, room, function(x, z, r)
        local dropPickup = function(dx, dz) pickups:spawn(dx, dz) end
        return enemies:damageAt(x, z, r, dropPickup) or boss:damageAt(x, z, r, dropPickup)
    end)

    if enemies:count() == 0 and not boss.alive then
        roomCleared = true
    end
end

function M.resize(w, h)
    renderer:setSize(w, h, camera)
end

function M.keypressed(k)
    if k == "escape" then love.event.quit() end
    if k == "w" or k == "up"    then keys.up    = true end
    if k == "s" or k == "down"  then keys.down  = true end
    if k == "a" or k == "left"  then keys.left  = true end
    if k == "d" or k == "right" then keys.right = true end
    if k == "r" and (gameOver or roomCleared) then restart() end
    if k == "space" and player:canFire() and not gameOver then
        local x, z, dx, dz = player:fire()
        tears:spawn(x, z, dx, dz)
    end
end

function M.keyreleased(k)
    if k == "w" or k == "up"    then keys.up    = false end
    if k == "s" or k == "down"  then keys.down  = false end
    if k == "a" or k == "left"  then keys.left  = false end
    if k == "d" or k == "right" then keys.right = false end
end

function M.mousemoved(x, y, dx, dy)
    controls:mousemoved(dx, dy)
end

function M.mousepressed(button)
    if button == 1 and player:canFire() and not gameOver then
        local x, z, dx, dz = player:fire()
        tears:spawn(x, z, dx, dz)
    end
end

local function drawHpBars()
    for _, e in ipairs(enemies.list) do
        local sx, sy, visible = HpBar.worldToScreen(e.x, 1.2, e.z, camera)
        if visible then
            HpBar.draw(sx, sy, e.hp / e.maxHp, 46)
        end
    end

    if boss.alive then
        local sx, sy, visible = HpBar.worldToScreen(boss.x, 2.2, boss.z, camera)
        if visible then
            HpBar.draw(sx, sy, boss.hp / boss.maxHp, 90)
        end
    end
end

local function drawHud()
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, 420, 60)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        ("WASD move   mouse look   SPACE/click shoot   R restart   ESC quit\nHP %d/%d   enemies left: %d"):format(
            player.hp, cfg.playerHp, enemies:count()),
        10, 10)

    if gameOver then
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, love.graphics.getHeight() / 2 - 30, love.graphics.getWidth(), 60)
        love.graphics.setColor(1, 0.3, 0.3, 1)
        love.graphics.printf("YOU DIED — press R to restart", 0, love.graphics.getHeight() / 2 - 10,
            love.graphics.getWidth(), "center")
    elseif roomCleared then
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, love.graphics.getHeight() / 2 - 30, love.graphics.getWidth(), 60)
        love.graphics.setColor(0.4, 1, 0.5, 1)
        love.graphics.printf("ROOM CLEARED — press R to restart", 0, love.graphics.getHeight() / 2 - 10,
            love.graphics.getWidth(), "center")
    end
end

function M.draw()
    renderer:render(scene, camera)
    drawHpBars()
    drawHud()
end

return M
