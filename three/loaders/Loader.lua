-- three/loaders/Loader.lua — shared scene assembly for the format loaders
--
-- Both importers return the same thing: a flat array of drawable primitives,
-- plus model-level `nodes`, `skins` and `animations`. This module turns that
-- into the { scene = Group, animations = {AnimationClip} } result three.js
-- loaders hand to their callback.
--
-- Only the FACADE is built here -- the entry tables keep pointing at the very
-- same love.Mesh objects and node list the importer produced, so nothing is
-- copied and the animation sampler still writes to the nodes the skinning
-- palette reads.

local Group              = require "three.core.Group"
local Mesh               = require "three.objects.Mesh"
local SkinnedMesh        = require "three.objects.SkinnedMesh"
local Skeleton           = require "three.objects.Skeleton"
local BufferGeometry     = require "three.core.BufferGeometry"
local MeshStandardMaterial = require "three.materials.MeshStandardMaterial"
local AnimationClip      = require "three.animation.AnimationClip"

local Loader = {}
Loader.__index = Loader

function Loader:new()
    local l = setmetatable({}, self)
    l.__index = l == Loader and Loader or l
    l.type = "Loader"
    l.path = ""
    return l
end

function Loader:extend(typeName)
    local Sub = setmetatable({}, { __index = self })
    Sub.__index = Sub
    Sub.__parentClass = self

    function Sub:new(...)
        local o = self.__parentClass.new(self, ...)
        o.type = typeName
        return o
    end

    return Sub
end

-- Prefix joined to every path passed to load(), as in three.js.
function Loader:setPath(path)
    self.path = path or ""
    return self
end

function Loader:resolveURL(url)
    if self.path == "" then return url end
    return self.path .. url
end

-- Build the facade over one importer result.
--
-- `sampler` is the format's animation module; it is stored on each clip so the
-- mixer can sample without knowing which importer produced it.
function Loader:_assemble(data, sampler)
    local root = Group:new()
    root.name = "root"

    -- One skeleton per model: both importers keep every node in a single flat
    -- list, and a skin is a selection of indices into it, so all skinned
    -- meshes in the file share this object.
    local skeletons = {}

    for _, entry in ipairs(data) do
        if entry.mesh then
            local geometry = BufferGeometry:new(entry)
            local material = MeshStandardMaterial:fromImporter(entry.material)

            local object
            if entry.skin then
                object = SkinnedMesh:new(geometry, material)

                local key = entry.skin
                if not skeletons[key] then
                    skeletons[key] = Skeleton:new(data.nodes, entry.skin)
                end
                object:bind(skeletons[key])

                object.skin            = entry.skin
                object.bindShapeMatrix = entry.bindShapeMatrix
            else
                object = Mesh:new(geometry, material)
            end

            object.name = entry.name or ""

            -- A skinned mesh's vertices already live in skeleton space, so its
            -- node transform must NOT be applied again -- doing so scales the
            -- model twice. Rigid meshes do need theirs.
            if not entry.skin and entry.transform then
                object.matrix:copy(entry.transform)
                object.matrix:decompose(object.position, object.quaternion, object.scale)
                object:_adoptQuaternion()
            end

            root:add(object)
        end
    end

    local animations = {}
    for i, clip in ipairs(data.animations or {}) do
        animations[i] = AnimationClip:fromImporter(clip, sampler, data.nodes)
    end

    return {
        scene      = root,
        animations = animations,
        -- the raw importer output, for anything the facade does not cover
        userData   = { importer = data },
    }
end

return Loader
