-- Playable test scene for engine/collision: a capsule-based player walks
-- around a box, a sphere, a sloped mesh ramp, and a bumpy heightfield, with
-- gravity and push-out resolution against all four collider kinds at once.
--
--   WASD + mouse look, space to jump, escape to quit.
--   Collider outlines print to console on overlap (see M.update).

local TL = require "init"

local M = {}

local scene, camera, renderer
local world

local player = {
    capsule = nil,        -- TL.Capsule, the collision volume
    velocity = nil,       -- TL.Vector3
    onGround = false,
    eyeHeight = 1.6,
}

local look   -- FlyControls, used for its yaw/pitch/forwardFlat/right math and
             -- camera:lookAt orientation only -- its own :update() (which
             -- moves the camera by WASD) is never called, the capsule drives
             -- position instead

local keys = {}

local GRAVITY = -18
local MOVE_SPEED = 5
local JUMP_SPEED = 7
local PLAYER_RADIUS = 0.4
local PLAYER_HEIGHT = 1.8   -- capsule start-to-finish span, radius excluded

local function addVisual(geometry, color, position)
    local mesh = TL.Mesh:new(geometry, TL.MeshStandardMaterial:new{ color = color, roughness = 0.8 })
    if position then mesh.position:copy(position) end
    scene:add(mesh)
    return mesh
end

local function buildHeightfield()
    local rows, cols, cellSize = 20, 20, 1
    local heights = {}
    for row = 1, rows do
        heights[row] = {}
        for col = 1, cols do
            -- a gentle bump so walking across it is visibly not flat
            local x, z = (col - cols / 2), (row - rows / 2)
            heights[row][col] = math.max(0, 1.5 - 0.02 * (x * x + z * z))
        end
    end

    local origin = TL.Vector3:new(-cols / 2 * cellSize, 0, -rows / 2 * cellSize)
    local field = TL.Heightfield:new(heights, cellSize, origin)

    -- visual: a plain grid mesh matching the same samples, so the eye can
    -- confirm the collider lines up with what's drawn
    local vertices, indices = {}, {}
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local p = field:pointAt(row, col)
            vertices[#vertices + 1] = { p.x, p.y, p.z, col / cols, row / rows, 0, 1, 0 }
        end
    end
    for row = 0, rows - 2 do
        for col = 0, cols - 2 do
            local a = row * cols + col + 1
            local b = a + 1
            local c = a + cols
            local d = c + 1
            indices[#indices + 1] = a
            indices[#indices + 1] = c
            indices[#indices + 1] = b
            indices[#indices + 1] = b
            indices[#indices + 1] = c
            indices[#indices + 1] = d
        end
    end

    local build = require "engine.geometries.build"
    local geometry = build("HeightfieldGeometry", vertices, indices, {}, true)
    addVisual(geometry, 0x5a7a4a)

    return field
end

local function buildRampMeshCollider()
    -- a sloped plane the player can walk up, testing MeshCollider separately
    -- from the heightfield
    local ramp = TL.Mesh:new(TL.PlaneGeometry:new(4, 8), TL.MeshStandardMaterial:new{ color = 0x8888aa, side = TL.DoubleSide })
    ramp:rotateX(-math.pi / 2 + 0.5)
    ramp.position:set(8, 1.5, 0)
    scene:add(ramp)
    return TL.MeshCollider:new(ramp)
end

function M.init()
    love.window.setTitle("TreeEngine — collision playground")
    love.mouse.setRelativeMode(true)

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x87ceeb)

    camera = TL.PerspectiveCamera:new(70, w / h, 0.1, 200)
    renderer = TL.WebGLRenderer:new()

    look = TL.FlyControls:new(camera, { lockMouse = false })

    scene:add(TL.HemisphereLight:new(0xbfd8ff, 0x3a2f28, 1))
    local sun = TL.DirectionalLight:new(0xfff3e0, 1.0)
    sun.position:set(10, 20, 5)
    scene:add(sun)

    world = TL.CollisionWorld:new()

    -- box collider
    local boxMesh = addVisual(TL.BoxGeometry:new(2, 2, 2), 0xcc6644, TL.Vector3:new(-6, 1, -4))
    local box = TL.Box3:new():setFromObject(boxMesh)
    world:add(box)

    -- sphere collider
    local sphereMesh = addVisual(TL.SphereGeometry:new(1.2, 24, 16), 0x4488cc, TL.Vector3:new(-3, 1.2, 4))
    world:add(TL.Sphere:new(sphereMesh.position, 1.2))

    -- mesh collider (sloped ramp)
    world:add(buildRampMeshCollider())

    -- heightfield collider (bumpy ground everyone stands on)
    world:add(buildHeightfield())

    player.capsule = TL.Capsule:new(
        TL.Vector3:new(0, 5 + PLAYER_RADIUS, 6),
        TL.Vector3:new(0, 5 + PLAYER_RADIUS + PLAYER_HEIGHT, 6),
        PLAYER_RADIUS
    )
    player.velocity = TL.Vector3:new(0, 0, 0)
end

local function resolveCollisions()
    -- Iterative push-out: every pass walks EVERY collider currently
    -- overlapped (not just the first one testCapsule would find) and pushes
    -- out of each in turn, re-testing that same collider's neighbours are
    -- still fine as it goes. Resolving only the first hit per pass (even
    -- across many passes) lets one collider "win" the query every time --
    -- e.g. a box the player is wedged against -- while the ground underneath
    -- never gets its turn, so gravity keeps digging the player into it.
    for _ = 1, 4 do
        local pushedAny = false

        world:testCapsuleAll(player.capsule, function(hit)
            pushedAny = true
            player.capsule:translate(hit.normal:clone():multiplyScalar(hit.depth))

            -- normal points from the collider toward the capsule axis; if it
            -- has a meaningful upward component, standing on it counts as ground
            if hit.normal.y > 0.5 then
                player.onGround = true
                if player.velocity.y < 0 then player.velocity.y = 0 end
            end
        end)

        if not pushedAny then break end
    end
end

function M.update(dt)
    if love.keyboard.isDown("escape") then love.event.quit() end

    local forward = look:forwardFlat()
    local right   = look:right()

    local move = TL.Vector3:new(0, 0, 0)
    if love.keyboard.isDown("w") then move:addSelf(forward) end
    if love.keyboard.isDown("s") then move:subSelf(forward) end
    if love.keyboard.isDown("d") then move:addSelf(right) end
    if love.keyboard.isDown("a") then move:subSelf(right) end
    if move:lengthSq() > 0 then move:normalizeSelf():multiplyScalar(MOVE_SPEED * dt) end

    if love.keyboard.isDown("space") and player.onGround then
        player.velocity.y = JUMP_SPEED
        player.onGround = false
    end

    player.velocity.y = player.velocity.y + GRAVITY * dt

    player.onGround = false
    player.capsule:translate(TL.Vector3:new(move.x, player.velocity.y * dt, move.z))

    resolveCollisions()

    local center = player.capsule:getCenter(TL.Vector3:new())
    camera.position:set(center.x, player.capsule.start.y + player.eyeHeight - PLAYER_RADIUS, center.z)
    look:_applyRotation()
end

function M.resize(w, h)
    renderer:setSize(w, h, camera)
end

function M.keypressed(k)
    keys[k] = true
end

function M.mousemoved(x, y, dx, dy)
    look:mousemoved(dx, dy)
end

function M.wheelmoved(dx, dy) end

function M.draw()
    renderer:render(scene, camera)
end

return M
