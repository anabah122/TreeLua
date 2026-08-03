-- three/geometries/SphereGeometry.lua
--
--   local geometry = SphereGeometry:new(0.5, 32, 16)
--
-- A UV sphere: rings of latitude subdivided along longitude. Argument order
-- and defaults follow three.js, including the phi/theta ranges that let a
-- partial sphere -- a dome, a wedge -- come out of the same generator.
--
-- The poles are degenerate: every vertex in the top row sits at the same
-- point. three.js still emits them so the UV seam runs somewhere sensible, and
-- skips the triangles that would be zero-area, which is what the index loop
-- below does.

local build = require "engine.geometries.build"

local SphereGeometry = {}

function SphereGeometry:new(radius, widthSegments, heightSegments,
                            phiStart, phiLength, thetaStart, thetaLength)
    radius = radius or 1

    local wSeg = math.max(3, math.floor(widthSegments  or 32))
    local hSeg = math.max(2, math.floor(heightSegments or 16))

    phiStart    = phiStart    or 0
    phiLength   = phiLength   or math.pi * 2
    thetaStart  = thetaStart  or 0
    thetaLength = thetaLength or math.pi

    local thetaEnd = math.min(thetaStart + thetaLength, math.pi)

    local vertices, indices = {}, {}
    local grid = {}

    for iy = 0, hSeg do
        local row = {}
        local v = iy / hSeg

        -- three.js nudges the pole UVs sideways by half a step so the texture
        -- does not pinch to a single column there
        local uOffset = 0
        if iy == 0 and thetaStart == 0 then
            uOffset = 0.5 / wSeg
        elseif iy == hSeg and thetaEnd == math.pi then
            uOffset = -0.5 / wSeg
        end

        local theta = thetaStart + v * thetaLength
        local sinTheta, cosTheta = math.sin(theta), math.cos(theta)

        for ix = 0, wSeg do
            local u = ix / wSeg
            local phi = phiStart + u * phiLength

            local x = -radius * math.cos(phi) * sinTheta
            local y =  radius * cosTheta
            local z =  radius * math.sin(phi) * sinTheta

            -- radius cancels out, so the position doubles as the normal
            local len = math.sqrt(x * x + y * y + z * z)
            local nx, ny, nz = 0, 1, 0
            if len > 0 then nx, ny, nz = x / len, y / len, z / len end

            vertices[#vertices + 1] = { x, y, z, u + uOffset, 1 - v, nx, ny, nz }
            row[#row + 1] = #vertices
        end

        grid[#grid + 1] = row
    end

    for iy = 1, hSeg do
        for ix = 1, wSeg do
            local a = grid[iy][ix + 1]
            local b = grid[iy][ix]
            local c = grid[iy + 1][ix]
            local d = grid[iy + 1][ix + 1]

            -- skip the degenerate triangle at each pole
            if iy ~= 1 or thetaStart > 0 then
                indices[#indices + 1] = a
                indices[#indices + 1] = b
                indices[#indices + 1] = d
            end
            if iy ~= hSeg or thetaEnd < math.pi then
                indices[#indices + 1] = b
                indices[#indices + 1] = c
                indices[#indices + 1] = d
            end
        end
    end

    return build("SphereGeometry", vertices, indices, {
        radius = radius,
        widthSegments = wSeg, heightSegments = hSeg,
        phiStart = phiStart, phiLength = phiLength,
        thetaStart = thetaStart, thetaLength = thetaLength,
    })
end

return SphereGeometry
