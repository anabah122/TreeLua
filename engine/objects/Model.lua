-- three/objects/Model.lua — the asset, loaded once, used by any number of
-- game objects
--
--   local model = Model:fromLoaderResult(TL.GLTFLoader:new():load(MODEL_PATH))
--   local enemy = model:createInstance()   -- cheap: no file I/O, no re-parse
--   scene:add(enemy.scene)
--   enemy.mixer:clipAction(enemy.animations[1]):play()
--   enemy.scene.position:set(x, 0, z)
--
-- A Model is not a game object (see TODO.md): geometry, material and the
-- joint hierarchy/inverse-bind matrices describe the asset once and never
-- change per spawn -- they are the STATIC half. Position/rotation/scale, the
-- current animation pose and which clip is playing belong to whichever game
-- object is using the model right now -- the DYNAMIC half, and there can be
-- any number of them live at once against one loaded Model.
--
-- createInstance() never clones geometry, materials or the source love.Mesh
-- objects -- those are read straight off the model's own Mesh/SkinnedMesh
-- instances by reference, same as three.js sharing BufferGeometry across
-- copies. What IS per instance is a fresh Object3D shell per primitive (so
-- each has its own matrixWorld to draw at) and, for skinned primitives, a
-- fresh Skeleton holding just the current pose -- joints/inverseBind still
-- point at the model's own skin data. That split is what makes N animated
-- instances of one model cheap: the file is parsed once, ever.

local Group       = require "engine.core.Group"
local Mesh        = require "engine.objects.Mesh"
local SkinnedMesh = require "engine.objects.SkinnedMesh"
local Skeleton    = require "engine.objects.Skeleton"
local AnimationMixer  = require "engine.animation.AnimationMixer"
local LOD             = require "engine.objects.LOD"
local SimplifyModifier = require "engine.modifiers.SimplifyModifier"

local Model = {}
Model.__index = Model

function Model:new(scene, animations, userData)
    return setmetatable({
        type       = "Model",
        scene      = scene,
        animations = animations or {},
        userData   = userData,
    }, Model)
end

function Model:isModel()
    return true
end

-- Wrap whatever a loader handed back: { scene, animations, userData }.
function Model:fromLoaderResult(result)
    return Model:new(result.scene, result.animations, result.userData)
end

-- One live, independently animatable use of this model: its own transform,
-- its own skeleton pose, its own AnimationMixer. Geometry/material/skin data
-- stay shared with the Model, so spawning many of these costs no extra file
-- I/O -- unlike reloading the whole asset per spawn.
function Model:createInstance()
    -- Skinned primitives in one file share one skeleton (see Loader:_assemble),
    -- so one clone covers however many skinned meshes the model has.
    local sharedSkeleton

    local root = Group:new()
    root.name = self.scene.name

    self.scene:traverse(function(src)
        if src == self.scene then return end

        local shell
        if src.isSkinnedMesh and src:isSkinnedMesh() then
            if not sharedSkeleton then
                sharedSkeleton = src.skeleton:clone()
            end
            shell = SkinnedMesh:new(src.geometry, src.material)
            shell:bind(sharedSkeleton, src.bindMatrix)
            shell.skin            = src.skin
            shell.bindShapeMatrix = src.bindShapeMatrix
        elseif src.isMesh and src:isMesh() then
            shell = Mesh:new(src.geometry, src.material)
        else
            shell = Group:new()
        end

        shell.name = src.name
        shell.position:copy(src.position)
        shell.quaternion:copy(src.quaternion)
        shell.scale:copy(src.scale)
        shell:_adoptQuaternion()

        local parentShell = src.parent == self.scene and root or src.parent._instanceShell
        src._instanceShell = shell
        parentShell:add(shell)
    end)

    self.scene:traverse(function(src) src._instanceShell = nil end)

    local animations = {}
    for i, clip in ipairs(self.animations) do
        animations[i] = sharedSkeleton and clip:withNodes(sharedSkeleton.nodes) or clip
    end

    return {
        scene      = root,
        animations = animations,
        mixer      = AnimationMixer:new(root),
    }
end

-- Generate LOD levels for every static Mesh in the model, in place, once.
-- Levels: 100% / 50% / 25% / 10% of triangle count, shown at opts.distances
-- (default {0, 15, 40, 80}). SkinnedMesh primitives are left untouched -- QEM
-- here doesn't account for skin weights -- and get a console warning per
-- occurrence.
--
--   model:autoLOD()                             -- default distances
--   model:autoLOD{ distances = {0, 20, 60, 120} }
--
-- Idempotent: a second call is a no-op once autoLODGenerated is set, so
-- calling this from spawn code repeatedly costs nothing after the first time.
function Model:autoLOD(opts)
    if self.autoLODGenerated then return self end
    opts = opts or {}
    local distances = opts.distances or {0, 15, 40, 80}
    local ratios     = {1, 0.5, 0.25, 0.1}

    -- collect first: traverse walks self.children live, so mutating the tree
    -- (remove/add) mid-traversal would skip or duplicate siblings
    local targets = {}
    self.scene:traverse(function(node)
        if node.isSkinnedMesh and node:isSkinnedMesh() then
            print("Model:autoLOD — skipping SkinnedMesh '" .. (node.name or "") .. "' (skinning not supported)")
        elseif node.isMesh and node:isMesh() then
            targets[#targets+1] = node
        end
    end)

    for _, node in ipairs(targets) do
        local lod = LOD:new()
        lod.name = node.name
        lod.position:copy(node.position)
        lod.quaternion:copy(node.quaternion)
        lod.scale:copy(node.scale)

        for i, ratio in ipairs(ratios) do
            local geo = ratio == 1 and node.geometry or SimplifyModifier.simplify(node.geometry, ratio)
            local levelMesh = Mesh:new(geo, node.material)
            lod:addLevel(levelMesh, distances[i])
        end

        local parent = node.parent
        parent:remove(node)
        parent:add(lod)
    end

    self.autoLODGenerated = true
    return self
end

return Model
