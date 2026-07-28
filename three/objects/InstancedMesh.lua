-- three/objects/InstancedMesh.lua — one geometry drawn at many transforms
--
--   local field = InstancedMesh:new(geometry, material, 200)
--   local m = Matrix4:new()
--   for i = 1, 200 do
--       m:makeTranslation(i % 20, 0, math.floor(i / 20))
--       field:setMatrixAt(i, m)
--   end
--   scene:add(field)
--
-- The API is three.js's, including the 1-based index (three.js counts from 0;
-- everything else in this engine counts from 1, and mixing the two inside one
-- library is worse than the small divergence).
--
-- What it does NOT do is one draw call for the whole set. The bundled shader
-- takes a single u_model, so the renderer walks the instances and issues one
-- draw each -- the saving is in the shared geometry, material and bounds, not
-- in the call count. The class exists so scene code written against three.js
-- runs; when the shader grows an instance attribute the internals change and
-- this surface does not.

local Mesh    = require "three.objects.Mesh"
local Matrix4 = require "math.mat4"
local Color   = require "math.color"

local InstancedMesh = Mesh:extend("InstancedMesh")

function InstancedMesh:new(geometry, material, count)
    local m = Mesh.new(self, geometry, material)
    m.type = "InstancedMesh"

    m.count      = count or 0
    m.instanceMatrix = {}
    m.instanceColor  = nil

    for i = 1, m.count do
        m.instanceMatrix[i] = Matrix4:new()
    end

    return m
end

function InstancedMesh:isInstancedMesh()
    return true
end

function InstancedMesh:getMatrixAt(index, target)
    target = target or Matrix4:new()
    local m = self.instanceMatrix[index]
    if m then target:copy(m) end
    return target
end

function InstancedMesh:setMatrixAt(index, matrix)
    if index < 1 or index > self.count then return self end

    self.instanceMatrix[index] = self.instanceMatrix[index] or Matrix4:new()
    self.instanceMatrix[index]:copy(matrix)

    return self
end

function InstancedMesh:getColorAt(index, target)
    target = target or Color:new()
    local c = self.instanceColor and self.instanceColor[index]
    if c then target:copy(c) end
    return target
end

function InstancedMesh:setColorAt(index, color)
    if index < 1 or index > self.count then return self end

    self.instanceColor = self.instanceColor or {}
    self.instanceColor[index] = self.instanceColor[index] or Color:new()
    self.instanceColor[index]:copy(color)

    return self
end

-- Grow or shrink the set. New slots get an identity matrix rather than nil, so
-- the renderer never has to test for a hole.
function InstancedMesh:setCount(count)
    for i = self.count + 1, count do
        self.instanceMatrix[i] = self.instanceMatrix[i] or Matrix4:new()
    end
    self.count = count
    return self
end

function InstancedMesh:copy(source, recursive)
    Mesh.copy(self, source, recursive)

    self.count = source.count
    self.instanceMatrix = {}
    for i = 1, source.count do
        self.instanceMatrix[i] = Matrix4:new():copy(source.instanceMatrix[i])
    end

    if source.instanceColor then
        self.instanceColor = {}
        for i, c in pairs(source.instanceColor) do
            self.instanceColor[i] = Color:new():copy(c)
        end
    end

    return self
end

function InstancedMesh:dispose()
    self.instanceMatrix = {}
    self.instanceColor  = nil
    return self
end

return InstancedMesh
