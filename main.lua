require 'lib.util'

local Camera = require 'class.camera'
local Model  = require 'class.model'

local camera, sh
local models = {}
local paused = false

function love.load()
    love.window.setTitle("TreeEngine")

    sh = love.graphics.newShader("assets/shader/skinned.glsl")
    camera = Camera:new{ x = 0, y = 1.2, z = 3.5, yaw = math.pi, speed = 3 }

    -- Same character from both importers. Neither needs a scale fudge: the
    -- glTF is authored in metres, and the DAE's <unit meter="0.01"> is folded
    -- into its root transform at load time.
    models[1] = Model:new("assets/model/model3dtest.glb",
        { position = { -0.8, 0, 0 } })
    models[2] = Model:new("assets/model/model3dtest/Dancing.dae",
        { position = {  0.8, 0, 0 } })

    -- the two exports differ by 17ms of clip length, enough to visibly drift
    -- apart after a few loops; pin the second to the first
    models[2].duration = models[1].clip.duration
end

function love.update(dt)
    camera:update(dt)
    if not paused then
        for _, m in ipairs(models) do m:update(dt) end
    end
end

function love.keypressed(k)
    if k == "escape" then love.event.quit() end
    if k == "space"  then paused = not paused end
end

function love.mousemoved(x, y, dx, dy) camera:mousemoved(dx, dy) end
function love.wheelmoved(dx, dy)       camera:wheelmoved(dy)     end

function love.draw()
    love.graphics.clear(0.09, 0.10, 0.13, 1)

    love.graphics.setDepthMode("lequal", true)
    love.graphics.setMeshCullMode("back")

    love.graphics.setShader(sh)
    sh:send("u_viewProj",   camera:viewproj())
    sh:send("u_lightDir",   { -0.4, -1.0, -0.6 })
    sh:send("u_lightColor", { 1.0, 0.97, 0.92 })
    sh:send("u_ambient",    { 0.28, 0.30, 0.36 })

    for _, m in ipairs(models) do m:draw(sh) end

    love.graphics.setShader()
    love.graphics.setMeshCullMode("none")
    love.graphics.setDepthMode()

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, 400, 62)
    love.graphics.setColor(1, 1, 1, 1)
    -- getFPS() reflects the frame loop's sleep, not the engine's speed;
    -- realFPS is measured before that sleep (see lib/util/FRAMELOOP.lua)
    love.graphics.print(
        ("WASD move  QE up/down  mouse look  wheel speed\nSPACE %s   ESC quit\n" ..
         "left: GLB   right: DAE\nfps %d   real %d")
            :format(paused and "paused" or "playing",
                    love.timer.getFPS(), math.floor(love.timer.realFPS)),
        10, 10)
end
