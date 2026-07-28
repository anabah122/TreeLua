-- three/renderers/WebGLRenderer.lua — draws a scene from a camera
--
--   local renderer = WebGLRenderer:new()
--   function love.draw() renderer:render(scene, camera) end
--
-- The name is three.js's, kept so the docs read across; there is no WebGL
-- here, LÖVE's own renderer does the work. This class is the only place that
-- touches love.graphics, which is the point: main.lua used to set depth mode,
-- cull mode, shader and light uniforms by hand.
--
-- Shaders come from shader/init.lua, which assembles variants out of
-- parts. There are two: skinned and static. The split is not cosmetic -- a
-- 128-bone array is 2048 vertex uniform components, and a static mesh has no
-- reason to declare it. `render` groups draws so each variant is bound once.
--
-- The shader takes ONE directional light and ONE ambient term. A scene with
-- more gets the brightest directional and the sum of the ambients, and says so
-- once rather than silently dropping the rest.

local Matrix4   = require "math.mat4"
local Color     = require "math.color"
local Vector3   = require "math.vec3"
local ShaderLib = require "shader"

local WebGLRenderer = {}
WebGLRenderer.__index = WebGLRenderer

-- must match MAX_BONES in shader/parts/skinning.lua
WebGLRenderer.MAX_BONES = 128

function WebGLRenderer:new(params)
    params = params or {}

    local r = setmetatable({}, WebGLRenderer)
    r.type = "WebGLRenderer"

    -- A caller can still force one shader for everything; otherwise the
    -- variant is picked per mesh.
    r.shader = params.shader

    r._shaders = {
        static  = r.shader or ShaderLib:get{ skinning = false },
        skinned = r.shader or ShaderLib:get{ skinning = true  },
    }

    -- three.js clears by default; the scene's background overrides this
    r.autoClear      = params.autoClear ~= false
    r.clearColor     = Color:new(params.clearColor or 0x171a21)
    r.clearAlpha     = params.clearAlpha == nil and 1 or params.clearAlpha

    r.sortObjects    = params.sortObjects ~= false
    r.autoUpdateScene = params.autoUpdateScene ~= false

    -- How far the diffuse terminator wraps past 90 degrees, 0 being physically
    -- strict and 1 flat. With one light and no global illumination, strict
    -- lighting leaves whole limbs black; 0.25 matches what the engine's
    -- original lambert shader baked in. Set to 0 for a strict PBR look.
    r.diffuseWrap = params.diffuseWrap or 0.25

    -- scratch, reused every frame so a draw allocates nothing
    r._viewProj = Matrix4:new()
    -- one bucket per shader variant, refilled each frame
    r._staticList  = {}
    r._skinnedList = {}
    r._lightScratch = Color:new()
    r._depthScratch = {}
    r._frustum = {}
    for i = 1, 6 do r._frustum[i] = { 0, 0, 0, 0 } end

    -- three.js's flag of the same name; off draws everything
    r.frustumCulling = params.frustumCulling ~= false
    r._cameraPos = Vector3:new()

    -- A 1x1 white pixel for sampler uniforms with nothing bound to them.
    --
    -- LOVE does supply a default for a uniform that was never sent, so this is
    -- not about avoiding a crash. It is about the branch: u_hasMRMap and
    -- friends are bools, and a GPU commonly evaluates BOTH sides of a fragment
    -- branch and discards the unused one, so Texel(u_mrMap, uv) is sampled
    -- even when the flag is false. Pointing every sampler at a known white
    -- texel makes that read harmless and identical everywhere, instead of
    -- depending on whatever the driver left bound.
    local blank = love.image.newImageData(1, 1)
    blank:setPixel(0, 0, 1, 1, 1, 1)
    r._blankTexture = love.graphics.newImage(blank)

    r.info = { render = {
        calls = 0, triangles = 0, meshes = 0, culled = 0, shaderSwaps = 0,
    } }

    r._warnedBones  = {}
    r._warnedLights = false

    return r
end

function WebGLRenderer:isWebGLRenderer()
    return true
end

function WebGLRenderer:setClearColor(color, alpha)
    self.clearColor:set(color)
    if alpha ~= nil then self.clearAlpha = alpha end
    return self
end

function WebGLRenderer:getSize()
    return love.graphics.getWidth(), love.graphics.getHeight()
end

-- three.js sizes a canvas here. LÖVE owns the window, so this only keeps a
-- perspective camera's aspect honest -- call it from love.resize.
function WebGLRenderer:setSize(width, height, camera)
    if camera and camera.setAspect then
        camera:setAspect(width / height)
    end
    return self
end

-- ── traversal ────────────────────────────────────────────────────────────────

-- One walk collects both drawables and lights: two walks would cost twice for
-- no benefit, since neither depends on the other's result.
--
-- Drawables land in two buckets rather than one list, split by which shader
-- variant they need. Drawing static then skinned binds each program once, with
-- no sort: bucketing during the walk is O(n) and the walk happens anyway,
-- where sorting the combined list would cost O(n log n) every frame to
-- rediscover a split already known here.
function WebGLRenderer:_collect(scene)
    local static  = self._staticList
    local skinned = self._skinnedList
    for i = #static,  1, -1 do static[i]  = nil end
    for i = #skinned, 1, -1 do skinned[i] = nil end

    local directional, ambient = nil, nil
    local extraDirectional = false

    local culled = 0

    scene:traverseVisible(function(obj)
        if obj.isMesh and obj:isMesh() and obj.geometry then
            if self:_isSkinned(obj) then
                -- skinned bounds describe the bind pose, which an animation
                -- routinely leaves; see _inFrustum
                skinned[#skinned + 1] = obj
            elseif not self.frustumCulling or self:_inFrustum(obj) then
                static[#static + 1] = obj
            else
                culled = culled + 1
            end

        elseif obj.isDirectionalLight and obj:isDirectionalLight() then
            if directional == nil then
                directional = obj
            else
                extraDirectional = true
                -- keep the brighter of the two, so the choice is at least
                -- predictable rather than depending on graph order
                if obj.intensity > directional.intensity then directional = obj end
            end

        elseif obj.isAmbientLight and obj:isAmbientLight() then
            if ambient == nil then
                ambient = self._lightScratch:copy(obj.color):multiplyScalar(obj.intensity)
            else
                ambient:add(self._lightScratch:copy(obj.color):multiplyScalar(obj.intensity))
            end
        end
    end)

    if extraDirectional and not self._warnedLights then
        print("[renderer] scene has several directional lights; " ..
              "the shader takes one, using the brightest")
        self._warnedLights = true
    end

    self.info.render.culled = culled

    return static, skinned, directional, ambient
end

-- ── uniforms ─────────────────────────────────────────────────────────────────

-- Frame-wide uniforms go to every variant that will be bound this frame, since
-- each is a separate program with its own uniform storage.
function WebGLRenderer:_sendLights(sh, directional, ambient)
    if directional then
        local dir = directional:direction()
        local col = Color:new():copy(directional.color):multiplyScalar(directional.intensity)
        sh:send("u_lightDir",   { dir.x, dir.y, dir.z })
        sh:send("u_lightColor", { col.r, col.g, col.b })
    else
        -- no light in the scene: kill the diffuse term rather than leaving
        -- whatever the last frame sent
        sh:send("u_lightDir",   { 0, -1, 0 })
        sh:send("u_lightColor", { 0, 0, 0 })
    end

    if ambient then
        sh:send("u_ambient", { ambient.r, ambient.g, ambient.b })
    else
        sh:send("u_ambient", { 0, 0, 0 })
    end
end

function WebGLRenderer:_sendMaterial(sh, material)
    local tex = material.map
    sh:send("u_baseColor",  material:baseColorArray())
    sh:send("u_hasTexture", tex ~= nil)

    sh:send("u_metalness", material.metalness)
    sh:send("u_roughness", material.roughness)

    local e, i = material.emissive, material.emissiveIntensity
    sh:send("u_emissive", { e.r * i, e.g * i, e.b * i })

    -- Sampler uniforms cannot be left dangling: a shader that declares an Image
    -- still samples it even behind a false flag on some drivers, so both are
    -- always bound and the flag decides whether the result is used.
    local mr = material.metalnessMap or material.roughnessMap
    sh:send("u_hasMRMap", mr ~= nil)
    sh:send("u_mrMap", mr or self._blankTexture)

    local em = material.emissiveMap
    sh:send("u_hasEmissiveMap", em ~= nil)
    sh:send("u_emissiveMap", em or self._blankTexture)

    return tex
end

-- Does this mesh need the skinned variant? Asked before drawing, and again
-- when the palette is sent, so both agree on the answer.
function WebGLRenderer:_isSkinned(mesh)
    return mesh.isSkinnedMesh and mesh:isSkinnedMesh() and mesh.skeleton ~= nil
end

-- Bone palette for one mesh, clamped to what the shader declares. A longer
-- skeleton would read past the uniform array and tear the mesh apart, so it is
-- cut and reported once per mesh.
--
-- There is no u_skinned flag any more: a mesh that needs skinning is drawn with
-- the variant that has the bone array compiled in, and one that does not is
-- drawn with the variant that never declares it.
function WebGLRenderer:_sendSkin(sh, mesh)
    local pal = mesh:palette()
    if not pal or #pal == 0 then return false end

    if #pal > WebGLRenderer.MAX_BONES then
        if not self._warnedBones[mesh.id] then
            print(("[renderer] %s has %d bones, shader supports %d")
                :format(tostring(mesh.name ~= "" and mesh.name or mesh.id),
                        #pal, WebGLRenderer.MAX_BONES))
            self._warnedBones[mesh.id] = true
        end
        for i = WebGLRenderer.MAX_BONES + 1, #pal do pal[i] = nil end
    end

    sh:send("u_bones", unpack(pal))
    return true
end

-- ── drawing ──────────────────────────────────────────────────────────────────

local SIDE_TO_CULL = {
    front  = "back",
    back   = "front",
    double = "none",
}

-- Distance from the camera to a mesh's origin, squared -- the square root
-- would not change any ordering. Cached on the mesh for the frame so the sort
-- comparator does not recompute it on every comparison.
function WebGLRenderer:_depthSort(mesh)
    local e = mesh.matrixWorld:elements()
    local dx = e[13] - self._cameraPos.x
    local dy = e[14] - self._cameraPos.y
    local dz = e[15] - self._cameraPos.z
    return dx * dx + dy * dy + dz * dz
end

function WebGLRenderer:_sortBucket(bucket)
    if #bucket < 2 then return self end

    local depth = self._depthScratch
    for i = #bucket, 1, -1 do depth[bucket[i]] = nil end
    for _, mesh in ipairs(bucket) do depth[mesh] = self:_depthSort(mesh) end

    table.sort(bucket, function(a, b)
        if a.renderOrder ~= b.renderOrder then
            return a.renderOrder < b.renderOrder
        end

        local at = a.material and a.material.transparent or false
        local bt = b.material and b.material.transparent or false
        if at ~= bt then return bt end

        local da, db = depth[a], depth[b]
        if da ~= db then
            -- transparent draws far-to-near, opaque near-to-far
            if at then return da > db end
            return da < db
        end

        return a.id < b.id
    end)

    return self
end

-- Is any part of this mesh inside the view frustum?
--
-- Tested against the geometry's bounding sphere pushed into world space, which
-- is one dot product per plane. A sphere is a loose fit for a long thin mesh,
-- so this errs toward drawing -- a false positive costs a draw call, a false
-- negative would pop geometry out of view.
--
-- Skinned meshes are exempt: their bounds are the BIND pose, and an animation
-- routinely swings limbs outside it, so testing that box would cull a
-- character mid-stride.
function WebGLRenderer:_inFrustum(mesh)
    if not mesh.frustumCulled then return true end

    local geometry = mesh.geometry
    local sphere = geometry.boundingSphere or geometry:computeBoundingSphere()
    if not sphere then return true end

    local e = mesh.matrixWorld:elements()

    -- world-space centre
    local c = sphere.center
    local cx = e[1] * c.x + e[5] * c.y + e[ 9] * c.z + e[13]
    local cy = e[2] * c.x + e[6] * c.y + e[10] * c.z + e[14]
    local cz = e[3] * c.x + e[7] * c.y + e[11] * c.z + e[15]

    -- the largest axis scale, so a scaled mesh is not clipped early
    local sx = e[1] * e[1] + e[2] * e[2] + e[ 3] * e[ 3]
    local sy = e[5] * e[5] + e[6] * e[6] + e[ 7] * e[ 7]
    local sz = e[9] * e[9] + e[10] * e[10] + e[11] * e[11]
    local radius = sphere.radius * math.sqrt(math.max(sx, sy, sz))

    for i = 1, 6 do
        local p = self._frustum[i]
        if p[1] * cx + p[2] * cy + p[3] * cz + p[4] < -radius then
            return false
        end
    end

    return true
end

-- Extract the six frustum planes from the view-projection matrix (Gribb-
-- Hartmann): each plane is a sum or difference of two rows, normalised so the
-- plane equation yields a true signed distance.
function WebGLRenderer:_updateFrustum(viewProj)
    local m = viewProj
    local planes = self._frustum

    -- row-major storage: m[1..4] is row 1, m[13..16] is row 4
    local r1 = { m[1],  m[2],  m[3],  m[4]  }
    local r2 = { m[5],  m[6],  m[7],  m[8]  }
    local r3 = { m[9],  m[10], m[11], m[12] }
    local r4 = { m[13], m[14], m[15], m[16] }

    local function setPlane(idx, a, b, sign)
        local p = planes[idx]
        for k = 1, 4 do p[k] = a[k] + sign * b[k] end

        local len = math.sqrt(p[1] * p[1] + p[2] * p[2] + p[3] * p[3])
        if len > 0 then
            for k = 1, 4 do p[k] = p[k] / len end
        end
    end

    setPlane(1, r4, r1,  1)   -- left
    setPlane(2, r4, r1, -1)   -- right
    setPlane(3, r4, r2,  1)   -- bottom
    setPlane(4, r4, r2, -1)   -- top
    setPlane(5, r4, r3,  1)   -- near
    setPlane(6, r4, r3, -1)   -- far

    return self
end

function WebGLRenderer:_drawBucket(bucket, variant, override, state, info)
    for _, mesh in ipairs(bucket) do
        local material = override or mesh.material
        local geometry = mesh.geometry

        if material and material.visible and geometry and geometry.mesh then
            local cull = SIDE_TO_CULL[material.side] or "back"
            if cull ~= state.cull then
                love.graphics.setMeshCullMode(cull)
                state.cull = cull
            end

            local sh = self.shader or self._shaders[variant]
            if sh ~= state.shader then
                love.graphics.setShader(sh)
                state.shader = sh
                info.shaderSwaps = info.shaderSwaps + 1
            end

            sh:send("u_model", mesh.matrixWorld)
            if variant == "skinned" then self:_sendSkin(sh, mesh) end
            local tex = self:_sendMaterial(sh, material)

            -- the love.Mesh carries its own texture, so an unset map means
            -- unbinding rather than just muting the sample
            geometry.mesh:setTexture(tex)

            love.graphics.draw(geometry.mesh)

            info.calls  = info.calls + 1
            info.meshes = info.meshes + 1
            if geometry.indices then
                info.triangles = info.triangles + #geometry.indices / 3
            end
        end
    end

    return self
end

function WebGLRenderer:clear(scene)
    local bg = scene and scene.background
    if bg then
        love.graphics.clear(bg.r, bg.g, bg.b, 1)
    else
        love.graphics.clear(self.clearColor.r, self.clearColor.g,
                            self.clearColor.b, self.clearAlpha)
    end
    return self
end

function WebGLRenderer:render(scene, camera)
    local info = self.info.render
    info.calls, info.triangles, info.meshes = 0, 0, 0
    info.shaderSwaps = 0

    -- world matrices first: everything below reads matrixWorld
    if self.autoUpdateScene then scene:updateMatrixWorld(false) end
    if camera.parent == nil then camera:updateMatrixWorld(false) end
    camera.matrixWorldInverse:copy(camera.matrixWorld):invert()

    if self.autoClear then self:clear(scene) end

    -- Camera state before collecting: _collect culls against the frustum and
    -- the sort needs the eye position, so both have to be current first.
    camera:viewProjectionMatrix(self._viewProj)
    camera:getWorldPosition(self._cameraPos)
    local eye = { self._cameraPos.x, self._cameraPos.y, self._cameraPos.z }

    if self.frustumCulling then self:_updateFrustum(self._viewProj) end

    local staticDraws, skinnedDraws, directional, ambient = self:_collect(scene)

    love.graphics.setDepthMode("lequal", true)

    -- Each variant is a separate program with its own uniform storage, so the
    -- frame-wide values go to both. Two shaders' worth of sends per frame is
    -- nothing against per-draw cost, and it keeps the draw loop from having to
    -- track which variant has been primed.
    for _, sh in pairs(self._shaders) do
        sh:send("u_viewProj", self._viewProj)
        -- the specular lobe depends on where it is viewed from
        sh:send("u_cameraPos", eye)
        sh:send("u_diffuseWrap", self.diffuseWrap)
        self:_sendLights(sh, directional, ambient)
    end

    -- Order within a bucket: renderOrder first, then opaque before transparent
    -- so blending composites onto a finished background, then by distance --
    -- near-to-far for opaque, which lets the depth test reject occluded
    -- fragments before they are shaded, and far-to-near for transparent, where
    -- blending demands it. Ties break on id so the order is stable frame to
    -- frame.
    if self.sortObjects then
        self:_sortBucket(staticDraws)
        self:_sortBucket(skinnedDraws)
    end

    local override = scene.overrideMaterial
    local state = { cull = nil, shader = nil }

    -- Static first, then skinned: each program binds once for the whole frame.
    self:_drawBucket(staticDraws,  "static",  override, state, info)
    self:_drawBucket(skinnedDraws, "skinned", override, state, info)

    love.graphics.setShader()
    love.graphics.setMeshCullMode("none")
    love.graphics.setDepthMode()

    return self
end

function WebGLRenderer:dispose()
    self.shader = nil
    self._shaders = {}
    return self
end

return WebGLRenderer
