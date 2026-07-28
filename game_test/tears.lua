-- Пул снарядов игрока ("слёзы").
local cfg = require "game_test.config"

local Tears = {}
Tears.__index = Tears

function Tears:new(TL, scene)
    local self = setmetatable({}, Tears)
    self.TL = TL
    self.scene = scene
    self.mat = TL.MeshStandardMaterial:new{ color = 0x7ec8ff, metalness = 0, roughness = 0.2 }
    self.list = {}
    return self
end

function Tears:spawn(x, z, dx, dz)
    local mesh = self.TL.Mesh:new(self.TL.SphereGeometry:new(cfg.tearRadius, 8, 6), self.mat)
    mesh.position:set(x, 0.4, z)
    self.scene:add(mesh)
    self.list[#self.list + 1] = {
        mesh = mesh, x = x, z = z, dx = dx, dz = dz, life = cfg.tearLife,
    }
end

function Tears:update(dt, room, onHit)
    for i = #self.list, 1, -1 do
        local t = self.list[i]
        t.life = t.life - dt
        t.x = t.x + t.dx * cfg.tearSpeed * dt
        t.z = t.z + t.dz * cfg.tearSpeed * dt

        local dead = t.life <= 0
        if not dead then
            for _, wall in ipairs(room.walls) do
                if t.x > wall.minX and t.x < wall.maxX and t.z > wall.minZ and t.z < wall.maxZ then
                    dead = true
                    break
                end
            end
        end
        if not dead and onHit then
            dead = onHit(t.x, t.z, cfg.tearRadius)
        end

        if dead then
            self.scene:remove(t.mesh)
            table.remove(self.list, i)
        else
            t.mesh.position.x = t.x
            t.mesh.position.z = t.z
        end
    end
end

return Tears
