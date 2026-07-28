# TreeLua

Minimal 3D engine for LÖVE 11.5 — the parts three.js adds on top of a renderer,
without the renderer itself, since LÖVE already has one.

The public API follows [three.js](https://threejs.org/docs/), so its
documentation reads across. Two deliberate differences are listed under
[Differences from three.js](#differences-from-threejs).

## Quick start

```lua
local TL = require "TreeEngine"

local scene, camera, renderer, mixer

function love.load()
    local w, h = love.graphics.getDimensions()

    scene  = TL.Scene:new()
    scene:setBackground(0x171a21)

    camera = TL.PerspectiveCamera:new(60, w / h, 0.1, 1000)
    camera.position:set(0, 1.2, 3.5)

    renderer = TL.WebGLRenderer:new()

    local sun = TL.DirectionalLight:new(0xfff7eb, 1)
    sun.position:set(0.4, 1.0, 0.6)
    scene:add(sun)
    scene:add(TL.AmbientLight:new(0x474d5c, 1))

    local gltf = TL.GLTFLoader:new():load("assets/model/model3dtest.glb")
    scene:add(gltf.scene)

    mixer = TL.AnimationMixer:new(gltf.scene)
    mixer:clipAction(gltf.animations[1]):play()
end

function love.update(dt) mixer:update(dt) end
function love.draw()     renderer:render(scene, camera) end
```

Requiring the library defines no globals and installs no hooks.

## API

### Math
`Vector3` `Vector4` `Matrix4` `Quaternion` `Euler` `Color` `Box3` `Sphere`
`Plane` `Ray` `Frustum` `MathUtils`

### Core
`Object3D` `Group` `BufferGeometry` `Scene` `Raycaster`

Picking follows three.js, with one addition. `setFromCamera` takes normalised
device coordinates as it does there; `setFromScreen` is the facade over it for
the pixels `love.mousepressed` actually hands you:

```lua
function love.mousepressed(x, y)
    local caster = TL.Raycaster:new():setFromScreen(x, y, camera)
    local hit = caster:intersectObjects(scene.children, true)[1]
    if hit then print(hit.object.name, hit.distance) end
end
```

`Vector3:project(camera)` / `:unproject(camera)` convert between world space
and NDC through a camera's view-projection, as in three.js. `Camera` adds the
facade over LÖVE's actual pixels, since NDC ↔ screen by hand is a common
source of bugs (the Y flip in particular):

```lua
local sx, sy, visible = camera:worldToScreen(enemy.position)
local worldPoint = camera:screenToWorld(mx, my)
```

### Geometries
`BoxGeometry` `SphereGeometry` `PlaneGeometry` `CylinderGeometry` `ConeGeometry`
`TorusGeometry`

Generated primitives, so a scene can be built without loading a file:

```lua
local mesh = TL.Mesh:new(
    TL.BoxGeometry:new(1, 1, 1),
    TL.MeshStandardMaterial:new{ color = 0xff8800 })
```

`PlaneGeometry` lies in the XY plane facing +Z, as in three.js — a floor wants
`mesh:rotateX(-math.pi / 2)`.

### Objects
`Mesh` `SkinnedMesh` `Skeleton` `InstancedMesh` `LOD`

`LOD` needs no renderer support — it only toggles which child is visible, which
the renderer's traversal already respects. Call `lod:update(camera)` yourself,
next to `controls:update`, since this renderer does not walk the scene looking
for them:

```lua
local lod = TL.LOD:new()
lod:addLevel(highDetail, 0)
lod:addLevel(lowDetail, 25)
```

`InstancedMesh` keeps the three.js surface but is **not** one draw call — see
[Limitations](#limitations). Indices are 1-based, like everything else here.

### Model
`Model` — the asset, loaded once, instantiated any number of times. Not a
three.js class: it exists because a glTF file and a live game object are
different things, and loading the file per spawn is wasteful.

```lua
local model = TL.Model:fromLoaderResult(TL.GLTFLoader:new():load(MODEL_PATH))

local enemy = model:createInstance()   -- cheap: no file I/O, no re-parse
scene:add(enemy.scene)
enemy.mixer:clipAction(enemy.animations[1]):play()
enemy.scene.position:set(x, 0, z)
```

`Model:fromLoaderResult(result)` wraps a loader's `{ scene, animations }`.
`model:createInstance()` returns `{ scene, animations, mixer }`: a fresh
`Object3D` shell per primitive (its own transform/`matrixWorld`), a cloned
`Skeleton` holding just the current pose (joints/inverse-bind stay shared with
the model), and its own `AnimationMixer`. Geometry, materials and the
underlying `love.Mesh` objects are never cloned — every instance reads them by
reference, same as three.js sharing a `BufferGeometry` across copies. That
split is what makes N animated instances of one model cheap: the source file
is parsed exactly once.

### Materials
`Material` `MeshStandardMaterial`

Shading is metallic-roughness PBR — Cook-Torrance with a GGX distribution,
Smith geometry and Schlick Fresnel — so `metalness`, `roughness`, `emissive`,
`normalMap`, `aoMap` and glTF's packed metallic-roughness map all reach the
shader:

```lua
local m = TL.MeshStandardMaterial:new{ color = 0xc84a3a, metalness = 0, roughness = 0.35 }
m.emissive:set(0x220800)
```

A model with no metallic-roughness map is a matte dielectric: `metalness` 0,
`roughness` 1. Factors written alongside no map are ignored, because exporters
write them whether or not anyone authored PBR — Mixamo puts 0.5/0.5 on every
material it touches, which would otherwise make skin half metal. Both are
ordinary fields, so a loaded material can still be adjusted by hand.

Normal maps need no tangent attribute: the tangent basis is derived per
fragment from screen-space derivatives, so the vertex format stays as it is.

Two departures from strict PBR, both deliberate and both adjustable:

- **No environment probe.** Ambient light stands in for one: metals reflect it
  tinted by their own colour, dielectrics scatter it. Without this a metal
  under a single light renders nearly black — correct, and useless.
- **Wrapped diffuse.** `renderer.diffuseWrap` (default `0.25`) softens the
  terminator so unlit faces stay readable. Set it to `0` for strict falloff.

### Cameras
`Camera` `PerspectiveCamera` `OrthographicCamera`

### Lights
`Light` `AmbientLight` `DirectionalLight` `PointLight` `SpotLight`

`PointLight` and `SpotLight` sit in the graph and carry their three.js fields,
but the bundled shader takes one directional light plus ambient, so they are
not yet sampled — they are there so scene code written against three.js loads.

### Renderer
`WebGLRenderer` — `render(scene, camera)`, `setClearColor`, `setSize`, `info.render`

Drawing is batched into two buckets by shader variant, filled during the single
scene traversal: static meshes first, then skinned, so each program binds once
per frame. Within a bucket, draws are ordered by `renderOrder`, then opaque
before transparent, then by distance — near-to-far for opaque, so the depth test
rejects occluded fragments early, and far-to-near for transparent, where
blending demands it.

Frustum culling happens in that same traversal, against each geometry's bounding
sphere. Skinned meshes are exempt: their bounds describe the bind pose, and an
animation routinely swings limbs outside it. Turn it off with
`renderer.frustumCulling = false`; `info.render.culled` reports what it dropped.

### Loaders
`GLTFLoader` `ColladaLoader` `TextureLoader` — `load(url, onLoad, onProgress,
onError)`. The model loaders return `{ scene, animations }`. LÖVE reads from
disk synchronously, so the callback fires immediately; the return value works
just as well.

### Animation
`AnimationClip` `AnimationAction` `AnimationMixer`

Every running action is blended by weight, so `crossFadeTo` is a real
transition:

```lua
walk:play()
run:play()
walk:crossFadeTo(run, 0.4)
```

Set `mixer.blending = false` for the cheaper path, where the highest-weight
action writes the pose outright.

### Controls
`FlyControls` — WASD/QE movement, mouse look, wheel to change speed.

`OrbitControls` — left drag orbits, right drag pans, wheel dollies. Unlike
three.js there is no DOM element to attach to, so the application forwards
LÖVE's callbacks:

```lua
function love.update(dt)             controls:update(dt) end
function love.mousemoved(x,y,dx,dy)  controls:mousemoved(x, y, dx, dy) end
function love.wheelmoved(x,y)        controls:wheelmoved(y) end
```

It owns the camera's position, deriving it from `target` plus a spherical
offset every update — move `target`, not `camera.position`.

## Differences from three.js

**Methods use `:`.** Every method takes the object as its first argument, so
three.js statics are methods here: `clip:findByName(clips, name)`.

**Mutating methods that collide with older names carry a suffix.** The engine's
`Vector3:add` predates the facade and returns a new vector; three.js `add`
mutates. Where both had to coexist the three.js one is suffixed:

| three.js | here |
|---|---|
| `Vector3.add` / `.sub` | `addSelf` / `subSelf` |
| `Vector3.normalize` | `normalizeSelf` |
| `Vector3.lerp` | `lerpSelf` |
| `Vector3.min` / `.max` | `minSelf` / `maxSelf` |
| `Vector3.clamp` | `clampSelf` |
| `Vector3.floor` / `.ceil` / `.round` | `floorSelf` / `ceilSelf` / `roundSelf` |
| `Matrix4.transpose` | `transposeSelf` |

Everything else — `set`, `copy`, `multiplyScalar`, `applyQuaternion`,
`addScaledVector`, `crossVectors` and the rest — keeps its three.js spelling and
its mutating three.js behaviour.

## Limitations

- The bundled shader takes **one** directional light plus an ambient term. A
  scene with more gets the brightest directional and the sum of the ambients,
  and says so rather than silently dropping the rest. `PointLight` and
  `SpotLight` are not sampled at all yet.
- `InstancedMesh` is not one draw call. The shader takes a single `u_model`, so
  the renderer walks the instances and issues one draw each — the saving is in
  the shared geometry, material and bounds. The API is three.js's, so this
  changes underneath without touching calling code.
- No environment map or IBL probe, so reflections have nothing to reflect —
  see the ambient substitute described under Materials.
- The derived tangent basis is exact wherever UVs are locally affine, which is
  nearly everywhere that is not a deliberately warped unwrap.
- `Raycaster` tests skinned meshes against their **bind pose**: the vertex data
  it reads is what the GPU deforms, not the result. A moving character picks
  roughly.
- The primitive generators assume a shape convex about the origin: triangles
  are wound outward by comparing each one against its centroid, in one place,
  rather than by hand per face. `TorusGeometry` opts out, being the one
  primitive with a genuine inner wall. Partial sweeps (`thetaLength` short of a
  full turn) fall outside that assumption and may come out inside-out; give
  them `side = "double"` if it shows.
- No `Texture` class — LÖVE's `Image` already carries the filter and wrap state
  three.js keeps on one.
- Skeletons are capped at 128 bones, matching `MAX_BONES` in the shader.

## Layout

| Path | |
|---|---|
| `init.lua` | the public API; everything below is reached through it |
| `three/` | the facade: core, objects, materials, cameras, lights, renderers, loaders, animation, controls |
| `math/` | vec3, vec4, mat4, quat, euler, color, box3, sphere, plane, ray, frustum |
| `shader/init.lua` | assembles shader variants from parts |
| `shader/parts/` | one file per feature: skinning, normalmap, pbr |
| `importer/gltf/` | glTF 2.0 / GLB: geometry, materials, skeleton, animation |
| `importer/dae/` | Collada: same output shape, so both formats feed one path |
| `importer/common.lua` | transforms, skinning palette, interpolation |
| `three/objects/Model.lua` | one loaded asset, instantiated cheaply any number of times |
| `class/` | legacy, superseded by the facade — see the note at the top of each |
| `lib/util/` | demo scaffolding only; installs globals, not used by the library |
| `game_test/` | a small game built on the engine as a plain library, used to exercise it end to end — not part of the engine itself |

## Shaders

LÖVE builds a shader from a string, so a variant is a different concatenation.
Each part in `shader/parts/` supplies GLSL grouped by the slot it fills, and
`shader/init.lua` holds the only copy of the overall shape.

Parts are split by **feature**, not by stage: skinning lives in exactly one
file, covering both its vertex uniforms and its vertex maths. Cutting by stage
instead would scatter every feature across several files and make each edit a
hunt.

There are two compiled variants, `static` and `skinned`. The split is not
cosmetic — a 128-bone array is 2048 vertex uniform components, against a
guaranteed floor of 1024, so a static mesh must not declare it.

## Tests

    lovec . --tests

256 assertions covering the maths, the object graph, the generators, library
hygiene, and the loaders/animation/renderer against a real graphics context.

## Running the test game

    love .

`main.lua` delegates entirely to `game_test/`, a small top-down shooter built
on TreeEngine used strictly as a library — no engine file is touched to make
it work, so it doubles as an integration check. It is not part of the engine
and not the place to look for API examples beyond what's already inlined
above; read `game_test/init.lua` if you want to see a full scene assembled.
