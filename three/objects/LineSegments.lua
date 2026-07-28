-- three/objects/LineSegments.lua — disconnected line pairs
--
--   local axes = LineSegments:new(LineGeometry:new{
--       Vector3:new(0,0,0), Vector3:new(1,0,0),   -- segment 1
--       Vector3:new(0,0,0), Vector3:new(0,1,0),   -- segment 2
--   }, LineBasicMaterial:new{ color = 0xffffff })
--
-- Points draw in pairs: (1,2), (3,4), ... each an independent segment, unlike
-- Line's continuous strip. Standard for gizmos/debug wireframes where
-- adjacent edges should not connect.

local Line = require "three.objects.Line"

local LineSegments = setmetatable({}, { __index = Line })
LineSegments.__index = LineSegments

function LineSegments:new(geometry, material)
    local l = Line.new(self, geometry, material)
    l.type = "LineSegments"
    return l
end

function LineSegments:isLineSegments()
    return true
end

return LineSegments
