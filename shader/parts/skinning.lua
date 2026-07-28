-- shader/parts/skinning.lua — GPU vertex skinning
--
-- A shader part: GLSL grouped by the slot it fills, not split across files.
-- ShaderLib pastes each slot into the skeleton in shader/init.lua.
--
-- Skinning runs on the GPU because doing it per-vertex in Lua would cost more
-- than the whole frame budget on a 16k-vertex mesh.
--
-- This is the one part worth making OPTIONAL rather than always-on. The bone
-- array costs 16 floats per matrix, so 128 bones is 2048 vertex uniform
-- components -- against a desktop GL floor of 1024 guaranteed. A static mesh
-- that never skins should not declare it at all, which is why the renderer
-- compiles a variant without this part instead of branching on a uniform.

return {
    name = "skinning",

    -- MAX_BONES is bounded by the uniform component limit, not by taste.
    -- Every driver worth targeting exposes far more than the guaranteed floor,
    -- and the Mixamo rigs used here need 65. 128 leaves headroom; a rig larger
    -- than this needs a bone texture instead.
    vertexUniforms = [[
        #define MAX_BONES 128
        uniform mat4 u_bones[MAX_BONES];
        attribute vec4 VertexJoints;
        attribute vec4 VertexWeights;
    ]],

    -- Blend the four influencing bones into one matrix. Weights are
    -- pre-normalised by the importer, so this is a plain convex combination.
    vertexCalc = [[
        // int() truncates, so a joint index arriving as 20.9999 would silently
        // pick bone 20 and tear that part of the mesh off; round instead.
        ivec4 _joints = ivec4(VertexJoints + 0.5);

        mat4 _skin = VertexWeights.x * u_bones[_joints.x]
                   + VertexWeights.y * u_bones[_joints.y]
                   + VertexWeights.z * u_bones[_joints.z]
                   + VertexWeights.w * u_bones[_joints.w];
    ]],

    -- Deform the vertex before the model transform runs.
    -- Rotating the normal by the skin matrix is only exact for rigid
    -- transforms; bones never scale here, so the shortcut holds.
    vertexMix = [[
        localPos = _skin * localPos;
        localNormal = mat3(_skin) * localNormal;
    ]],
}
