-- Тестовая сцена для Model:autoLOD — сравнение всех четырёх уровней
-- (100/50/25/10%) бок о бок, без переключения по дистанции: каждая копия
-- жёстко показывает один захардкоженный уровень.
local TL = require "init"

local MODEL_PATH = "assets/model/noskinModel.glb"

local M = {}

local scene, camera, renderer, controls
local shown = {} -- { {mesh=Mesh, label=string}, ... }

function M.init()
    love.window.setTitle("TreeEngine — autoLOD test")

    local w, h = love.graphics.getDimensions()

    scene = TL.Scene:new()
    scene:setBackground(0x1b1e26)

    camera = TL.PerspectiveCamera:new(55, w / h, 0.1, 200)
    camera.position:set(0, 3, 10)
    camera:lookAt(0, 0, 0)

    controls = TL.FlyControls:new(camera, { movementSpeed = 8 })

    renderer = TL.WebGLRenderer:new()

    scene:add(TL.AmbientLight:new(0x606773, 1))
    local sun = TL.DirectionalLight:new(0xfff3e0, 1)
    sun.position:set(3, 6, 2)
    scene:add(sun)

    local model = TL.Model:fromLoaderResult(TL.GLTFLoader:new():load(MODEL_PATH))
    model:autoLOD()

    -- Один LOD-узел на модель, все четыре уровня внутри -- вытащить их
    -- напрямую и разложить рядом, каждый навсегда на своём уровне.
    local lod
    model.scene:traverse(function(o)
        if o.isLOD and o:isLOD() then lod = o end
    end)

    for i, level in ipairs(lod.levels) do
        local mesh = level.object:clone(true)
        mesh.position:set((i - 1) * 4 - 6, 0, 0)
        scene:add(mesh)
        shown[#shown+1] = { mesh = mesh, label = "LOD" .. (i - 1) }
    end
end

local function vertexCount(mesh)
    local idx = mesh.geometry.indices
    return idx and #idx or #mesh.geometry.vertices
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

    for _, s in ipairs(shown) do
        local mesh = s.mesh
        local sphere = mesh.geometry.boundingSphere or mesh.geometry:computeBoundingSphere()

        local top = mesh:localToWorld(sphere.center:clone():add(TL.Vector3:new(0, sphere.radius, 0)))
        local sx, sy, visible = camera:worldToScreen(top)
        if visible then
            love.graphics.print(s.label .. ": " .. vertexCount(mesh), sx, sy - 14)
        end
    end
end

return M
