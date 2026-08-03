-- three/geometries/CylinderGeometry.lua
--
--   local geometry = CylinderGeometry:new(0.5, 0.5, 2, 32)
--   local cone     = CylinderGeometry:new(0, 0.5, 2, 32)   -- top radius 0
--
-- Argument order follows three.js: radiusTop, radiusBottom, height. A zero top
-- radius gives a cone, which is why three.js's ConeGeometry is just this with
-- one argument pinned -- see ConeGeometry.lua.

local build = require "engine.geometries.build"

local CylinderGeometry = {}

function CylinderGeometry:new(radiusTop, radiusBottom, height, radialSegments,
                              heightSegments, openEnded, thetaStart, thetaLength)
    radiusTop    = radiusTop    or 1
    radiusBottom = radiusBottom or 1
    height       = height       or 1

    local rSeg = math.max(3, math.floor(radialSegments or 32))
    local hSeg = math.max(1, math.floor(heightSegments or 1))

    openEnded   = openEnded or false
    thetaStart  = thetaStart  or 0
    thetaLength = thetaLength or math.pi * 2

    local vertices, indices = {}, {}
    local halfHeight = height / 2

    -- ── side wall ────────────────────────────────────────────────────────────
    -- The normal tilts with the taper: a cone's wall does not face straight
    -- out, so slope feeds the y component.
    local slope = (radiusBottom - radiusTop) / height
    local grid = {}

    for iy = 0, hSeg do
        local row = {}
        local v = iy / hSeg
        local radius = v * (radiusBottom - radiusTop) + radiusTop

        for ix = 0, rSeg do
            local u = ix / rSeg
            local theta = u * thetaLength + thetaStart
            local sinTheta, cosTheta = math.sin(theta), math.cos(theta)

            local x =  radius * sinTheta
            local y = -v * height + halfHeight
            local z =  radius * cosTheta

            local nx, ny, nz = sinTheta, slope, cosTheta
            local len = math.sqrt(nx * nx + ny * ny + nz * nz)
            if len > 0 then nx, ny, nz = nx / len, ny / len, nz / len end

            vertices[#vertices + 1] = { x, y, z, u, 1 - v, nx, ny, nz }
            row[#row + 1] = #vertices
        end

        grid[#grid + 1] = row
    end

    for ix = 1, rSeg do
        for iy = 1, hSeg do
            local a = grid[iy][ix]
            local b = grid[iy + 1][ix]
            local c = grid[iy + 1][ix + 1]
            local d = grid[iy][ix + 1]

            -- a cone's tip row collapses to a point; those triangles are
            -- zero-area and would only waste fill rate
            if radiusTop > 0 or iy ~= 1 then
                indices[#indices + 1] = a
                indices[#indices + 1] = b
                indices[#indices + 1] = d
            end
            if radiusBottom > 0 or iy ~= hSeg then
                indices[#indices + 1] = b
                indices[#indices + 1] = c
                indices[#indices + 1] = d
            end
        end
    end

    -- ── caps ─────────────────────────────────────────────────────────────────
    local function cap(top)
        local radius = top and radiusTop or radiusBottom
        if radius <= 0 then return end

        local sign = top and 1 or -1
        local y    = halfHeight * sign

        local centre = #vertices + 1
        vertices[#vertices + 1] = { 0, y, 0, 0.5, 0.5, 0, sign, 0 }

        local first = #vertices + 1
        for ix = 0, rSeg do
            local u = ix / rSeg
            local theta = u * thetaLength + thetaStart
            local sinTheta, cosTheta = math.sin(theta), math.cos(theta)

            vertices[#vertices + 1] = {
                radius * sinTheta, y, radius * cosTheta,
                sinTheta * 0.5 * sign + 0.5, cosTheta * 0.5 + 0.5,
                0, sign, 0,
            }
        end

        -- Index order here is arbitrary: build() reorients every triangle
        -- outward, so the cap does not have to know which way its rim runs.
        for ix = 0, rSeg - 1 do
            local a = first + ix
            indices[#indices + 1] = centre
            indices[#indices + 1] = a
            indices[#indices + 1] = a + 1
        end
    end

    if not openEnded then
        cap(true)
        cap(false)
    end

    return build("CylinderGeometry", vertices, indices, {
        radiusTop = radiusTop, radiusBottom = radiusBottom, height = height,
        radialSegments = rSeg, heightSegments = hSeg,
        openEnded = openEnded,
        thetaStart = thetaStart, thetaLength = thetaLength,
    })
end

return CylinderGeometry
