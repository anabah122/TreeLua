-- three/controls/OrbitControls.lua — orbit, dolly and pan around a target
--
--   local controls = OrbitControls:new(camera)
--   controls.target:set(0, 1, 0)
--
--   function love.update(dt)            controls:update(dt) end
--   function love.mousemoved(x,y,dx,dy) controls:mousemoved(x, y, dx, dy) end
--   function love.wheelmoved(x,y)       controls:wheelmoved(y) end
--
-- Left drag orbits, right drag pans, the wheel dollies -- the same bindings as
-- three.js. Unlike FlyControls this one owns the camera's position: it derives
-- it from the target plus a spherical offset every update, so writing
-- camera.position by hand is overwritten on the next frame. Move `target`
-- instead.
--
-- three.js listens on a DOM element; there is nothing to attach to here, so the
-- application forwards LOVE's callbacks. `enableDamping` is honoured, which is
-- why update() takes a dt three.js does not.

local Vector3 = require "math.vec3"

local OrbitControls = {}
OrbitControls.__index = OrbitControls

function OrbitControls:new(camera, params)
    params = params or {}

    local c = setmetatable({}, OrbitControls)
    c.type    = "OrbitControls"
    c.object  = camera
    c.enabled = params.enabled ~= false

    c.target = params.target or Vector3:new()

    c.minDistance = params.minDistance or 0.1
    c.maxDistance = params.maxDistance or math.huge

    -- just short of the poles: at exactly 0 or pi the azimuth loses meaning and
    -- the camera's up vector flips
    c.minPolarAngle = params.minPolarAngle or 1e-3
    c.maxPolarAngle = params.maxPolarAngle or math.pi - 1e-3

    c.enableRotate = params.enableRotate ~= false
    c.enableZoom   = params.enableZoom   ~= false
    c.enablePan    = params.enablePan    ~= false

    c.rotateSpeed = params.rotateSpeed or 0.005
    c.zoomSpeed   = params.zoomSpeed   or 1.1
    c.panSpeed    = params.panSpeed    or 0.002

    c.enableDamping = params.enableDamping or false
    c.dampingFactor = params.dampingFactor or 0.08

    -- Spherical coordinates of the camera relative to the target, seeded from
    -- wherever the camera already sits so construction does not teleport it.
    local offset = Vector3:new():subVectors(camera.position, c.target)
    c.radius = math.max(offset:length(), 1e-4)
    c.theta  = math.atan2(offset.x, offset.z)
    c.phi    = math.acos(math.max(-1, math.min(1, offset.y / c.radius)))

    -- where the spherical coordinates are heading, which damping eases toward
    c._targetTheta  = c.theta
    c._targetPhi    = c.phi
    c._targetRadius = c.radius

    c._dragging = nil

    c:update(0)
    return c
end

function OrbitControls:isOrbitControls()
    return true
end

function OrbitControls:_clampTargets()
    self._targetPhi = math.max(self.minPolarAngle,
                      math.min(self.maxPolarAngle, self._targetPhi))
    self._targetRadius = math.max(self.minDistance,
                         math.min(self.maxDistance, self._targetRadius))
    return self
end

-- ── input ────────────────────────────────────────────────────────────────────

function OrbitControls:mousepressed(x, y, button)
    if not self.enabled then return self end
    if button == 1 then self._dragging = "rotate"
    elseif button == 2 then self._dragging = "pan" end
    return self
end

function OrbitControls:mousereleased(x, y, button)
    self._dragging = nil
    return self
end

-- The button is read live rather than tracked, so an application that never
-- forwards mousepressed still works.
function OrbitControls:mousemoved(x, y, dx, dy)
    if not self.enabled then return self end

    local mode = self._dragging
    if not mode then
        if love.mouse.isDown(1) then mode = "rotate"
        elseif love.mouse.isDown(2) then mode = "pan" end
    end

    if mode == "rotate" and self.enableRotate then
        self._targetTheta = self._targetTheta - dx * self.rotateSpeed
        self._targetPhi   = self._targetPhi   - dy * self.rotateSpeed
        self:_clampTargets()

    elseif mode == "pan" and self.enablePan then
        -- pan in the camera's own plane, scaled by distance so the target
        -- tracks the cursor at any zoom
        local scale = self.radius * self.panSpeed
        local right, up = self:_basis()
        self.target:addScaledVector(right, -dx * scale)
        self.target:addScaledVector(up,     dy * scale)
    end

    return self
end

function OrbitControls:wheelmoved(dy)
    if not self.enabled or not self.enableZoom or dy == 0 then return self end

    local factor = dy > 0 and (1 / self.zoomSpeed) or self.zoomSpeed
    self._targetRadius = self._targetRadius * factor

    return self:_clampTargets()
end

-- Camera-right and camera-up in world space, derived from the current angles
-- rather than read back off the camera matrix.
function OrbitControls:_basis()
    local sinPhi, cosPhi = math.sin(self.phi), math.cos(self.phi)
    local sinTheta, cosTheta = math.sin(self.theta), math.cos(self.theta)

    local right = Vector3:new(cosTheta, 0, -sinTheta)
    local up    = Vector3:new(-cosPhi * sinTheta, sinPhi, -cosPhi * cosTheta)

    return right, up
end

function OrbitControls:update(dt)
    if self.enableDamping and dt and dt > 0 then
        -- frame-rate independent ease: the same fraction of the remaining gap
        -- closes per second whatever the step size
        local t = 1 - (1 - self.dampingFactor) ^ (dt * 60)
        self.theta  = self.theta  + (self._targetTheta  - self.theta)  * t
        self.phi    = self.phi    + (self._targetPhi    - self.phi)    * t
        self.radius = self.radius + (self._targetRadius - self.radius) * t
    else
        self.theta, self.phi, self.radius =
            self._targetTheta, self._targetPhi, self._targetRadius
    end

    local sinPhi = math.sin(self.phi)

    self.object.position:set(
        self.target.x + self.radius * sinPhi * math.sin(self.theta),
        self.target.y + self.radius * math.cos(self.phi),
        self.target.z + self.radius * sinPhi * math.cos(self.theta)
    )

    self.object:lookAt(self.target.x, self.target.y, self.target.z)

    return self
end

-- three.js's name for putting the camera back where it started.
function OrbitControls:saveState()
    self._saved = {
        target = self.target:clone(),
        theta = self._targetTheta, phi = self._targetPhi,
        radius = self._targetRadius,
    }
    return self
end

function OrbitControls:reset()
    local s = self._saved
    if not s then return self end

    self.target:copy(s.target)
    self._targetTheta, self._targetPhi, self._targetRadius = s.theta, s.phi, s.radius
    self.theta, self.phi, self.radius = s.theta, s.phi, s.radius

    return self:update(0)
end

function OrbitControls:dispose()
    self.enabled = false
    self._dragging = nil
    return self
end

return OrbitControls
