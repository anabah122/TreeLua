-- shader/depth.lua — the shadow pass's own tiny shaders
--
-- Not assembled from shader/init.lua's part system: the shadow pass draws
-- nothing but a caster's depth, so it needs none of pbr/normalmap's machinery.
-- It DOES need skinning, though -- an animated SkinnedMesh casts its shadow
-- from whatever pose it is in this frame, not its bind pose, or an animated
-- character would drag a statue-shaped shadow around with it. So there are
-- variants here, same split as the main shader's static/skinned and reusing
-- its skinning GLSL directly rather than forking it.
--
-- Two depth METRICS, not just two skinning variants:
--   - 2D (directional/spot): NDC z in [0,1], compared against shadow.lua's
--     u_shadowViewProj-reprojected fragment. One view direction, one matrix.
--   - cube (point): a point light has 6 faces with 6 different projections,
--     so NDC z from one face means nothing when sampled from another
--     direction. Instead this writes plain distance-from-light / far, which
--     is projection-independent and comparable across all 6 faces.
--
-- LOVE has no bindable depth-only render target, so distance is written into
-- the canvas's red channel instead (an r32f canvas, so no precision is lost
-- the way an 8-bit one would).

local skinning = require "shader.parts.skinning"

local function source(withSkinning, cube)
    return table.concat({
        "uniform mat4 u_viewProj;",
        "uniform mat4 u_model;",
        cube and "uniform vec3 u_lightPos;" or "",
        cube and "uniform float u_far;" or "",
        "varying float v_depth;",
        cube and "varying vec3 v_worldPos;" or "",
        "",
        "#ifdef VERTEX",
        withSkinning and skinning.vertexUniforms or "",
        "vec4 position(mat4 transform_projection, vec4 vertex_position)",
        "{",
        "    vec4 localPos = vec4(vertex_position.xyz, 1.0);",
        withSkinning and skinning.vertexCalc or "",
        withSkinning and "localPos = _skin * localPos;" or "",
        "    vec4 world = u_model * localPos;",
        "    vec4 clip = u_viewProj * world;",
        cube
            and "    v_worldPos = world.xyz;"
            -- NDC z in [-1,1] -> [0,1], the range the compare in shadow.lua expects
            or  "    v_depth = clip.z / clip.w * 0.5 + 0.5;",
        "    return clip;",
        "}",
        "#endif",
        "",
        "#ifdef PIXEL",
        "vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)",
        "{",
        cube and "    float d = length(v_worldPos - u_lightPos) / max(u_far, 1e-4);"
             or  "    float d = v_depth;",
        "    return vec4(d, d, d, 1.0);",
        "}",
        "#endif",
    }, "\n")
end

local cache = {}

-- get(withSkinning, cube) -> one of 4 cached variants.
return function(withSkinning, cube)
    local key = (withSkinning and "skinned" or "static") .. (cube and "_cube" or "_2d")
    if not cache[key] then
        cache[key] = love.graphics.newShader(source(withSkinning, cube))
    end
    return cache[key]
end
