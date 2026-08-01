-- shader/parts/shadow.lua — sample up to MAX_SHADOWS shadow maps
--
-- Must come before pbr: this part fills `shadowFactor[MAX_LIGHTS]` (1.0 = fully
-- lit, 0.0 = fully shadowed, one entry per light slot in u_light*), and pbr
-- multiplies each light's contribution by its own entry. Lights past
-- MAX_SHADOWS, or with no shadow map bound, read 1.0 -- a scene with no
-- shadow-casting light costs one branch per light and renders exactly as
-- before shadows existed.
--
-- Directional and spot lights use a single 2D depth map (u_shadowMap2D),
-- because both have one coherent view direction. Point lights need all 6
-- cube faces (u_shadowMapCube) since there is no single direction to project
-- from -- which map a light slot reads is decided by u_shadowIsCube. Both
-- kinds get the same PCF softness knob (u_shadowKernel), just applied in
-- texel space for 2D and in sample-direction space for cube.
--
-- Depth is packed into red channel because LOVE has no bindable depth-only
-- render target (see shader/depth.lua). Comparing against it is the standard
-- shadow-map test: a fragment is in shadow if something ELSE was closer to
-- the light than it is.

return {
    name = "shadow",

    -- World-space position (v_worldPos, declared by the skeleton) is enough:
    -- each shadow slot re-projects it with its own light-space matrix in the
    -- fragment stage, since a vertex has no room for MAX_SHADOWS interpolated
    -- shadow coords.
    varyings = "",

    fragmentUniforms = [[
        // Defined here (not pbr.lua) because shadow's slot is assembled
        // before pbr's in shader/init.lua's ALWAYS list, and shadowFactor[]
        // below needs MAX_LIGHTS already known.
        #define MAX_LIGHTS 16
        #define MAX_SHADOWS 4

        uniform int    u_shadowCount;
        uniform int    u_shadowLightIndex[MAX_SHADOWS];  // which u_light* slot this shadow belongs to
        uniform bool   u_shadowIsCube[MAX_SHADOWS];
        uniform mat4   u_shadowViewProj[MAX_SHADOWS];    // 2D shadows only
        uniform vec3   u_shadowLightPos[MAX_SHADOWS];    // cube shadows only: distance is the depth metric
        uniform float  u_shadowFar[MAX_SHADOWS];         // cube shadows only: far plane, to normalize distance
        uniform float  u_shadowBias[MAX_SHADOWS];
        uniform float  u_shadowNormalBias[MAX_SHADOWS];  // world units, offset along the normal
        uniform vec3   u_shadowLightDir[MAX_SHADOWS];    // 2D shadows: direction the light travels
        uniform vec2   u_shadowMapSize[MAX_SHADOWS];
        uniform Image     u_shadowMap2D[MAX_SHADOWS];
        uniform CubeImage u_shadowMapCube[MAX_SHADOWS];

        // Sample radius in texels each direction: 0 is one sample (hard edge),
        // 1 is a 3x3 PCF kernel, 2 is 5x5, and so on. Driven by
        // TL.settings.shadowSoftness -- see WebGLRenderer:_sendShadowUniforms.
        // MAX_SHADOW_KERNEL bounds the loop so it stays a compile-time
        // constant (some GLSL ES drivers reject a uniform loop bound); a
        // uniform kernel smaller than the max just exits its loop early.
        uniform int u_shadowKernel;

        // Per-mesh, not per-frame: three.js's `receiveShadow` flag. A mesh
        // with it off reads fully lit even while every map/matrix above
        // stays bound for meshes that don't -- sent per-draw in _drawBucket.
        uniform bool u_hasShadow;
    ]],

    fragmentFunctions = [[
        #define MAX_SHADOW_KERNEL 3

        float sampleShadow2D(int slot, vec3 texel3, vec2 texelSize, float bias)
        {
            vec2 _texel = 1.0 / texelSize;
            float _lit = 0.0;
            float _count = 0.0;

            for (int dx = -MAX_SHADOW_KERNEL; dx <= MAX_SHADOW_KERNEL; dx++) {
                if (dx < -u_shadowKernel || dx > u_shadowKernel) continue;
                for (int dy = -MAX_SHADOW_KERNEL; dy <= MAX_SHADOW_KERNEL; dy++) {
                    if (dy < -u_shadowKernel || dy > u_shadowKernel) continue;

                    vec2 _offset = vec2(float(dx), float(dy)) * _texel;
                    float _casterDepth = slot == 0 ? Texel(u_shadowMap2D[0], texel3.xy + _offset).r
                                       : slot == 1 ? Texel(u_shadowMap2D[1], texel3.xy + _offset).r
                                       : slot == 2 ? Texel(u_shadowMap2D[2], texel3.xy + _offset).r
                                       :             Texel(u_shadowMap2D[3], texel3.xy + _offset).r;
                    // smoothstep, not a 0/1 test: N binary samples can only
                    // produce N+1 distinct values, which band on smooth surfaces
                    _lit += smoothstep(-bias, bias, _casterDepth - texel3.z);
                    _count += 1.0;
                }
            }

            return _lit / _count;
        }

        float texelCube(int slot, vec3 dir)
        {
            return slot == 0 ? Texel(u_shadowMapCube[0], dir).r
                 : slot == 1 ? Texel(u_shadowMapCube[1], dir).r
                 : slot == 2 ? Texel(u_shadowMapCube[2], dir).r
                 :             Texel(u_shadowMapCube[3], dir).r;
        }

        // PCF for a cube map: there is no 2D texel grid to offset in, so the
        // kernel instead nudges the sample DIRECTION sideways, in a basis
        // perpendicular to `dir`.
        //
        // The basis is built with Duff's branchless method rather than picking
        // an up vector by a threshold: a threshold flips the whole kernel's
        // orientation as `dir` crosses it, which draws a hard seam across the
        // surface exactly along that crossing.
        float sampleShadowCube(int slot, vec3 dir, float dist, float bias)
        {
            vec3 _n = normalize(dir);
            float _sign = _n.z >= 0.0 ? 1.0 : -1.0;
            float _a = -1.0 / (_sign + _n.z);
            float _b = _n.x * _n.y * _a;
            vec3 _right = vec3(1.0 + _sign * _n.x * _n.x * _a, _sign * _b, -_sign * _n.x);
            vec3 _up     = vec3(_b, _sign + _n.y * _n.y * _a, -_n.y);

            // Angular offsets on the unit direction, NOT scaled by distance:
            // a far fragment would otherwise swing its taps wide enough to
            // cross a cube face edge, where the neighbouring face holds a
            // different projection and lights up a band along the seam.
            float _spread = 0.006 * float(max(u_shadowKernel, 0));
            float _lit = 0.0;
            float _count = 0.0;

            for (int dx = -MAX_SHADOW_KERNEL; dx <= MAX_SHADOW_KERNEL; dx++) {
                if (dx < -u_shadowKernel || dx > u_shadowKernel) continue;
                for (int dy = -MAX_SHADOW_KERNEL; dy <= MAX_SHADOW_KERNEL; dy++) {
                    if (dy < -u_shadowKernel || dy > u_shadowKernel) continue;

                    vec3 _sampleDir = _n + (_right * float(dx) + _up * float(dy)) * _spread;
                    _lit += smoothstep(-bias, bias, texelCube(slot, _sampleDir) - dist);
                    _count += 1.0;
                }
            }

            return _lit / _count;
        }
    ]],

    fragmentCalc = [[
        float shadowFactor[MAX_LIGHTS];
        for (int i = 0; i < MAX_LIGHTS; i++) { shadowFactor[i] = 1.0; }

        if (u_hasShadow) {
            vec3 _shadowNormal = normalize(v_normal);

            for (int s = 0; s < MAX_SHADOWS; s++) {
                if (s >= u_shadowCount) break;

                int _light = u_shadowLightIndex[s];
                if (_light < 0 || _light >= u_lightCount) continue;

                // Normal bias: sample from just off the surface instead of on
                // it, so a face never tests against its own depth. Scaled by
                // sin of the light angle, so a face facing the light gets
                // almost none -- the full offset near a silhouette edge would
                // push the sample past the edge onto the neighbouring face and
                // light up a band along it.
                vec3 _lightDir = u_shadowIsCube[s]
                    ? normalize(u_shadowLightPos[s] - v_worldPos)
                    : -u_shadowLightDir[s];
                float _cos = clamp(dot(_shadowNormal, _lightDir), 0.0, 1.0);
                float _slope = sqrt(1.0 - _cos * _cos);
                vec3 _biasedPos = v_worldPos
                    + _shadowNormal * u_shadowNormalBias[s] * _slope;

                if (u_shadowIsCube[s]) {
                    vec3 _toFrag = _biasedPos - u_shadowLightPos[s];
                    float _dist = length(_toFrag) / max(u_shadowFar[s], 1e-4);
                    shadowFactor[_light] = sampleShadowCube(s, _toFrag, _dist, u_shadowBias[s]);
                } else {
                    vec4 _clip = u_shadowViewProj[s] * vec4(_biasedPos, 1.0);
                    vec3 _proj = _clip.xyz / _clip.w;
                    _proj = _proj * 0.5 + 0.5;

                    if (_proj.x >= 0.0 && _proj.x <= 1.0 &&
                        _proj.y >= 0.0 && _proj.y <= 1.0 &&
                        _proj.z >= 0.0 && _proj.z <= 1.0) {
                        shadowFactor[_light] = sampleShadow2D(s, _proj, u_shadowMapSize[s], u_shadowBias[s]);
                    }
                }
            }
        }
    ]],
}
