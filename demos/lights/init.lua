-- Тестовая сцена для multi-light forward-рендеринга: 4 источника разных типов
-- и цветов, все castShadow (упирается в MAX_SHADOWS=4 -- проверяет, что 2D и
-- cube shadow-карты уживаются одновременно).
local TL = require "init"

local M = {}

local scene, camera, renderer, controls
local pillars
local lights = {}

function M.init()
    love.window.setTitle("TreeEngine — 4 lights / 4 shadows test")

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x10121a)

    camera = TL.PerspectiveCamera:new(60, w / h, 0.1, 100)
    camera.position:set(0, 6, 10)
    camera:lookAt(0, 1, 0)

    controls = TL.FlyControls:new(camera, { movementSpeed = 5 })

    renderer = TL.WebGLRenderer:new()

    -- Floor: a wide flat box, so every shadow has something to land on.
    local floor = TL.Mesh:new(
        TL.BoxGeometry:new(20, 0.2, 20),
        TL.MeshStandardMaterial:new{ color = 0x777777, roughness = 0.9 }
    )
    floor.position:set(0, -0.1, 0)
    floor.receiveShadow = true
    scene:add(floor)

    -- A ring of pillars: enough occluders that all 4 shadows are visible
    -- landing on the floor and on each other.
    pillars = {}
    for i = 1, 6 do
        local angle = (i - 1) / 6 * math.pi * 2
        local pillar = TL.Mesh:new(
            TL.BoxGeometry:new(0.8, 2.5, 0.8),
            TL.MeshStandardMaterial:new{ color = 0xcccccc, roughness = 0.6 }
        )
        pillar.position:set(math.cos(angle) * 4, 1.25, math.sin(angle) * 4)
        pillar.castShadow = true
        pillar.receiveShadow = true
        scene:add(pillar)
        pillars[i] = pillar
    end

    local center = TL.Mesh:new(
        TL.SphereGeometry:new(1, 32, 16),
        TL.MeshStandardMaterial:new{ color = 0xeeeeee, roughness = 0.3, metalness = 0.2 }
    )
    center.position:set(0, 1.5, 0)
    center.castShadow = true
    center.receiveShadow = true
    scene:add(center)

    -- 4 different light types, all castShadow -- exercises directional (2D
    -- ortho), point x2 (cube), and spot (2D perspective) all at once, using
    -- the full MAX_SHADOWS=4 budget.
    local moon = TL.DirectionalLight:new(0xaad4ff, 0.5)
    moon.position:set(-4, 8, -4)
    moon.castShadow = true
    scene:add(moon)
    lights.directional = moon

    local red = TL.PointLight:new(0xff3333, 4, 14)
    red.position:set(5, 2.5, 2)
    red.castShadow = true
    scene:add(red)
    lights.point1 = red

    local green = TL.PointLight:new(0x33ff66, 4, 14)
    green.position:set(-5, 2.5, -2)
    green.castShadow = true
    scene:add(green)
    lights.point2 = green

    local blue = TL.SpotLight:new(0x3388ff, 6, 16, math.pi / 5, 0.4)
    blue.position:set(0, 7, 6)
    blue.target.position:set(0, 0, 0)
    blue.castShadow = true
    scene:add(blue)
    scene:add(blue.target)
    lights.spot = blue

    print("[demo] 4 lights (directional/point/point/spot), all castShadow -- MAX_SHADOWS=4 fully used")
    print("[demo] 1-4: isolate one light (directional/point1/point2/spot), 0: show all")
end

function M.update(dt)
    controls:update(dt)
end

function M.resize(w, h)
    renderer:setSize(w, h, camera)
end

local ORDER = { "directional", "point1", "point2", "spot" }

function M.keypressed(k)
    if k == "escape" then love.event.quit() end

    local only = ({ ["1"] = "directional", ["2"] = "point1", ["3"] = "point2", ["4"] = "spot" })[k]
    if only then
        for _, name in ipairs(ORDER) do lights[name].visible = (name == only) end
        print("[demo] isolating: " .. only)
    elseif k == "0" then
        for _, name in ipairs(ORDER) do lights[name].visible = true end
        print("[demo] showing all 4 lights")
    end
end

function M.mousemoved(x, y, dx, dy) controls:mousemoved(dx, dy) end
function M.wheelmoved(dx, dy)       controls:wheelmoved(dy)     end

function M.draw()
    renderer:render(scene, camera)
end

return M
