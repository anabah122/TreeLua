-- three/core/LineGeometry.lua — vertex positions for a Line/LineSegments
--
--   local geo = LineGeometry:new{ Vector3:new(0,0,0), Vector3:new(1,0,0) }
--
-- Unlike BufferGeometry there is no love.Mesh: LÖVE has no GL_LINES draw mode,
-- so Line/LineSegments project each point to screen space on the CPU and draw
-- with love.graphics.line (see WebGLRenderer:_drawLines). This holds just the
-- point list.

local LineGeometry = {}
LineGeometry.__index = LineGeometry

function LineGeometry:new(points)
    local g = setmetatable({}, self)
    g.type   = "LineGeometry"
    g.points = points or {}
    g.boundingBox    = nil
    g.boundingSphere = nil
    return g
end

function LineGeometry:isLineGeometry()
    return true
end

function LineGeometry:setPoints(points)
    self.points = points
    return self
end

function LineGeometry:computeBoundingSphere()
    local Sphere = require "math.sphere"
    local Vector3 = require "math.vec3"

    if #self.points == 0 then
        self.boundingSphere = Sphere:new(Vector3:new(), 0)
        return self.boundingSphere
    end

    local min = self.points[1]:clone()
    local max = self.points[1]:clone()
    for _, p in ipairs(self.points) do
        min.x, min.y, min.z = math.min(min.x, p.x), math.min(min.y, p.y), math.min(min.z, p.z)
        max.x, max.y, max.z = math.max(max.x, p.x), math.max(max.y, p.y), math.max(max.z, p.z)
    end

    local center = Vector3:new((min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2)
    local r2 = 0
    for _, p in ipairs(self.points) do
        local dx, dy, dz = p.x - center.x, p.y - center.y, p.z - center.z
        r2 = math.max(r2, dx * dx + dy * dy + dz * dz)
    end

    self.boundingSphere = Sphere:new(center, math.sqrt(r2))
    return self.boundingSphere
end

function LineGeometry:dispose()
    return self
end

return LineGeometry
