-- shader/depth.lua — the shadow pass's own tiny shaders
--
-- Not assembled from shader/init.lua's part system: the shadow pass draws
-- nothing but distance from the light, so it needs none of pbr/normalmap's
-- machinery. It DOES need skinning, though -- an animated SkinnedMesh casts
-- its shadow from whatever pose it is in this frame, not its bind pose, or
-- an animated character would drag a statue-shaped shadow around with it.
-- So there are two variants here, same split as the main shader's
-- static/skinned and reusing its skinning GLSL directly rather than
-- forking it.
--
-- LOVE has no bindable depth-only render target, so distance is written into
-- the canvas's red channel instead (an r32f canvas, so no precision is lost
-- the way an 8-bit one would).

local skinning = require "shader.parts.skinning"

local function source(withSkinning)
    return table.concat({
        "uniform mat4 u_viewProj;",
        "uniform mat4 u_model;",
        "varying float v_depth;",
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
        -- NDC z in [-1,1] -> [0,1], the range the compare in shadow.lua expects
        "    v_depth = clip.z / clip.w * 0.5 + 0.5;",
        "    return clip;",
        "}",
        "#endif",
        "",
        "#ifdef PIXEL",
        "vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)",
        "{",
        "    return vec4(v_depth, v_depth, v_depth, 1.0);",
        "}",
        "#endif",
    }, "\n")
end

local cache = {}

-- get(false) -> static variant, get(true) -> skinned variant.
return function(withSkinning)
    local key = withSkinning and "skinned" or "static"
    if not cache[key] then
        cache[key] = love.graphics.newShader(source(withSkinning))
    end
    return cache[key]
end
