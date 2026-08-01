-- three/particles/ParticleSystem.lua — GPU-simulated billboard particles
--
--   local fire = ParticleSystem:new{
--       count      = 2000,
--       lifetime   = 2,
--       spawnShape = "cone",
--       coneAngle  = 0.3,
--       direction  = Vector3:new(0, 1, 0),
--       speed      = { 1, 3 },
--       gravity    = Vector3:new(0, -1, 0),
--       size       = { 0.4, 0.0 },
--       color      = { Color:new(0xffcc66), Color:new(0xff2200) },
--       opacity    = { 1, 0 },
--       shape          = "box",  -- optional: "billboard" (default), "box", "sphere"
--       rotationSpeed  = 2,      -- radians/second: 2D spin for billboards, 3D tumble for meshes
--   }
--   scene:add(fire)
--
-- `shape` swaps the per-particle geometry from the default camera-facing
-- billboard quad to an actual 3D primitive (box/sphere), still driven by the
-- same GPU simulation -- mesh particles ride the emitter's model matrix in
-- full 3D and tumble around their own seed-derived axis instead of spinning
-- flat toward the camera. Both are unlit: mesh particles get no PBR shading,
-- just the same lifetime colour gradient, since it is the same shader.
--
-- By default an emitter is continuous: particles trickle in and out forever,
-- each on its own clock (staggered by its seed). Set `burst = true` for a
-- system with a visible start and end instead -- a spell effect, an
-- explosion -- where the whole set is synchronized to one repeating cycle
-- (see cycleDuration/riseFraction/sustainFraction/decayFraction below).
--
-- No per-particle CPU state and no update() call: shader/particles.lua derives
-- every particle's position/size/color from (seed, u_time, these emitter
-- params) each frame, so `count` is the only thing that costs anything ahead
-- of time -- it sizes the one-time instance buffer of seeds, drawn with a
-- single love.graphics.drawInstanced call (see WebGLRenderer:_drawParticles).
--
-- Position/rotation/scale come from the object's own transform (u_model), same
-- as any Mesh -- moving the emitter moves the whole system, spawn point and
-- all, since the simulation runs in the emitter's local space.

local Object3D = require "three.core.Object3D"
local Color    = require "math.color"

local ParticleSystem = Object3D:extend("ParticleSystem")

local SPAWN_SHAPES = { point = 0, sphere = 1, cone = 2 }

-- Unit quad in local particle space; the shader expands it along the camera's
-- right/up per-instance, so this is the only per-vertex data every particle
-- shares (position.xy in [-0.5, 0.5], corner offset before size/billboarding).
local QUAD_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
}
local QUAD_VERTICES = {
    { -0.5, -0.5, 0, 0, 0 },
    {  0.5, -0.5, 0, 1, 0 },
    {  0.5,  0.5, 0, 1, 1 },
    { -0.5,  0.5, 0, 0, 1 },
}
local QUAD_INDICES = { 1, 2, 3, 1, 3, 4 }

local INSTANCE_FORMAT = {
    { "a_seed", "float", 1 },
}

-- Builds the per-particle geometry for `shape`: the default camera-facing
-- quad, or a real 3D primitive's position-only vertices (uv/normal from
-- BoxGeometry/SphereGeometry are dropped -- the shader is unlit and only
-- reads vertex_position). Reuses the generators' vertex/index tables rather
-- than the love.Mesh they build, since QUAD_FORMAT has no normal attribute.
local function buildShapeMesh(shape)
    if shape == "billboard" or shape == nil then
        local mesh = love.graphics.newMesh(QUAD_FORMAT, QUAD_VERTICES, "triangles", "static")
        mesh:setVertexMap(QUAD_INDICES)
        return mesh
    end

    local geo
    if shape == "box" then
        geo = require("three.geometries.BoxGeometry"):new(1, 1, 1)
    elseif shape == "sphere" then
        geo = require("three.geometries.SphereGeometry"):new(0.5, 12, 8)
    else
        error("ParticleSystem: unknown shape '" .. tostring(shape) .. "'")
    end

    local verts = {}
    for i, v in ipairs(geo.vertices) do
        verts[i] = { v[1], v[2], v[3], 0, 0 }   -- position only, uv unused by shader
    end

    local mesh = love.graphics.newMesh(QUAD_FORMAT, verts, "triangles", "static")
    mesh:setVertexMap(geo.indices)
    return mesh
end

function ParticleSystem:new(params)
    params = params or {}

    local p = Object3D.new(self)
    p.type = "ParticleSystem"

    p.count      = params.count or 1000
    p.lifetime   = params.lifetime or 2
    p.visible    = params.visible ~= false

    -- Burst mode: the whole system shares one start/end cycle (see
    -- shader/particles.lua) instead of particles trickling continuously --
    -- cycleDuration is the repeat period; leave it >= lifetime or particles
    -- get cut off before finishing their own fade.
    --
    -- rise/sustain/decay split the cycle into three phases, as fractions of
    -- cycleDuration (they need not sum to 1 -- anything left over is silence
    -- before the cycle repeats). During rise, particles appear one by one in
    -- seed order; during sustain, all are alive; during decay, they vanish
    -- one by one, same order they appeared in, so the population is a full
    -- lifecycle rather than a single alpha fade over everything at once --
    -- e.g. Skyrim-style spell sparks that build up, hold, then die out.
    p.burst = params.burst or false
    p.cycleDuration    = params.cycleDuration or p.lifetime
    p.riseFraction     = params.riseFraction or 0.15
    p.sustainFraction  = params.sustainFraction or 0.6
    p.decayFraction    = params.decayFraction or 0.25

    p.spawnShape  = SPAWN_SHAPES[params.spawnShape or "point"] or 0
    p.spawnRadius = params.spawnRadius or 1
    p.coneAngle   = params.coneAngle or 0.4

    p.direction = params.direction and params.direction:clone()
                  or require("math.vec3"):new(0, 1, 0)

    local speed = params.speed or { 1, 1 }
    p.speedMin, p.speedMax = speed[1], speed[2] or speed[1]

    p.gravity = params.gravity and params.gravity:clone()
                or require("math.vec3"):new(0, 0, 0)

    local size = params.size or { 1, 1 }
    p.sizeStart, p.sizeEnd = size[1], size[2] or size[1]

    local color = params.color or { Color:new(0xffffff), Color:new(0xffffff) }
    p.colorStart = color[1]:clone()
    p.colorEnd   = (color[2] or color[1]):clone()

    local opacity = params.opacity or { 1, 1 }
    p.opacityStart, p.opacityEnd = opacity[1], opacity[2] or opacity[1]

    p.map = params.map or nil

    p.shape         = params.shape or "billboard"
    p.rotationSpeed = params.rotationSpeed or 0

    p._mesh = buildShapeMesh(p.shape)

    p:setCount(p.count)

    return p
end

function ParticleSystem:isParticleSystem()
    return true
end

-- Rebuilds the instance buffer of seeds. Cheap and one-shot: called from
-- :new and whenever the caller changes `count`, never per frame.
function ParticleSystem:setCount(count)
    self.count = count

    local seeds = {}
    for i = 1, count do
        seeds[i] = { i * 1.61803398875 }   -- golden-ratio spacing decorrelates hash11 between neighbours
    end

    self._instanceMesh = love.graphics.newMesh(INSTANCE_FORMAT, seeds, nil, "static")
    self._mesh:attachAttribute("a_seed", self._instanceMesh, "perinstance")

    return self
end

function ParticleSystem:copy(source, recursive)
    Object3D.copy(self, source, recursive)

    self.count       = source.count
    self.lifetime     = source.lifetime
    self.burst         = source.burst
    self.cycleDuration = source.cycleDuration
    self.riseFraction    = source.riseFraction
    self.sustainFraction = source.sustainFraction
    self.decayFraction   = source.decayFraction
    self.spawnShape   = source.spawnShape
    self.spawnRadius  = source.spawnRadius
    self.coneAngle    = source.coneAngle
    self.direction    = source.direction:clone()
    self.speedMin     = source.speedMin
    self.speedMax     = source.speedMax
    self.gravity      = source.gravity:clone()
    self.sizeStart    = source.sizeStart
    self.sizeEnd      = source.sizeEnd
    self.colorStart   = source.colorStart:clone()
    self.colorEnd     = source.colorEnd:clone()
    self.opacityStart = source.opacityStart
    self.opacityEnd   = source.opacityEnd
    self.map          = source.map
    self.shape         = source.shape
    self.rotationSpeed = source.rotationSpeed

    self._mesh = buildShapeMesh(self.shape)
    self:setCount(self.count)

    return self
end

function ParticleSystem:dispose()
    self._mesh = nil
    self._instanceMesh = nil
    return self
end

return ParticleSystem
