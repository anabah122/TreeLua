-- Тестовая сцена для новых фич: Fog/FogExp2, HemisphereLight, Line/LineSegments, ParticleSystem.
-- Движок используется только как библиотека — вся логика лежит в three/ и
-- shader/, здесь только сборка сцены и визуальная/консольная проверка.
local TL = require "init"

local M = {}

local scene, camera, renderer, controls
local axes, fogMode

function M.init()
    love.window.setTitle("TreeEngine — fog / hemisphere light / lines test")

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x2a3038)

    camera = TL.PerspectiveCamera:new(55, w / h, 0.1, 100)
    camera.position:set(4, 3, 8)
    camera:lookAt(0, 0, 0)

    controls = TL.FlyControls:new(camera, { movementSpeed = 4 })

    renderer = TL.WebGLRenderer:new()

    -- Fog: exp2 by default, toggled to linear/off with keys (see keypressed).
    fogMode = "exp2"
    scene.fog = TL.FogExp2:new(0x2a3038, 0.06)

    -- HemisphereLight instead of AmbientLight: sky/ground split, no shadows.
    scene:add(TL.HemisphereLight:new(0x88ccff, 0x554433, 1))

    local sun = TL.DirectionalLight:new(0xfff3e0, 0.8)
    sun.position:set(3, 6, 2)
    scene:add(sun)

    -- A grid of boxes receding into the distance, so the fog falloff is visible.
    for i = 1, 8 do
        local geo = TL.BoxGeometry:new(1, 1, 1)
        local mat = TL.MeshStandardMaterial:new{ color = 0x8899aa, roughness = 0.8 }
        local box = TL.Mesh:new(geo, mat)
        box.position:set(0, 0.5, -i * 3)
        scene:add(box)
    end

    -- LineSegments: three axis gizmo at the origin (red/green/blue).
    local axisPoints = {
        TL.Vector3:new(0, 0, 0), TL.Vector3:new(2, 0, 0),
        TL.Vector3:new(0, 0, 0), TL.Vector3:new(0, 2, 0),
        TL.Vector3:new(0, 0, 0), TL.Vector3:new(0, 0, 2),
    }
    axes = TL.LineSegments:new(
        TL.LineGeometry:new(axisPoints),
        TL.LineBasicMaterial:new{ color = 0xffffff, linewidth = 2 }
    )
    scene:add(axes)

    -- Line: a closed square loop (continuous strip) a bit off to the side.
    local loopPoints = {
        TL.Vector3:new(-1, 0.01, 3), TL.Vector3:new(1, 0.01, 3),
        TL.Vector3:new(1, 0.01, 5),  TL.Vector3:new(-1, 0.01, 5),
        TL.Vector3:new(-1, 0.01, 3),
    }
    local loop = TL.Line:new(
        TL.LineGeometry:new(loopPoints),
        TL.LineBasicMaterial:new{ color = 0xffdd33 }
    )
    scene:add(loop)

    -- GPU particles: a fire-like cone emitter, purely shader-simulated.
    local fire = TL.ParticleSystem:new{
        count      = 500,
        lifetime   = 1.5,
        spawnShape = "cone",
        coneAngle  = 0.3,
        direction  = TL.Vector3:new(0, 1, 0),
        speed      = { 1, 2.5 },
        gravity    = TL.Vector3:new(0, 0.5, 0),
        size       = { 0.3, 0.05 },
        color      = { TL.Color:new(0xffcc66), TL.Color:new(0xff2200) },
        opacity    = { 1, 0 },
    }
    fire.position:set(0, 0.5, 0)
    scene:add(fire)

    print("[demo] F: toggle fog mode (exp2 -> linear -> off), current: " .. fogMode)
end

function M.update(dt)
    controls:update(dt)
end

function M.resize(w, h)
    renderer:setSize(w, h, camera)
end

function M.keypressed(k)
    if k == "escape" then love.event.quit() end
    if k == "f" then
        if fogMode == "exp2" then
            fogMode = "linear"
            scene.fog = TL.Fog:new(0x2a3038, 2, 18)
        elseif fogMode == "linear" then
            fogMode = "off"
            scene.fog = nil
        else
            fogMode = "exp2"
            scene.fog = TL.FogExp2:new(0x2a3038, 0.06)
        end
        print("[demo] fog mode: " .. fogMode)
    end
end

function M.mousemoved(x, y, dx, dy) controls:mousemoved(dx, dy) end
function M.wheelmoved(dx, dy)       controls:wheelmoved(dy)     end

function M.draw()
    renderer:render(scene, camera)
end

return M
