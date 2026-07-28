-- three/animation/PoseAccumulator.lua — weighted blend of several clips
--
-- Used by AnimationMixer. Each running action evaluates its tracks into this,
-- scaled by weight; `commit` normalises and writes the result into the node
-- list, which is where the skinning palette reads from.
--
-- The importers never had to change for this. Both already split a clip into
-- per-node translation/rotation/scale tracks -- Collada's baked matrices are
-- decomposed on load -- and both expose `evaluate(track, time)`, which RETURNS
-- values rather than writing them. Only `sample` writes, and the mixer no
-- longer calls it. So blending is a layer above the samplers, not a rewrite of
-- them.
--
-- Translation and scale accumulate linearly. Rotations cannot: a component-wise
-- sum of quaternions is not a rotation, and normalising it afterwards still
-- skews the arc. They are folded in one at a time with slerp instead, each
-- against the running result at the weight it contributes -- which for two
-- actions is exactly a slerp between them, and for more is the standard
-- incremental approximation.
--
-- Sign matters there: q and -q are the same rotation but slerp between them
-- takes the long way round, so each incoming quaternion is flipped to the
-- hemisphere of what has accumulated so far.

local common = require "importer.common"

local PoseAccumulator = {}
PoseAccumulator.__index = PoseAccumulator

function PoseAccumulator:new()
    return setmetatable({
        type     = "PoseAccumulator",
        _nodes   = {},   -- node index -> { t, r, s, tw, rw, sw }
        _touched = {},   -- ordered node indices, so commit needs no pairs()
    }, PoseAccumulator)
end

function PoseAccumulator:isPoseAccumulator()
    return true
end

function PoseAccumulator:reset()
    for _, idx in ipairs(self._touched) do
        local slot = self._nodes[idx]
        slot.tw, slot.rw, slot.sw = 0, 0, 0
    end
    for i = #self._touched, 1, -1 do self._touched[i] = nil end
    return self
end

-- Slots are kept between frames so a steady set of actions allocates nothing.
function PoseAccumulator:_slot(index)
    local slot = self._nodes[index]

    if not slot then
        slot = { t = { 0, 0, 0 }, r = { 0, 0, 0, 1 }, s = { 0, 0, 0 },
                 tw = 0, rw = 0, sw = 0 }
        self._nodes[index] = slot
    end

    if slot.tw == 0 and slot.rw == 0 and slot.sw == 0 then
        self._touched[#self._touched + 1] = index
    end

    return slot
end

function PoseAccumulator:addTranslation(index, v, weight)
    local slot = self:_slot(index)
    slot.t[1] = slot.t[1] + v[1] * weight
    slot.t[2] = slot.t[2] + v[2] * weight
    slot.t[3] = slot.t[3] + v[3] * weight
    slot.tw = slot.tw + weight
    return self
end

function PoseAccumulator:addScale(index, v, weight)
    local slot = self:_slot(index)
    slot.s[1] = slot.s[1] + v[1] * weight
    slot.s[2] = slot.s[2] + v[2] * weight
    slot.s[3] = slot.s[3] + v[3] * weight
    slot.sw = slot.sw + weight
    return self
end

function PoseAccumulator:addRotation(index, q, weight)
    local slot = self:_slot(index)
    local r = slot.r

    if slot.rw == 0 then
        r[1], r[2], r[3], r[4] = q[1], q[2], q[3], q[4]
        slot.rw = weight
        return self
    end

    local x, y, z, w = q[1], q[2], q[3], q[4]

    -- same rotation, opposite sign takes the long way round
    if r[1]*x + r[2]*y + r[3]*z + r[4]*w < 0 then
        x, y, z, w = -x, -y, -z, -w
    end

    slot.rw = slot.rw + weight
    r[1], r[2], r[3], r[4] = common.slerp(
        r[1], r[2], r[3], r[4], x, y, z, w, weight / slot.rw)

    return self
end

-- Write the blend into `nodes` and rebuild each touched local matrix.
--
-- A channel no track wrote keeps whatever the node already had, which is what
-- makes a clip that only animates rotation leave translation alone.
function PoseAccumulator:commit(nodes)
    for _, idx in ipairs(self._touched) do
        local node = nodes[idx]
        local slot = self._nodes[idx]

        if node then
            if slot.tw > 0 then
                local inv = 1 / slot.tw
                node.translation = { slot.t[1] * inv, slot.t[2] * inv, slot.t[3] * inv }
            end

            if slot.sw > 0 then
                local inv = 1 / slot.sw
                node.scale = { slot.s[1] * inv, slot.s[2] * inv, slot.s[3] * inv }
            end

            if slot.rw > 0 then
                local x, y, z, w = slot.r[1], slot.r[2], slot.r[3], slot.r[4]
                local len = math.sqrt(x*x + y*y + z*z + w*w)
                if len > 0 then
                    node.rotation = { x/len, y/len, z/len, w/len }
                end
            end

            node.localMatrix = common.compose(
                node.translation or { 0, 0, 0 },
                node.rotation    or { 0, 0, 0, 1 },
                node.scale       or { 1, 1, 1 })
            node.hasMatrix = false
        end

        -- zeroed here rather than in reset, so the next frame's _slot sees a
        -- clean slot without a second pass
        slot.t[1], slot.t[2], slot.t[3] = 0, 0, 0
        slot.s[1], slot.s[2], slot.s[3] = 0, 0, 0
        slot.tw, slot.rw, slot.sw = 0, 0, 0
    end

    for i = #self._touched, 1, -1 do self._touched[i] = nil end

    return nodes
end

return PoseAccumulator
