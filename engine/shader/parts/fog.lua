-- shader/parts/fog.lua — linear or exponential distance fog
--
-- Mirrors three.js's Fog/FogExp2: one blend toward u_fogColor by distance from
-- the camera. u_fogMode picks the falloff so both live behind one uniform set
-- rather than two shader variants -- a scene toggling Fog<->FogExp2 costs a
-- uniform send, not a recompile.
--
-- Runs after pbr in ALWAYS (shader/init.lua), so it mixes over the shaded
-- result rather than the raw base colour.

return {
    name = "fog",

    -- u_cameraPos already declared by shader/parts/pbr.lua, which runs first
    -- in ALWAYS -- redeclaring it here would be a duplicate uniform.
    fragmentUniforms = [[
        uniform bool  u_hasFog;
        uniform vec3  u_fogColor;
        uniform float u_fogNear;
        uniform float u_fogFar;
        uniform float u_fogDensity;
        uniform int   u_fogMode;   // 0 = linear, 1 = exp2
    ]],

    fragmentCalc = [[
        float _fogFactor = 0.0;
        if (u_hasFog) {
            float _fogDist = length(u_cameraPos - v_worldPos);
            if (u_fogMode == 1) {
                _fogFactor = 1.0 - exp(-u_fogDensity * u_fogDensity * _fogDist * _fogDist);
            } else {
                _fogFactor = (_fogDist - u_fogNear) / max(u_fogFar - u_fogNear, 1e-4);
            }
            _fogFactor = clamp(_fogFactor, 0.0, 1.0);
        }
    ]],

    fragmentMix = [[
        outColor.rgb = mix(outColor.rgb, u_fogColor, _fogFactor);
    ]],
}
