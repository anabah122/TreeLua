-- Тестовая сцена для пост-процессинга (three/postprocessing/): EffectComposer
-- + RenderPass + BloomPass поверх обычной сцены. Проверяет оба источника
-- bloom-канала: emissive-материалы (MeshStandardMaterial.emissive) и GPU-
-- частицы (всегда unlit, весь их цвет уходит во второй MRT-таргет).
-- Движок используется только как библиотека — без изменений в three/ или shader/.
local TL = require "init"

local M = {}

local scene, camera, renderer, composer, controls
local bloomPass

function M.init()
    love.window.setTitle("TreeEngine — bloom post-processing test")

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x0a0a12)

    camera = TL.PerspectiveCamera:new(55, w / h, 0.1, 100)
    camera.position:set(0, 3, 10)
    camera:lookAt(0, 1, 0)

    controls = TL.FlyControls:new(camera, { movementSpeed = 6 })

    renderer = TL.WebGLRenderer:new()

    scene:add(TL.HemisphereLight:new(0x334455, 0x110814, 0.4))
    local sun = TL.DirectionalLight:new(0xccccff, 0.3)
    sun.position:set(3, 6, 2)
    scene:add(sun)

    local floor = TL.Mesh:new(
        TL.PlaneGeometry:new(24, 24),
        TL.MeshStandardMaterial:new{ color = 0x1a1a22, roughness = 1 }
    )
    floor:rotateX(-math.pi / 2)
    scene:add(floor)

    -- A row of emissive boxes, each a different colour/intensity, so the
    -- threshold behaviour is visible: dim ones stay dark, bright ones bloom.
    local emissiveColors = { 0xff2244, 0xff8822, 0xffee44, 0x44ff88, 0x44aaff, 0xaa44ff }
    for i, hex in ipairs(emissiveColors) do
        local mat = TL.MeshStandardMaterial:new{ color = 0x111111, roughness = 0.6 }
        mat.emissive:set(hex)
        mat.emissiveIntensity = i * 0.6   -- ramps from barely-there to blown-out
        local box = TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), mat)
        box.position:set((i - (#emissiveColors + 1) / 2) * 2, 0.5, -2)
        scene:add(box)
    end

    -- A couple of particle emitters -- unlit, so their entire colour blooms.
    local fire = TL.ParticleSystem:new{
        count = 500, lifetime = 1.2, spawnShape = "cone", coneAngle = 0.25,
        direction = TL.Vector3:new(0, 1, 0), speed = { 1.5, 3 },
        gravity = TL.Vector3:new(0, 1.2, 0), size = { 0.35, 0.05 },
        color = { TL.Color:new(0xffdd66), TL.Color:new(0xff2200) }, opacity = { 1, 0 },
    }
    fire.position:set(-4, 0, 3)
    scene:add(fire)

    local magic = TL.ParticleSystem:new{
        count = 300, lifetime = 3, spawnShape = "sphere", spawnRadius = 0.6,
        speed = { 0.1, 0.4 }, gravity = TL.Vector3:new(0, 0.05, 0), size = { 0.08, 0.18 },
        color = { TL.Color:new(0x66ccff), TL.Color:new(0xaa66ff) }, opacity = { 1, 0 },
    }
    magic.position:set(4, 1.5, 3)
    scene:add(magic)

    -- Composer: RenderPass fills the MRT pair, BloomPass blurs the bright
    -- target and composites it back over the scene onto the screen.
    composer = TL.EffectComposer:new(renderer)
    composer:addPass(TL.RenderPass:new(scene, camera))
    bloomPass = TL.BloomPass:new{ threshold = 0.5, intensity = 1.5, blurRadius = 1.5, blurPasses = 2 }
    composer:addPass(bloomPass)

    print("[demo] Q/E: bloom intensity down/up, current: " .. bloomPass.intensity)
end

function M.update(dt)
    controls:update(dt)
end

function M.resize(w, h)
    renderer:setSize(w, h, camera)
end

function M.keypressed(k)
    if k == "escape" then love.event.quit() end
    if k == "q" then
        bloomPass.intensity = math.max(0, bloomPass.intensity - 0.25)
        print("[demo] bloom intensity: " .. bloomPass.intensity)
    end
    if k == "e" then
        bloomPass.intensity = bloomPass.intensity + 0.25
        print("[demo] bloom intensity: " .. bloomPass.intensity)
    end
end

function M.mousemoved(x, y, dx, dy) controls:mousemoved(dx, dy) end
function M.wheelmoved(dx, dy)       controls:wheelmoved(dy)     end

function M.draw()
    composer:render()
end

return M
