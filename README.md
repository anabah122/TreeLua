# TreeLua

Minimal 3D engine for LÖVE 11.5 — the parts three.js adds on top of a renderer,
without the renderer itself, since LÖVE already has one.

## What's here

- `math/` — vec3, vec4, mat4
- `class/camera.lua` — free-look camera
- `class/model.lua` — loaded model with animation playback
- `importer/gltf/` — glTF 2.0 / GLB: geometry, materials, skeleton, animation
- `importer/dae/` — Collada: same output shape, so both formats feed one path
- `importer/common.lua` — transforms, skinning palette, interpolation
- `assets/shader/skinned.glsl` — forward lighting with GPU skinning

## Running

    love .

WASD moves, QE goes up and down, the mouse looks around, the wheel changes
speed, space pauses playback.
