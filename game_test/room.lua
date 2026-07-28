-- Комната: пол + стены из примитивов движка, плюс AABB стен для коллизий.
local cfg = require "game_test.config"

local Room = {}
Room.__index = Room

function Room:new(TL, scene)
    local self = setmetatable({}, Room)
    self.walls = {} -- { minX, maxX, minZ, maxZ } for collision

    local floorMat = TL.MeshStandardMaterial:new{ color = 0x2b2f38, metalness = 0, roughness = 1 }
    local floor = TL.Mesh:new(
        TL.PlaneGeometry:new(cfg.roomHalfW * 2, cfg.roomHalfD * 2),
        floorMat)
    floor:rotateX(-math.pi / 2)
    scene:add(floor)

    local wallMat = TL.MeshStandardMaterial:new{ color = 0x50566b, metalness = 0, roughness = 0.8 }
    local thickness = 0.5

    local function addWall(cx, cz, sx, sz)
        local mesh = TL.Mesh:new(
            TL.BoxGeometry:new(sx, cfg.wallHeight, sz),
            wallMat)
        mesh.position:set(cx, cfg.wallHeight / 2, cz)
        scene:add(mesh)
        self.walls[#self.walls + 1] = {
            minX = cx - sx / 2, maxX = cx + sx / 2,
            minZ = cz - sz / 2, maxZ = cz + sz / 2,
        }
    end

    local w, d = cfg.roomHalfW, cfg.roomHalfD
    addWall(0, -d - thickness / 2, w * 2 + thickness * 2, thickness) -- north
    addWall(0,  d + thickness / 2, w * 2 + thickness * 2, thickness) -- south
    addWall(-w - thickness / 2, 0, thickness, d * 2 + thickness * 2) -- west
    addWall( w + thickness / 2, 0, thickness, d * 2 + thickness * 2) -- east

    return self
end

-- Резолвит столкновение круга (x,z,radius) со стенами, возвращает скорректированные x,z.
function Room:resolveCircle(x, z, radius)
    for _, wall in ipairs(self.walls) do
        local closestX = math.max(wall.minX, math.min(x, wall.maxX))
        local closestZ = math.max(wall.minZ, math.min(z, wall.maxZ))
        local dx, dz = x - closestX, z - closestZ
        local distSq = dx * dx + dz * dz
        if distSq < radius * radius then
            local dist = math.sqrt(distSq)
            if dist < 1e-6 then
                -- center is inside the wall box; push out along smallest overlap axis
                local overlapX = math.min(x - wall.minX, wall.maxX - x)
                local overlapZ = math.min(z - wall.minZ, wall.maxZ - z)
                if overlapX < overlapZ then
                    x = x + (x < (wall.minX + wall.maxX) / 2 and -overlapX or overlapX)
                else
                    z = z + (z < (wall.minZ + wall.maxZ) / 2 and -overlapZ or overlapZ)
                end
            else
                local push = radius - dist
                x = x + dx / dist * push
                z = z + dz / dist * push
            end
        end
    end
    return x, z
end

function Room:clampToBounds(x, z, radius)
    local w, d = cfg.roomHalfW - radius, cfg.roomHalfD - radius
    x = math.max(-w, math.min(w, x))
    z = math.max(-d, math.min(d, z))
    return x, z
end

return Room
