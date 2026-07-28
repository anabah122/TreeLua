-- Demo: an animated glTF character.
--
-- Written entirely against the public API, so it doubles as the worked example
-- for it. Nothing here reaches into importer/ or class/ -- if something needs
-- to, that is a gap in the facade.

-- `love . --tests` runs the suite instead of the demo. Checked before
-- lib/util loads, because that replaces love.run and the runner needs the
-- stock one to quit cleanly.
for _, a in ipairs(arg or {}) do
    if a == "--tests" then
        require "tests.main"
        return
    end
end

-- lib/util is demo scaffolding, not part of the library: it installs globals
-- (LG, LK, serpent), replaces love.run to measure a pre-sleep FPS, and
-- overwrites several table.*/math.* functions. Nothing under three/, math/ or
-- importer/ touches any of it -- `require "TreeEngine"` defines no globals.
-- Loaded here only for the realFPS readout, and tolerated if absent.
pcall(require, 'lib.util')

local TL = require 'init'

local scene, camera, renderer, controls
local mixers = {}
local paused = false

function love.load()
    love.window.setTitle("TreeLua")

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x171a21)

    camera = TL.PerspectiveCamera:new(60, w / h, 0.1, 1024)
    camera.position:set(0, 1.2, 3.5)

    controls = TL.FlyControls:new(camera, { movementSpeed = 3 })

    renderer = TL.WebGLRenderer:new()

    -- Direction comes from where the light sits relative to its target, so
    -- placing it up and to one side is what aims it; the distance is ignored.
    local sun = TL.DirectionalLight:new(0xfff7eb, 1)
    sun.position:set(0.4, 1.0, 0.6)
    scene:add(sun)

    scene:add(TL.AmbientLight:new(0x474d5c, 1))

    local gltf = TL.GLTFLoader:new():load("assets/model/model3dtest.glb")
    scene:add(gltf.scene)

    local mixer = TL.AnimationMixer:new(gltf.scene)
    mixer:clipAction(gltf.animations[1]):play()
    mixers[#mixers + 1] = mixer
end

function love.update(dt)
    controls:update(dt)
    if not paused then
        for _, m in ipairs(mixers) do m:update(dt) end
    end
end

function love.resize(w, h)
    renderer:setSize(w, h, camera)
end

function love.keypressed(k)
    if k == "escape" then love.event.quit() end
    if k == "space"  then paused = not paused end
end

function love.mousemoved(x, y, dx, dy) controls:mousemoved(dx, dy) end
function love.wheelmoved(dx, dy)       controls:wheelmoved(dy)     end

function love.draw()
    renderer:render(scene, camera)

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, 400, 50)
    love.graphics.setColor(1, 1, 1, 1)
    -- getFPS() reflects the frame loop's sleep, not the engine's speed;
    -- realFPS is measured before that sleep (see lib/util/FRAMELOOP.lua) and
    -- is absent when that scaffolding is not loaded
    local real = love.timer.realFPS
    love.graphics.print(
        ("WASD move  QE up/down  mouse look  wheel speed\nSPACE %s   ESC quit\n" ..
         "fps %d%s")
            :format(paused and "paused" or "playing", love.timer.getFPS(),
                    real and ("   real %d"):format(math.floor(real)) or ""),
        10, 10)
end
