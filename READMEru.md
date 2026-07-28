# TreeLua

Минималистичный 3D-движок для LÖVE 11.5 — это функционал, который three.js добавляет поверх рендерера, но без самого рендерера, поскольку у LÖVE он уже есть.

Публичный API повторяет [three.js](https://threejs.org/docs/), поэтому его документацию можно использовать в качестве справочника. Два намеренных отличия описаны в разделе [Отличия от three.js](#отличия-от-threejs).

## Быстрый старт

```lua
local TL = require "TreeEngine"

local scene, camera, renderer, mixer

function love.load()
    local w, h = love.graphics.getDimensions()

    scene  = TL.Scene:new()
    scene:setBackground(0x171a21)

    camera = TL.PerspectiveCamera:new(60, w / h, 0.1, 1000)
    camera.position:set(0, 1.2, 3.5)

    renderer = TL.WebGLRenderer:new()

    local sun = TL.DirectionalLight:new(0xfff7eb, 1)
    sun.position:set(0.4, 1.0, 0.6)
    scene:add(sun)
    scene:add(TL.AmbientLight:new(0x474d5c, 1))

    local gltf = TL.GLTFLoader:new():load("assets/model/model3dtest.glb")
    scene:add(gltf.scene)

    mixer = TL.AnimationMixer:new(gltf.scene)
    mixer:clipAction(gltf.animations[1]):play()
end

function love.update(dt) mixer:update(dt) end
function love.draw()     renderer:render(scene, camera) end