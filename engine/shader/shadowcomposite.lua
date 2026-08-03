-- shader/shadowcomposite.lua — merge a static and a dynamic depth canvas
--
-- Both canvases store distance/NDC-depth in their red channel (see
-- shader/depth.lua). The merged shadow map at any texel is whichever caster
-- was closer to the light, so the merge is just a per-texel min -- one
-- fullscreen draw per canvas pair (per cube face, for point lights),
-- cheaper than redrawing the static geometry every frame.
--
-- Two variants: 2D samples by uv like any fullscreen effect; cube samples
-- both faces by a fixed direction, since CubeImage has no uv-space texel.

local function source2D()
    return table.concat({
        "uniform Image u_static;",
        "uniform Image u_dynamic;",
        "",
        "#ifdef PIXEL",
        "vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)",
        "{",
        "    float a = Texel(u_static, uv).r;",
        "    float b = Texel(u_dynamic, uv).r;",
        "    float d = min(a, b);",
        "    return vec4(d, d, d, 1.0);",
        "}",
        "#endif",
    }, "\n")
end

-- u_faceDir/u_faceRight/u_faceUp are the face's own basis (same convention
-- as PointLight.lua's FACES table); each fragment reconstructs its own
-- sample direction from uv the same way a cube camera's face plane would,
-- since a single constant direction would sample only one texel for the
-- whole quad instead of covering the face.
local function sourceCube()
    return table.concat({
        "uniform CubeImage u_static;",
        "uniform CubeImage u_dynamic;",
        "uniform vec3 u_faceDir;",
        "uniform vec3 u_faceRight;",
        "uniform vec3 u_faceUp;",
        "",
        "#ifdef PIXEL",
        "vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)",
        "{",
        "    vec2 ndc = uv * 2.0 - 1.0;",
        "    vec3 dir = u_faceDir + u_faceRight * ndc.x + u_faceUp * ndc.y;",
        "    float a = Texel(u_static, dir).r;",
        "    float b = Texel(u_dynamic, dir).r;",
        "    float d = min(a, b);",
        "    return vec4(d, d, d, 1.0);",
        "}",
        "#endif",
    }, "\n")
end

local cache = {}

-- get(cube) -> the cached composite shader for that variant.
return function(cube)
    local key = cube and "cube" or "2d"
    if not cache[key] then
        cache[key] = love.graphics.newShader(cube and sourceCube() or source2D())
    end
    return cache[key]
end
