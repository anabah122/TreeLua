-- three/scenes/Scene.lua — the root of a scene graph
--
--   local scene = Scene:new()
--   scene.background = Color:new(0x101018)
--   scene:add(mesh)
--   renderer:render(scene, camera)
--
-- Beyond being an Object3D it carries the frame-wide settings the renderer
-- reads once per draw: the clear colour and an optional material override.

local Object3D = require "engine.core.Object3D"
local Color    = require "engine.math.color"

local Scene = Object3D:extend("Scene")

function Scene:new()
    local s = Object3D.new(self)
    s.type = "Scene"

    -- nil means "do not clear", matching three.js where a null background
    -- leaves whatever was in the buffer
    s.background = nil

    -- when set, every mesh draws with this material instead of its own
    s.overrideMaterial = nil

    -- Fog or FogExp2, or nil for none -- matches three.js's scene.fog.
    s.fog = nil

    return s
end

function Scene:isScene()
    return true
end

-- Convenience the renderer also accepts: a hex, a name or a Color.
function Scene:setBackground(value)
    if value == nil then
        self.background = nil
    elseif type(value) == "table" and value.type == "color" then
        self.background = value
    else
        self.background = Color:new(value)
    end
    return self
end

function Scene:copy(source, recursive)
    Object3D.copy(self, source, recursive)
    self.background      = source.background and source.background:clone() or nil
    self.overrideMaterial = source.overrideMaterial
    self.fog              = source.fog
    return self
end

return Scene
