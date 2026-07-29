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
-- The shader takes up to MAX_LIGHTS directional/point/spot lights (brightest
-- win beyond the cap) plus the sum of every ambient. Up to MAX_SHADOWS of
-- those lights may cast a shadow simultaneously -- one 2D depth map each for
-- directional/spot, one 6-face cube map each for point, since an omni light
-- has no single view direction to project a flat map from.

local Matrix4   = require "math.mat4"
-- Cube face basis, needed by the shadow composite pass to reconstruct a
-- sample direction per face; required up here rather than inside the shadow
-- loop, which runs once per face per light per frame.
local PointLightFaces = require("three.lights.PointLight").FACES
local Color     = require "math.color"
local Vector3   = require "math.vec3"
local Frustum   = require "math.frustum"
local ShaderLib = require "shader"
local getParticleShader = require "shader.particles"

local WebGLRenderer = {}
WebGLRenderer.__index = WebGLRenderer

-- must match MAX_BONES in shader/parts/skinning.lua
WebGLRenderer.MAX_BONES = 128
-- must match MAX_LIGHTS in shader/parts/pbr.lua
WebGLRenderer.MAX_LIGHTS = 16
-- must match MAX_SHADOWS in shader/parts/shadow.lua
WebGLRenderer.MAX_SHADOWS = 4

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

    -- World point directional shadow cameras centre their frustum on (a
    -- directional light has no position that bounds its coverage, unlike
    -- point/spot). three.js's CSM follows the main camera automatically;
    -- here the caller says what matters most (e.g. the player), defaulting
    -- to the origin.
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

    -- Shadow pass state, built lazily on first use (see _renderShadowMaps) so
    -- a scene with no castShadow light never allocates a canvas. Indexed 1..
    -- MAX_SHADOWS, one slot per simultaneous caster; a slot holds either a 2D
    -- canvas+viewProj (directional/spot) or a cube canvas+far (point), never
    -- both, decided per-frame by the light at that slot.
    r._shadowTarget    = Vector3:new()
    r._shadow2DCanvas  = {}
    r._shadowCubeCanvas = {}
    -- Static/dynamic split: each caster slot's static layer (redrawn only
    -- when dirty) and dynamic layer (redrawn every frame) get merged into
    -- the working canvas above every frame -- see _renderShadowMaps.
    r._shadowStatic2DCanvas    = {}
    r._shadowDynamic2DCanvas   = {}
    r._shadowStaticCubeCanvas  = {}
    r._shadowDynamicCubeCanvas = {}
    r._shadowSlotSeen  = {}   -- which light last rendered into each caster slot
    r._shadowFaceViewProj = Matrix4:new()  -- scratch, cube faces reuse it
    r._shadowLastViewProj = {}  -- per slot: what the static layer was drawn with
    r._shadowLastLightPos = {}   -- per slot: where a point light was when its static layer was drawn
    r._shadowLightPosScratch = {}  -- per slot, so worldPosition allocates nothing per frame
    r._depthPosScratch = { 0, 0, 0 }  -- reused for the depth shaders' u_lightPos
    r._shadowFrustum = Frustum:new()  -- rebuilt per light (per cube face) to cull casters
    r._shadowDirScratch = Vector3:new()
    r._shadowViewProj  = {}
    for i = 1, WebGLRenderer.MAX_SHADOWS do r._shadowViewProj[i] = Matrix4:new() end
    r._noShadow2D   = love.graphics.newImage(blank)     -- u_shadowMap2D[i] when unbound
    r._noShadowCube = love.graphics.newCubeImage({ blank, blank, blank, blank, blank, blank })

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
-- Insert `light` into `lights` (a flat array, brightest first) if it still
-- fits under MAX_LIGHTS, otherwise displace the dimmest entry if `light` is
-- brighter than it. O(n) per light, n <= MAX_LIGHTS -- fine at this scale,
-- and simpler than a heap for a cap this small.
local function considerLight(lights, light)
    local max = WebGLRenderer.MAX_LIGHTS
    if #lights < max then
        lights[#lights + 1] = light
        return true
    end

    local dimmestIdx, dimmest = nil, math.huge
    for i, l in ipairs(lights) do
        if l.intensity < dimmest then dimmestIdx, dimmest = i, l.intensity end
    end
    if light.intensity > dimmest then
        lights[dimmestIdx] = light
        return true
    end
    return false
end

function WebGLRenderer:_collect(scene)
    local static    = self._staticList
    local skinned   = self._skinnedList
    local lines     = self._lineList
    local particles = self._particleList
    for i = #static,    1, -1 do static[i]    = nil end
    for i = #skinned,   1, -1 do skinned[i]   = nil end
    for i = #lines,     1, -1 do lines[i]     = nil end
    for i = #particles, 1, -1 do particles[i] = nil end

    local lights = self._lightList or {}
    self._lightList = lights
    for i = #lights, 1, -1 do lights[i] = nil end

    local ambient, hemisphere = nil, nil
    local droppedLights = false

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

        elseif (obj.isDirectionalLight and obj:isDirectionalLight())
            or (obj.isPointLight and obj:isPointLight())
            or (obj.isSpotLight and obj:isSpotLight()) then
            if not considerLight(lights, obj) then droppedLights = true end

        elseif obj.isAmbientLight and obj:isAmbientLight() then
            if ambient == nil then
                ambient = self._lightScratch:copy(obj.color):multiplyScalar(obj.intensity)
            else
                ambient:add(self._lightScratch:copy(obj.color):multiplyScalar(obj.intensity))
            end

        elseif obj.isHemisphereLight and obj:isHemisphereLight() then
            -- brightest wins, same rule as the main lights -- the shader
            -- takes one hemisphere term
            if hemisphere == nil or obj.intensity > hemisphere.intensity then
                hemisphere = obj
            end
        end
    end)

    if droppedLights and not self._warnedLights then
        print(("[renderer] scene has more than %d directional/point/spot lights; " ..
               "using the brightest %d"):format(WebGLRenderer.MAX_LIGHTS, WebGLRenderer.MAX_LIGHTS))
        self._warnedLights = true
    end

    self.info.render.culled = culled

    return static, skinned, lines, particles, lights, ambient, hemisphere
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

local LIGHT_TYPE = { directional = 0, point = 1, spot = 2 }

-- Frame-wide uniforms go to every variant that will be bound this frame, since
-- each is a separate program with its own uniform storage.
--
-- Every u_light* array is sent full-width (MAX_LIGHTS entries) each frame:
-- LOVE requires an exact-length array for a `send`, and padding with inert
-- entries (type -1, color 0) is simpler than tracking a previous frame's
-- count to know how many stale slots need clearing.
function WebGLRenderer:_sendLights(sh, lights, ambient, hemisphere)
    local max = WebGLRenderer.MAX_LIGHTS
    sh:send("u_lightCount", #lights)

    local types, pos, dir, col = {}, {}, {}, {}
    local dist, decay, angleCos, penumbraCos = {}, {}, {}, {}

    for i = 1, max do
        local light = lights[i]
        if light then
            local c = self._lightScratch:copy(light.color):multiplyScalar(light.intensity)
            col[i] = { c.r, c.g, c.b }

            if light.isPointLight and light:isPointLight() then
                local p = light:worldPosition()
                types[i] = LIGHT_TYPE.point
                pos[i] = { p.x, p.y, p.z }
                dir[i] = { 0, -1, 0 }
                dist[i], decay[i] = light.distance, light.decay
                angleCos[i], penumbraCos[i] = -1, -1

            elseif light.isSpotLight and light:isSpotLight() then
                local p = Vector3:new():setFromMatrixPosition(light.matrixWorld)
                local d = light:direction()
                types[i] = LIGHT_TYPE.spot
                pos[i] = { p.x, p.y, p.z }
                dir[i] = { d.x, d.y, d.z }
                dist[i], decay[i] = light.distance, light.decay
                angleCos[i] = math.cos(light.angle)
                penumbraCos[i] = math.cos(light.angle * (1 - light.penumbra))

            else -- directional
                local d = light:direction()
                types[i] = LIGHT_TYPE.directional
                pos[i] = { 0, 0, 0 }
                dir[i] = { d.x, d.y, d.z }
                dist[i], decay[i] = 0, 0
                angleCos[i], penumbraCos[i] = -1, -1
            end
        else
            types[i] = -1
            pos[i], dir[i], col[i] = { 0, 0, 0 }, { 0, -1, 0 }, { 0, 0, 0 }
            dist[i], decay[i], angleCos[i], penumbraCos[i] = 0, 0, -1, -1
        end
    end

    sh:send("u_lightType", unpack(types))
    sh:send("u_lightPos", unpack(pos))
    sh:send("u_lightDir", unpack(dir))
    sh:send("u_lightColor", unpack(col))
    sh:send("u_lightDistance", unpack(dist))
    sh:send("u_lightDecay", unpack(decay))
    sh:send("u_lightAngleCos", unpack(angleCos))
    sh:send("u_lightPenumbraCos", unpack(penumbraCos))

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

-- Frame-wide shadow uniforms: each caster's map and matrix are the same for
-- every mesh, so they go out once per shader like the other lights.
-- u_hasShadow itself is sent per-mesh in _drawBucket (see there), since
-- `receiveShadow` is a per-object flag -- a mesh with it off must read as
-- fully lit even while the maps stay bound for meshes that don't.
--
-- `casters` is an array of { light, lightIndex } built by _renderShadowMaps,
-- lightIndex being this light's slot in the u_light* arrays so the shader
-- knows which light a given shadow slot darkens.
function WebGLRenderer:_sendShadowUniforms(sh, casters)
    local max = WebGLRenderer.MAX_SHADOWS
    sh:send("u_shadowCount", #casters)

    local lightIndex, isCube, bias, mapSize = {}, {}, {}, {}
    local viewProj, lightPos, far = {}, {}, {}
    local maps2D, mapsCube = {}, {}
    local normalBias, lightDir = {}, {}

    for i = 1, max do
        local entry = casters[i]
        if entry then
            local light = entry.light
            local cube = (light.isPointLight and light:isPointLight()) or false
            lightIndex[i] = entry.lightIndex - 1   -- GLSL is 0-based
            isCube[i] = cube
            bias[i] = light.shadow.bias
            normalBias[i] = light.shadow.normalBias or 0
            mapSize[i] = { light.shadow.mapSize, light.shadow.mapSize }

            if cube then
                viewProj[i] = Matrix4:new()
                lightPos[i] = { entry.lightPos.x, entry.lightPos.y, entry.lightPos.z }
                lightDir[i] = { 0, -1, 0 }
                far[i] = light.shadow.cameras[1].far
                maps2D[i], mapsCube[i] = self._noShadow2D, self._shadowCubeCanvas[i]
            else
                local dir = light:direction(self._shadowDirScratch)
                viewProj[i] = self._shadowViewProj[i]
                lightPos[i] = { 0, 0, 0 }
                lightDir[i] = { dir.x, dir.y, dir.z }
                far[i] = 0
                maps2D[i], mapsCube[i] = self._shadow2DCanvas[i], self._noShadowCube
            end
        else
            lightIndex[i], isCube[i], bias[i], normalBias[i] = -1, false, 0, 0
            mapSize[i], viewProj[i], lightPos[i], far[i] = { 1, 1 }, Matrix4:new(), { 0, 0, 0 }, 0
            lightDir[i] = { 0, -1, 0 }
            maps2D[i], mapsCube[i] = self._noShadow2D, self._noShadowCube
        end
    end

    sh:send("u_shadowMap2D", unpack(maps2D))
    sh:send("u_shadowMapCube", unpack(mapsCube))
    sh:send("u_shadowLightIndex", unpack(lightIndex))
    sh:send("u_shadowIsCube", unpack(isCube))
    sh:send("u_shadowBias", unpack(bias))
    sh:send("u_shadowNormalBias", unpack(normalBias))
    sh:send("u_shadowLightDir", unpack(lightDir))
    sh:send("u_shadowMapSize", unpack(mapSize))
    sh:send("u_shadowViewProj", unpack(viewProj))
    sh:send("u_shadowLightPos", unpack(lightPos))
    sh:send("u_shadowFar", unpack(far))

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
--
-- `frustum` defaults to the camera's; the shadow pass passes a light's
-- instead, to cull casters that cannot project into that light's map.
function WebGLRenderer:_inFrustum(mesh, frustum)
    if not mesh.frustumCulled then return true end

    local geometry = mesh.geometry
    local sphere = geometry.boundingSphere or geometry:computeBoundingSphere()
    if not sphere then return true end

    frustum = frustum or self._frustum

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
        local p = frustum.planes[i]
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
    local sx, sy, front = self._lineSx or {}, self._lineSy or {}, self._lineFront or {}
    self._lineSx, self._lineSy, self._lineFront = sx, sy, front

    for _, line in ipairs(bucket) do
        local material = line.material
        local geometry = line.geometry
        if material and material.visible and geometry and #geometry.points > 0 then
            line:updateWorldMatrix(true, false)

            local n = #geometry.points
            for i = 1, n do
                local world = geometry.points[i]:clone():applyMatrix4(line.matrixWorld)
                sx[i], sy[i] = camera:worldToScreen(world, width, height)
                front[i] = camera:isInFrontOf(world)
            end

            local c = material.color
            love.graphics.setColor(c.r, c.g, c.b, material.opacity)
            love.graphics.setLineWidth(material.linewidth)

            local drewAny = false
            local segmented = line.isLineSegments and line:isLineSegments()
            local step = segmented and 2 or 1
            local last = segmented and (n - 1) or (n - 1)
            for i = 1, last, step do
                if front[i] and front[i + 1] then
                    love.graphics.line(sx[i], sy[i], sx[i + 1], sy[i + 1])
                    drewAny = true
                end
            end

            if drewAny then
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

-- Up to MAX_SHADOWS casters for this frame: every collected light with
-- castShadow set, in `lights` order (already brightest-first from
-- _collect), each paired with its index into u_light* so the shadow pass
-- knows which light slot it darkens.
function WebGLRenderer:_pickShadowCasters(lights)
    local casters = self._casterScratch or {}
    self._casterScratch = casters
    for i = #casters, 1, -1 do casters[i] = nil end

    for i, light in ipairs(lights) do
        if #casters >= WebGLRenderer.MAX_SHADOWS then break end
        if light.castShadow then
            casters[#casters + 1] = { light = light, lightIndex = i }
        end
    end

    return casters
end

-- Depth-only pass shared by both shadow map kinds: draws castShadow meshes
-- with `viewProj`, into whatever canvas is currently bound. Only castShadow
-- meshes are drawn -- a shadow only needs to know what can OCCLUDE, not what
-- receives, so this walk is usually much smaller than the main scene
-- traversal.
--
-- `wantMovable` filters by shadowMovable; nil draws every caster. Returns
-- whether anything was drawn, so the caller can skip the composite. Casters
-- outside the light's frustum are culled.
function WebGLRenderer:_renderDepthPass(scene, viewProj, cube, lightPos, far, wantMovable)
    local getDepthShader = require "shader.depth"
    local staticShader  = getDepthShader(false, cube)
    local skinnedShader = getDepthShader(true, cube)

    local posScratch = self._depthPosScratch
    if cube then
        posScratch[1], posScratch[2], posScratch[3] = lightPos.x, lightPos.y, lightPos.z
    end
    staticShader:send("u_viewProj", viewProj)
    skinnedShader:send("u_viewProj", viewProj)
    if cube then
        staticShader:send("u_lightPos", posScratch)
        staticShader:send("u_far", far)
        skinnedShader:send("u_lightPos", posScratch)
        skinnedShader:send("u_far", far)
    end

    local drewAny = false

    local lightFrustum
    if self.frustumCulling then
        lightFrustum = self._shadowFrustum
        lightFrustum:setFromProjectionMatrix(viewProj)
    end

    scene:traverseVisible(function(obj)
        if obj.isMesh and obj:isMesh() and obj.geometry and obj.geometry.mesh
           and obj.castShadow
           and (wantMovable == nil or obj.shadowMovable == wantMovable) then
            local skinned = self:_isSkinned(obj)

            -- skinned bounds are the bind pose, same exemption as the camera pass
            if lightFrustum and not skinned and not self:_inFrustum(obj, lightFrustum) then
                return
            end

            local sh = skinned and skinnedShader or staticShader

            love.graphics.setShader(sh)
            sh:send("u_model", obj.matrixWorld)
            if skinned then self:_sendSkin(sh, obj) end

            love.graphics.draw(obj.geometry.mesh)
            drewAny = true
        end
    end)

    return drewAny
end

-- 2D depth maps sample linearly so PCF taps blend between texels. Cube maps
-- stay nearest: filtering across a face boundary bleeds in the neighbouring
-- face's depth, which shows up as a seam along the cube's edges.
local function newShadowCanvas(size, cube)
    if cube then
        return love.graphics.newCanvas(size, size, 6, { type = "cube", format = "r32f" })
    end
    local canvas = love.graphics.newCanvas(size, size, { format = "r32f" })
    canvas:setFilter("linear", "linear")
    return canvas
end

-- Per-texel min of the static and dynamic depth canvases into `target`.
-- `faceBasis` selects the cube variant.
function WebGLRenderer:_compositeShadowMin(staticCanvas, dynamicCanvas, target, size, faceBasis)
    local getCompositeShader = require "shader.shadowcomposite"
    local sh = getCompositeShader(faceBasis ~= nil)
    sh:send("u_static", staticCanvas)
    sh:send("u_dynamic", dynamicCanvas)
    if faceBasis then
        local sent = faceBasis._uniforms   -- constants, built once per face
        if not sent then
            sent = {
                dir   = { faceBasis.dir.x,   faceBasis.dir.y,   faceBasis.dir.z },
                right = { faceBasis.right.x, faceBasis.right.y, faceBasis.right.z },
                up    = { faceBasis.up.x,    faceBasis.up.y,    faceBasis.up.z },
            }
            faceBasis._uniforms = sent
        end
        sh:send("u_faceDir",   sent.dir)
        sh:send("u_faceRight", sent.right)
        sh:send("u_faceUp",    sent.up)
    end

    love.graphics.push("all")
    love.graphics.setCanvas(target)
    love.graphics.setShader(sh)
    love.graphics.setDepthMode()
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.origin()
    love.graphics.rectangle("fill", 0, 0, size, size)
    love.graphics.pop()
end

-- Render every shadow-casting light's depth into its own map: a 2D canvas
-- for directional/spot (one coherent view direction), a 6-face cube canvas
-- for point (none). Fills self._shadow2DCanvas/self._shadowCubeCanvas and
-- self._shadowViewProj, indexed the same as `casters`.
--
-- Each map is a static layer (redrawn only when dirty) plus a dynamic layer
-- (every frame), merged into the working canvas. autoUpdate=false with no
-- needsUpdate skips the light entirely, as in three.js.
function WebGLRenderer:_renderShadowMaps(scene, casters)
    love.graphics.setDepthMode("lequal", true)
    -- Standard shadow-mapping trick: cull FRONT faces (the ones facing the
    -- light), so the map stores the BACK face's depth instead. This is what
    -- actually fixes contact-shadow acne/peter-panning at an object's base --
    -- comparing a fragment against its own front face needs a bias at all,
    -- and any bias large enough to silence that self-shadowing on a
    -- near-grazing surface is also large enough to detach the shadow from
    -- the object that casts it. Culling the front face sidesteps the
    -- self-compare entirely, no bias tuning required.
    love.graphics.setMeshCullMode("front")

    -- one walk for the whole pass, not one per light/face
    local hasMovableCaster = false
    scene:traverseVisible(function(obj)
        if obj.castShadow and obj.shadowMovable
           and obj.isMesh and obj:isMesh() and obj.geometry and obj.geometry.mesh then
            hasMovableCaster = true
        end
    end)

    for i, entry in ipairs(casters) do
        local light = entry.light
        local shadow = light.shadow

        -- slots are not stable per-light, so a different light landing here
        -- means the cached canvases hold someone else's depth
        local isNewSlot = self._shadowSlotSeen[i] ~= light
        self._shadowSlotSeen[i] = light

        if shadow.autoUpdate == false and not shadow.needsUpdate and not isNewSlot then
            -- reuse last frame's canvas; a point light still needs its position
            if light.isPointLight and light:isPointLight() then
                local pos = self._shadowLightPosScratch[i]
                if not pos then
                    pos = Vector3:new()
                    self._shadowLightPosScratch[i] = pos
                end
                entry.lightPos = light:worldPosition(pos)
            end
            goto continue
        end

        local staticDirty = isNewSlot or shadow.needsUpdate

        if light.isPointLight and light:isPointLight() then
            local size = light.shadow.mapSize
            local canvas = self._shadowCubeCanvas[i]
            if not canvas or canvas:getWidth() ~= size then
                canvas = newShadowCanvas(size, true)
                self._shadowCubeCanvas[i] = canvas
            end
            -- needed even on a cached frame: the shader measures distance from it
            local pos = self._shadowLightPosScratch[i]
            if not pos then
                pos = Vector3:new()
                self._shadowLightPosScratch[i] = pos
            end
            light:worldPosition(pos)
            entry.lightPos = pos
            local far = light.shadow.cameras[1].far

            -- a moved lamp reprojects all 6 faces, so the static layer is stale
            local lastPos = self._shadowLastLightPos[i]
            if not lastPos then
                lastPos = Vector3:new()
                self._shadowLastLightPos[i] = lastPos
                staticDirty = true
            elseif not lastPos:equals(pos) then
                staticDirty = true
            end
            lastPos:copy(pos)

            -- nothing moves: draw static straight into the working canvas,
            -- no dynamic layer and no composite
            local direct = not hasMovableCaster
            if direct and not staticDirty then goto continue end

            local staticCanvas = canvas
            if not direct then
                staticCanvas = self._shadowStaticCubeCanvas[i]
                if not staticCanvas or staticCanvas:getWidth() ~= size then
                    staticCanvas = newShadowCanvas(size, true)
                    self._shadowStaticCubeCanvas[i] = staticCanvas
                    staticDirty = true
                end
            end

            for face, cam in ipairs(light:updateShadowCameras()) do
                cam:updateMatrixWorld(true)
                cam.matrixWorldInverse:copy(cam.matrixWorld):invert()
                local vp = self._shadowFaceViewProj
                cam:viewProjectionMatrix(vp)

                if staticDirty then
                    love.graphics.setCanvas({ { staticCanvas, face = face } })
                    love.graphics.clear(1, 1, 1, 1)
                    love.graphics.setDepthMode("lequal", true)
                    self:_renderDepthPass(scene, vp, true, pos, far, false)
                end

                if not direct then
                    local dynamicCanvas = self._shadowDynamicCubeCanvas[i]
                    if not dynamicCanvas or dynamicCanvas:getWidth() ~= size then
                        dynamicCanvas = newShadowCanvas(size, true)
                        self._shadowDynamicCubeCanvas[i] = dynamicCanvas
                    end

                    love.graphics.setCanvas({ { dynamicCanvas, face = face } })
                    love.graphics.clear(1, 1, 1, 1)
                    love.graphics.setDepthMode("lequal", true)
                    self:_renderDepthPass(scene, vp, true, pos, far, true)

                    self:_compositeShadowMin(staticCanvas, dynamicCanvas,
                        { { canvas, face = face } }, size, PointLightFaces[face])
                end
            end

        else -- directional or spot
            local size = light.shadow.mapSize
            local canvas = self._shadow2DCanvas[i]
            if not canvas or canvas:getWidth() ~= size then
                canvas = newShadowCanvas(size, false)
                self._shadow2DCanvas[i] = canvas
            end
            local cam
            if light.isSpotLight and light:isSpotLight() then
                cam = light:updateShadowCamera()
            else
                cam = light:updateShadowCamera(self._shadowTarget:copy(self.shadowTarget))
            end

            cam:updateMatrixWorld(true)
            cam.matrixWorldInverse:copy(cam.matrixWorld):invert()
            cam:viewProjectionMatrix(self._shadowViewProj[i])

            -- a moved light reprojects everything, so the static layer is stale
            local lastViewProj = self._shadowLastViewProj[i]
            if not lastViewProj then
                lastViewProj = Matrix4:new()
                self._shadowLastViewProj[i] = lastViewProj
                staticDirty = true
            elseif not lastViewProj:equals(self._shadowViewProj[i]) then
                staticDirty = true
            end
            lastViewProj:copy(self._shadowViewProj[i])

            local direct = not hasMovableCaster
            if direct and not staticDirty then goto continue end

            local staticCanvas = canvas
            if not direct then
                staticCanvas = self._shadowStatic2DCanvas[i]
                if not staticCanvas or staticCanvas:getWidth() ~= size then
                    staticCanvas = newShadowCanvas(size, false)
                    self._shadowStatic2DCanvas[i] = staticCanvas
                    staticDirty = true
                end
            end

            if staticDirty then
                love.graphics.setCanvas(staticCanvas)
                love.graphics.clear(1, 1, 1, 1)
                love.graphics.setDepthMode("lequal", true)
                self:_renderDepthPass(scene, self._shadowViewProj[i], false, nil, nil, false)
            end

            if not direct then
                local dynamicCanvas = self._shadowDynamic2DCanvas[i]
                if not dynamicCanvas or dynamicCanvas:getWidth() ~= size then
                    dynamicCanvas = newShadowCanvas(size, false)
                    self._shadowDynamic2DCanvas[i] = dynamicCanvas
                end
                love.graphics.setCanvas(dynamicCanvas)
                love.graphics.clear(1, 1, 1, 1)
                love.graphics.setDepthMode("lequal", true)
                self:_renderDepthPass(scene, self._shadowViewProj[i], false, nil, nil, true)

                self:_compositeShadowMin(staticCanvas, dynamicCanvas, canvas, size)
            end
        end

        shadow.needsUpdate = false

        ::continue::
    end

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

    local staticDraws, skinnedDraws, lineDraws, particleDraws, lights, ambient, hemisphere = self:_collect(scene)

    -- The shadow pass renders to its own canvases and must finish (and
    -- restore the real canvas/shader/depth state) before anything below
    -- touches the screen -- hence doing it here, after collecting but before
    -- the clear that would otherwise be undone by _renderShadowMaps' own
    -- setCanvas.
    local casters = self:_pickShadowCasters(lights)
    if #casters > 0 then
        self:_renderShadowMaps(scene, casters)
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
        self:_sendLights(sh, lights, ambient, hemisphere)
        self:_sendShadowUniforms(sh, casters)
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

    local hasShadowMap = #casters > 0

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
