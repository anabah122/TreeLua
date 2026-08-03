-- three/core/Group.lua — an Object3D that exists only to hold children
--
-- Identical to Object3D in behaviour; the separate type is what lets callers
-- (and the renderer) tell "this is a container" from "this is a thing that
-- happens to have children".

local Object3D = require "engine.core.Object3D"

local Group = Object3D:extend("Group")

function Group:isGroup()
    return true
end

return Group
