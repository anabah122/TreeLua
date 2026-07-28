-- Подбираемые сердца: выпадают со смертью врага, текстурированный quad
-- (PlaneGeometry + MeshStandardMaterial.map), покачивается и лечит игрока
-- при контакте. Первое использование текстур в demos/isaac -- проверяет
-- TextureLoader + material.map на реальном PNG, а не только на встроенной
-- в glTF текстуре.
local cfg = require "demos.isaac.config"

local HEAL_AMOUNT = 15
local RADIUS       = 0.3
local BOB_SPEED    = 3
local BOB_HEIGHT   = 0.08

local Pickups = {}
Pickups.__index = Pickups

function Pickups:new(TL, scene)
    local self = setmetatable({}, Pickups)
    self.TL = TL
    self.scene = scene
    self.list = {}

    local texture = TL.TextureLoader:new():load("assets/model/model3dtest/textures/Ch36_1001_Diffuse.png")
    self.material = TL.MeshStandardMaterial:new{
        map = texture, metalness = 0, roughness = 1, transparent = true,
        side = TL.DoubleSide, -- plane крутится вокруг Y, иначе бэккулинг съедает половину кадров
    }
    self.geometry = TL.PlaneGeometry:new(0.5, 0.5)
    return self
end

function Pickups:spawn(x, z)
    local mesh = self.TL.Mesh:new(self.geometry, self.material)
    mesh.position:set(x, 0.5, z)
    self.scene:add(mesh)
    self.list[#self.list + 1] = { mesh = mesh, x = x, z = z, t = math.random() * 10 }
end

function Pickups:update(dt, player)
    for i = #self.list, 1, -1 do
        local p = self.list[i]
        p.t = p.t + dt
        p.mesh.position.y = 0.5 + math.sin(p.t * BOB_SPEED) * BOB_HEIGHT
        p.mesh.rotation.y = p.t -- крутится лицом во все стороны, раз это plane, а не billboard

        local dx, dz = player.x - p.x, player.z - p.z
        if player.alive and dx * dx + dz * dz < (RADIUS + cfg.playerRadius) ^ 2 then
            player.hp = math.min(cfg.playerHp, player.hp + HEAL_AMOUNT)
            self.scene:remove(p.mesh)
            table.remove(self.list, i)
        end
    end
end

return Pickups
