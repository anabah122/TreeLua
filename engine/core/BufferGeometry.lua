-- three/core/BufferGeometry.lua — vertex data for one primitive
--
-- three.js stores attributes in typed arrays and uploads them to the GPU. LÖVE
-- already owns that step: the importers build a `love.Mesh` per primitive with
-- the vertex format declared in importer.common. So this class holds the
-- love.Mesh plus the raw vertex/index tables the importer produced, and offers
-- the handful of three.js methods that make sense on top of them.
--
--   geometry.mesh      : love.Mesh, what actually draws
--   geometry.vertices  : interleaved vertex tables (position, uv, normal, ...)
--   geometry.indices   : triangle indices
--   geometry.skinned   : whether the format carries joints/weights

local Vector3 = require "engine.math.vec3"

local BufferGeometry = {}
BufferGeometry.__index = BufferGeometry

-- Built either from an importer entry or by one of the generators in
-- three/geometries/, which fill the same fields.
--
-- Called as BufferGeometry:new(entry) for a plain one, or as
-- BufferGeometry.new(SubClass, entry) from a subclass constructor -- hence the
-- metatable coming from `self` rather than being hardcoded.
function BufferGeometry:new(entry)
    entry = entry or {}

    local g = setmetatable({}, self)
    g.__index = g == BufferGeometry and BufferGeometry or g

    g.type       = "BufferGeometry"
    g.name       = entry.name or ""
    g.mesh       = entry.mesh
    g.vertices   = entry.vertices
    g.indices    = entry.indices
    g.attributes = entry.attributes
    g.skinned    = entry.skinned or false
    g.boundingBox    = nil
    g.boundingSphere = nil

    return g
end

function BufferGeometry:extend(typeName)
    local Sub = setmetatable({}, { __index = self })
    Sub.__index = Sub
    Sub.__parentClass = self

    function Sub:new(...)
        local g = self.__parentClass.new(self, ...)
        g.type = typeName
        return g
    end

    return Sub
end

function BufferGeometry:isBufferGeometry()
    return true
end

-- Axis-aligned bounds, cached on the geometry as three.js does.
function BufferGeometry:computeBoundingBox()
    local Box3 = require "engine.math.box3"
    self.boundingBox = Box3:new():setFromVertices(self.vertices or {})
    return self.boundingBox
end

function BufferGeometry:computeBoundingSphere()
    local Sphere = require "engine.math.sphere"

    local box = self.boundingBox or self:computeBoundingBox()
    local center = Vector3:new(
        (box.min.x + box.max.x) / 2,
        (box.min.y + box.max.y) / 2,
        (box.min.z + box.max.z) / 2
    )

    local r2 = 0
    for _, v in ipairs(self.vertices or {}) do
        local dx, dy, dz = v[1] - center.x, v[2] - center.y, v[3] - center.z
        local d = dx*dx + dy*dy + dz*dz
        if d > r2 then r2 = d end
    end

    self.boundingSphere = Sphere:new(center, math.sqrt(r2))
    return self.boundingSphere
end

function BufferGeometry:getAttribute(name)
    return self.attributes and self.attributes[name] or nil
end

function BufferGeometry:setTexture(tex)
    if self.mesh then self.mesh:setTexture(tex) end
    return self
end

-- three.js frees GPU buffers here; LÖVE meshes are garbage collected, so this
-- only drops the reference and exists so teardown code reads the same.
function BufferGeometry:dispose()
    self.mesh = nil
    return self
end

return BufferGeometry
