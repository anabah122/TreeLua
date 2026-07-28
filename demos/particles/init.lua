-- Тестовая сцена для GPU-частиц (three/particles/ParticleSystem.lua):
-- сетка 5x5 эмиттеров с разными spawnShape/gravity/size/color/burst, чтобы
-- визуально проверить весь диапазон параметров разом.
-- Движок используется только как библиотека — сборка сцены и проверка, без
-- изменений в three/ или shader/.
local TL = require "init"

local M = {}

local scene, camera, renderer, controls

local GRID_COLS = 5
local GRID_ROWS = 5
local SPACING = 6   -- world units between emitters, both axes

-- Continuous emitters (rows 1-3): each particle cycles on its own clock, the
-- system as a whole looks like it has always been running. 15 distinct
-- definitions, one per grid cell in those rows -- no repeats.
local CONTINUOUS = {
    { name = "fire", spawnShape = "cone", coneAngle = 0.25, direction = { 0, 1, 0 },
      speed = { 1.5, 3 }, gravity = { 0, 1.2, 0 }, size = { 0.35, 0.05 },
      color = { 0xffdd66, 0xff2200 }, opacity = { 1, 0 }, lifetime = 1.2, count = 500 },

    { name = "smoke", spawnShape = "cone", coneAngle = 0.6, direction = { 0, 1, 0 },
      speed = { 0.3, 0.8 }, gravity = { 0, 0.15, 0 }, size = { 0.2, 1.4 },
      color = { 0x888888, 0x333333 }, opacity = { 0.5, 0 }, lifetime = 4, count = 300 },

    { name = "sparks", spawnShape = "sphere", spawnRadius = 0.1,
      speed = { 2, 5 }, gravity = { 0, -4, 0 }, size = { 0.08, 0.02 },
      color = { 0xffffff, 0xffaa00 }, opacity = { 1, 0 }, lifetime = 1.5, count = 400 },

    { name = "magic", spawnShape = "sphere", spawnRadius = 0.6,
      speed = { 0.1, 0.4 }, gravity = { 0, 0.05, 0 }, size = { 0.06, 0.15 },
      color = { 0x66ccff, 0xaa66ff }, opacity = { 1, 0 }, lifetime = 3, count = 250 },

    { name = "fountain", spawnShape = "cone", coneAngle = 0.35, direction = { 0, 1, 0 },
      speed = { 3, 5 }, gravity = { 0, -6, 0 }, size = { 0.12, 0.12 },
      color = { 0x66ddff, 0x2266cc }, opacity = { 0.9, 0.2 }, lifetime = 2, count = 500 },

    { name = "toxic-cloud", spawnShape = "sphere", spawnRadius = 0.4,
      speed = { 0.2, 0.5 }, gravity = { 0, 0.1, 0 }, size = { 0.3, 0.9 },
      color = { 0x66ff44, 0x225511 }, opacity = { 0.6, 0 }, lifetime = 3.5, count = 280 },

    { name = "snow", spawnShape = "sphere", spawnRadius = 1.2,
      speed = { 0.1, 0.3 }, gravity = { 0, -0.4, 0 }, size = { 0.06, 0.06 },
      color = { 0xffffff, 0xeeeeff }, opacity = { 0.9, 0.3 }, lifetime = 5, count = 350 },

    { name = "ember-rise", spawnShape = "point",
      speed = { 0.5, 1.2 }, gravity = { 0, 0.6, 0 }, size = { 0.05, 0.01 },
      color = { 0xff8822, 0xff2200 }, opacity = { 1, 0 }, lifetime = 2.5, count = 200,
      rotationSpeed = 4 },   -- billboard spins in screen space, like a tumbling ember

    { name = "bubbles", spawnShape = "sphere", spawnRadius = 0.5,
      speed = { 0.3, 0.7 }, gravity = { 0, 0.3, 0 }, size = { 0.05, 0.12 },
      color = { 0x88ccff, 0xffffff }, opacity = { 0.5, 0.8 }, lifetime = 2.8, count = 220 },

    { name = "waterfall-mist", spawnShape = "cone", coneAngle = 0.5, direction = { 0, -1, 0 },
      speed = { 1, 2 }, gravity = { 0, -1.5, 0 }, size = { 0.15, 0.35 },
      color = { 0xaaddff, 0x6699cc }, opacity = { 0.7, 0 }, lifetime = 1.8, count = 300 },

    { name = "acid-drip", spawnShape = "point",
      speed = { 0.5, 1, }, gravity = { 0, -5, 0 }, size = { 0.1, 0.03 },
      color = { 0xaaff00, 0x557700 }, opacity = { 1, 0.2 }, lifetime = 1.4, count = 200 },

    { name = "portal-swirl", spawnShape = "sphere", spawnRadius = 0.9,
      speed = { 0.4, 0.9 }, gravity = { 0, 0, 0 }, size = { 0.15, 0.05 },
      color = { 0xcc55ff, 0x220044 }, opacity = { 1, 0 }, lifetime = 2.2, count = 120,
      shape = "sphere", rotationSpeed = 3 },   -- 3D mesh particles, tumbling

    { name = "dust-motes", spawnShape = "sphere", spawnRadius = 1,
      speed = { 0.02, 0.08 }, gravity = { 0, 0.02, 0 }, size = { 0.03, 0.06 },
      color = { 0xffeecc, 0xffeecc }, opacity = { 0.4, 0 }, lifetime = 6, count = 150,
      rotationSpeed = 1 },   -- slow billboard spin

    { name = "lava-bubble", spawnShape = "cone", coneAngle = 0.15, direction = { 0, 1, 0 },
      speed = { 0.8, 1.6 }, gravity = { 0, -2, 0 }, size = { 0.25, 0.1 },
      color = { 0xff6600, 0x330000 }, opacity = { 1, 0 }, lifetime = 1.6, count = 120,
      shape = "box", rotationSpeed = 5 },   -- 3D mesh particles, tumbling boxes

    { name = "starfield", spawnShape = "sphere", spawnRadius = 1.5,
      speed = { 0.05, 0.15 }, gravity = { 0, 0, 0 }, size = { 0.06, 0.06 },
      color = { 0xffffff, 0x8888ff }, opacity = { 1, 0.3 }, lifetime = 4.5, count = 150,
      shape = "box", rotationSpeed = 1.5 },   -- 3D mesh particles, slow tumble

    { name = "blood-spray", spawnShape = "cone", coneAngle = 0.4, direction = { 0, 1, 0 },
      speed = { 1, 2.5 }, gravity = { 0, -7, 0 }, size = { 0.1, 0.06 },
      color = { 0xaa0000, 0x330000 }, opacity = { 1, 0.3 }, lifetime = 1.6, count = 260 },

    { name = "pollen", spawnShape = "sphere", spawnRadius = 1.3,
      speed = { 0.05, 0.2 }, gravity = { 0, 0.08, 0 }, size = { 0.04, 0.08 },
      color = { 0xffee44, 0xffcc00 }, opacity = { 0.7, 0.1 }, lifetime = 5.5, count = 200 },

    { name = "electric-arc", spawnShape = "sphere", spawnRadius = 0.3,
      speed = { 1, 3 }, gravity = { 0, 0, 0 }, size = { 0.04, 0.01 },
      color = { 0xaaddff, 0xffffff }, opacity = { 1, 0 }, lifetime = 0.5, count = 300 },

    { name = "coin-sparkle", spawnShape = "point",
      speed = { 0.3, 0.9 }, gravity = { 0, 1.5, 0 }, size = { 0.05, 0.01 },
      color = { 0xffdd00, 0xfff2aa }, opacity = { 1, 0 }, lifetime = 1, count = 180 },

    { name = "geyser-mist", spawnShape = "cone", coneAngle = 0.7, direction = { 0, 1, 0 },
      speed = { 0.5, 1.4 }, gravity = { 0, -0.8, 0 }, size = { 0.1, 0.5 },
      color = { 0xddeeff, 0x99bbdd }, opacity = { 0.6, 0 }, lifetime = 2.4, count = 260 },
}

-- Burst emitters (row 5): the whole system has a start, a hold, and an end --
-- e.g. Skyrim-style spell sparks -- instead of trickling forever. 5 distinct
-- definitions, one per grid cell in that row.
local BURST = {
    { name = "burst-fire", spawnShape = "cone", coneAngle = 0.3, direction = { 0, 1, 0 },
      speed = { 2, 4 }, gravity = { 0, 1, 0 }, size = { 0.3, 0.05 },
      color = { 0xffdd66, 0xff2200 }, opacity = { 1, 0 }, lifetime = 1.5, count = 500,
      cycleDuration = 3, riseFraction = 0.2, sustainFraction = 0.4, decayFraction = 0.4 },

    { name = "burst-explosion", spawnShape = "sphere", spawnRadius = 0.05,
      speed = { 3, 7 }, gravity = { 0, -2, 0 }, size = { 0.15, 0.03 },
      color = { 0xffffff, 0xff6600 }, opacity = { 1, 0 }, lifetime = 1.2, count = 600,
      cycleDuration = 2.5, riseFraction = 0.05, sustainFraction = 0.15, decayFraction = 0.8 },

    { name = "burst-spell", spawnShape = "sphere", spawnRadius = 0.4,
      speed = { 0.5, 1.5 }, gravity = { 0, 0.2, 0 }, size = { 0.1, 0.2 },
      color = { 0x66ccff, 0xffffff }, opacity = { 1, 0 }, lifetime = 2, count = 400,
      cycleDuration = 4, riseFraction = 0.3, sustainFraction = 0.4, decayFraction = 0.3 },

    { name = "burst-geyser", spawnShape = "cone", coneAngle = 0.2, direction = { 0, 1, 0 },
      speed = { 4, 6 }, gravity = { 0, -8, 0 }, size = { 0.1, 0.1 },
      color = { 0x66ddff, 0x2266cc }, opacity = { 1, 0.1 }, lifetime = 1.8, count = 500,
      cycleDuration = 3.5, riseFraction = 0.15, sustainFraction = 0.5, decayFraction = 0.35 },

    { name = "burst-firework", spawnShape = "sphere", spawnRadius = 0.02,
      speed = { 4, 8 }, gravity = { 0, -3, 0 }, size = { 0.12, 0.02 },
      color = { 0xffee88, 0xff4488 }, opacity = { 1, 0 }, lifetime = 1.6, count = 700,
      cycleDuration = 3, riseFraction = 0.03, sustainFraction = 0.1, decayFraction = 0.87 },

}

local function spawn(def, x, z)
    local ps = TL.ParticleSystem:new{
        count       = def.count,
        lifetime    = def.lifetime,
        spawnShape  = def.spawnShape,
        spawnRadius = def.spawnRadius,
        coneAngle   = def.coneAngle,
        direction   = def.direction and TL.Vector3:new(def.direction[1], def.direction[2], def.direction[3]),
        speed       = def.speed,
        gravity     = TL.Vector3:new(def.gravity[1], def.gravity[2], def.gravity[3]),
        size        = def.size,
        color       = { TL.Color:new(def.color[1]), TL.Color:new(def.color[2]) },
        opacity     = def.opacity,
        burst           = def.cycleDuration ~= nil,
        cycleDuration   = def.cycleDuration,
        riseFraction    = def.riseFraction,
        sustainFraction = def.sustainFraction,
        decayFraction   = def.decayFraction,
        shape           = def.shape,
        rotationSpeed   = def.rotationSpeed,
    }
    ps.position:set(x, 0, z)
    return ps
end

function M.init()
    love.window.setTitle("TreeEngine — GPU particles grid (5x5)")

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x14161c)
    scene.fog = TL.FogExp2:new(0x14161c, 0.015)

    -- Grid spans SPACING*(GRID_COLS-1) x SPACING*(GRID_ROWS-1); camera pulled
    -- back far enough to see the whole thing from a corner angle.
    local halfW = SPACING * (GRID_COLS - 1) / 2
    local halfD = SPACING * (GRID_ROWS - 1) / 2
    camera = TL.PerspectiveCamera:new(60, w / h, 0.1, 200)
    camera.position:set(-halfW - 8, 10, halfD + 16)
    camera:lookAt(0, 1, 0)

    controls = TL.FlyControls:new(camera, { movementSpeed = 10 })

    renderer = TL.WebGLRenderer:new()

    scene:add(TL.HemisphereLight:new(0x445577, 0x221100, 0.6))
    local sun = TL.DirectionalLight:new(0xfff3e0, 0.5)
    sun.position:set(3, 6, 2)
    scene:add(sun)

    local floor = TL.Mesh:new(
        TL.PlaneGeometry:new(SPACING * GRID_COLS + 10, SPACING * GRID_ROWS + 10),
        TL.MeshStandardMaterial:new{ color = 0x22242c, roughness = 1 }
    )
    floor:rotateX(-math.pi / 2)
    scene:add(floor)

    -- Rows 1-4: 20 continuous emitters, one distinct definition per cell.
    -- Row 5: 5 burst emitters, one full lifecycle per cycleDuration.
    for row = 1, GRID_ROWS do
        local z = -halfD + (row - 1) * SPACING
        for col = 1, GRID_COLS do
            local x = -halfW + (col - 1) * SPACING
            local def
            if row == GRID_ROWS then
                def = BURST[col]
            else
                def = CONTINUOUS[(row - 1) * GRID_COLS + col]
            end
            scene:add(spawn(def, x, z))
        end
    end

    print(("[demo] %dx%d grid, spacing %d: 20 distinct continuous emitters (rows 1-4), "
        .. "5 distinct burst emitters with rise/sustain/decay (row 5)")
        :format(GRID_COLS, GRID_ROWS, SPACING))
end

function M.update(dt)
    controls:update(dt)
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
