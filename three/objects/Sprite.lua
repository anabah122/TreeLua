-- three/objects/Sprite.lua — a flat quad that always faces the camera
--
--   local sprite = Sprite:new(SpriteMaterial:new{ map = texture })
--   sprite.position:set(0, 1.2, 0)
--   sprite.scale:set(0.5, 0.5, 1)
--   scene:add(sprite)
--
-- Position/scale come from the object's own transform, same as any Mesh; only
-- the ORIENTATION is not the object's own -- three.js overwrites a sprite's
-- world rotation with the camera's at render time, so it stays flat-on to the
-- viewer no matter which way the object graph points it. WebGLRenderer does
-- that overwrite (see _billboard there); this class only carries the quad and
-- the flag the renderer looks for.
--
-- The quad is a unit PlaneGeometry lying in XY facing +Z, so with no
-- rotation applied it already faces the camera along -Z the way three.js
-- sprites do.

local Mesh          = require "three.objects.Mesh"
local PlaneGeometry = require "three.geometries.PlaneGeometry"

local Sprite = Mesh:extend("Sprite")

-- Shared by every sprite: a 1x1 quad, scaled per instance via `scale`.
local unitPlane

function Sprite:new(material)
    if not unitPlane then unitPlane = PlaneGeometry:new(1, 1) end

    local s = Mesh.new(self, unitPlane, material)
    s.type = "Sprite"
    s.center = { x = 0.5, y = 0.5 }   -- three.js's pivot, unused by the quad above but kept for parity
    return s
end

function Sprite:isSprite()
    return true
end

return Sprite
