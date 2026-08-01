-- shader/parts/normalmap.lua — tangent-space normal and occlusion maps
--
-- Must come before pbr: overwrites shadingNormal and ambientOcclusion.
--
-- The tangent basis is derived per fragment from screen-space derivatives
-- rather than stored as a vertex attribute, so the vertex format shared by both
-- importers and every primitive generator stays as it is.

return {
    name = "normalmap",

    fragmentUniforms = [[
        uniform bool  u_hasNormalMap;
        uniform Image u_normalMap;
        uniform float u_normalScale;
        uniform bool  u_hasOcclusionMap;
        uniform Image u_occlusionMap;
        uniform float u_occlusionStrength;
    ]],

    fragmentFunctions = [[
        mat3 cotangentFrame(vec3 n, vec3 p, vec2 uv)
        {
            vec3 dp1 = dFdx(p);
            vec3 dp2 = dFdy(p);
            vec2 duv1 = dFdx(uv);
            vec2 duv2 = dFdy(uv);

            vec3 dp2perp = cross(dp2, n);
            vec3 dp1perp = cross(n, dp1);

            vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
            vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;

            // a degenerate UV patch gives a zero-length basis
            float invmax = inversesqrt(max(dot(t, t), dot(b, b)) + 1e-12);
            return mat3(t * invmax, b * invmax, n);
        }
    ]],

    fragmentCalc = [[
        if (u_hasNormalMap) {
            vec3 _tn = Texel(u_normalMap, uv).xyz * 2.0 - 1.0;
            _tn.xy *= u_normalScale;

            vec3 _geom = normalize(v_normal);
            shadingNormal = normalize(cotangentFrame(_geom, v_worldPos, uv) * _tn);
        }

        if (u_hasOcclusionMap) {
            float _ao = Texel(u_occlusionMap, uv).r;
            ambientOcclusion = 1.0 + u_occlusionStrength * (_ao - 1.0);
        }
    ]],
}
