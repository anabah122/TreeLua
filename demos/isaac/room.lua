-- Комната: пол + стены из примитивов движка, плюс AABB стен для коллизий.
local cfg = require "demos.isaac.config"

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

-- Лабиринт внутри комнаты: прямоугольная сетка ячеек, стены между соседними
-- ячейками ломаются случайным DFS-обходом (recursive backtracker) -- гарантирует
-- связность (из любой ячейки можно дойти до любой) без циклов.
function Room:buildMaze(TL, scene, cellSize)
    cellSize = cellSize or 2
    local w, d = cfg.roomHalfW, cfg.roomHalfD
    local cols = math.floor((w * 2 - 1) / cellSize)
    local rows = math.floor((d * 2 - 1) / cellSize)
    local originX = -(cols * cellSize) / 2
    local originZ = -(rows * cellSize) / 2

    -- walls[cy][cx] = { N=true, S=true, E=true, W=true } -- true = стена стоит
    local grid = {}
    for cy = 1, rows do
        grid[cy] = {}
        for cx = 1, cols do
            grid[cy][cx] = { N = true, S = true, E = true, W = true }
        end
    end

    local visited = {}
    local function key(cx, cy) return cy * 10000 + cx end

    local stack = { { 1, 1 } }
    visited[key(1, 1)] = true
    while #stack > 0 do
        local cx, cy = stack[#stack][1], stack[#stack][2]
        local neighbors = {}
        local candidates = {
            { cx, cy - 1, "N", "S" }, { cx, cy + 1, "S", "N" },
            { cx + 1, cy, "E", "W" }, { cx - 1, cy, "W", "E" },
        }
        for _, c in ipairs(candidates) do
            local nx, ny = c[1], c[2]
            if nx >= 1 and nx <= cols and ny >= 1 and ny <= rows and not visited[key(nx, ny)] then
                neighbors[#neighbors + 1] = c
            end
        end

        if #neighbors == 0 then
            table.remove(stack)
        else
            local pick = neighbors[math.random(#neighbors)]
            local nx, ny, side, opposite = pick[1], pick[2], pick[3], pick[4]
            grid[cy][cx][side] = false
            grid[ny][nx][opposite] = false
            visited[key(nx, ny)] = true
            stack[#stack + 1] = { nx, ny }
        end
    end

    local thickness = 0.3
    local wallH = cfg.wallHeight
    local mazeMat = TL.MeshStandardMaterial:new{ color = 0x3d4356, metalness = 0, roughness = 0.85 }

    local function segment(cx1, cz1, cx2, cz2)
        local sx = math.max(math.abs(cx2 - cx1), thickness)
        local sz = math.max(math.abs(cz2 - cz1), thickness)
        if sx < sz then sx = thickness else sz = thickness end
        local mesh = TL.Mesh:new(TL.BoxGeometry:new(sx, wallH, sz), mazeMat)
        mesh.position:set((cx1 + cx2) / 2, wallH / 2, (cz1 + cz2) / 2)
        scene:add(mesh)
        self.walls[#self.walls + 1] = {
            minX = (cx1 + cx2) / 2 - sx / 2, maxX = (cx1 + cx2) / 2 + sx / 2,
            minZ = (cz1 + cz2) / 2 - sz / 2, maxZ = (cz1 + cz2) / 2 + sz / 2,
        }
    end

    for cy = 1, rows do
        for cx = 1, cols do
            local cell = grid[cy][cx]
            local x0 = originX + (cx - 1) * cellSize
            local z0 = originZ + (cy - 1) * cellSize
            local x1, z1 = x0 + cellSize, z0 + cellSize
            if cell.N then segment(x0, z0, x1, z0) end
            if cell.W then segment(x0, z0, x0, z1) end
            -- S/E ставятся соседями через их N/W, кроме внешней границы лабиринта
            if cy == rows and cell.S then segment(x0, z1, x1, z1) end
            if cx == cols and cell.E then segment(x1, z0, x1, z1) end
        end
    end

    -- точка старта/спавна игрока: центр первой ячейки
    return originX + cellSize / 2, originZ + cellSize / 2
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
