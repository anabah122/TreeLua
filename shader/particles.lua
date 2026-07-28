-- shader/particles.lua — GPU-simulated billboard particles
--
-- Not assembled from shader/init.lua's part system: particles are unlit
-- billboards, not a lit surface, so none of pbr/shadow/normalmap applies.
--
-- The simulation itself lives entirely in the vertex stage as a closed-form
-- function of time -- there is no per-particle CPU update and no ping-pong
-- state texture (LÖVE has no compute shaders to drive one). Each particle is
-- one instance carrying a single per-instance attribute, a_seed, and its
-- position/age/size/color at any time t are all pure functions of
-- (a_seed, u_time, the emitter uniforms below). Rewinding or fast-forwarding
-- u_time re-derives the whole system with no accumulated error.
--
-- Per-particle randomness comes from hashing a_seed (an ever-incrementing
-- instance index) rather than storing random numbers: a GLSL hash of an int
-- is deterministic and free, so every particle gets a stable-but-varied
-- direction/speed/lifetime offset without a texture lookup.

local function source()
    return table.concat({
        "uniform mat4  u_viewProj;",
        "uniform mat4  u_model;",
        "uniform vec3  u_cameraRight;",
        "uniform vec3  u_cameraUp;",
        "",
        "uniform float u_time;",          -- seconds, wraps particles via mod(t, lifetime)
        "uniform float u_lifetime;",      -- seconds a particle lives before recycling
        "uniform float u_emitRate;",      -- particles/second, only used to size the mesh CPU-side
        "",
        -- Burst mode: the whole system shares one cycle instead of each
        -- particle wrapping on its own offset -- every particle spawns at
        -- cycle start and is dead by cycle end, so the emitter reads as
        -- "born, plays out, gone" rather than a steady continuous stream.
        -- The cycle itself still repeats forever, just with nothing shown
        -- between repeats once particles have faded -- looping 0..1 is the
        -- caller's job (see u_time), not a one-shot flag here.
        "uniform bool  u_burst;",
        "uniform float u_cycleDuration;",  -- seconds per repeat, only read when u_burst
        "",
        -- Envelope over the burst cycle, as fractions of u_cycleDuration that
        -- sum to <= 1: rise, sustain, decay. Not an alpha fade -- it gates
        -- which particles exist at all, ordered by seed, so a Skyrim-style
        -- spell burst visibly gains sparks during rise, holds a full spread
        -- during sustain, and loses them one by one during decay rather than
        -- the whole cloud dimming together.
        "uniform float u_riseFraction;",
        "uniform float u_sustainFraction;",
        "uniform float u_decayFraction;",
        "",
        "uniform int   u_spawnShape;",    -- 0 = point, 1 = sphere, 2 = cone
        "uniform float u_spawnRadius;",
        "uniform float u_coneAngle;",     -- radians, half-angle for u_spawnShape == 2
        "",
        "uniform float u_speedMin;",
        "uniform float u_speedMax;",
        "uniform vec3  u_direction;",     -- base emit direction (cone axis / sphere bias)
        "uniform vec3  u_gravity;",
        "",
        "uniform float u_sizeStart;",
        "uniform float u_sizeEnd;",
        "",
        "uniform vec4  u_colorStart;",
        "uniform vec4  u_colorEnd;",
        "",
        -- Rotation: billboard particles spin the quad in screen space (a
        -- single angle, since a billboard has no meaningful 3rd axis); mesh
        -- particles (u_isMesh) tumble in local space around a per-particle
        -- axis derived from their own seed, so a field of rotating boxes
        -- doesn't all spin around the same axis in lockstep.
        "uniform bool  u_isMesh;",
        "uniform float u_rotationSpeed;",  -- radians/second
        "",
        "varying vec4 v_color;",
        "",
        "#ifdef VERTEX",
        "attribute float a_seed;",
        "",
        -- three cheap hashes of the same seed, decorrelated by an additive
        -- offset each -- good enough for emitter spread, not for anything
        -- that needs real statistical quality
        "float hash11(float x) { return fract(sin(x * 127.1) * 43758.5453); }",
        "",
        "vec3 randomInSphere(float seed, float radius)",
        "{",
        "    float u = hash11(seed);",
        "    float v = hash11(seed + 17.0);",
        "    float theta = u * 6.28318530718;",
        "    float phi = acos(2.0 * v - 1.0);",
        "    float r = radius * pow(hash11(seed + 31.0), 1.0 / 3.0);",
        "    return vec3(r * sin(phi) * cos(theta), r * sin(phi) * sin(theta), r * cos(phi));",
        "}",
        "",
        -- direction spread inside a cone around u_direction, biased by
        -- u_coneAngle; point/sphere shapes fall back to a full-sphere spread
        "vec3 randomDirection(float seed)",
        "{",
        "    if (u_spawnShape == 2) {",
        "        vec3 axis = normalize(u_direction);",
        "        vec3 arbitrary = abs(axis.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);",
        "        vec3 tangent = normalize(cross(arbitrary, axis));",
        "        vec3 bitangent = cross(axis, tangent);",
        "        float u = hash11(seed + 53.0);",
        "        float v = hash11(seed + 71.0);",
        "        float cosAngle = mix(cos(u_coneAngle), 1.0, u);",
        "        float sinAngle = sqrt(1.0 - cosAngle * cosAngle);",
        "        float phi = v * 6.28318530718;",
        "        return normalize(axis * cosAngle + (tangent * cos(phi) + bitangent * sin(phi)) * sinAngle);",
        "    }",
        "    return normalize(randomInSphere(seed + 91.0, 1.0));",
        "}",
        "",
        "vec4 position(mat4 transform_projection, vec4 vertex_position)",
        "{",
        "    float age, lifeT;",
        "    bool alive = true;",
        "    if (u_burst) {",
        -- one shared phase for the whole system: every particle is born at
        -- t01=0 and fully dead at t01=1, so the system as a whole has a
        -- visible start and end instead of particles trickling in and out
        -- independently. u_time is expected to be free-running -- the mod
        -- here is what makes the cycle repeat, not an external timer.
        "        float t01 = mod(u_time, u_cycleDuration) / u_cycleDuration;",
        "        lifeT = t01;",
        "        age = t01 * u_lifetime;",
        "",
        -- Each particle gets a fixed rank in [0,1) from its own seed, standing
        -- in for spawn order. rise: only ranks below how far into the rise
        -- window we are are alive (population grows). sustain: everyone.
        -- decay: only ranks below how far into decay we are REMAIN, so the
        -- same rank that appeared first also survives longest, and the
        -- population shrinks back down to zero exactly at cycle end.
        "        float rank = hash11(a_seed + 197.0);",
        "        float riseEnd = u_riseFraction;",
        "        float sustainEnd = riseEnd + u_sustainFraction;",
        "        float decayEnd = sustainEnd + u_decayFraction;",
        "        if (t01 < riseEnd) {",
        "            float riseT = u_riseFraction > 0.0 ? t01 / u_riseFraction : 1.0;",
        "            alive = rank <= riseT;",
        "        } else if (t01 < sustainEnd) {",
        "            alive = true;",
        "        } else if (t01 < decayEnd) {",
        "            float decayT = u_decayFraction > 0.0",
        "                ? (t01 - sustainEnd) / u_decayFraction : 1.0;",
        "            alive = rank > decayT;",
        "        } else {",
        "            alive = false;",
        "        }",
        "    } else {",
        -- each particle's own clock: a fixed per-particle offset so the whole
        -- set does not spawn in lockstep, wrapped to [0, lifetime)
        "        float offset = hash11(a_seed) * u_lifetime;",
        "        age = mod(u_time + offset, u_lifetime);",
        "        lifeT = age / u_lifetime;",
        "    }",
        "",
        "    vec3 spawnPos = vec3(0.0);",
        "    if (u_spawnShape == 1) { spawnPos = randomInSphere(a_seed, u_spawnRadius); }",
        "",
        "    vec3 dir = randomDirection(a_seed);",
        "    float speed = mix(u_speedMin, u_speedMax, hash11(a_seed + 113.0));",
        "    vec3 vel = dir * speed;",
        "",
        -- ballistic closed form: pos = p0 + v*t + 0.5*g*t^2, so re-evaluating
        -- at any `age` needs no accumulated integration state
        "    vec3 localPos = spawnPos + vel * age + 0.5 * u_gravity * age * age;",
        "",
        "    float size = mix(u_sizeStart, u_sizeEnd, lifeT);",
        "    v_color = mix(u_colorStart, u_colorEnd, lifeT);",
        "",
        -- a dead particle (gated out by the rise/decay envelope) collapses to
        -- a zero-area quad rather than branching the draw -- cheapest way to
        -- make it fully disappear, not just fade, with no discard/alpha trick
        "    if (!alive) { size = 0.0; }",
        "",
        "    vec3 localCorner = vertex_position.xyz * size;",
        "",
        "    if (u_isMesh) {",
        -- 3D tumble: Rodrigues' rotation formula around a fixed-but-random
        -- per-particle axis, angle growing linearly with age -- each particle
        -- spins at the same rate but around its own axis, so a field of boxes
        -- doesn't read as one rigid rotating block
        "        vec3 axis = normalize(randomInSphere(a_seed + 233.0, 1.0));",
        "        float angle = age * u_rotationSpeed;",
        "        float c = cos(angle), s = sin(angle);",
        "        localCorner = localCorner * c + cross(axis, localCorner) * s",
        "                    + axis * dot(axis, localCorner) * (1.0 - c);",
        "    } else {",
        -- 2D screen-space spin: rotate the quad corner within the
        -- camera-right/camera-up plane before billboarding, same trick sprite
        -- systems use for spinning embers/leaves
        "        float angle = age * u_rotationSpeed;",
        "        float c = cos(angle), s = sin(angle);",
        "        localCorner = vec3(localCorner.x * c - localCorner.y * s,",
        "                           localCorner.x * s + localCorner.y * c, 0.0);",
        "    }",
        "",
        -- billboard: expanded along the camera's own right/up so every
        -- particle faces the camera regardless of emitter rotation; mesh
        -- particles instead ride the emitter's own model matrix in full 3D
        "    vec4 world;",
        "    if (u_isMesh) {",
        "        world = u_model * vec4(localPos + localCorner, 1.0);",
        "    } else {",
        "        vec3 corner = u_cameraRight * localCorner.x + u_cameraUp * localCorner.y;",
        "        world = u_model * vec4(localPos, 1.0) + vec4(corner, 0.0);",
        "    }",
        "    return u_viewProj * world;",
        "}",
        "#endif",
        "",
        "#ifdef PIXEL",
        "uniform Image u_map;",
        "uniform bool  u_hasMap;",
        "",
        "vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)",
        "{",
        "    vec4 base = v_color;",
        "    if (u_hasMap) { base *= Texel(u_map, uv); }",
        "    return base * color;",
        "}",
        "#endif",
    }, "\n")
end

local cached

return function()
    if not cached then cached = love.graphics.newShader(source()) end
    return cached
end
