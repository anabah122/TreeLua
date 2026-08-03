-- three/geometries/ConeGeometry.lua
--
--   local geometry = ConeGeometry:new(0.5, 1, 32)
--
-- A cylinder whose top radius is zero. three.js defines it exactly this way,
-- so the argument list drops radiusTop and everything else lines up.

local CylinderGeometry = require "engine.geometries.CylinderGeometry"

local ConeGeometry = {}

function ConeGeometry:new(radius, height, radialSegments, heightSegments,
                          openEnded, thetaStart, thetaLength)
    local g = CylinderGeometry:new(0, radius or 1, height or 1,
        radialSegments, heightSegments, openEnded, thetaStart, thetaLength)

    g.type = "ConeGeometry"
    g.name = "ConeGeometry"
    g.parameters.radius = radius or 1

    return g
end

return ConeGeometry
