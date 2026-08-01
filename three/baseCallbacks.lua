-- Wires a demo module's M.init/update/draw/... into the love.* callbacks,
-- plus a work/frame timing overlay. Only callbacks the module actually
-- defines are hooked, so modules can add/omit ones freely (e.g. isaac's
-- keyreleased/mousepressed, no wheelmoved).
local NAMES = {
    "update", "draw", "resize", "keypressed", "keyreleased",
    "mousemoved", "mousepressed", "mousereleased", "wheelmoved",
}

return function(game)
    local timing = { workStart = 0, work = 0, frame = 0, lastFrameStart = 0 }

    function love.load()
        if game.init then game.init() end
        timing.lastFrameStart = love.timer.getTime()
    end

    function love.update(dt)
        local now = love.timer.getTime()
        timing.frame = now - timing.lastFrameStart
        timing.lastFrameStart = now
        timing.workStart = now

        if game.update then game.update(dt) end
    end

    function love.draw()
        if game.draw then game.draw() end

        timing.work = love.timer.getTime() - timing.workStart

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(string.format("work %.2f ms ", timing.work * 1000), 10, 32)
    end

    for _, name in ipairs(NAMES) do
        if name ~= "update" and name ~= "draw" and game[name] then
            love[name] = function(...) game[name](...) end
        end
    end
end
