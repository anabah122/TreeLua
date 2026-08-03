-- three/geometries/TorusGeometry.lua
--
--   local geometry = TorusGeometry:new(1, 0.4, 16, 48)
--
-- Argument order follows three.js: radius, tube, radialSegments,
-- tubularSegments, arc.
--
-- A torus is the one primitive here that is NOT convex, so build()'s
-- centroid-from-origin rule would flip the inner wall: those triangles face
-- toward the axis, away from the centre. The winding is therefore produced
-- correctly by the loop and passed through with `flat` set -- the normals come
-- from the tube's own centre, which is the real outward direction.

local build = require "engine.geometries.build"

local TorusGeometry = {}

function TorusGeometry:new(radius, tube, radialSegments, tubularSegments, arc)
    radius = radius or 1
    tube   = tube   or 0.4
    arc    = arc    or math.pi * 2

    local rSeg = math.max(3, math.floor(radialSegments  or 12))
    local tSeg = math.max(3, math.floor(tubularSegments or 48))

    local vertices, indices = {}, {}

    for j = 0, rSeg do
        for i = 0, tSeg do
            local u = i / tSeg * arc
            local v = j / rSeg * math.pi * 2

            local cosU, sinU = math.cos(u), math.sin(u)
            local cosV, sinV = math.cos(v), math.sin(v)

            local x = (radius + tube * cosV) * cosU
            local y = (radius + tube * cosV) * sinU
            local z =  tube * sinV

            -- outward from the tube's centre at this angle, not from the origin
            local cx, cy = radius * cosU, radius * sinU
            local nx, ny, nz = x - cx, y - cy, z
            local len = math.sqrt(nx * nx + ny * ny + nz * nz)
            if len > 0 then nx, ny, nz = nx / len, ny / len, nz / len end

            vertices[#vertices + 1] = { x, y, z, i / tSeg, j / rSeg, nx, ny, nz }
        end
    end

    local stride = tSeg + 1

    for j = 1, rSeg do
        for i = 1, tSeg do
            local a = (j - 1) * stride + i
            local b = (j - 1) * stride + i + 1
            local c =  j      * stride + i + 1
            local d =  j      * stride + i

            indices[#indices + 1] = a
            indices[#indices + 1] = d
            indices[#indices + 1] = b

            indices[#indices + 1] = b
            indices[#indices + 1] = d
            indices[#indices + 1] = c
        end
    end

    return build("TorusGeometry", vertices, indices, {
        radius = radius, tube = tube,
        radialSegments = rSeg, tubularSegments = tSeg,
        arc = arc,
    }, true)
end

return TorusGeometry
