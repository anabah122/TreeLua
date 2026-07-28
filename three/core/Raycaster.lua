-- three/core/Raycaster.lua — picking against scene geometry
--
--   local caster = Raycaster:new()
--   caster:setFromCamera(mouseX, mouseY, camera, screenW, screenH)
--   local hits = caster:intersectObjects(scene.children, true)
--   if hits[1] then print(hits[1].object.name, hits[1].distance) end
--
-- Each hit is { distance, point, object, face, faceIndex, uv }, ordered
-- nearest first, as in three.js.
--
-- Skinned meshes are tested against their BIND pose: the vertex tables here are
-- the pre-skinning data, since the deformation happens on the GPU. A moving
-- character therefore picks roughly, not exactly.

local Vector3 = require "math.vec3"
local Ray     = require "math.ray"
local Matrix4 = require "math.mat4"
local Sphere  = require "math.sphere"

local Raycaster = {}
Raycaster.__index = Raycaster

function Raycaster:new(origin, direction, near, far)
    local r = setmetatable({}, Raycaster)

    r.type = "Raycaster"
    r.ray  = Ray:new(origin, direction)
    r.near = near or 0
    r.far  = far  or math.huge

    -- three.js keeps per-object-type settings here; only the mesh one applies
    r.params = { Mesh = {} }

    return r
end

function Raycaster:isRaycaster()
    return true
end

function Raycaster:set(origin, direction)
    self.ray:set(origin, direction)
    return self
end

-- three.js signature: `coords` carries normalised device coordinates, both
-- components in [-1, 1] with +Y up.
function Raycaster:setFromCamera(coords, camera)
    local ndcX, ndcY = coords.x, coords.y

    camera:updateWorldMatrix(true, false)

    if camera.isPerspectiveCamera and camera:isPerspectiveCamera() then
        -- origin at the eye, direction through the unprojected near point
        self.ray.origin:setFromMatrixPosition(camera.matrixWorld)
        self.ray.direction
            :set(ndcX, ndcY, 0.5)
            :applyMatrix4(camera.projectionMatrixInverse)
            :applyMatrix4(camera.matrixWorld)
            :subV(self.ray.origin)
            :normalizeSelf()
    else
        -- orthographic: parallel rays, so the origin slides across the near
        -- plane and the direction is the camera's own forward
        self.ray.origin
            :set(ndcX, ndcY, -1)
            :applyMatrix4(camera.projectionMatrixInverse)
            :applyMatrix4(camera.matrixWorld)
        camera:getWorldDirection(self.ray.direction)
    end

    return self
end

-- Facade over setFromCamera for the coordinates LOVE actually hands you.
--
-- three.js has no equivalent because a WebGLRenderer knows its own canvas and
-- every example normalises by hand; a love.mousepressed handler gets pixels,
-- so the conversion lives here instead of in every caller. Note the flipped Y:
-- screen space grows downward, NDC upward.
function Raycaster:setFromScreen(x, y, camera, width, height)
    width  = width  or love.graphics.getWidth()
    height = height or love.graphics.getHeight()

    return self:setFromCamera({
        x =  (x / width)  * 2 - 1,
        y = -((y / height) * 2 - 1),
    }, camera)
end

-- Barycentric interpolation of the UVs at a hit point, so a pick can report
-- where on the texture it landed.
local function uvAt(point, a, b, c, uvA, uvB, uvC)
    local v0 = Vector3:new():subVectors(b, a)
    local v1 = Vector3:new():subVectors(c, a)
    local v2 = Vector3:new():subVectors(point, a)

    local d00, d01, d11 = v0:dot(v0), v0:dot(v1), v1:dot(v1)
    local d20, d21 = v2:dot(v0), v2:dot(v1)

    local denom = d00 * d11 - d01 * d01
    if denom == 0 then return nil end

    local v = (d11 * d20 - d01 * d21) / denom
    local w = (d00 * d21 - d01 * d20) / denom
    local u = 1 - v - w

    return {
        u * uvA[1] + v * uvB[1] + w * uvC[1],
        u * uvA[2] + v * uvB[2] + w * uvC[2],
    }
end

-- Test one mesh. The ray is pulled into the mesh's local space rather than the
-- vertices pushed into world space: one matrix inverse against thousands of
-- transforms.
function Raycaster:intersectMesh(object, hits)
    local geometry = object.geometry
    if not geometry or not geometry.vertices then return hits end

    local material = object.material
    if material and material.visible == false then return hits end

    -- cheap reject on the bounding sphere before touching any triangle
    local bs = geometry.boundingSphere or geometry:computeBoundingSphere()
    if bs then
        local world = Sphere:new(bs.center, bs.radius):applyMatrix4(object.matrixWorld)
        if not self.ray:intersectsSphere(world) then return hits end
    end

    local inverse = Matrix4:new():copy(object.matrixWorld):invert()
    local localRay = Ray:new():copy(self.ray):applyMatrix4(inverse)

    local vertices = geometry.vertices
    local indices  = geometry.indices

    -- an unindexed mesh draws its vertices in order, three at a time
    local count = indices and #indices or #vertices

    local backfaceCulling = not (material and material.side ~= "front")

    local a, b, c = Vector3:new(), Vector3:new(), Vector3:new()
    local hitPoint = Vector3:new()

    for i = 1, count - 2, 3 do
        local i1 = indices and indices[i]     or i
        local i2 = indices and indices[i + 1] or i + 1
        local i3 = indices and indices[i + 2] or i + 2

        local v1, v2, v3 = vertices[i1], vertices[i2], vertices[i3]
        if v1 and v2 and v3 then
            a:set(v1[1], v1[2], v1[3])
            b:set(v2[1], v2[2], v2[3])
            c:set(v3[1], v3[2], v3[3])

            if localRay:intersectTriangle(a, b, c, backfaceCulling, hitPoint) then
                -- back to world space to measure: a scaled mesh's local
                -- distance is not the distance the caller means
                local world = Vector3:new():copy(hitPoint):applyMatrix4(object.matrixWorld)
                local distance = self.ray.origin:distanceTo(world)

                if distance >= self.near and distance <= self.far then
                    local normal = Vector3:new():crossVectors(
                        Vector3:new():subVectors(c, b),
                        Vector3:new():subVectors(a, b)
                    ):normalizeSelf()

                    hits[#hits + 1] = {
                        distance  = distance,
                        point     = world,
                        object    = object,
                        faceIndex = (i - 1) / 3 + 1,
                        face      = { a = i1, b = i2, c = i3, normal = normal },
                        uv        = uvAt(hitPoint, a, b, c,
                                         { v1[4], v1[5] }, { v2[4], v2[5] }, { v3[4], v3[5] }),
                    }
                end
            end
        end
    end

    return hits
end

function Raycaster:intersectObject(object, recursive, hits)
    hits = hits or {}

    if object.visible == false then return hits end

    object:updateWorldMatrix(true, false)

    if object.isMesh and object:isMesh() then
        self:intersectMesh(object, hits)
    end

    if recursive ~= false then
        for _, child in ipairs(object.children) do
            self:intersectObject(child, true, hits)
        end
    end

    table.sort(hits, function(p, q) return p.distance < q.distance end)
    return hits
end

function Raycaster:intersectObjects(objects, recursive, hits)
    hits = hits or {}

    for _, object in ipairs(objects) do
        self:intersectObject(object, recursive, hits)
    end

    table.sort(hits, function(p, q) return p.distance < q.distance end)
    return hits
end

return Raycaster
