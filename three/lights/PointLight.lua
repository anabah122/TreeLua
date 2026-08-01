-- three/lights/PointLight.lua — omnidirectional light with falloff
--
--   local lamp = PointLight:new(0xffeecc, 2, 10)
--   lamp.position:set(0, 3, 0)
--   scene:add(lamp)
--
-- Constructor and fields follow three.js: color, intensity, distance, decay.
-- `distance` of 0 means the light never cuts off; `decay` of 2 is the physical
-- inverse-square falloff and three.js's default.
--
-- Shadows: an omnidirectional light has no single view direction, so its
-- shadow needs all 6 cube faces. `shadow.cameras` holds one 90-degree
-- PerspectiveCamera per face (+X,-X,+Y,-Y,+Z,-Z, three.js's cube-map order),
-- aimed by `updateShadowCameras` right before the renderer's shadow pass.

local Light             = require "three.lights.Light"
local Vector3            = require "math.vec3"
local PerspectiveCamera  = require "three.cameras.PerspectiveCamera"

local PointLight = Light:extend("PointLight")

-- three.js's CubeCamera face order: dirs paired with an up vector that keeps
-- each face's basis consistent (no face ends up mirrored against its neighbors).
-- `right` completes the basis (cross(up, dir), same convention a camera
-- would use) -- WebGLRenderer's shadow composite pass needs it to
-- reconstruct each fragment's sample direction across a cube face.
local FACES = {
    { dir = Vector3:new( 1,  0,  0), up = Vector3:new(0, -1,  0) },
    { dir = Vector3:new(-1,  0,  0), up = Vector3:new(0, -1,  0) },
    { dir = Vector3:new( 0,  1,  0), up = Vector3:new(0,  0,  1) },
    { dir = Vector3:new( 0, -1,  0), up = Vector3:new(0,  0, -1) },
    { dir = Vector3:new( 0,  0,  1), up = Vector3:new(0, -1,  0) },
    { dir = Vector3:new( 0,  0, -1), up = Vector3:new(0, -1,  0) },
}
for _, face in ipairs(FACES) do
    face.right = Vector3:new():crossVectors(face.up, face.dir):normalizeSelf()
end

PointLight.FACES = FACES

function PointLight:new(color, intensity, distance, decay)
    local l = Light.new(self, color, intensity)
    l.type = "PointLight"

    l.distance = distance or 0
    l.decay    = decay == nil and 2 or decay

    -- Off by default, same convention as DirectionalLight/SpotLight.
    l.castShadow = false
    l.shadow = {
        mapSize = 512,   -- smaller default: this is 6 faces, not 1
        bias    = 0.005,
        normalBias = 0.05,
        cameras = {},
        autoUpdate  = true,
        needsUpdate = false,
    }
    for i = 1, 6 do
        l.shadow.cameras[i] = PerspectiveCamera:new(90, 1, 0.1, distance and distance > 0 and distance or 50)
    end

    return l
end

function PointLight:isPointLight()
    return true
end

-- three.js's accessor pair: intensity expressed in candela.
function PointLight:getPower()
    return self.intensity * 4 * math.pi
end

function PointLight:setPower(power)
    self.intensity = power / (4 * math.pi)
    return self
end

function PointLight:worldPosition(target)
    target = target or Vector3:new()
    self:updateWorldMatrix(true, false)
    return target:setFromMatrixPosition(self.matrixWorld)
end

-- Point all 6 face cameras at the light's current world position. Called by
-- the renderer once per frame before the point-light shadow pass, since the
-- light (and thus every face's frustum) may have moved.
function PointLight:updateShadowCameras()
    local pos = self:worldPosition()
    for i, cam in ipairs(self.shadow.cameras) do
        local face = FACES[i]
        cam.position:copy(pos)
        cam.up:copy(face.up)
        cam:lookAt(pos.x + face.dir.x, pos.y + face.dir.y, pos.z + face.dir.z)
    end
    return self.shadow.cameras
end

function PointLight:copy(source, recursive)
    Light.copy(self, source, recursive)
    self.distance = source.distance
    self.decay    = source.decay
    return self
end

return PointLight
