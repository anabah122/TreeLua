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
TL.settings = require "engine.core.settings"

-- ── math ─────────────────────────────────────────────────────────────────────
TL.Vector3    = require "engine.math.vec3"
TL.Vector4    = require "engine.math.vec4"
TL.Matrix4    = require "engine.math.mat4"
TL.Quaternion = require "engine.math.quat"
TL.Euler      = require "engine.math.euler"
TL.Color      = require "engine.math.color"
TL.Box3       = require "engine.math.box3"
TL.Sphere     = require "engine.math.sphere"
TL.Plane      = require "engine.math.plane"
TL.Ray        = require "engine.math.ray"
TL.Frustum    = require "engine.math.frustum"
TL.Capsule    = require "engine.math.capsule"

-- ── core ─────────────────────────────────────────────────────────────────────
TL.Object3D       = require "engine.core.Object3D"
TL.Group          = require "engine.core.Group"
TL.BufferGeometry = require "engine.core.BufferGeometry"
TL.LineGeometry   = require "engine.core.LineGeometry"
TL.Raycaster      = require "engine.core.Raycaster"

-- ── scene ────────────────────────────────────────────────────────────────────
TL.Scene   = require "engine.scenes.Scene"
TL.Fog     = require "engine.scenes.Fog"
TL.FogExp2 = require "engine.scenes.FogExp2"

-- ── objects ──────────────────────────────────────────────────────────────────
TL.Mesh          = require "engine.objects.Mesh"
TL.SkinnedMesh   = require "engine.objects.SkinnedMesh"
TL.Skeleton      = require "engine.objects.Skeleton"
TL.InstancedMesh = require "engine.objects.InstancedMesh"
TL.LOD           = require "engine.objects.LOD"
TL.Model         = require "engine.objects.Model"
TL.Sprite        = require "engine.objects.Sprite"
TL.Line          = require "engine.objects.Line"
TL.LineSegments  = require "engine.objects.LineSegments"
TL.ParticleSystem = require "engine.particles.ParticleSystem"

-- ── geometries ───────────────────────────────────────────────────────────────
-- Generated primitives, so a scene can be built without loading a file.
TL.BoxGeometry      = require "engine.geometries.BoxGeometry"
TL.SphereGeometry   = require "engine.geometries.SphereGeometry"
TL.PlaneGeometry    = require "engine.geometries.PlaneGeometry"
TL.CylinderGeometry = require "engine.geometries.CylinderGeometry"
TL.ConeGeometry     = require "engine.geometries.ConeGeometry"
TL.TorusGeometry    = require "engine.geometries.TorusGeometry"

-- ── materials ────────────────────────────────────────────────────────────────
TL.Material             = require "engine.materials.Material"
TL.MeshStandardMaterial = require "engine.materials.MeshStandardMaterial"
TL.LineBasicMaterial    = require "engine.materials.LineBasicMaterial"

-- ── cameras ──────────────────────────────────────────────────────────────────
TL.Camera            = require "engine.cameras.Camera"
TL.PerspectiveCamera = require "engine.cameras.PerspectiveCamera"
TL.OrthographicCamera = require "engine.cameras.OrthographicCamera"

-- ── lights ───────────────────────────────────────────────────────────────────
TL.Light            = require "engine.lights.Light"
TL.AmbientLight     = require "engine.lights.AmbientLight"
TL.DirectionalLight = require "engine.lights.DirectionalLight"
TL.HemisphereLight  = require "engine.lights.HemisphereLight"
TL.PointLight       = require "engine.lights.PointLight"
TL.SpotLight        = require "engine.lights.SpotLight"

-- ── renderers ────────────────────────────────────────────────────────────────
TL.WebGLRenderer = require "engine.renderers.WebGLRenderer"

-- ── postprocessing ───────────────────────────────────────────────────────────
TL.EffectComposer = require "engine.postprocessing.EffectComposer"
TL.RenderPass      = require "engine.postprocessing.RenderPass"
TL.BloomPass       = require "engine.postprocessing.BloomPass"

-- ── loaders ──────────────────────────────────────────────────────────────────
TL.Loader        = require "engine.loaders.Loader"
TL.GLTFLoader    = require "engine.loaders.GLTFLoader"
TL.ColladaLoader = require "engine.loaders.ColladaLoader"
TL.TextureLoader = require "engine.loaders.TextureLoader"

-- ── animation ────────────────────────────────────────────────────────────────
TL.AnimationClip   = require "engine.animation.AnimationClip"
TL.AnimationAction = require "engine.animation.AnimationAction"
TL.AnimationMixer  = require "engine.animation.AnimationMixer"
TL.PoseAccumulator = require "engine.animation.PoseAccumulator"

-- ── controls ─────────────────────────────────────────────────────────────────
TL.FlyControls   = require "engine.controls.FlyControls"
TL.OrbitControls = require "engine.controls.OrbitControls"

-- ── collision ────────────────────────────────────────────────────────────────
TL.CollisionWorld = require "engine.collision.World"
TL.FlatBroadphase = require "engine.collision.FlatBroadphase"
TL.Octree         = require "engine.collision.Octree"
TL.MeshCollider   = require "engine.collision.MeshCollider"
TL.Heightfield    = require "engine.collision.Heightfield"
TL.Triangle       = require "engine.math.triangle"

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
        common = require "engine.importer.common",
        gltf   = require "engine.importer.gltf",
        dae    = require "engine.importer.dae",
        obj    = require "engine.importer.obj",
    },
}

return TL
