-- class/model.lua — a loaded model with playback state
--
--   local m = Model:new("assets/model/x.glb", { scale = 1 })
--   m:update(dt)
--   m:draw(shader)
--
-- Wraps either importer so the caller never branches on file format: both
-- produce the same node/skin/clip shapes.

local common   = require "importer.common"
local matClass = require "math.mat4"

local Model = {}
Model.__index = Model

-- must match MAX_BONES in assets/shader/skinned.glsl
Model.MAX_BONES = 128

function Model:new(path, opts)
    opts = opts or {}
    local m = setmetatable({}, Model)

    local isDae = path:lower():match("%.dae$") ~= nil
    local loader = isDae and require "importer.dae" or require "importer.gltf"

    m.data = loader:load{ path = path, mesh = true, tex = opts.tex ~= false }
    m.animation = isDae and require "importer.dae.animation"
                        or  require "importer.gltf.animation"

    m.path     = path
    m.position = opts.position or { 0, 0, 0 }
    m.rotation = opts.rotation or { 0, 0, 0, 1 }
    m.scale    = opts.scale    or 1
    m.time     = 0
    m.speed    = opts.speed or 1
    m.loop     = opts.loop ~= false
    m.clip     = m.data.animations and m.data.animations[1] or nil

    -- Same motion exported twice rarely lands on the same length: Blender's
    -- glTF here is 8.083s at 24fps, Mixamo's Collada 8.100s at 30fps. Left
    -- alone the two drift apart over a few loops, so a clip can be told to
    -- play in a fixed wall-clock duration instead of its authored one.
    m.duration = opts.duration

    return m
end

-- Effective playback rate: `speed`, plus whatever it takes to stretch the
-- clip's authored length onto `duration` when one was requested.
function Model:rate()
    if self.duration and self.clip and self.clip.duration > 0 then
        return self.speed * (self.clip.duration / self.duration)
    end
    return self.speed
end

function Model:setClip(nameOrIndex)
    local clips = self.data.animations or {}
    if type(nameOrIndex) == "number" then
        self.clip = clips[nameOrIndex]
    else
        self.clip = self.animation.find(clips, nameOrIndex)
    end
    self.time = 0
    return self.clip ~= nil
end

-- model matrix, rebuilt each frame (cheap: one compose)
function Model:matrix()
    local s = self.scale
    return common.compose(self.position, self.rotation, { s, s, s })
end

function Model:update(dt)
    if not self.clip then return end
    self.time = self.time + dt * self:rate()

    self.animation.sample(self.clip, self.time, self.data.nodes, self.loop)
    common.update_world(self.data.nodes, self.data.nodes.rootMatrix)
end

-- Build the bone palette for one primitive.
--
-- The mesh node's own transform is NOT cancelled out here. Skinned vertices
-- already live in skeleton space, so jointWorld * inverseBind puts them where
-- they belong; folding in inverse(meshWorld) on top applies the node's scale a
-- second time, which blew this model up by 100x (its node carries scale 0.01).
function Model:palette(entry)
    if not entry.skin then return nil end

    local pal = common.palette(self.data.nodes, entry.skin)

    -- DAE puts the mesh into bind space with a separate matrix
    if entry.bindShapeMatrix then
        for i, mm in ipairs(pal) do
            pal[i] = matClass:new():mul(mm, entry.bindShapeMatrix)
        end
    end

    return pal
end

function Model:draw(shader, opts)
    opts = opts or {}
    shader:send("u_model", self:matrix())

    for _, entry in ipairs(self.data) do
        if entry.mesh then
            local pal = entry.skinned and self:palette(entry) or nil

            if pal then
                -- the shader array is fixed size; a longer skeleton would
                -- silently read garbage, so it is clamped and reported once
                if #pal > Model.MAX_BONES then
                    if not self._warned then
                        print(("[model] %s has %d bones, shader supports %d")
                            :format(self.path, #pal, Model.MAX_BONES))
                        self._warned = true
                    end
                    for i = Model.MAX_BONES + 1, #pal do pal[i] = nil end
                end
                shader:send("u_bones", unpack(pal))
                shader:send("u_skinned", true)
            else
                shader:send("u_skinned", false)
            end

            local mat = entry.material
            local tex = mat and mat.texture
            if opts.textured == false then tex = nil end

            shader:send("u_baseColor", mat and mat.baseColor or { 1, 1, 1, 1 })
            shader:send("u_hasTexture", tex ~= nil)

            -- the mesh carries its own texture, so toggling it off means
            -- unbinding rather than just muting the sample
            entry.mesh:setTexture(tex)

            love.graphics.draw(entry.mesh)
        end
    end
end

-- convenience: axis-aligned bounds of the raw geometry, for framing a camera
function Model:bounds()
    local lo = { math.huge, math.huge, math.huge }
    local hi = { -math.huge, -math.huge, -math.huge }
    for _, entry in ipairs(self.data) do
        for _, v in ipairs(entry.vertices) do
            for k = 1, 3 do
                if v[k] < lo[k] then lo[k] = v[k] end
                if v[k] > hi[k] then hi[k] = v[k] end
            end
        end
    end
    return lo, hi
end

return Model
