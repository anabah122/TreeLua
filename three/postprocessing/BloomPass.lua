-- three/postprocessing/BloomPass.lua — threshold + separable blur + composite
--
--   composer:addPass(BloomPass:new{ threshold = 0.8, intensity = 1.2, blurRadius = 1 })
--
-- Reads composer.brightColor (the MRT bright-pass target RenderPass filled),
-- runs it through: threshold cut -> horizontal blur -> vertical blur, then
-- draws composer.sceneColor + blurred bloom to the screen. Two ping-pong
-- canvases at half resolution keep the blur cheap -- bloom is meant to be
-- soft, not sharp, so the resolution loss is invisible in the result and
-- the blur cost drops to a quarter.

local postprocess = require "shader.postprocess"

local BloomPass = {}
BloomPass.__index = BloomPass

function BloomPass:new(params)
    params = params or {}

    local p = setmetatable({}, BloomPass)
    p.threshold  = params.threshold or 0.6
    p.intensity  = params.intensity or 1
    p.blurRadius = params.blurRadius or 1.5   -- texels, at half-res canvas size
    p.blurPasses = params.blurPasses or 2      -- repeats of H+V for a softer, wider glow

    p._pingA = nil
    p._pingB = nil
    p._w, p._h = 0, 0

    return p
end

function BloomPass:_ensureCanvases(w, h)
    if self._w == w and self._h == h and self._pingA then return end
    self._w, self._h = w, h
    self._pingA = love.graphics.newCanvas(w, h)
    self._pingB = love.graphics.newCanvas(w, h)
end

function BloomPass:render(composer)
    local fullW, fullH = composer.sceneColor:getWidth(), composer.sceneColor:getHeight()
    -- half-res: cheap and bloom is meant to look soft, not pixel-sharp
    local w, h = math.max(1, math.floor(fullW / 2)), math.max(1, math.floor(fullH / 2))
    self:_ensureCanvases(w, h)

    -- threshold: brightColor (full-res) -> pingA (half-res)
    local thresholdShader = postprocess.threshold()
    love.graphics.setCanvas(self._pingA)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setShader(thresholdShader)
    thresholdShader:send("u_threshold", self.threshold)
    love.graphics.draw(composer.brightColor, 0, 0, 0, w / fullW, h / fullH)

    -- separable blur, ping-ponging between the two half-res canvases
    local blurShader = postprocess.blur()
    love.graphics.setShader(blurShader)
    local src, dst = self._pingA, self._pingB
    for _ = 1, self.blurPasses do
        love.graphics.setCanvas(dst)
        love.graphics.clear(0, 0, 0, 1)
        blurShader:send("u_direction", { 1 / w, 0 })
        blurShader:send("u_radius", self.blurRadius)
        love.graphics.draw(src, 0, 0)
        src, dst = dst, src

        love.graphics.setCanvas(dst)
        love.graphics.clear(0, 0, 0, 1)
        blurShader:send("u_direction", { 0, 1 / h })
        blurShader:send("u_radius", self.blurRadius)
        love.graphics.draw(src, 0, 0)
        src, dst = dst, src
    end

    -- composite: sceneColor + blurred bloom -> screen
    --
    -- Canvases render with OpenGL's Y-up convention, the window framebuffer
    -- with Y-down -- every canvas-to-canvas draw above stays consistent since
    -- both ends share that convention, but this last draw crosses into the
    -- window, so it needs the flip the others don't.
    local compositeShader = postprocess.composite()
    love.graphics.setCanvas()
    love.graphics.setShader(compositeShader)
    compositeShader:send("u_bloom", src)
    compositeShader:send("u_intensity", self.intensity)
    love.graphics.draw(composer.sceneColor, 0, fullH, 0, 1, -1)

    love.graphics.setShader()

    return self
end

return BloomPass
