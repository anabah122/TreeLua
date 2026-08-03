-- three/core/Object3D.lua — base of the scene graph
--
--   local o = Object3D:new()
--   o.position:set(1, 0, 0)
--   o.rotation:set(0, math.pi, 0)     -- euler, kept in sync with .quaternion
--   parent:add(o)
--
-- Every method is called with ':' and takes the object as its first argument,
-- per the engine's convention. That is also why three.js's `object.up` style
-- static helpers appear here as methods rather than module functions.
--
-- The transform is stored as position/quaternion/scale, exactly as three.js
-- does, and baked into `matrix` (local) and `matrixWorld` (absolute) by
-- updateMatrixWorld. Those two are plain `math.mat4` instances in the engine's
-- row-major layout, so they hand straight to the renderer and the importers'
-- skinning code without conversion.

local Vector3    = require "engine.math.vec3"
local Quaternion = require "engine.math.quat"
local Euler      = require "engine.math.euler"
local Matrix4    = require "engine.math.mat4"

local Object3D = {}
Object3D.__index = Object3D

Object3D.DEFAULT_UP = { x = 0, y = 1, z = 0 }

local nextId = 0

function Object3D:new()
    nextId = nextId + 1

    local o = setmetatable({}, self)
    o.__index = o == Object3D and Object3D or o

    o.id       = nextId
    o.uuid     = string.format("obj-%d", nextId)
    o.name     = ""
    o.type     = "Object3D"

    o.parent   = nil
    o.children = {}

    o.up       = Vector3:new(0, 1, 0)
    o.position = Vector3:new(0, 0, 0)
    o.quaternion = Quaternion:new()
    o.scale    = Vector3:new(1, 1, 1)

    -- three.js exposes both `.rotation` (Euler) and `.quaternion` and keeps
    -- them in lockstep via property setters. Lua has no such hook on field
    -- writes, so the two are reconciled at updateMatrix() time instead: see
    -- `_syncRotation` below for which one wins.
    o.rotation = Euler:new(0, 0, 0, "XYZ")
    o._rotationCache = { x = 0, y = 0, z = 0, order = "XYZ" }

    o.matrix      = Matrix4:new()
    o.matrixWorld = Matrix4:new()

    o.matrixAutoUpdate      = true
    o.matrixWorldNeedsUpdate = false

    o.visible          = true
    o.castShadow       = false
    o.receiveShadow    = false
    -- static by default: set true on anything that moves, so its shadow
    -- redraws every frame instead of being cached in the static layer
    o.shadowMovable    = false
    o.frustumCulled    = true
    o.renderOrder      = 0
    o.userData         = {}

    return o
end

-- Subclassing hook: Scene, Group, Mesh and the cameras all call this so they
-- inherit the transform machinery without copying it.
function Object3D:extend(typeName)
    local Sub = setmetatable({}, { __index = self })
    Sub.__index = Sub
    Sub.__parentClass = self

    function Sub:new(...)
        local o = self.__parentClass.new(self, ...)
        o.type = typeName
        return o
    end

    return Sub
end

function Object3D:isObject3D()
    return true
end

-- ── hierarchy ────────────────────────────────────────────────────────────────

-- Accepts several children at once, as three.js does. Re-parents rather than
-- duplicating: an object appearing in two parents would be drawn twice with
-- one of the two world matrices, which is never what the caller meant.
function Object3D:add(...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if child and child ~= self then
            if child.parent then child.parent:remove(child) end
            child.parent = self
            self.children[#self.children + 1] = child
        end
    end
    return self
end

function Object3D:remove(...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        for k, c in ipairs(self.children) do
            if c == child then
                table.remove(self.children, k)
                child.parent = nil
                break
            end
        end
    end
    return self
end

function Object3D:removeFromParent()
    if self.parent then self.parent:remove(self) end
    return self
end

function Object3D:clear()
    for _, c in ipairs(self.children) do c.parent = nil end
    self.children = {}
    return self
end

-- Re-parent while preserving the object's absolute transform, which is what
-- three.js's `attach` is for -- plain `add` would snap it to the new parent's
-- space and visibly teleport it.
-- The child's new local matrix is its old WORLD matrix expressed in the new
-- parent's space: inverse(newParentWorld) * childWorld. Note it composes
-- against the child's world matrix, not its local one -- using `child.matrix`
-- would drop whatever the old parent contributed.
function Object3D:attach(child)
    self:updateWorldMatrix(true, false)
    child:updateWorldMatrix(true, false)

    local local_ = self.matrixWorld:clone():invert():multiply(child.matrixWorld)

    self:add(child)
    child.matrix:copy(local_)
    child.matrix:decompose(child.position, child.quaternion, child.scale)
    child:_adoptQuaternion()
    child:updateWorldMatrix(false, true)
    return self
end

function Object3D:getObjectById(id)
    return self:getObjectByProperty("id", id)
end

function Object3D:getObjectByName(name)
    return self:getObjectByProperty("name", name)
end

function Object3D:getObjectByProperty(key, value)
    if self[key] == value then return self end
    for _, c in ipairs(self.children) do
        local found = c:getObjectByProperty(key, value)
        if found then return found end
    end
    return nil
end

function Object3D:getObjectsByProperty(key, value, out)
    out = out or {}
    if self[key] == value then out[#out + 1] = self end
    for _, c in ipairs(self.children) do
        c:getObjectsByProperty(key, value, out)
    end
    return out
end

function Object3D:traverse(callback)
    callback(self)
    for _, c in ipairs(self.children) do c:traverse(callback) end
    return self
end

function Object3D:traverseVisible(callback)
    if not self.visible then return self end
    callback(self)
    for _, c in ipairs(self.children) do c:traverseVisible(callback) end
    return self
end

function Object3D:traverseAncestors(callback)
    if self.parent then
        callback(self.parent)
        self.parent:traverseAncestors(callback)
    end
    return self
end

-- ── transform ────────────────────────────────────────────────────────────────

-- three.js keeps `.rotation` and `.quaternion` in sync through property
-- setters; without those, whichever the caller touched last has to win. The
-- euler is cached each sync, so a changed euler means the caller wrote to it
-- and the quaternion is rebuilt from it; otherwise the euler is refreshed from
-- the quaternion. Writing both between two updates resolves in the euler's
-- favour, which matches how three.js code is usually written.
function Object3D:_syncRotation()
    local r, c = self.rotation, self._rotationCache

    if r.x ~= c.x or r.y ~= c.y or r.z ~= c.z or r.order ~= c.order then
        self.quaternion:setFromEuler(r)
    else
        r:setFromQuaternion(self.quaternion, r.order)
    end

    c.x, c.y, c.z, c.order = r.x, r.y, r.z, r.order
end

function Object3D:updateMatrix()
    self:_syncRotation()
    self.matrix:compose(self.position, self.quaternion, self.scale)
    self.matrixWorldNeedsUpdate = true
    return self
end

-- Refresh this object's world matrix and everything below it. `force` pushes
-- the update through even where matrixWorldNeedsUpdate is clear, which the
-- renderer uses on the frame a parent moved.
function Object3D:updateMatrixWorld(force)
    if self.matrixAutoUpdate then self:updateMatrix() end

    if self.matrixWorldNeedsUpdate or force then
        if self.parent then
            self.matrixWorld:multiplyMatrices(self.parent.matrixWorld, self.matrix)
        else
            self.matrixWorld:copy(self.matrix)
        end
        self.matrixWorldNeedsUpdate = false
        force = true   -- children must follow a moved parent
    end

    for _, c in ipairs(self.children) do c:updateMatrixWorld(force) end
    return self
end

-- Targeted variant: walk up first so this object's own world matrix is
-- trustworthy without refreshing the whole scene.
function Object3D:updateWorldMatrix(updateParents, updateChildren)
    if updateParents and self.parent then
        self.parent:updateWorldMatrix(true, false)
    end

    if self.matrixAutoUpdate then self:updateMatrix() end

    if self.parent then
        self.matrixWorld:multiplyMatrices(self.parent.matrixWorld, self.matrix)
    else
        self.matrixWorld:copy(self.matrix)
    end
    self.matrixWorldNeedsUpdate = false

    if updateChildren then
        for _, c in ipairs(self.children) do c:updateWorldMatrix(false, true) end
    end
    return self
end

function Object3D:applyMatrix4(m)
    if self.matrixAutoUpdate then self:updateMatrix() end
    self.matrix:premultiply(m)
    self.matrix:decompose(self.position, self.quaternion, self.scale)
    -- the quaternion is now authoritative; refresh the euler to match
    self.rotation:setFromQuaternion(self.quaternion, self.rotation.order)
    local c = self._rotationCache
    c.x, c.y, c.z = self.rotation.x, self.rotation.y, self.rotation.z
    return self
end

function Object3D:applyQuaternion(q)
    self.quaternion:premultiply(q)
    self.rotation:setFromQuaternion(self.quaternion, self.rotation.order)
    local c = self._rotationCache
    c.x, c.y, c.z = self.rotation.x, self.rotation.y, self.rotation.z
    return self
end

function Object3D:setRotationFromAxisAngle(axis, angle)
    self.quaternion:setFromAxisAngle(axis, angle)
    return self:_adoptQuaternion()
end

function Object3D:setRotationFromEuler(euler)
    self.quaternion:setFromEuler(euler)
    return self:_adoptQuaternion()
end

function Object3D:setRotationFromMatrix(m)
    self.quaternion:setFromRotationMatrix(m)
    return self:_adoptQuaternion()
end

function Object3D:setRotationFromQuaternion(q)
    self.quaternion:copy(q)
    return self:_adoptQuaternion()
end

-- After anything writes the quaternion directly, the euler and its cache have
-- to follow, or the next _syncRotation would see a stale euler and undo it.
function Object3D:_adoptQuaternion()
    self.rotation:setFromQuaternion(self.quaternion, self.rotation.order)
    local c = self._rotationCache
    c.x, c.y, c.z, c.order = self.rotation.x, self.rotation.y, self.rotation.z, self.rotation.order
    return self
end

function Object3D:rotateOnAxis(axis, angle)
    local q = Quaternion:new():setFromAxisAngle(axis, angle)
    self.quaternion:multiply(q)
    return self:_adoptQuaternion()
end

-- Same rotation applied in world space rather than the object's own.
function Object3D:rotateOnWorldAxis(axis, angle)
    local q = Quaternion:new():setFromAxisAngle(axis, angle)
    self.quaternion:premultiply(q)
    return self:_adoptQuaternion()
end

function Object3D:rotateX(angle) return self:rotateOnAxis(Vector3:new(1, 0, 0), angle) end
function Object3D:rotateY(angle) return self:rotateOnAxis(Vector3:new(0, 1, 0), angle) end
function Object3D:rotateZ(angle) return self:rotateOnAxis(Vector3:new(0, 0, 1), angle) end

function Object3D:translateOnAxis(axis, distance)
    local v = Vector3:new(axis.x, axis.y, axis.z):applyQuaternion(self.quaternion)
    self.position:addScaledVector(v, distance)
    return self
end

function Object3D:translateX(d) return self:translateOnAxis(Vector3:new(1, 0, 0), d) end
function Object3D:translateY(d) return self:translateOnAxis(Vector3:new(0, 1, 0), d) end
function Object3D:translateZ(d) return self:translateOnAxis(Vector3:new(0, 0, 1), d) end

function Object3D:localToWorld(v)
    self:updateWorldMatrix(true, false)
    return v:applyMatrix4(self.matrixWorld)
end

function Object3D:worldToLocal(v)
    self:updateWorldMatrix(true, false)
    return v:applyMatrix4(self.matrixWorld:clone():invert())
end

-- Point the object's -Z at a target, three.js's convention for meshes. The
-- cameras override this: they look down -Z too, but the eye/target roles swap,
-- so PerspectiveCamera:lookAt reverses the arguments.
function Object3D:lookAt(x, y, z)
    local target
    if type(x) == "table" then
        target = Vector3:new(x.x or x[1], x.y or x[2], x.z or x[3])
    else
        target = Vector3:new(x, y, z)
    end

    self:updateWorldMatrix(true, false)

    local pos = Vector3:new():setFromMatrixPosition(self.matrixWorld)

    -- Matrix4:lookAt builds the orientation whose -Z runs from eye to target,
    -- which is what both meshes and cameras want, so there is no camera
    -- special case here.
    local m = Matrix4:new():lookAt(pos, target, self.up)

    self.quaternion:setFromRotationMatrix(m)

    -- a rotated parent means the world-space aim has to be expressed locally
    if self.parent then
        local pq = Quaternion:new():setFromRotationMatrix(self.parent.matrixWorld)
        self.quaternion:premultiply(pq:invert())
    end

    return self:_adoptQuaternion()
end

function Object3D:getWorldPosition(target)
    target = target or Vector3:new()
    self:updateWorldMatrix(true, false)
    return target:setFromMatrixPosition(self.matrixWorld)
end

function Object3D:getWorldQuaternion(target)
    target = target or Quaternion:new()
    self:updateWorldMatrix(true, false)
    local p, s = Vector3:new(), Vector3:new()
    self.matrixWorld:decompose(p, target, s)
    return target
end

function Object3D:getWorldScale(target)
    target = target or Vector3:new()
    self:updateWorldMatrix(true, false)
    return target:setFromMatrixScale(self.matrixWorld)
end

-- Where the object's -Z points in world space.
function Object3D:getWorldDirection(target)
    target = target or Vector3:new()
    self:updateWorldMatrix(true, false)
    local e = self.matrixWorld:elements()
    return target:set(-e[9], -e[10], -e[11]):normalizeSelf()
end

-- ── copying ──────────────────────────────────────────────────────────────────

function Object3D:copy(source, recursive)
    self.name    = source.name
    self.up:copy(source.up)
    self.position:copy(source.position)
    self.quaternion:copy(source.quaternion)
    self.rotation:copy(source.rotation)
    self.scale:copy(source.scale)

    self.matrix:copy(source.matrix)
    self.matrixWorld:copy(source.matrixWorld)

    self.matrixAutoUpdate       = source.matrixAutoUpdate
    self.matrixWorldNeedsUpdate = source.matrixWorldNeedsUpdate

    self.visible       = source.visible
    self.castShadow    = source.castShadow
    self.receiveShadow = source.receiveShadow
    self.frustumCulled = source.frustumCulled
    self.renderOrder   = source.renderOrder

    self.userData = {}
    for k, v in pairs(source.userData) do self.userData[k] = v end

    if recursive ~= false then
        for _, c in ipairs(source.children) do self:add(c:clone(true)) end
    end

    return self
end

function Object3D:clone(recursive)
    local Class = getmetatable(self)
    return Class.new(Class):copy(self, recursive)
end

function Object3D:__tostring()
    return string.format("%s(%s#%d)", self.type,
        self.name ~= "" and self.name or "-", self.id)
end

return Object3D
