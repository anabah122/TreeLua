-- three/geometries/PlaneGeometry.lua
--
--   local ground = PlaneGeometry:new(10, 10)
--
-- Lies in the XY plane facing +Z, as in three.js -- NOT flat on the ground.
-- A floor therefore wants rotating: `mesh:rotateX(-math.pi / 2)`.

local build = require "engine.geometries.build"

local PlaneGeometry = {}

function PlaneGeometry:new(width, height, widthSegments, heightSegments)
    width  = width  or 1
    height = height or 1

    local wSeg = math.max(1, math.floor(widthSegments  or 1))
    local hSeg = math.max(1, math.floor(heightSegments or 1))

    local halfW, halfH = width / 2, height / 2
    local segW, segH = width / wSeg, height / hSeg

    local vertices, indices = {}, {}

    for iy = 0, hSeg do
        local y = iy * segH - halfH
        for ix = 0, wSeg do
            local x = ix * segW - halfW
            -- -y so the texture runs top-down, matching three.js
            vertices[#vertices + 1] = {
                x, -y, 0,
                ix / wSeg, iy / hSeg,
                0, 0, 1,
            }
        end
    end

    local stride = wSeg + 1
    for iy = 0, hSeg - 1 do
        for ix = 0, wSeg - 1 do
            local a = iy * stride + ix + 1
            local b = a + 1
            local c = a + stride
            local d = c + 1
            indices[#indices + 1] = a
            indices[#indices + 1] = c
            indices[#indices + 1] = b
            indices[#indices + 1] = b
            indices[#indices + 1] = c
            indices[#indices + 1] = d
        end
    end

    -- flat: a plane has no inside, so build's outward test does not apply --
    -- it lies at z = 0 and every centroid is coplanar with the origin. The
    -- winding above already faces +Z, matching the normal.
    return build("PlaneGeometry", vertices, indices, {
        width = width, height = height,
        widthSegments = wSeg, heightSegments = hSeg,
    }, true)
end

return PlaneGeometry
