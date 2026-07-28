-- three/geometries/build.lua — turn generated vertex data into a BufferGeometry
--
-- Every generator in this directory ends the same way: hand over interleaved
-- vertices and a triangle list, get back a BufferGeometry wrapping a love.Mesh.
-- Kept in one place so the vertex format stays tied to importer.common, which
-- is what the shader's attribute declarations follow.
--
-- Vertices are { x, y, z, u, v, nx, ny, nz }, matching common.FORMAT.

local BufferGeometry = require "three.core.BufferGeometry"
local common         = require "importer.common"

-- Force every triangle to wind outward.
--
-- All the primitives here are convex and centred on the origin, so "outward"
-- has a cheap definition: the face normal from the winding must agree with the
-- direction from the centre to the triangle. Where it does not, two indices
-- swap and the triangle flips.
--
-- Doing this here rather than getting the winding right in each generator is
-- deliberate. Hand-ordering indices per face is the part of geometry code that
-- reliably goes wrong -- a backwards triangle is culled and simply vanishes,
-- which on a solid body looks like nothing at all, because the far side's
-- inward-facing triangles show through in its place. Both the cylinder's top
-- cap and two of the cube's faces shipped wrong that way. One rule applied to
-- everything is smaller than six sign conventions and cannot drift out of sync.
--
-- Degenerate triangles -- the collapsed rows at a sphere's poles or a cone's
-- tip -- have no meaningful orientation and are left alone.
local function orientOutward(vertices, indices)
    for i = 1, #indices, 3 do
        local p1 = vertices[indices[i]]
        local p2 = vertices[indices[i + 1]]
        local p3 = vertices[indices[i + 2]]

        local ax, ay, az = p2[1] - p1[1], p2[2] - p1[2], p2[3] - p1[3]
        local bx, by, bz = p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3]

        -- cross(a, b): the face normal implied by counter-clockwise winding
        local nx = ay * bz - az * by
        local ny = az * bx - ax * bz
        local nz = ax * by - ay * bx

        -- centroid, which doubles as the outward direction from the origin
        local cx = (p1[1] + p2[1] + p3[1]) / 3
        local cy = (p1[2] + p2[2] + p3[2]) / 3
        local cz = (p1[3] + p2[3] + p3[3]) / 3

        if nx * cx + ny * cy + nz * cz < 0 then
            indices[i + 1], indices[i + 2] = indices[i + 2], indices[i + 1]
        end
    end
    return indices
end

-- `flat` marks geometry that is not a closed convex body -- a plane, an open
-- cylinder wall -- where the centroid test is meaningless: such a surface has
-- no inside, and its centroid can sit on either side of the origin. Those keep
-- the winding their generator produced.
return function(typeName, vertices, indices, parameters, flat)
    if not flat then
        orientOutward(vertices, indices)
    end

    local g = BufferGeometry:new{
        name     = typeName,
        vertices = vertices,
        indices  = indices,
        mesh     = love.graphics.newMesh(common.FORMAT, vertices, "triangles", "static"),
    }

    g.type = typeName
    g.mesh:setVertexMap(indices)
    g.parameters = parameters

    return g
end
