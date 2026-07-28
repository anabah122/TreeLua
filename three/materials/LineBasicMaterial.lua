-- three/materials/LineBasicMaterial.lua — flat, unlit line colour
--
--   local mat = LineBasicMaterial:new{ color = 0xff0000, linewidth = 2 }
--
-- Lines never go through the PBR shader (see Line.lua / WebGLRenderer's line
-- pass), so only colour/opacity/linewidth matter; the rest of Material's
-- fields are inherited but ignored.

local Material = require "three.materials.Material"

local LineBasicMaterial = Material:extend("LineBasicMaterial")

function LineBasicMaterial:new(params)
    params = params or {}
    local m = Material.new(self, params)
    m.type = "LineBasicMaterial"

    -- LÖVE's setLineWidth is capped and driver-dependent above a few pixels;
    -- documented here rather than clamped, since the cap varies by machine.
    m.linewidth = params.linewidth or 1

    return m
end

function LineBasicMaterial:copy(source)
    Material.copy(self, source)
    self.linewidth = source.linewidth
    return self
end

return LineBasicMaterial
