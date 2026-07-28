-- shader/parts/pbr.lua — metallic-roughness shading, up to MAX_LIGHTS lights
--
-- Cook-Torrance: GGX distribution, Smith geometry, Schlick Fresnel. This is
-- the model glTF stores and both importers already extract, so nothing has to
-- be converted on the way in.
--
-- Directional/point/spot all sit in one uniform array rather than three
-- separate ones: a scene mixes them freely, and one loop that branches on
-- u_lightType is simpler than unrolling three loops of different lengths.
-- MAX_LIGHTS must match WebGLRenderer.MAX_LIGHTS.
--
-- Always included -- unlike skinning it costs no uniform array, and a variant
-- without it would just be a second lighting model to keep in step. If an
-- unlit variant is ever wanted, this is the part to make optional.

return {
    name = "pbr",

    fragmentUniforms = [[
        // MAX_LIGHTS is defined by shader/parts/shadow.lua, whose slot is
        // assembled first (see shader/init.lua's ALWAYS list).
        uniform int   u_lightCount;
        uniform int   u_lightType[MAX_LIGHTS];       // 0 directional, 1 point, 2 spot
        uniform vec3  u_lightPos[MAX_LIGHTS];         // point/spot: world position
        uniform vec3  u_lightDir[MAX_LIGHTS];         // directional/spot: ray direction (light -> scene)
        uniform vec3  u_lightColor[MAX_LIGHTS];       // color * intensity
        uniform float u_lightDistance[MAX_LIGHTS];    // point/spot cutoff, 0 = infinite
        uniform float u_lightDecay[MAX_LIGHTS];
        uniform float u_lightAngleCos[MAX_LIGHTS];    // spot: cos(angle), outer cone edge
        uniform float u_lightPenumbraCos[MAX_LIGHTS]; // spot: cos(angle*(1-penumbra)), inner edge

        uniform vec3  u_ambient;
        uniform bool  u_hasHemi;
        uniform vec3  u_hemiSkyColor;
        uniform vec3  u_hemiGroundColor;
        uniform vec3  u_hemiDir;
        uniform vec3  u_cameraPos;
        uniform float u_metalness;
        uniform float u_roughness;
        uniform vec3  u_emissive;
        uniform float u_diffuseWrap;
        uniform bool  u_hasMRMap;
        uniform bool  u_hasEmissiveMap;
        uniform Image u_mrMap;
        uniform Image u_emissiveMap;
    ]],

    -- Helper functions, emitted at file scope above the entry point.
    fragmentFunctions = [[
        // GGX/Trowbridge-Reitz: how much of the surface is angled to reflect
        // toward the viewer. The alpha = roughness^2 remap is what makes the
        // roughness slider feel linear; without it everything below ~0.5 looks
        // equally mirror-like.
        float distributionGGX(float ndh, float roughness)
        {
            float a  = roughness * roughness;
            float a2 = a * a;
            float d  = ndh * ndh * (a2 - 1.0) + 1.0;
            return a2 / max(3.14159265 * d * d, 1e-7);
        }

        // Smith geometry with the Schlick-GGX approximation, split across both
        // directions: rough surfaces shadow and mask their own microfacets.
        float geometrySmith(float ndv, float ndl, float roughness)
        {
            float r = roughness + 1.0;
            float k = (r * r) / 8.0;
            float gv = ndv / (ndv * (1.0 - k) + k);
            float gl = ndl / (ndl * (1.0 - k) + k);
            return gv * gl;
        }

        // Fresnel: everything turns mirror at a grazing angle.
        vec3 fresnelSchlick(float cosTheta, vec3 f0)
        {
            return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
        }

        // Physical inverse-square falloff, windowed to zero at `distance`
        // (0 = never cuts off) so a point/spot light does not light the whole
        // level. Same smoothstep-based window three.js's punctual lights use.
        float punctualAttenuation(float dist, float range, float decay)
        {
            float atten = 1.0 / max(pow(dist, decay), 1e-4);
            if (range > 0.0) {
                float falloff = clamp(1.0 - pow(dist / range, 4.0), 0.0, 1.0);
                atten *= falloff * falloff;
            }
            return atten;
        }
    ]],

    -- Reads `baseColor` and the varyings; leaves the result in `_shaded`.
    fragmentCalc = [[
        float _metalness = u_metalness;
        float _roughness = u_roughness;

        // glTF packs roughness in G and metalness in B of one texture
        if (u_hasMRMap) {
            vec4 _mr = Texel(u_mrMap, uv);
            _roughness *= _mr.g;
            _metalness *= _mr.b;
        }

        // a perfectly smooth surface gives a singular highlight; clamp low
        _roughness = clamp(_roughness, 0.04, 1.0);
        _metalness = clamp(_metalness, 0.0, 1.0);

        vec3 _n = shadingNormal;
        vec3 _v = normalize(u_cameraPos - v_worldPos);

        float _ndv = max(dot(_n, _v), 1e-4);

        // Dielectrics reflect ~4% head-on; metals reflect their own base
        // colour and have no diffuse lobe at all.
        vec3 _f0 = mix(vec3(0.04), baseColor.rgb, _metalness);

        // shadowFactor[i] is declared by shader/parts/shadow.lua, which runs
        // before this part (see shader/init.lua's ALWAYS list) and is 1.0
        // (fully lit) for any light with no bound shadow map.
        vec3 _lit = vec3(0.0);
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= u_lightCount) break;

            vec3 _l;
            float _atten = 1.0;

            if (u_lightType[i] == 0) {
                // directional: parallel rays, no distance falloff
                _l = -normalize(u_lightDir[i]);
            } else {
                vec3 _toLight = u_lightPos[i] - v_worldPos;
                float _dist = length(_toLight);
                _l = _toLight / max(_dist, 1e-4);
                _atten = punctualAttenuation(_dist, u_lightDistance[i], u_lightDecay[i]);

                if (u_lightType[i] == 2) {
                    // spot: cone falloff between the outer and inner (penumbra) edge
                    float _cosAngle = dot(-_l, normalize(u_lightDir[i]));
                    float _spot = clamp(
                        (_cosAngle - u_lightAngleCos[i]) /
                        max(u_lightPenumbraCos[i] - u_lightAngleCos[i], 1e-4),
                        0.0, 1.0);
                    _atten *= _spot * _spot;
                }
            }

            if (_atten <= 0.0) continue;

            vec3 _h = normalize(_v + _l);
            float _ndl = max(dot(_n, _l), 0.0);
            float _ndh = max(dot(_n, _h), 0.0);
            float _vdh = max(dot(_v, _h), 0.0);

            float _d = distributionGGX(_ndh, _roughness);
            float _g = geometrySmith(_ndv, _ndl, _roughness);
            vec3  _f = fresnelSchlick(_vdh, _f0);

            vec3 _specular = (_d * _g * _f) / max(4.0 * _ndv * _ndl, 1e-4);

            // Energy conservation: what is not reflected is available to
            // scatter. The Lambert lobe is albedo/pi, but the pi is folded
            // away rather than divided out: light intensities in this engine
            // are authored against the old lambert shader, where a directional
            // light of 1.0 meant "full brightness". Keeping the pi would
            // darken every scene by 3.14x and force every caller to retune.
            vec3 _kd = (vec3(1.0) - _f) * (1.0 - _metalness);
            vec3 _diffuse = _kd * baseColor.rgb;

            // Wrapped diffuse: the lit side follows ndl, but the terminator
            // softens so faces angled away stay readable instead of dropping
            // to flat black. The specular lobe keeps the true ndl -- wrapping
            // it would smear highlights around the back of the object.
            float _wrapped = _ndl * (1.0 - u_diffuseWrap) + u_diffuseWrap;

            _lit += (_diffuse * u_lightColor[i] * _wrapped
                  +  _specular * u_lightColor[i] * _ndl) * _atten * shadowFactor[i];
        }

        // Ambient stands in for the environment this renderer has no probe for.
        //
        // This matters most for metal. A metal has no diffuse lobe at all: it
        // is lit purely by what it reflects, so with no environment map it
        // renders nearly black -- physically right, and useless on screen. So
        // the ambient term doubles as a crude environment: metals reflect it
        // tinted by f0 (their own colour), dielectrics scatter it as albedo. A
        // rough surface gathers it from a wider cone, so roughness does not
        // dim it the way a mirror lobe would.
        //
        // A real IBL probe would replace these two lines.
        // Hemisphere term: same environment stand-in as u_ambient, but split
        // into a sky and ground colour blended by how much the normal faces
        // up vs down -- cheap proxy for outdoor bounce light with no shadows.
        vec3 _envLight = u_ambient;
        if (u_hasHemi) {
            float _hemiMix = dot(_n, u_hemiDir) * 0.5 + 0.5;
            _envLight += mix(u_hemiGroundColor, u_hemiSkyColor, _hemiMix);
        }

        vec3 _ambient = (_envLight * baseColor.rgb * (1.0 - _metalness)
                      +  _envLight * _f0 * mix(1.0, 0.5, _roughness))
                      * ambientOcclusion;

        _emissive = u_emissive;
        if (u_hasEmissiveMap) {
            _emissive *= Texel(u_emissiveMap, uv).rgb;
        }

        vec3 _shaded = _lit + _ambient + _emissive;
    ]],

    fragmentMix = [[
        outColor.rgb = _shaded;
    ]],
}
