-- three/objects/Line.lua — connected polyline
--
--   local line = Line:new(LineGeometry:new(points), LineBasicMaterial:new{ color = 0xff0000 })
--   scene:add(line)
--
-- Points draw as one continuous strip: point i connects to point i+1. See
-- LineSegments for disconnected pairs (gizmo axes, wireframe edges).

local Object3D = require "three.core.Object3D"

local Line = Object3D:extend("Line")

function Line:new(geometry, material)
    local l = Object3D.new(self)
    l.type = "Line"
    l.geometry = geometry
    l.material = material
    return l
end

function Line:isLine()
    return true
end

function Line:copy(source, recursive)
    Object3D.copy(self, source, recursive)
    self.geometry = source.geometry
    self.material = source.material
    return self
end

return Line
