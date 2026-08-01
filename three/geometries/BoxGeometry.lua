-- three/geometries/BoxGeometry.lua
--
--   local geometry = BoxGeometry:new(1, 1, 1)
--   scene:add(TL.Mesh:new(geometry, TL.MeshStandardMaterial:new{ color = 0xff8800 }))
--
-- Six faces built from one shared routine, as three.js does: each is a plane
-- laid out in two of the three axes and pushed out along the third. Segment
-- counts follow the three.js constructor, so a segmented box subdivides the
-- same way -- worth having even without a displacement shader, because a flat
-- quad lit per-vertex bands badly.

local build = require "three.geometries.build"

local BoxGeometry = {}

-- u, v and w name which axis each face's two in-plane directions and its
-- normal map onto; the signs flip the winding so every face points outward.
local FACES = {
    -- udir, vdir, wdir, uSign, vSign, wSign
    { 3, 2, 1,  1, -1,  1 },   -- +X
    { 3, 2, 1, -1, -1, -1 },   -- -X
    { 1, 3, 2,  1,  1,  1 },   -- +Y
    { 1, 3, 2,  1, -1, -1 },   -- -Y
    { 1, 2, 3,  1, -1,  1 },   -- +Z
    { 1, 2, 3, -1, -1, -1 },   -- -Z
}

function BoxGeometry:new(width, height, depth, widthSegments, heightSegments, depthSegments)
    width  = width  or 1
    height = height or 1
    depth  = depth  or 1

    local segs = {
        math.max(1, math.floor(widthSegments  or 1)),
        math.max(1, math.floor(heightSegments or 1)),
        math.max(1, math.floor(depthSegments  or 1)),
    }
    local size = { width, height, depth }

    local vertices, indices = {}, {}

    for _, face in ipairs(FACES) do
        local u, v, w = face[1], face[2], face[3]
        local uSign, vSign, wSign = face[4], face[5], face[6]

        local gridU = segs[u]
        local gridV = segs[v]
        local half  = size[w] / 2

        local base = #vertices

        for iv = 0, gridV do
            for iu = 0, gridU do
                local su = (iu / gridU - 0.5) * size[u] * uSign
                local sv = (iv / gridV - 0.5) * size[v] * vSign

                local pos = { 0, 0, 0 }
                pos[u] = su
                pos[v] = sv
                pos[w] = half * wSign

                local nrm = { 0, 0, 0 }
                nrm[w] = wSign

                vertices[#vertices + 1] = {
                    pos[1], pos[2], pos[3],
                    iu / gridU, 1 - iv / gridV,
                    nrm[1], nrm[2], nrm[3],
                }
            end
        end

        -- The uSign/vSign pairs above are picked for the NORMALS; they do not
        -- give a consistent winding across the six faces (two of them come out
        -- reversed). That is fine: build() reorients every triangle outward.
        local stride = gridU + 1
        for iv = 0, gridV - 1 do
            for iu = 0, gridU - 1 do
                local a = base + iv * stride + iu + 1
                local b = a + 1
                local c = a + stride
                local d = c + 1
                indices[#indices + 1] = a
                indices[#indices + 1] = b
                indices[#indices + 1] = c
                indices[#indices + 1] = b
                indices[#indices + 1] = d
                indices[#indices + 1] = c
            end
        end
    end

    return build("BoxGeometry", vertices, indices, {
        width = width, height = height, depth = depth,
        widthSegments  = segs[1],
        heightSegments = segs[2],
        depthSegments  = segs[3],
    })
end

return BoxGeometry
