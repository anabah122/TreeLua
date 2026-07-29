-- three/lights/DirectionalLight.lua — parallel rays, like the sun
--
--   local sun = DirectionalLight:new(0xfff5ec, 1)
--   sun.position:set(-0.4, 1.0, 0.6)
--   scene:add(sun)
--
-- The direction is NOT a field: three.js derives it from the light's position
-- relative to `target`, whose default sits at the origin. So moving the light
-- aims it, and only the direction matters -- distance does nothing, since the
-- rays are parallel.

local Light   = require "three.lights.Light"
local Object3D = require "three.core.Object3D"
local Vector3 = require "math.vec3"
local OrthographicCamera = require "three.cameras.OrthographicCamera"

local DirectionalLight = Light:extend("DirectionalLight")

function DirectionalLight:new(color, intensity)
    local l = Light.new(self, color, intensity)
    l.type = "DirectionalLight"

    -- three.js defaults the light to (0,1,0) looking at the origin
    l.position:set(0, 1, 0)
    l.target = Object3D:new()

    -- Off by default: only a light actually being used as a shadow caster
    -- should cost the renderer a second pass. Mirrors three.js's
    -- `light.castShadow` flag plus its `light.shadow` (a DirectionalLightShadow,
    -- here just an OrthographicCamera -- parallel rays need no perspective).
    -- `shadow.mapSize`/`shadow.camera` read the same as three.js's fields.
    l.castShadow = false
    l.shadow = {
        mapSize = 1024,
        -- Normalised NDC depth, so this is bias * (far - near) in world units:
        -- 0.0003 over the default 50-unit frustum is ~1.5cm, small enough to
        -- keep a shadow attached where its caster meets the ground.
        bias    = 0.0003,
        -- world units along the normal; kills acne on faceted geometry, where
        -- a flat face's depth disagrees with its interpolated shading normal
        normalBias = 0.05,
        camera  = OrthographicCamera:new(-10, 10, 10, -10, 0.1, 50),
        -- Mirrors three.js: false skips this light's shadow pass entirely
        -- (reusing last frame's map) unless needsUpdate is set for one frame.
        autoUpdate  = true,
        needsUpdate = false,
    }

    return l
end

function DirectionalLight:isDirectionalLight()
    return true
end

-- Unit vector along which the light TRAVELS: from the light toward its target,
-- which is what the shader's u_lightDir expects. three.js computes the same
-- vector internally when it fills its light uniforms.
function DirectionalLight:direction(target)
    target = target or Vector3:new()

    self:updateWorldMatrix(true, false)
    local from = Vector3:new():setFromMatrixPosition(self.matrixWorld)

    self.target:updateWorldMatrix(true, false)
    local to = Vector3:new():setFromMatrixPosition(self.target.matrixWorld)

    target:subVectors(to, from)

    -- a light sitting exactly on its target has no direction; point it down
    -- rather than handing the shader a zero vector
    if target:lengthSq() == 0 then return target:set(0, -1, 0) end

    return target:normalizeSelf()
end

-- Point `shadow.camera` down this light's direction, centred on `target`
-- (world space -- typically the scene's centre or whatever the shadow should
-- follow, e.g. the player). three.js does the same thing at render time on
-- its light's own shadow camera; called from WebGLRenderer before the
-- shadow pass runs.
function DirectionalLight:updateShadowCamera(target)
    local cam = self.shadow.camera
    local dir = self:direction()

    self:updateWorldMatrix(true, false)
    local lightPos = Vector3:new():setFromMatrixPosition(self.matrixWorld)

    -- Sit the camera back along -direction from `target` so `target` lands
    -- mid-frustum, then aim it forward along `direction` -- the light's own
    -- distance from `target` does not matter for parallel rays, only that the
    -- camera is far enough back to clear whatever casts shadows near it.
    local back = target:clone():sub(dir:clone():multiplyScalar(cam.far * 0.5))
    cam.position:copy(back)
    cam:lookAt(target.x, target.y, target.z)

    return cam
end

function DirectionalLight:copy(source, recursive)
    Light.copy(self, source, recursive)
    self.target = source.target:clone(false)
    return self
end

return DirectionalLight
