-- Тестовая сцена для проверки теней движка (shadow mapping).
-- Движок используется только как библиотека — вся логика теней лежит в
-- three/renderers/WebGLRenderer.lua и shader/, здесь только сборка сцены.
local TL = require "init"

local MODEL_PATH = "assets/model/model3dtest.glb"

local M = {}

local scene, camera, renderer, controls
local actor, mixer

function M.init()
    love.window.setTitle("TreeEngine — shadow mapping test")

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x1b1e26)

    camera = TL.PerspectiveCamera:new(55, w / h, 0.1, 100)
    camera.position:set(4, 4, 6)
    camera:lookAt(0, 0, 0)

    controls = TL.FlyControls:new(camera, { movementSpeed = 4 })

    renderer = TL.WebGLRenderer:new{ shadowTarget = TL.Vector3:new(0, 0, 0) }

    -- The one light the shader/shadow map support: castShadow opts it into
    -- the renderer's shadow pass.
    local sun = TL.DirectionalLight:new(0xfff3e0, 1)
    sun.position:set(3, 6, 2)
    sun.castShadow = true
    sun.shadow.camera.left, sun.shadow.camera.right = -8, 8
    sun.shadow.camera.top, sun.shadow.camera.bottom  = 8, -8
    sun.shadow.camera:updateProjectionMatrix()
    scene:add(sun)

    scene:add(TL.AmbientLight:new(0x40444f, 1))

    -- Floor: receives the shadow, casts none of its own.
    local floorGeo = TL.PlaneGeometry:new(14, 14)
    local floorMat = TL.MeshStandardMaterial:new{ color = 0x8a8f9c, roughness = 1 }
    local floor = TL.Mesh:new(floorGeo, floorMat)
    floor:rotateX(-math.pi / 2)
    floor.receiveShadow = true
    scene:add(floor)

    -- Animated actor: floats above the floor, casts its shadow in whatever
    -- pose the animation is currently in (see WebGLRenderer:_renderShadowMap's
    -- skinned depth variant), and is spun by hand here to see the shadow turn
    -- with it independent of the animation itself.
    local model = TL.Model:fromLoaderResult(TL.GLTFLoader:new():load(MODEL_PATH))
    local instance = model:createInstance()
    actor = instance.scene
    actor.position:set(0, 0, 0)
    actor.scale:set(1, 1, 1)
    actor:traverse(function(o)
        if o.isMesh and o:isMesh() then o.castShadow = true end
    end)
    scene:add(actor)

    mixer = instance.mixer
    if instance.animations[1] then
        mixer:clipAction(instance.animations[1]):play()
    end
end

function M.update(dt)
    controls:update(dt)
    mixer:update(dt)
    actor:rotateY(dt * 0.6)
end

function M.resize(w, h)
    renderer:setSize(w, h, camera)
end

function M.keypressed(k)
    if k == "escape" then love.event.quit() end
end

function M.mousemoved(x, y, dx, dy) controls:mousemoved(dx, dy) end
function M.wheelmoved(dx, dy)       controls:wheelmoved(dy)     end

function M.draw()
    renderer:render(scene, camera)
end

return M
