-- shader/parts/shadow.lua — sample the directional light's shadow map
--
-- Must come before pbr: this part fills `shadowFactor` (1.0 = fully lit, 0.0 =
-- fully shadowed), and pbr multiplies its light contribution by it. When no
-- shadow map is bound (u_hasShadow false) shadowFactor stays 1.0, so a scene
-- with no shadow-casting light costs one branch and renders exactly as before
-- this part existed.
--
-- The shadow map is a single Canvas written by the depth pass (shader/depth.lua)
-- with distance-from-light packed into its red channel, because LOVE has no
-- bindable depth-only render target. Comparing against it here is the standard
-- shadow-map test: a fragment is in shadow if something ELSE was closer to the
-- light than it is.

return {
    name = "shadow",

    -- Shared between stages, like v_normal/v_worldPos in the skeleton: the
    -- vertex stage writes the light-space position, the fragment stage
    -- samples with it.
    varyings = [[
        varying vec4 v_shadowCoord;
    ]],

    vertexUniforms = [[
        uniform mat4 u_lightViewProj;
        uniform bool u_hasShadow;
    ]],

    vertexMix = [[
        v_shadowCoord = u_hasShadow ? u_lightViewProj * (u_model * localPos) : vec4(0.0);
    ]],

    fragmentUniforms = [[
        uniform bool  u_hasShadow;
        uniform Image u_shadowMap;
        uniform float u_shadowBias;
        uniform vec2  u_shadowMapSize;
        // Sample radius in texels each direction: 0 is one sample (hard edge),
        // 1 is a 3x3 PCF kernel, 2 is 5x5, and so on. Driven by
        // TL.settings.shadowSoftness -- see WebGLRenderer:_sendShadowUniforms.
        // MAX_SHADOW_KERNEL bounds the loop so it stays a compile-time
        // constant (some GLSL ES drivers reject a uniform loop bound); a
        // uniform kernel smaller than the max just exits its loop early.
        uniform int u_shadowKernel;
    ]],

    fragmentFunctions = [[
        #define MAX_SHADOW_KERNEL 3
    ]],

    fragmentCalc = [[
        float shadowFactor = 1.0;
        if (u_hasShadow) {
            vec3 _proj = v_shadowCoord.xyz / v_shadowCoord.w;
            _proj = _proj * 0.5 + 0.5;

            if (_proj.x >= 0.0 && _proj.x <= 1.0 &&
                _proj.y >= 0.0 && _proj.y <= 1.0 &&
                _proj.z >= 0.0 && _proj.z <= 1.0) {
                // PCF: average several offset samples instead of one, so an
                // edge falls off over a few texels rather than snapping
                // texel-hard.
                vec2 _texel = 1.0 / u_shadowMapSize;
                float _lit = 0.0;
                float _count = 0.0;

                for (int dx = -MAX_SHADOW_KERNEL; dx <= MAX_SHADOW_KERNEL; dx++) {
                    if (dx < -u_shadowKernel || dx > u_shadowKernel) continue;
                    for (int dy = -MAX_SHADOW_KERNEL; dy <= MAX_SHADOW_KERNEL; dy++) {
                        if (dy < -u_shadowKernel || dy > u_shadowKernel) continue;

                        vec2 _offset = vec2(float(dx), float(dy)) * _texel;
                        float _casterDepth = Texel(u_shadowMap, _proj.xy + _offset).r;
                        if (_proj.z - u_shadowBias <= _casterDepth) {
                            _lit += 1.0;
                        }
                        _count += 1.0;
                    }
                }

                shadowFactor = _lit / _count;
            }
        }
    ]],
}
