-- Тестовая сцена: репродукция бага с текстурой на нескольких мешах.
local TL = require "init"

local M = {}

local scene, camera, renderer, controls
local model

function M.init()
    love.window.setTitle("TreeEngine — maria texture bug test")

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x2a3038)

    camera = TL.PerspectiveCamera:new(55, w / h, 0.1, 100)
    camera.position:set(0, 1.2, 2.5)
    camera:lookAt(0, 0.9, 0)

    controls = TL.FlyControls:new(camera, { movementSpeed = 4 })

    renderer = TL.WebGLRenderer:new()

    scene:add(TL.HemisphereLight:new(0x88ccff, 0x554433, 1))
    local sun = TL.DirectionalLight:new(0xfff3e0, 1.0)
    sun.position:set(3, 6, 2)
    scene:add(sun)

    local loader = TL.ColladaLoader:new()
    local result = loader:load("assets/model/Maria WProp J J Ong/Maria WProp J J Ong.dae")

    model = TL.Model:fromLoaderResult(result)
    local instance = model:createInstance()
    scene:add(instance.scene)

    -- log material/texture per mesh so the console shows what actually got resolved
    instance.scene:traverse(function(obj)
        if obj.isMesh and obj:isMesh() then
            local mat = obj.material
            print(("[demo] mesh '%s' material=%s texture=%s"):format(
                obj.name, mat and mat.name or "nil", mat and (mat.map ~= nil) or "no-mat"))
        end
    end)
end

function M.update(dt)
    controls:update(dt)
end

function M.resize(w, h)
    renderer:setSize(w, h, camera)
end

function M.keypressed(k)
    if k == "escape" then love.event.quit() end
end

function M.mousemoved(x, y, dx, dy) controls:mousemoved(dx, dy) end
function M.wheelmoved(dx, dy)       controls:wheelmoved(dy)     end

function M.draw()
    renderer:render(scene, camera)
end

return M
