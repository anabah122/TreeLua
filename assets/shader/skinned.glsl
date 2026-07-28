// skinned.glsl — forward-lit shader with optional GPU skinning
//
// Skinning runs on the GPU because doing it per-vertex in Lua would cost more
// than the whole frame budget on a 16k-vertex mesh.
//
// MAX_BONES is bounded by the uniform component limit, not by taste: each
// mat4 costs 16 floats. Desktop GL guarantees 1024 vertex uniform components,
// but every driver worth targeting exposes far more, and the Mixamo rigs used
// here need 65. 128 leaves headroom without risking the guaranteed floor by
// much; a rig larger than this needs a bone texture instead.

#define MAX_BONES 128

uniform mat4 u_viewProj;
uniform mat4 u_model;
uniform mat4 u_bones[MAX_BONES];
uniform bool u_skinned;

uniform vec3 u_lightDir;
uniform vec3 u_lightColor;
uniform vec3 u_ambient;
uniform vec4 u_baseColor;
uniform bool u_hasTexture;

varying vec3 v_normal;

#ifdef VERTEX

attribute vec3 VertexNormal;
attribute vec4 VertexJoints;
attribute vec4 VertexWeights;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec4 pos = vec4(vertex_position.xyz, 1.0);
    vec3 nrm = VertexNormal;

    if (u_skinned) {
        // weights are pre-normalised by the importer, so this is a plain
        // convex combination of the four influencing bones
        // int() truncates, so a joint index arriving as 20.9999 would silently
        // pick bone 20 and tear that part of the mesh off; round instead.
        ivec4 j = ivec4(VertexJoints + 0.5);

        mat4 skin =
            VertexWeights.x * u_bones[j.x] +
            VertexWeights.y * u_bones[j.y] +
            VertexWeights.z * u_bones[j.z] +
            VertexWeights.w * u_bones[j.w];

        pos = skin * pos;
        // rotating the normal by the skin matrix is only exact for rigid
        // transforms; bones never scale here, so the shortcut holds
        nrm = mat3(skin) * nrm;
    }

    vec4 world = u_model * pos;
    v_normal = normalize(mat3(u_model) * nrm);

    return u_viewProj * world;
}

#endif

#ifdef PIXEL

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen)
{
    // `uv` and `tex` come from love: mesh:setTexture() binds the image and the
    // interpolated VertexTexCoord arrives here, so no varying of our own.
    vec4 base = u_baseColor;
    if (u_hasTexture) {
        base *= Texel(tex, uv);
    }

    vec3 n = normalize(v_normal);
    float ndl = max(dot(n, -normalize(u_lightDir)), 0.0);

    // wrap the diffuse term slightly so back faces stay readable instead of
    // going flat black
    float wrapped = ndl * 0.75 + 0.25;

    vec3 lit = base.rgb * (u_ambient + u_lightColor * wrapped);
    return vec4(lit, base.a) * color;
}

#endif
