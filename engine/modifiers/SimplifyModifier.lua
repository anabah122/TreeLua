-- three/modifiers/SimplifyModifier.lua — vertex clustering mesh simplification
--
--   local simplified = SimplifyModifier.simplify(geometry, 0.5)
--
-- Grid-based vertex clustering, scaled to the model's own size so it works
-- the same on a 2-unit prop and a 200-unit building:
--   1. compute the model's bounding box, pick a grid resolution from the
--      target vertex count (targetRatio * vertexCount cells, cube root split
--      across x/y/z)
--   2. bucket every vertex into its cell
--   3. each cell collapses to one vertex -- not the plain average, but the
--      point minimizing the summed quadric error of the vertices in it, which
--      keeps sharp features instead of just blurring them to a centroid
--   4. triangles get their indices remapped to the merged vertices; triangles
--      that end up with a repeated index (all 3 corners fell in one cell) are
--      dropped
--
-- Only handles unskinned geometry: { x,y,z, u,v, nx,ny,nz } vertices.

local common = require "engine.importer.common"

local SimplifyModifier = {}

local function planeFromPoints(p1, p2, p3)
    local ax, ay, az = p2[1]-p1[1], p2[2]-p1[2], p2[3]-p1[3]
    local bx, by, bz = p3[1]-p1[1], p3[2]-p1[2], p3[3]-p1[3]

    local nx = ay*bz - az*by
    local ny = az*bx - ax*bz
    local nz = ax*by - ay*bx
    local len = math.sqrt(nx*nx + ny*ny + nz*nz)
    if len < 1e-12 then return nil end
    nx, ny, nz = nx/len, ny/len, nz/len

    local d = -(nx*p1[1] + ny*p1[2] + nz*p1[3])
    return nx, ny, nz, d
end

-- symmetric 4x4 quadric as 10 upper-triangle terms: a2 ab ac ad b2 bc bd c2 cd d2
local function addPlane(q, nx, ny, nz, d)
    q[1]=q[1]+nx*nx; q[2]=q[2]+nx*ny; q[3]=q[3]+nx*nz; q[4]=q[4]+nx*d
    q[5]=q[5]+ny*ny; q[6]=q[6]+ny*nz; q[7]=q[7]+ny*d
    q[8]=q[8]+nz*nz; q[9]=q[9]+nz*d
    q[10]=q[10]+d*d
end

-- Solve the 3x3 system minimizing v^T*Q*v; nil when singular (flat cluster).
local function optimalPoint(q)
    local a,b,c,d, e,f,g, h,i = q[1],q[2],q[3],q[4], q[5],q[6],q[7], q[8],q[9]

    local det = a*(e*h - f*f) - b*(b*h - f*c) + c*(b*f - e*c)
    if math.abs(det) < 1e-9 then return nil end

    local rx, ry, rz = -d, -g, -i
    local invDet = 1 / det

    local x = (rx*(e*h - f*f) - b*(ry*h - f*rz) + c*(ry*f - e*rz)) * invDet
    local y = (a*(ry*h - f*rz) - rx*(b*h - f*c) + c*(b*rz - ry*c)) * invDet
    local z = (a*(e*rz - ry*f) - b*(b*rz - ry*c) + rx*(b*f - e*c)) * invDet

    return x, y, z
end

-- SimplifyModifier.simplify(geometry, targetRatio) -> new BufferGeometry
function SimplifyModifier.simplify(geometry, targetRatio)
    local verts = geometry.vertices
    local idx   = geometry.indices
    if not verts or not idx then return geometry end

    local vertexCount = #verts

    local minX, minY, minZ =  math.huge,  math.huge,  math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for _, v in ipairs(verts) do
        if v[1] < minX then minX = v[1] end
        if v[2] < minY then minY = v[2] end
        if v[3] < minZ then minZ = v[3] end
        if v[1] > maxX then maxX = v[1] end
        if v[2] > maxY then maxY = v[2] end
        if v[3] > maxZ then maxZ = v[3] end
    end
    local sizeX, sizeY, sizeZ = maxX-minX, maxY-minY, maxZ-minZ

    -- grid resolution adapts to model scale: target cell count is
    -- targetRatio * vertexCount, split across 3 axes proportionally to the
    -- bounding box shape so cells stay roughly cubic on non-uniform models
    local targetCells = math.max(1, math.floor(vertexCount * targetRatio))
    local volume = math.max(sizeX * sizeY * sizeZ, 1e-9)
    local cellSize = (volume / targetCells) ^ (1/3)
    if cellSize < 1e-9 then return geometry end

    local resX = math.max(1, math.ceil(sizeX / cellSize))
    local resY = math.max(1, math.ceil(sizeY / cellSize))
    local resZ = math.max(1, math.ceil(sizeZ / cellSize))

    local function cellOf(v)
        local cx = sizeX > 0 and math.min(resX-1, math.floor((v[1]-minX) / sizeX * resX)) or 0
        local cy = sizeY > 0 and math.min(resY-1, math.floor((v[2]-minY) / sizeY * resY)) or 0
        local cz = sizeZ > 0 and math.min(resZ-1, math.floor((v[3]-minZ) / sizeZ * resZ)) or 0
        return (cz * resY + cy) * resX + cx
    end

    -- accumulate quadric + averaged uv/normal per occupied cell
    local clusters = {}
    local cellOfVertex = {}
    for vi, v in ipairs(verts) do
        local key = cellOf(v)
        cellOfVertex[vi] = key
        local c = clusters[key]
        if not c then
            c = { q = {0,0,0,0,0,0,0,0,0,0}, u=0, vv=0, nx=0, ny=0, nz=0, n=0,
                  fx=v[1], fy=v[2], fz=v[3] }
            clusters[key] = c
        end
        c.u = c.u + v[4]; c.vv = c.vv + v[5]
        c.nx = c.nx + v[6]; c.ny = c.ny + v[7]; c.nz = c.nz + v[8]
        c.n = c.n + 1
    end

    -- feed each cluster's quadric from the faces touching its vertices
    for i = 1, #idx, 3 do
        local i1, i2, i3 = idx[i], idx[i+1], idx[i+2]
        local p1, p2, p3 = verts[i1], verts[i2], verts[i3]
        local nx, ny, nz, d = planeFromPoints(p1, p2, p3)
        if nx then
            addPlane(clusters[cellOfVertex[i1]].q, nx, ny, nz, d)
            addPlane(clusters[cellOfVertex[i2]].q, nx, ny, nz, d)
            addPlane(clusters[cellOfVertex[i3]].q, nx, ny, nz, d)
        end
    end

    -- resolve one output vertex per cluster
    local mergedIndex = {}
    local outVerts = {}
    for key, c in pairs(clusters) do
        local x, y, z = optimalPoint(c.q)
        if not x then x, y, z = c.fx, c.fy, c.fz end
        outVerts[#outVerts+1] = { x, y, z, c.u/c.n, c.vv/c.n, c.nx/c.n, c.ny/c.n, c.nz/c.n }
        mergedIndex[key] = #outVerts
    end

    -- remap triangles, dropping ones collapsed to a point or a line
    local finalIdx = {}
    for i = 1, #idx, 3 do
        local a = mergedIndex[cellOfVertex[idx[i]]]
        local b = mergedIndex[cellOfVertex[idx[i+1]]]
        local c = mergedIndex[cellOfVertex[idx[i+2]]]
        if a ~= b and b ~= c and a ~= c then
            finalIdx[#finalIdx+1] = a
            finalIdx[#finalIdx+1] = b
            finalIdx[#finalIdx+1] = c
        end
    end

    local BufferGeometry = require "engine.core.BufferGeometry"
    local out = BufferGeometry:new{
        name     = geometry.name,
        vertices = outVerts,
        indices  = finalIdx,
        mesh     = love.graphics.newMesh(common.FORMAT, outVerts, "triangles", "static"),
    }
    out.mesh:setVertexMap(finalIdx)
    return out
end

return SimplifyModifier
