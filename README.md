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

    local gltf = TL.GLTFLoader:new():load("assets/model/hero.glb")
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
`Vector3` `Vector4` `Matrix4` `Quaternion` `Euler` `Color` `Box3` `MathUtils`

### Core
`Object3D` `Group` `BufferGeometry` `Scene`

### Geometries
`BoxGeometry` `SphereGeometry` `PlaneGeometry` `CylinderGeometry` `ConeGeometry`

Generated primitives, so a scene can be built without loading a file:

```lua
local mesh = TL.Mesh:new(
    TL.BoxGeometry:new(1, 1, 1),
    TL.MeshStandardMaterial:new{ color = 0xff8800 })
```

`PlaneGeometry` lies in the XY plane facing +Z, as in three.js — a floor wants
`mesh:rotateX(-math.pi / 2)`.

### Objects
`Mesh` `SkinnedMesh` `Skeleton`

### Materials
`Material` `MeshStandardMaterial`

Shading is metallic-roughness PBR — Cook-Torrance with a GGX distribution,
Smith geometry and Schlick Fresnel — so `metalness`, `roughness`, `emissive`
and glTF's packed metallic-roughness map all reach the shader:

```lua
local m = TL.MeshStandardMaterial:new{ color = 0xc84a3a, metalness = 0, roughness = 0.35 }
m.emissive:set(0x220800)
```

Two departures from strict PBR, both deliberate and both adjustable:

- **No environment probe.** Ambient light stands in for one: metals reflect it
  tinted by their own colour, dielectrics scatter it. Without this a metal
  under a single light renders nearly black — correct, and useless.
- **Wrapped diffuse.** `renderer.diffuseWrap` (default `0.25`) softens the
  terminator so unlit faces stay readable. Set it to `0` for strict falloff.

### Cameras
`Camera` `PerspectiveCamera` `OrthographicCamera`

### Lights
`Light` `AmbientLight` `DirectionalLight`

### Renderer
`WebGLRenderer` — `render(scene, camera)`, `setClearColor`, `setSize`, `info.render`

### Loaders
`GLTFLoader` `ColladaLoader` — `load(url, onLoad, onProgress, onError)` returns
`{ scene, animations }`. LÖVE reads from disk synchronously, so the callback
fires immediately; the return value works just as well.

### Animation
`AnimationClip` `AnimationAction` `AnimationMixer`

### Controls
`FlyControls` — WASD/QE movement, mouse look, wheel to change speed.

## Differences from three.js

**Methods use `:`.** Every method takes the object as its first argument, so
three.js statics are methods here: `clip:findByName(clips, name)`.

**Mutating methods that collide with older names carry a suffix.** The engine's
`Vector3:add` predates the facade and returns a new vector; three.js `add`
mutates. Where both had to coexist the three.js one is suffixed:

| three.js | here |
|---|---|
| `Vector3.add` / `.sub` | `addV` / `subV` |
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

- The bundled shader takes **one** directional light plus an ambient term.
- `AnimationMixer` samples the highest-weight running action rather than
  blending several. `crossFadeTo` ramps weights, so the switch lands at the
  crossover point, but it is a cut and not a blend.
- No environment map or IBL probe, so reflections have nothing to reflect —
  see the ambient substitute described under Materials.
- `normalMap` and the occlusion map are imported but not yet sampled; that
  needs tangents, which the vertex format does not carry.
- glTF defaults `metallicFactor` to 1. A file that leaves it at exactly 1 with
  no metallic-roughness map is read as never having authored PBR and treated as
  a dielectric — otherwise every such model turns to chrome. An explicit value,
  or a 1 alongside a map, is taken at face value.
- The primitive generators assume a shape convex about the origin: triangles
  are wound outward by comparing each one against its centroid, in one place,
  rather than by hand per face. Partial sweeps (`thetaLength` short of a full
  turn) fall outside that assumption and may come out inside-out; give them
  `side = "double"` if it shows.
- No `Raycaster`, `Frustum`, `TextureLoader`, `PointLight`/`SpotLight`,
  `InstancedMesh`, `LOD`, `TorusGeometry` or `OrbitControls`.
- Skeletons are capped at 128 bones, matching `MAX_BONES` in the shader.

## Layout

| Path | |
|---|---|
| `init.lua` | the public API; everything below is reached through it |
| `three/` | the facade: core, objects, materials, cameras, lights, renderers, loaders, animation, controls |
| `math/` | vec3, vec4, mat4, quat, euler, color |
| `importer/gltf/` | glTF 2.0 / GLB: geometry, materials, skeleton, animation |
| `importer/dae/` | Collada: same output shape, so both formats feed one path |
| `importer/common.lua` | transforms, skinning palette, interpolation |
| `assets/shader/skinned.glsl` | forward lighting with GPU skinning |
| `class/` | legacy, superseded by the facade — see the note at the top of each |
| `lib/util/` | demo scaffolding only; installs globals, not used by the library |

## Running the demo

    love .

WASD moves, QE goes up and down, the mouse looks around, the wheel changes
speed, space pauses playback. The same character is loaded twice, through both
importers, to show they produce the same result.
