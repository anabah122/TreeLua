-- three/objects/LOD.lua — swap detail with distance
--
--   local lod = LOD:new()
--   lod:addLevel(highMesh, 0)
--   lod:addLevel(lowMesh, 25)
--   scene:add(lod)
--
-- Every level is a child, so the whole set inherits the LOD's transform. Only
-- one is left visible at a time, which is what the renderer's traverseVisible
-- walk then picks up -- there is no special case in the renderer for this.
--
-- three.js updates levels from inside its render loop. This renderer does not
-- know about LOD, so `update(camera)` is called by the application, usually
-- next to controls:update. `autoUpdate` is kept for signature compatibility.

local Object3D = require "engine.core.Object3D"
local Vector3  = require "engine.math.vec3"

local LOD = Object3D:extend("LOD")

function LOD:new()
    local o = Object3D.new(self)
    o.type = "LOD"

    o.levels     = {}
    o.autoUpdate = true

    o._scratchA = Vector3:new()
    o._scratchB = Vector3:new()

    return o
end

function LOD:isLOD()
    return true
end

-- Levels stay sorted by distance so `update` can stop at the first one that is
-- further away than the camera.
function LOD:addLevel(object, distance, hysteresis)
    distance = math.abs(distance or 0)

    local level = {
        distance   = distance,
        hysteresis = hysteresis or 0,
        object     = object,
    }

    local at = #self.levels + 1
    for i, existing in ipairs(self.levels) do
        if distance < existing.distance then at = i break end
    end

    table.insert(self.levels, at, level)
    self:add(object)

    return self
end

function LOD:removeLevel(distance)
    for i, level in ipairs(self.levels) do
        if level.distance == distance then
            table.remove(self.levels, i)
            self:remove(level.object)
            return true
        end
    end
    return false
end

function LOD:getCurrentLevel()
    return self._currentLevel or 1
end

function LOD:getObjectForDistance(distance)
    if #self.levels == 0 then return nil end

    for i = 2, #self.levels do
        local level = self.levels[i]

        -- hysteresis widens the threshold in the direction already taken, so a
        -- camera hovering on a boundary does not flicker between two levels
        local threshold = level.distance
        if level.hysteresis > 0 then
            if self._currentLevel and self._currentLevel >= i then
                threshold = threshold - threshold * level.hysteresis
            else
                threshold = threshold + threshold * level.hysteresis
            end
        end

        if distance < threshold then return self.levels[i - 1].object end
    end

    return self.levels[#self.levels].object
end

-- Pick the level for where the camera is now and hide the rest.
function LOD:update(camera)
    if #self.levels == 0 then return self end

    self:updateWorldMatrix(true, false)
    camera:updateWorldMatrix(true, false)

    local here = self._scratchA:setFromMatrixPosition(self.matrixWorld)
    local eye  = self._scratchB:setFromMatrixPosition(camera.matrixWorld)

    local distance = here:distanceTo(eye)
    local chosen = self:getObjectForDistance(distance)

    for i, level in ipairs(self.levels) do
        level.object.visible = level.object == chosen
        if level.object == chosen then self._currentLevel = i end
    end

    return self
end

function LOD:copy(source, recursive)
    Object3D.copy(self, source, false)

    self.levels     = {}
    self.autoUpdate = source.autoUpdate

    for _, level in ipairs(source.levels) do
        self:addLevel(level.object:clone(true), level.distance, level.hysteresis)
    end

    return self
end

return LOD
