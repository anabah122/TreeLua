-- TreeLua — the public API
--
--   local TL = require "TreeEngine"        -- or require "." from inside
--
--   local scene    = TL.Scene:new()
--   local camera   = TL.PerspectiveCamera:new(60, w / h, 0.1, 1000)
--   local renderer = TL.WebGLRenderer:new()
--
--   local gltf = TL.GLTFLoader:new():load("assets/model/model3dtest.glb")
--   scene:add(gltf.scene)
--
--   local mixer = TL.AnimationMixer:new(gltf.scene)
--   mixer:clipAction(gltf.animations[1]):play()
--
--   function love.update(dt) mixer:update(dt) end
--   function love.draw()     renderer:render(scene, camera) end
--
-- Names and call signatures follow three.js, so its documentation reads across
-- with two deliberate exceptions:
--
--   * Methods are called with ':' and take the object as the first argument.
--     three.js statics (AnimationClip.findByName) are methods here.
--   * Where a three.js name was already taken by an older immutable method,
--     the mutating version carries a suffix: addSelf, subSelf, normalizeSelf,
--     lerpSelf, minSelf/maxSelf, clampSelf, floorSelf/ceilSelf/roundSelf,
--     transposeSelf. Everything else keeps its three.js spelling.
--
-- Requiring this module defines no globals.

local TL = {}

TL.VERSION = "0.1.0"

-- ── settings ─────────────────────────────────────────────────────────────────
TL.settings = require "three.settings"

-- ── math ─────────────────────────────────────────────────────────────────────
TL.Vector3    = require "math.vec3"
TL.Vector4    = require "math.vec4"
TL.Matrix4    = require "math.mat4"
TL.Quaternion = require "math.quat"
TL.Euler      = require "math.euler"
TL.Color      = require "math.color"
TL.Box3       = require "math.box3"
TL.Sphere     = require "math.sphere"
TL.Plane      = require "math.plane"
TL.Ray        = require "math.ray"
TL.Frustum    = require "math.frustum"

-- ── core ─────────────────────────────────────────────────────────────────────
TL.Object3D       = require "three.core.Object3D"
TL.Group          = require "three.core.Group"
TL.BufferGeometry = require "three.core.BufferGeometry"
TL.LineGeometry   = require "three.core.LineGeometry"
TL.Raycaster      = require "three.core.Raycaster"

-- ── scene ────────────────────────────────────────────────────────────────────
TL.Scene   = require "three.scenes.Scene"
TL.Fog     = require "three.scenes.Fog"
TL.FogExp2 = require "three.scenes.FogExp2"

-- ── objects ──────────────────────────────────────────────────────────────────
TL.Mesh          = require "three.objects.Mesh"
TL.SkinnedMesh   = require "three.objects.SkinnedMesh"
TL.Skeleton      = require "three.objects.Skeleton"
TL.InstancedMesh = require "three.objects.InstancedMesh"
TL.LOD           = require "three.objects.LOD"
TL.Model         = require "three.objects.Model"
TL.Sprite        = require "three.objects.Sprite"
TL.Line          = require "three.objects.Line"
TL.LineSegments  = require "three.objects.LineSegments"

-- ── geometries ───────────────────────────────────────────────────────────────
-- Generated primitives, so a scene can be built without loading a file.
TL.BoxGeometry      = require "three.geometries.BoxGeometry"
TL.SphereGeometry   = require "three.geometries.SphereGeometry"
TL.PlaneGeometry    = require "three.geometries.PlaneGeometry"
TL.CylinderGeometry = require "three.geometries.CylinderGeometry"
TL.ConeGeometry     = require "three.geometries.ConeGeometry"
TL.TorusGeometry    = require "three.geometries.TorusGeometry"

-- ── materials ────────────────────────────────────────────────────────────────
TL.Material             = require "three.materials.Material"
TL.MeshStandardMaterial = require "three.materials.MeshStandardMaterial"
TL.LineBasicMaterial    = require "three.materials.LineBasicMaterial"

-- ── cameras ──────────────────────────────────────────────────────────────────
TL.Camera            = require "three.cameras.Camera"
TL.PerspectiveCamera = require "three.cameras.PerspectiveCamera"
TL.OrthographicCamera = require "three.cameras.OrthographicCamera"

-- ── lights ───────────────────────────────────────────────────────────────────
TL.Light            = require "three.lights.Light"
TL.AmbientLight     = require "three.lights.AmbientLight"
TL.DirectionalLight = require "three.lights.DirectionalLight"
TL.HemisphereLight  = require "three.lights.HemisphereLight"
TL.PointLight       = require "three.lights.PointLight"
TL.SpotLight        = require "three.lights.SpotLight"

-- ── renderers ────────────────────────────────────────────────────────────────
TL.WebGLRenderer = require "three.renderers.WebGLRenderer"

-- ── loaders ──────────────────────────────────────────────────────────────────
TL.Loader        = require "three.loaders.Loader"
TL.GLTFLoader    = require "three.loaders.GLTFLoader"
TL.ColladaLoader = require "three.loaders.ColladaLoader"
TL.TextureLoader = require "three.loaders.TextureLoader"

-- ── animation ────────────────────────────────────────────────────────────────
TL.AnimationClip   = require "three.animation.AnimationClip"
TL.AnimationAction = require "three.animation.AnimationAction"
TL.AnimationMixer  = require "three.animation.AnimationMixer"
TL.PoseAccumulator = require "three.animation.PoseAccumulator"

-- ── controls ─────────────────────────────────────────────────────────────────
TL.FlyControls   = require "three.controls.FlyControls"
TL.OrbitControls = require "three.controls.OrbitControls"

-- ── constants ────────────────────────────────────────────────────────────────
TL.FrontSide  = "front"
TL.BackSide   = "back"
TL.DoubleSide = "double"

TL.LoopOnce     = "once"
TL.LoopRepeat   = "repeat"
TL.LoopPingPong = "pingpong"

-- Degrees/radians helpers, three.js's MathUtils.
TL.MathUtils = {
    degToRad = function(_, d) return d * math.pi / 180 end,
    radToDeg = function(_, r) return r * 180 / math.pi end,
    clamp    = function(_, v, lo, hi) return math.min(math.max(v, lo), hi) end,
    lerp     = function(_, a, b, t) return a + (b - a) * t end,
}

-- ── internals ────────────────────────────────────────────────────────────────
-- The blackboxes underneath, exposed for anything the facade does not cover.
-- Their shapes are not part of the stable API.
TL.internal = {
    importer = {
        common = require "importer.common",
        gltf   = require "importer.gltf",
        dae    = require "importer.dae",
        obj    = require "importer.obj",
    },
}

return TL
