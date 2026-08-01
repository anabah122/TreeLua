-- importer/common.lua — shared scene/skeleton/animation machinery
--
-- Both the glTF and DAE importers produce the same node/skin/clip shapes, so
-- everything downstream (rendering, playback) works with either format.
--
--   common.compose(t, r, s)                 -> mat4 from translation/quat/scale
--   common.update_world(nodes, root)        -> fills node.worldMatrix
--   common.palette(nodes, skin, meshInv)    -> skinning matrices
--   common.slerp(...)                       -> shortest-arc quaternion blend
--   common.quat_from_matrix(m)              -> {x,y,z,w}
--   common.FORMAT / common.FORMAT_SKINNED   -> love vertex formats

local matClass = require "math.mat4"

local common = {}

-- ── vertex formats ───────────────────────────────────────────────────────────
-- Attributes are read in declaration order, so the vertex tables built by the
-- importers must interleave in exactly this order. No VertexColor: it is 2D
-- baggage that would only fatten every vertex.
common.FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
    { "VertexNormal",   "float", 3 },
}

common.FORMAT_SKINNED = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
    { "VertexNormal",   "float", 3 },
    { "VertexJoints",   "float", 4 },
    { "VertexWeights",  "float", 4 },
}

-- ── transforms ───────────────────────────────────────────────────────────────
-- Build a TRS matrix from translation + QUATERNION + scale.
--
-- mat4:setTransformationMatrix() takes euler angles; both glTF and DAE express
-- rotation as quaternions (or matrices we convert to quaternions), so the
-- matrix is composed directly here to avoid a silent euler misread.
function common.compose(t, r, s)
    t = t or {0,0,0}
    r = r or {0,0,0,1}
    s = s or {1,1,1}

    local x, y, z, w = r[1], r[2], r[3], r[4]
    local x2, y2, z2 = x+x, y+y, z+z
    local xx, xy, xz = x*x2, x*y2, x*z2
    local yy, yz, zz = y*y2, y*z2, z*z2
    local wx, wy, wz = w*x2, w*y2, w*z2

    local sx, sy, sz = s[1], s[2], s[3]

    local m = matClass:new()
    -- row-major, matching math/mat4.lua layout
    m[1],  m[2],  m[3],  m[4]  = (1-(yy+zz))*sx, (xy-wz)*sy,     (xz+wy)*sz,     t[1]
    m[5],  m[6],  m[7],  m[8]  = (xy+wz)*sx,     (1-(xx+zz))*sy, (yz-wx)*sz,     t[2]
    m[9],  m[10], m[11], m[12] = (xz-wy)*sx,     (yz+wx)*sy,     (1-(xx+yy))*sz, t[3]
    m[13], m[14], m[15], m[16] = 0, 0, 0, 1
    return m
end

-- Extract a quaternion from a rotation matrix (scale is divided out first).
-- DAE animates whole matrices, so tracks have to be converted back to TRS.
function common.decompose(m)
    -- column lengths give the scale
    local sx = math.sqrt(m[1]*m[1] + m[5]*m[5] + m[9]*m[9])
    local sy = math.sqrt(m[2]*m[2] + m[6]*m[6] + m[10]*m[10])
    local sz = math.sqrt(m[3]*m[3] + m[7]*m[7] + m[11]*m[11])

    -- a negative determinant means one axis is mirrored; fold it into X
    local det = m:determinant()
    if det < 0 then sx = -sx end

    local t = { m[4], m[8], m[12] }
    local s = { sx, sy, sz }

    local ix = sx ~= 0 and 1/sx or 0
    local iy = sy ~= 0 and 1/sy or 0
    local iz = sz ~= 0 and 1/sz or 0

    local r11, r12, r13 = m[1]*ix, m[2]*iy, m[3]*iz
    local r21, r22, r23 = m[5]*ix, m[6]*iy, m[7]*iz
    local r31, r32, r33 = m[9]*ix, m[10]*iy, m[11]*iz

    local trace = r11 + r22 + r33
    local qx, qy, qz, qw

    if trace > 0 then
        local k = 0.5 / math.sqrt(trace + 1)
        qw = 0.25 / k
        qx = (r32 - r23) * k
        qy = (r13 - r31) * k
        qz = (r21 - r12) * k
    elseif r11 > r22 and r11 > r33 then
        local k = 2 * math.sqrt(1 + r11 - r22 - r33)
        qw = (r32 - r23) / k
        qx = 0.25 * k
        qy = (r12 + r21) / k
        qz = (r13 + r31) / k
    elseif r22 > r33 then
        local k = 2 * math.sqrt(1 + r22 - r11 - r33)
        qw = (r13 - r31) / k
        qx = (r12 + r21) / k
        qy = 0.25 * k
        qz = (r23 + r32) / k
    else
        local k = 2 * math.sqrt(1 + r33 - r11 - r22)
        qw = (r21 - r12) / k
        qx = (r13 + r31) / k
        qy = (r23 + r32) / k
        qz = 0.25 * k
    end

    return t, { qx, qy, qz, qw }, s
end

-- ── hierarchy ────────────────────────────────────────────────────────────────
-- Walk the tree and fill node.worldMatrix.
-- Roots are seeded with `root` (or identity) so a model transform can be baked in.
function common.update_world(nodes, root)
    local function visit(idx, parentWorld)
        local node = nodes[idx]
        if not node then return end
        if parentWorld then
            node.worldMatrix = matClass:new():mul(parentWorld, node.localMatrix)
        else
            node.worldMatrix = node.localMatrix
        end
        for _, c in ipairs(node.children) do
            visit(c, node.worldMatrix)
        end
    end

    for i, node in ipairs(nodes) do
        if node.parent == nil then visit(i, root) end
    end
    return nodes
end

-- Per-frame skinning palette:  skinMatrix = jointWorld * inverseBind
-- Pass `meshWorldInverse` to cancel the mesh node's own transform.
function common.palette(nodes, skin, meshWorldInverse)
    local out = {}
    for k, node_idx in ipairs(skin.joints) do
        local jointWorld = nodes[node_idx] and nodes[node_idx].worldMatrix
        if jointWorld then
            local m = matClass:new():mul(jointWorld, skin.inverseBind[k])
            if meshWorldInverse then
                m = matClass:new():mul(meshWorldInverse, m)
            end
            out[k] = m
        else
            out[k] = matClass:new()
        end
    end
    return out
end

-- ── interpolation ────────────────────────────────────────────────────────────
function common.lerp(a, b, t) return a + (b - a) * t end

-- shortest-arc quaternion interpolation; linear blending of quats distorts
-- rotation speed and breaks down entirely past 90 degrees
function common.slerp(ax,ay,az,aw, bx,by,bz,bw, t)
    local cosom = ax*bx + ay*by + az*bz + aw*bw
    if cosom < 0 then
        cosom = -cosom
        bx, by, bz, bw = -bx, -by, -bz, -bw
    end
    local s0, s1
    if 1 - cosom > 1e-6 then
        local omega = math.acos(cosom)
        local sinom = math.sin(omega)
        s0 = math.sin((1 - t) * omega) / sinom
        s1 = math.sin(t * omega) / sinom
    else
        s0, s1 = 1 - t, t   -- nearly identical: fall back to linear
    end
    return ax*s0 + bx*s1, ay*s0 + by*s1, az*s0 + bz*s1, aw*s0 + bw*s1
end

-- Sampling rate a clip was baked at, recovered from its densest track.
-- Exporters disagree -- Blender writes glTF at 24, Mixamo's Collada at 30 --
-- so anything that counts frames rather than seconds needs this.
function common.clip_rate(clip)
    local keys = 0
    for _, t in ipairs(clip.tracks) do
        if #t.times > keys then keys = #t.times end
    end
    clip.frames = keys
    clip.fps = (keys > 1 and clip.duration > 0)
        and ((keys - 1) / clip.duration) or 0
    return clip
end

-- binary search: last keyframe index with times[i] <= t
function common.find_key(times, t)
    local lo, hi = 1, #times
    if hi == 0 then return nil end
    if t <= times[1] then return 1 end
    if t >= times[hi] then return hi end
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if times[mid] <= t then lo = mid else hi = mid - 1 end
    end
    return lo
end

-- ── skinning weights ─────────────────────────────────────────────────────────
-- Reduce an arbitrary-length influence list to the 4 the shader can take.
-- DAE allows any number per vertex, so the smallest are dropped and the
-- survivors renormalised (otherwise the mesh visibly shrinks toward origin).
function common.top4_weights(influences)
    table.sort(influences, function(a, b) return a.weight > b.weight end)

    local j = {0, 0, 0, 0}
    local w = {0, 0, 0, 0}
    local sum = 0

    for i = 1, math.min(4, #influences) do
        j[i] = influences[i].joint
        w[i] = influences[i].weight
        sum = sum + w[i]
    end

    if sum > 0 then
        for i = 1, 4 do w[i] = w[i] / sum end
    else
        j[1], w[1] = 0, 1   -- unweighted vertex: pin it to the first joint
    end

    return j, w
end

return common
