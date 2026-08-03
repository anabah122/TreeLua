-- three/lights/SpotLight.lua — cone of light aimed at a target
--
--   local spot = SpotLight:new(0xffffff, 3, 20, math.pi / 6, 0.3)
--   spot.position:set(0, 5, 0)
--   spot.target.position:set(0, 0, 0)
--   scene:add(spot)
--
-- Like DirectionalLight, the aim comes from `target` rather than a stored
-- vector, so moving either end re-aims the cone. `angle` is the half-angle in
-- radians; `penumbra` in [0,1] softens the rim.

local Light             = require "engine.lights.Light"
local Object3D          = require "engine.core.Object3D"
local Vector3           = require "engine.math.vec3"
local PerspectiveCamera = require "engine.cameras.PerspectiveCamera"

local SpotLight = Light:extend("SpotLight")

function SpotLight:new(color, intensity, distance, angle, penumbra, decay)
    local l = Light.new(self, color, intensity)
    l.type = "SpotLight"

    l.position:set(0, 1, 0)
    l.target = Object3D:new()

    l.distance = distance or 0
    l.angle    = angle    or math.pi / 3
    l.penumbra = penumbra or 0
    l.decay    = decay == nil and 2 or decay

    -- Off by default, same convention as DirectionalLight. The cone maps
    -- directly onto a perspective camera: fov = 2*angle, aspect 1 (square map).
    l.castShadow = false
    l.shadow = {
        mapSize = 1024,
        bias    = 0.003,
        normalBias = 0.05,
        camera  = PerspectiveCamera:new(math.deg(angle or math.pi / 3) * 2, 1, 0.1, distance and distance > 0 and distance or 50),
        autoUpdate  = true,
        needsUpdate = false,
    }

    return l
end

function SpotLight:isSpotLight()
    return true
end

function SpotLight:getPower()
    return self.intensity * 2 * math.pi * (1 - math.cos(self.angle / 2))
end

function SpotLight:setPower(power)
    self.intensity = power / (2 * math.pi * (1 - math.cos(self.angle / 2)))
    return self
end

-- Unit vector along which the light travels, from the cone's apex toward its
-- target -- the same convention as DirectionalLight:direction.
function SpotLight:direction(target)
    target = target or Vector3:new()

    self:updateWorldMatrix(true, false)
    local from = Vector3:new():setFromMatrixPosition(self.matrixWorld)

    self.target:updateWorldMatrix(true, false)
    local to = Vector3:new():setFromMatrixPosition(self.target.matrixWorld)

    target:subVectors(to, from)

    if target:lengthSq() == 0 then return target:set(0, -1, 0) end
    return target:normalizeSelf()
end

-- Aim `shadow.camera` from the light's own position toward its target, cone
-- angle already baked into the camera's fov at construction. Unlike
-- DirectionalLight there is no external focus point -- a spot's frustum is
-- fully determined by where the light itself sits.
function SpotLight:updateShadowCamera()
    local cam = self.shadow.camera

    self:updateWorldMatrix(true, false)
    local pos = Vector3:new():setFromMatrixPosition(self.matrixWorld)
    local dir = self:direction()

    cam.position:copy(pos)
    cam:lookAt(pos.x + dir.x, pos.y + dir.y, pos.z + dir.z)

    return cam
end

function SpotLight:copy(source, recursive)
    Light.copy(self, source, recursive)
    self.target   = source.target:clone(false)
    self.distance = source.distance
    self.angle    = source.angle
    self.penumbra = source.penumbra
    self.decay    = source.decay
    return self
end

return SpotLight
