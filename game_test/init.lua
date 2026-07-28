-- Тестовая игра на TreeEngine: минималистичный клон Айзека с 3D-визуализацией.
-- Движок используется только как библиотека (require "init"), файлы движка не меняются.
local TL = require "init"
local Vector3 = require "math.vec3"

local cfg      = require "game_test.config"
local Room     = require "game_test.room"
local Player   = require "game_test.player"
local Tears    = require "game_test.tears"
local Enemies  = require "game_test.enemies"
local HpBar    = require "game_test.hpbar"
local Aim      = require "game_test.aim"
local Boss     = require "game_test.boss"
local Decor    = require "game_test.decor"

local M = {}

local scene, camera, renderer
local room, player, tears, enemies, aim, boss
local orbitControls
local debugCamera = false
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
    love.window.setTitle("TreeEngine test game — Isaac-like")

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x0e1016)

    camera = TL.PerspectiveCamera:new(50, w / h, 0.1, 100)
    camera.position:set(0, cfg.camHeight, cfg.camBack)
    camera:lookAt(0, 0, 0)

    renderer = TL.WebGLRenderer:new()

    local sun = TL.DirectionalLight:new(0xfff3e0, 1)
    sun.position:set(0.4, 1.0, 0.3)
    scene:add(sun)
    scene:add(TL.AmbientLight:new(0x4a4f5c, 1))

    room    = Room:new(TL, scene)
    player  = Player:new(TL, scene)
    tears   = Tears:new(TL, scene)
    enemies = Enemies:new(TL, scene)
    aim     = Aim:new()
    boss    = Boss:new(TL, scene)
    Decor:spawn(TL, scene)

    orbitControls = TL.OrbitControls:new(camera, { target = Vector3:new(0, 0, 0) })
    debugCamera = false

    spawnWave()
end

local function restart()
    -- simplest reset: rebuild scene from scratch
    M.init()
    roomCleared = false
    gameOver = false
end

function M.update(dt)
    if debugCamera then
        orbitControls:update(dt)
        boss.lod:update(camera) -- LOD still needs an up-to-date camera distance
        return
    end

    if gameOver then return end

    player:update(dt, room, keys)
    if not player.alive then
        gameOver = true
        return
    end

    local mx, mz = aim:groundPointUnderCursor(camera)
    if mx then player:aimAt(mx, mz) end

    enemies:update(dt, room, player)
    boss:update(dt, room, player, camera)
    tears:update(dt, room, function(x, z, r)
        return enemies:damageAt(x, z, r) or boss:damageAt(x, z, r)
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
    if k == "space" and player:canFire() and not gameOver and not debugCamera then
        local x, z, dx, dz = player:fire()
        tears:spawn(x, z, dx, dz)
    end
    if k == "tab" then
        debugCamera = not debugCamera
        if not debugCamera then
            camera.position:set(0, cfg.camHeight, cfg.camBack)
            camera:lookAt(0, 0, 0)
        end
    end
end

function M.keyreleased(k)
    if k == "w" or k == "up"    then keys.up    = false end
    if k == "s" or k == "down"  then keys.down  = false end
    if k == "a" or k == "left"  then keys.left  = false end
    if k == "d" or k == "right" then keys.right = false end
end

function M.mousemoved(x, y, dx, dy)
    if debugCamera then orbitControls:mousemoved(x, y, dx, dy) end
end

function M.wheelmoved(dx, dy)
    if debugCamera then orbitControls:wheelmoved(dy) end
end

local function drawHpBars()
    if player.alive then
        local sx, sy, visible = HpBar.worldToScreen(
            player.x, player.mesh.position.y + 0.7, player.z, camera)
        if visible then
            HpBar.draw(sx, sy, player.hp / cfg.playerHp, 60)
        end
    end

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
        ("WASD move   mouse aim   SPACE shoot   TAB debug camera   R restart   ESC quit\nHP %d/%d   enemies left: %d"):format(
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
