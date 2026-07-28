-- three/materials/Material.lua — base material
--
-- three.js materials are a description of a shader program plus its uniforms;
-- this engine ships one forward-lit shader (shader/), so a
-- material here is purely the uniform side. The renderer reads these fields
-- and sends them; nothing swaps programs per material.
--
-- Fields that the shader has no equivalent for (metalness, roughness, the
-- emissive term) are still stored, because the importers extract them and
-- dropping them at the facade would lose data the shader may later grow to
-- use. They are inert until then.

local Color = require "math.color"

local Material = {}
Material.__index = Material

local nextId = 0

function Material:new(params)
    nextId = nextId + 1
    params = params or {}

    local m = setmetatable({}, self)
    m.__index = m == Material and Material or m

    m.id   = nextId
    m.uuid = string.format("mat-%d", nextId)
    m.name = params.name or ""
    m.type = "Material"

    m.color       = Color:new(params.color == nil and 0xffffff or params.color)
    m.opacity     = params.opacity == nil and 1 or params.opacity

    -- Declared on the base so the renderer never has to test for them.
    -- MeshStandardMaterial overrides these; a plain Material is a matte
    -- dielectric.
    m.metalness   = params.metalness or 0
    m.roughness   = params.roughness or 1
    m.emissive    = Color:new(params.emissive or 0x000000)
    m.emissiveIntensity = params.emissiveIntensity or 1

    m.normalMap       = params.normalMap or nil
    m.normalScale     = params.normalScale == nil and 1 or params.normalScale
    m.aoMap           = params.aoMap or nil
    m.aoMapIntensity  = params.aoMapIntensity == nil and 1 or params.aoMapIntensity

    m.transparent = params.transparent or false
    m.visible     = params.visible ~= false
    m.side        = params.side or "front"   -- "front" | "back" | "double"

    m.map         = params.map or nil        -- love.Image / Texture

    m.depthTest   = params.depthTest ~= false
    m.depthWrite  = params.depthWrite ~= false

    m.alphaTest   = params.alphaTest or 0
    m.wireframe   = params.wireframe or false

    m.userData    = params.userData or {}

    return m
end

function Material:extend(typeName)
    local Sub = setmetatable({}, { __index = self })
    Sub.__index = Sub
    Sub.__parentClass = self

    function Sub:new(params)
        local m = self.__parentClass.new(self, params)
        m.type = typeName
        return m
    end

    return Sub
end

function Material:isMaterial()
    return true
end

-- What the shader wants for u_baseColor: rgb from the colour, alpha from
-- opacity, matching how three.js keeps the two separate.
function Material:baseColorArray()
    return { self.color.r, self.color.g, self.color.b, self.opacity }
end

function Material:setValues(params)
    for k, v in pairs(params or {}) do
        if k == "color" and type(v) ~= "table" then
            self.color:set(v)
        else
            self[k] = v
        end
    end
    return self
end

function Material:copy(source)
    self.name        = source.name
    self.color:copy(source.color)
    self.opacity     = source.opacity
    self.transparent = source.transparent
    self.visible     = source.visible
    self.side        = source.side
    self.map         = source.map
    self.depthTest   = source.depthTest
    self.depthWrite  = source.depthWrite
    self.alphaTest   = source.alphaTest
    self.wireframe   = source.wireframe
    self.metalness   = source.metalness
    self.roughness   = source.roughness
    self.emissive:copy(source.emissive)
    self.emissiveIntensity = source.emissiveIntensity
    self.normalMap      = source.normalMap
    self.normalScale    = source.normalScale
    self.aoMap          = source.aoMap
    self.aoMapIntensity = source.aoMapIntensity
    return self
end

function Material:clone()
    local Class = getmetatable(self)
    return Class.new(Class):copy(self)
end

-- LÖVE frees images by collection; kept so teardown code reads like three.js.
function Material:dispose()
    self.map = nil
    return self
end

return Material
