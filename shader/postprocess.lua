-- shader/postprocess.lua — fullscreen shaders for the post-processing chain
--
-- Small, standalone shaders in the same spirit as shader/depth.lua: no part
-- system, since a fullscreen pass has no vertex stage worth varying and no
-- lighting model to share with the main shader.

local M = {}
local cache = {}

local function get(key, source)
    if not cache[key] then cache[key] = love.graphics.newShader(source) end
    return cache[key]
end

-- Separable Gaussian blur, one direction per draw (see BloomPass, which runs
-- this twice -- horizontal then vertical -- rather than a single 2D kernel,
-- since an NxN blur costs O(N) per axis this way instead of O(N^2)).
function M.blur()
    return get("blur", [[
        uniform vec2 u_direction;   // (1,0)/w for horizontal, (0,1)/h for vertical, pre-divided by texel size
        uniform float u_radius;     // blur spread in texels

        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
        {
            // 9-tap Gaussian, weights for sigma ~= radius/3, symmetric around the center tap
            float weights[5];
            weights[0] = 0.227027; weights[1] = 0.1945946; weights[2] = 0.1216216;
            weights[3] = 0.054054; weights[4] = 0.016216;

            vec3 result = Texel(tex, uv).rgb * weights[0];
            for (int i = 1; i < 5; i += 1) {
                vec2 offset = u_direction * u_radius * float(i);
                result += Texel(tex, uv + offset).rgb * weights[i];
                result += Texel(tex, uv - offset).rgb * weights[i];
            }
            return vec4(result, 1.0) * color;
        }
    ]])
end

-- Cuts the bright-pass canvas down to what's actually above `u_threshold`.
-- The MRT bright target already holds only emissive/particle colour (see
-- shader/init.lua and shader/particles.lua), so this is a second filter on
-- top of that -- useful when an emissive material is present but too dim to
-- bloom, or to dial bloom down without touching material authoring.
function M.threshold()
    return get("threshold", [[
        uniform float u_threshold;

        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
        {
            vec3 c = Texel(tex, uv).rgb;
            float brightness = max(c.r, max(c.g, c.b));
            float keep = smoothstep(u_threshold, u_threshold + 0.1, brightness);
            return vec4(c * keep, 1.0) * color;
        }
    ]])
end

-- Additive composite: scene + blurred bright-pass * intensity, drawn straight
-- to whatever canvas is bound (the screen, from BloomPass).
function M.composite()
    return get("composite", [[
        uniform Image u_bloom;
        uniform float u_intensity;

        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
        {
            vec3 base = Texel(tex, uv).rgb;
            vec3 bloom = Texel(u_bloom, uv).rgb * u_intensity;
            return vec4(base + bloom, 1.0) * color;
        }
    ]])
end

return M
