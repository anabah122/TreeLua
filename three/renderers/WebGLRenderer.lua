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
local Frustum   = require "math.frustum"
local ShaderLib = require "shader"
local getParticleShader = require "shader.particles"

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
    r._lineList    = {}
    r._particleList = {}
    r._clock = 0   -- seconds; particles derive state from this, not from dt accumulation elsewhere
    r._lightScratch = Color:new()
    r._depthScratch = {}
    r._frustum = Frustum:new()
    r._instanceScratch  = {}
    r._instanceComposed = {}

    -- three.js's flag of the same name; off draws everything
    r.frustumCulling = params.frustumCulling ~= false
    r._cameraPos = Vector3:new()

    -- World point the shadow camera centres its frustum on. three.js's
    -- CSM/shadow cameras follow the main camera automatically; this engine
    -- has one shadow map for one directional light, so the caller says what
    -- matters most (e.g. the player), defaulting to the origin.
    r.shadowTarget = params.shadowTarget or Vector3:new()

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

    -- Shadow pass state, built lazily on first use (see _shadowMapFor) so a
    -- scene with no castShadow light never allocates the canvas or compiles
    -- the depth shader.
    r._depthShader   = nil
    r._shadowCanvas  = nil
    r._shadowTarget  = Vector3:new()
    r._lightViewProj = Matrix4:new()
    r._noShadow      = love.graphics.newImage(blank)   -- u_shadowMap when unbound

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
    local static    = self._staticList
    local skinned   = self._skinnedList
    local lines     = self._lineList
    local particles = self._particleList
    for i = #static,    1, -1 do static[i]    = nil end
    for i = #skinned,   1, -1 do skinned[i]   = nil end
    for i = #lines,     1, -1 do lines[i]     = nil end
    for i = #particles, 1, -1 do particles[i] = nil end

    local directional, ambient, hemisphere = nil, nil, nil
    local extraDirectional = false

    local culled = 0

    scene:traverseVisible(function(obj)
        if obj.isLine and obj:isLine() and obj.geometry then
            lines[#lines + 1] = obj

        elseif obj.isParticleSystem and obj:isParticleSystem() then
            if obj.visible then particles[#particles + 1] = obj end

        elseif obj.isMesh and obj:isMesh() and obj.geometry then
            if obj.isSprite and obj:isSprite() then
                self:_billboard(obj)
            end

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

        elseif obj.isHemisphereLight and obj:isHemisphereLight() then
            -- brightest wins, same rule as directional -- the shader takes one
            if hemisphere == nil or obj.intensity > hemisphere.intensity then
                hemisphere = obj
            end
        end
    end)

    if extraDirectional and not self._warnedLights then
        print("[renderer] scene has several directional lights; " ..
              "the shader takes one, using the brightest")
        self._warnedLights = true
    end

    self.info.render.culled = culled

    return static, skinned, lines, particles, directional, ambient, hemisphere
end

-- A sprite always faces the camera: three.js overwrites its world rotation
-- with the camera's at render time, so the graph can still parent/move it
-- like any other object while the orientation itself never comes from the
-- object's own quaternion. Position and scale stay the object's own -- only
-- the rotation columns are replaced, straight from the camera's world matrix,
-- which is what "facing the camera" means (same basis, so the quad's local
-- +Z lines up with the camera's).
function WebGLRenderer:_billboard(sprite)
    local cm = self._billboardCameraMatrix
    if not cm then return end

    sprite:updateWorldMatrix(true, false)

    -- raw row-major slots throughout -- NOT :elements(), which transposes to
    -- three.js's column-major docs order and would read the wrong indices
    -- for both the translation and the camera's basis vectors
    local m = sprite.matrixWorld
    local px, py, pz = m[4], m[8], m[12]
    local sx = sprite.scale.x
    local sy = sprite.scale.y
    local sz = sprite.scale.z

    sprite.matrixWorld:set(
        cm[1] * sx, cm[2] * sy, cm[3]  * sz, px,
        cm[5] * sx, cm[6] * sy, cm[7]  * sz, py,
        cm[9] * sx, cm[10] * sy, cm[11] * sz, pz,
        0, 0, 0, 1
    )
end

-- ── uniforms ─────────────────────────────────────────────────────────────────

-- Frame-wide uniforms go to every variant that will be bound this frame, since
-- each is a separate program with its own uniform storage.
function WebGLRenderer:_sendLights(sh, directional, ambient, hemisphere)
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

    if hemisphere then
        local sky = self._lightScratch:copy(hemisphere.color):multiplyScalar(hemisphere.intensity)
        local up = Vector3:new():setFromMatrixPosition(hemisphere.matrixWorld):normalizeSelf()
        sh:send("u_hasHemi", true)
        sh:send("u_hemiSkyColor", { sky.r, sky.g, sky.b })
        sh:send("u_hemiGroundColor", {
            hemisphere.groundColor.r * hemisphere.intensity,
            hemisphere.groundColor.g * hemisphere.intensity,
            hemisphere.groundColor.b * hemisphere.intensity,
        })
        sh:send("u_hemiDir", { up.x, up.y, up.z })
    else
        sh:send("u_hasHemi", false)
    end
end

-- Frame-wide shadow uniforms: the map and the light's view-proj are the same
-- for every mesh, so they go out once per shader like the other lights.
-- u_hasShadow itself is sent per-mesh in _drawBucket (see there), since
-- `receiveShadow` is a per-object flag -- a mesh with it off must read as
-- fully lit even while the map and matrix stay bound for meshes that don't.
function WebGLRenderer:_sendShadowUniforms(sh, caster)
    local has = caster ~= nil and self._shadowCanvas ~= nil
    sh:send("u_shadowMap", has and self._shadowCanvas or self._noShadow)
    sh:send("u_lightViewProj", has and self._lightViewProj or Matrix4:new())
    sh:send("u_shadowBias", has and caster.shadow.bias or 0)
    -- PCF's sample offsets are in texels of the actual map, not a fixed guess
    local size = has and caster.shadow.mapSize or 1
    sh:send("u_shadowMapSize", { size, size })

    -- Global, not per-light: one game wants one softness everywhere. Clamped
    -- to what shader/parts/shadow.lua's loop actually supports.
    local settings = require "three.settings"
    local kernel = math.max(0, math.min(3, math.floor(settings.shadowSoftness)))
    sh:send("u_shadowKernel", kernel)
end

-- Frame-wide, like lights: one fog per scene, not per mesh.
function WebGLRenderer:_sendFog(sh, fog)
    if fog == nil then
        sh:send("u_hasFog", false)
        return
    end

    sh:send("u_hasFog", true)
    sh:send("u_fogColor", { fog.color.r, fog.color.g, fog.color.b })

    if fog.isFogExp2 and fog:isFogExp2() then
        sh:send("u_fogMode", 1)
        sh:send("u_fogDensity", fog.density)
        sh:send("u_fogNear", 0)
        sh:send("u_fogFar", 1)
    else
        sh:send("u_fogMode", 0)
        sh:send("u_fogNear", fog.near)
        sh:send("u_fogFar", fog.far)
        sh:send("u_fogDensity", 0)
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

    local nm = material.normalMap
    sh:send("u_hasNormalMap", nm ~= nil)
    sh:send("u_normalMap", nm or self._blankTexture)
    sh:send("u_normalScale", material.normalScale)

    local ao = material.aoMap
    sh:send("u_hasOcclusionMap", ao ~= nil)
    sh:send("u_occlusionMap", ao or self._blankTexture)
    sh:send("u_occlusionStrength", material.aoMapIntensity)

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
--
-- The sphere is expanded inline rather than through Frustum:intersectsObject
-- so the hot path allocates nothing per mesh per frame.
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
        local p = self._frustum.planes[i]
        local n = p.normal
        if n.x * cx + n.y * cy + n.z * cz + p.constant < -radius then
            return false
        end
    end

    return true
end

function WebGLRenderer:_updateFrustum(viewProj)
    self._frustum:setFromProjectionMatrix(viewProj)
    return self
end

-- The model matrices to draw this mesh at: one for an ordinary mesh, one per
-- instance for an InstancedMesh, each composed onto the object's own world
-- transform so a moved InstancedMesh carries its whole set with it.
--
-- The result table and its matrices are reused between meshes and frames, so
-- the common single-matrix case allocates nothing.
function WebGLRenderer:_instanceMatrices(mesh)
    local out = self._instanceScratch

    if not (mesh.isInstancedMesh and mesh:isInstancedMesh()) then
        out[1] = mesh.matrixWorld
        for i = #out, 2, -1 do out[i] = nil end
        return out
    end

    for i = #out, mesh.count + 1, -1 do out[i] = nil end

    for i = 1, mesh.count do
        local composed = self._instanceComposed[i]
        if not composed then
            composed = Matrix4:new()
            self._instanceComposed[i] = composed
        end

        composed:multiplyMatrices(mesh.matrixWorld, mesh.instanceMatrix[i])
        out[i] = composed
    end

    return out
end

function WebGLRenderer:_drawBucket(bucket, variant, override, state, info, hasShadowMap)
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

            if variant == "skinned" then self:_sendSkin(sh, mesh) end
            local tex = self:_sendMaterial(sh, material)
            sh:send("u_hasShadow", hasShadowMap and mesh.receiveShadow)

            -- the love.Mesh carries its own texture, so an unset map means
            -- unbinding rather than just muting the sample
            geometry.mesh:setTexture(tex)

            local instances = self:_instanceMatrices(mesh)

            for _, model in ipairs(instances) do
                sh:send("u_model", model)
                love.graphics.draw(geometry.mesh)
                info.calls = info.calls + 1
            end

            info.meshes = info.meshes + 1
            if geometry.indices then
                info.triangles = info.triangles + #geometry.indices / 3 * #instances
            end
        end
    end

    return self
end

-- Draw every Line/LineSegments, unlit and shaderless.
--
-- LÖVE has no GL_LINES mesh mode, so each point is projected to screen space
-- on the CPU (Camera:worldToScreen, the same math the shader's u_viewProj
-- would do) and drawn with love.graphics.line. A world-space polyline of a
-- few dozen points costs nothing this way and needs no shader variant.
function WebGLRenderer:_drawLines(bucket, camera)
    if #bucket == 0 then return self end

    local width, height = love.graphics.getDimensions()
    local screen = self._lineScratch or {}
    self._lineScratch = screen

    for _, line in ipairs(bucket) do
        local material = line.material
        local geometry = line.geometry
        if material and material.visible and geometry and #geometry.points > 0 then
            line:updateWorldMatrix(true, false)

            for i = #screen, 1, -1 do screen[i] = nil end
            local anyVisible = false
            for _, p in ipairs(geometry.points) do
                local world = p:clone():applyMatrix4(line.matrixWorld)
                local sx, sy, visible = camera:worldToScreen(world, width, height)
                screen[#screen + 1] = sx
                screen[#screen + 1] = sy
                if visible then anyVisible = true end
            end

            if anyVisible then
                local c = material.color
                love.graphics.setColor(c.r, c.g, c.b, material.opacity)
                love.graphics.setLineWidth(material.linewidth)

                if line.isLineSegments and line:isLineSegments() then
                    for i = 1, #screen - 3, 4 do
                        love.graphics.line(screen[i], screen[i + 1], screen[i + 2], screen[i + 3])
                    end
                else
                    love.graphics.line(screen)
                end

                self.info.render.calls = self.info.render.calls + 1
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)

    return self
end

-- Draw every ParticleSystem: one shared unlit billboard shader, one
-- drawInstanced call per system.
--
-- There is no per-particle CPU work here -- shader/particles.lua derives
-- every particle's position/size/color from (a_seed, u_time, the emitter's
-- own uniforms) in the vertex stage, so this method only sets the emitter's
-- uniforms once and issues one instanced draw of the shared unit quad.
function WebGLRenderer:_drawParticles(bucket, camera)
    if #bucket == 0 then return self end

    local sh = getParticleShader()
    love.graphics.setShader(sh)
    love.graphics.setBlendMode("add", "alphamultiply")
    love.graphics.setDepthMode("lequal", false)   -- test against the scene, don't occlude each other

    sh:send("u_viewProj", self._viewProj)

    -- billboard basis: the camera's own right/up, read straight off its world
    -- matrix so every particle faces the camera without a per-particle
    -- lookAt -- same trick as WebGLRenderer:_billboard for Sprite.
    local cm = camera.matrixWorld
    sh:send("u_cameraRight", { cm[1], cm[5], cm[9] })
    sh:send("u_cameraUp",    { cm[2], cm[6], cm[10] })

    for _, ps in ipairs(bucket) do
        sh:send("u_model", ps.matrixWorld)
        sh:send("u_time", self._clock)
        sh:send("u_lifetime", ps.lifetime)

        sh:send("u_spawnShape", ps.spawnShape)
        sh:send("u_spawnRadius", ps.spawnRadius)
        sh:send("u_coneAngle", ps.coneAngle)

        sh:send("u_speedMin", ps.speedMin)
        sh:send("u_speedMax", ps.speedMax)
        sh:send("u_direction", { ps.direction.x, ps.direction.y, ps.direction.z })
        sh:send("u_gravity", { ps.gravity.x, ps.gravity.y, ps.gravity.z })

        sh:send("u_sizeStart", ps.sizeStart)
        sh:send("u_sizeEnd", ps.sizeEnd)

        sh:send("u_colorStart", { ps.colorStart.r, ps.colorStart.g, ps.colorStart.b, ps.opacityStart })
        sh:send("u_colorEnd",   { ps.colorEnd.r,   ps.colorEnd.g,   ps.colorEnd.b,   ps.opacityEnd })

        sh:send("u_burst", ps.burst)
        sh:send("u_cycleDuration", ps.cycleDuration)
        sh:send("u_riseFraction", ps.riseFraction)
        sh:send("u_sustainFraction", ps.sustainFraction)
        sh:send("u_decayFraction", ps.decayFraction)

        -- sampler must stay bound to something even when unused, same reason
        -- as _sendMaterial's blank texture: a driver may sample both branches
        sh:send("u_hasMap", ps.map ~= nil)
        sh:send("u_map", ps.map or self._blankTexture)

        sh:send("u_isMesh", ps.shape ~= "billboard")
        sh:send("u_rotationSpeed", ps.rotationSpeed)

        love.graphics.drawInstanced(ps._mesh, ps.count)
        self.info.render.calls = self.info.render.calls + 1
    end

    love.graphics.setDepthMode()
    love.graphics.setBlendMode("alpha")
    love.graphics.setShader()

    return self
end

-- The shadow-casting light for this frame, or nil. Mirrors _collect's
-- brightest-directional-wins rule for the main light, so the same light that
-- lights the scene is the one that shadows it.
function WebGLRenderer:_shadowCaster(directional)
    if directional and directional.castShadow then return directional end
    return nil
end

-- Render the scene's depth from `light`'s point of view into a square canvas,
-- filling self._lightViewProj (for the main pass to sample with) and
-- self._shadowCanvas (the depth-as-color texture, see shader/depth.lua).
--
-- Only castShadow meshes are drawn here -- a shadow only needs to know what
-- can OCCLUDE, not what receives, so this walk is usually much smaller than
-- the main scene traversal.
function WebGLRenderer:_renderShadowMap(scene, light, focus)
    local size = light.shadow.mapSize
    if not self._shadowCanvas or self._shadowCanvas:getWidth() ~= size then
        self._shadowCanvas = love.graphics.newCanvas(size, size, { format = "r32f" })
    end

    local getDepthShader = require "shader.depth"
    local staticShader, skinnedShader = getDepthShader(false), getDepthShader(true)

    local cam = light:updateShadowCamera(self._shadowTarget:copy(focus))
    cam:updateMatrixWorld(true)
    cam.matrixWorldInverse:copy(cam.matrixWorld):invert()
    cam:viewProjectionMatrix(self._lightViewProj)

    love.graphics.setCanvas(self._shadowCanvas)
    love.graphics.clear(1, 1, 1, 1)   -- far plane: nothing is closer than this
    love.graphics.setDepthMode("lequal", true)
    staticShader:send("u_viewProj", self._lightViewProj)
    skinnedShader:send("u_viewProj", self._lightViewProj)

    scene:traverseVisible(function(obj)
        if obj.isMesh and obj:isMesh() and obj.geometry and obj.geometry.mesh
           and obj.castShadow then
            local skinned = self:_isSkinned(obj)
            local sh = skinned and skinnedShader or staticShader

            love.graphics.setShader(sh)
            sh:send("u_model", obj.matrixWorld)
            if skinned then self:_sendSkin(sh, obj) end

            love.graphics.draw(obj.geometry.mesh)
        end
    end)

    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.setDepthMode()

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

-- `renderTarget`, if given, is whatever love.graphics.setCanvas accepts: a
-- single canvas, or a MRT table like { sceneCanvas, brightCanvas, depth =
-- true }. Every part/particle shader writes love_Canvases[0] (lit colour) and
-- love_Canvases[1] (bloom's bright-pass source) unconditionally -- LÖVE simply
-- drops the second write when only one canvas is bound, so this needs no
-- separate code path for "no post-processing". Omit it to draw straight to
-- the screen, same as before EffectComposer existed.
function WebGLRenderer:render(scene, camera, renderTarget)
    local info = self.info.render
    info.calls, info.triangles, info.meshes = 0, 0, 0
    info.shaderSwaps = 0

    -- particles' clock: love.timer.getTime() rather than an accumulated dt,
    -- so pausing/resuming the game loop cannot drift it out of sync with
    -- anything else that reads the same clock
    self._clock = love.timer.getTime()

    -- world matrices first: everything below reads matrixWorld
    if self.autoUpdateScene then scene:updateMatrixWorld(false) end
    if camera.parent == nil then camera:updateMatrixWorld(false) end
    camera.matrixWorldInverse:copy(camera.matrixWorld):invert()
    self._billboardCameraMatrix = camera.matrixWorld

    -- Camera state before collecting: _collect culls against the frustum and
    -- the sort needs the eye position, so both have to be current first.
    camera:viewProjectionMatrix(self._viewProj)
    camera:getWorldPosition(self._cameraPos)
    local eye = { self._cameraPos.x, self._cameraPos.y, self._cameraPos.z }

    if self.frustumCulling then self:_updateFrustum(self._viewProj) end

    local staticDraws, skinnedDraws, lineDraws, particleDraws, directional, ambient, hemisphere = self:_collect(scene)

    -- The shadow pass renders to its own canvas and must finish (and restore
    -- the real canvas/shader/depth state) before anything below touches the
    -- screen -- hence doing it here, after collecting but before the clear
    -- that would otherwise be undone by _renderShadowMap's own setCanvas.
    local caster = self:_shadowCaster(directional)
    if caster then
        self:_renderShadowMap(scene, caster, self.shadowTarget)
    end

    love.graphics.setCanvas(renderTarget)
    if self.autoClear then self:clear(scene) end

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
        self:_sendLights(sh, directional, ambient, hemisphere)
        self:_sendShadowUniforms(sh, caster)
        self:_sendFog(sh, scene.fog)
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

    local hasShadowMap = caster ~= nil and self._shadowCanvas ~= nil

    -- Static first, then skinned: each program binds once for the whole frame.
    self:_drawBucket(staticDraws,  "static",  override, state, info, hasShadowMap)
    self:_drawBucket(skinnedDraws, "skinned", override, state, info, hasShadowMap)

    love.graphics.setShader()
    love.graphics.setMeshCullMode("none")
    love.graphics.setDepthMode()

    -- Particles draw after the opaque/skinned pass but before lines, so they
    -- occlude against the depth buffer already written (smoke behind a wall
    -- stays hidden) while gizmos still land on top of everything.
    self:_drawParticles(particleDraws, camera)

    -- Lines draw last, screen-projected and depth-untested -- gizmos/debug
    -- overlays are meant to read on top of the scene, as in three.js's
    -- typical usage (helpers added with no depth write).
    self:_drawLines(lineDraws, camera)

    love.graphics.setCanvas()

    return self
end

function WebGLRenderer:dispose()
    self.shader = nil
    self._shaders = {}
    return self
end

return WebGLRenderer
