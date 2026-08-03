-- three/postprocessing/EffectComposer.lua — render target chain + a list of passes
--
--   local composer = EffectComposer:new(renderer)
--   composer:addPass(RenderPass:new(scene, camera))
--   composer:addPass(BloomPass:new{ threshold = 0.8, intensity = 1.2 })
--   function love.draw() composer:render() end
--
-- Mirrors three.js's EffectComposer: a RenderPass draws the scene into the
-- composer's own MRT canvas pair (sceneColor + brightColor, see
-- WebGLRenderer:render's renderTarget argument) instead of the screen, and
-- every later pass reads/writes canvases in turn. The final pass in the list
-- is expected to draw to the screen (BloomPass does); passes before it stay
-- offscreen. This is the seam every future post effect (tonemap, color
-- grading, DOF) hangs off of -- add a Pass, no renderer changes needed.

local EffectComposer = {}
EffectComposer.__index = EffectComposer

function EffectComposer:new(renderer)
    local c = setmetatable({}, EffectComposer)

    c.renderer = renderer
    c.passes = {}

    c.sceneColor  = nil   -- love.Canvas, lit result -- love_Canvases[0]
    c.brightColor = nil   -- love.Canvas, bloom source -- love_Canvases[1]
    c.depthCanvas = nil

    c:_resize()

    return c
end

function EffectComposer:addPass(pass)
    self.passes[#self.passes + 1] = pass
    return self
end

-- (Re)allocates the MRT pair at the current window size. Cheap to call every
-- frame (an early-out below), but exists as its own method so love.resize can
-- call it directly rather than waiting for the next render to notice.
function EffectComposer:_resize()
    local w, h = love.graphics.getDimensions()
    if self.sceneColor and self.sceneColor:getWidth() == w and self.sceneColor:getHeight() == h then
        return self
    end

    self.sceneColor  = love.graphics.newCanvas(w, h)
    self.brightColor = love.graphics.newCanvas(w, h)
    self.depthCanvas = love.graphics.newCanvas(w, h, { format = "depth24", readable = false })

    return self
end

function EffectComposer:render()
    self:_resize()

    for _, pass in ipairs(self.passes) do
        pass:render(self)
    end

    return self
end

return EffectComposer
