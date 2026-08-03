-- engine/collision/Heightfield.lua — regular-grid heightmap collider (facade,
-- no three.js equivalent -- this is Cannon/Ammo's HeightfieldShape by name)
--
--   local field = Heightfield:new(heights, cellSize, origin)
--   -- heights: heights[row][col], row/col 0-based, `cellSize` world units apart
--   field:intersectsCapsule(capsule)
--
-- Each cell is two triangles, generated on demand from the height samples
-- around the capsule's footprint rather than baked once -- a heightfield can
-- be large, and only a handful of cells matter for any single query.

local Vector3  = require "engine.math.vec3"
local Box3     = require "engine.math.box3"
local Triangle = require "engine.math.triangle"

local Heightfield = {}
Heightfield.__index = Heightfield

function Heightfield:new(heights, cellSize, origin)
    local rows = #heights
    local cols = #heights[1]

    return setmetatable({
        type     = "Heightfield",
        heights  = heights,
        cellSize = cellSize or 1,
        origin   = origin and origin:clone() or Vector3:new(0, 0, 0),
        rows     = rows,
        cols     = cols,
    }, Heightfield)
end

function Heightfield:heightAt(row, col)
    row = math.min(math.max(row, 0), self.rows - 1)
    col = math.min(math.max(col, 0), self.cols - 1)
    return self.heights[row + 1][col + 1]
end

function Heightfield:pointAt(row, col)
    return Vector3:new(
        self.origin.x + col * self.cellSize,
        self:heightAt(row, col),
        self.origin.z + row * self.cellSize
    )
end

function Heightfield:getBoundingBox(target)
    target = target or Box3:new()
    target:makeEmpty()

    local minH, maxH = math.huge, -math.huge
    for row = 0, self.rows - 1 do
        for col = 0, self.cols - 1 do
            local h = self.heights[row + 1][col + 1]
            if h < minH then minH = h end
            if h > maxH then maxH = h end
        end
    end

    target:set(
        Vector3:new(self.origin.x, minH, self.origin.z),
        Vector3:new(self.origin.x + (self.cols - 1) * self.cellSize, maxH, self.origin.z + (self.rows - 1) * self.cellSize)
    )
    return target
end

-- Two triangles for the cell whose lower-left corner is (row, col).
function Heightfield:trianglesForCell(row, col)
    local a = self:pointAt(row, col)
    local b = self:pointAt(row, col + 1)
    local c = self:pointAt(row + 1, col)
    local d = self:pointAt(row + 1, col + 1)
    return Triangle:new(a, b, c), Triangle:new(b, d, c)
end

function Heightfield:intersectsCapsule(capsule)
    local box = capsule:getBoundingBox()

    local colMin = math.floor((box.min.x - self.origin.x) / self.cellSize)
    local colMax = math.floor((box.max.x - self.origin.x) / self.cellSize)
    local rowMin = math.floor((box.min.z - self.origin.z) / self.cellSize)
    local rowMax = math.floor((box.max.z - self.origin.z) / self.cellSize)

    colMin = math.max(colMin, 0)
    rowMin = math.max(rowMin, 0)
    colMax = math.min(colMax, self.cols - 2)
    rowMax = math.min(rowMax, self.rows - 2)

    for row = rowMin, rowMax do
        for col = colMin, colMax do
            local t1, t2 = self:trianglesForCell(row, col)
            local hit = capsule:intersectsTriangle(t1) or capsule:intersectsTriangle(t2)
            if hit then return hit end
        end
    end

    return nil
end

return Heightfield
