-- three/postprocessing/RenderPass.lua — draws the scene into the composer's MRT canvases
--
--   composer:addPass(RenderPass:new(scene, camera))
--
-- Always the first pass: everything after it (BloomPass, a future ShaderPass)
-- reads composer.sceneColor/brightColor rather than the scene itself.

local RenderPass = {}
RenderPass.__index = RenderPass

function RenderPass:new(scene, camera)
    local p = setmetatable({}, RenderPass)
    p.scene = scene
    p.camera = camera
    return p
end

function RenderPass:render(composer)
    composer.renderer:render(self.scene, self.camera, {
        composer.sceneColor, composer.brightColor,
        depthstencil = composer.depthCanvas,
    })
    return self
end

return RenderPass
