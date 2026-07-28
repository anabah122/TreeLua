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

local Group       = require "three.core.Group"
local Mesh        = require "three.objects.Mesh"
local SkinnedMesh = require "three.objects.SkinnedMesh"
local Skeleton    = require "three.objects.Skeleton"
local AnimationMixer = require "three.animation.AnimationMixer"

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

return Model
