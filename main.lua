-- Entry point: delegates to demos/shadows, the test scene built on top
-- of TreeEngine (used strictly as a library — engine files are not modified).

for _, a in ipairs(arg or {}) do
    if a == "--tests" then
        require "tests.main"
        return
    end
end

local game = require "demos.lights.init"

-- work = update+draw, frame = wall clock between frames (includes vsync wait)
local timing = { workStart = 0, work = 0, frame = 0, lastFrameStart = 0 }

function love.load()
    game.init()
    timing.lastFrameStart = love.timer.getTime()
end

function love.update(dt)
    local now = love.timer.getTime()
    timing.frame = now - timing.lastFrameStart
    timing.lastFrameStart = now
    timing.workStart = now

    game.update(dt)
end

function love.draw()
    game.draw()

    timing.work = love.timer.getTime() - timing.workStart

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format(
        "work %.2f ms ",
        timing.work * 1000, timing.frame * 1000
        ), 10, 32)
end
function love.resize(w, h) game.resize(w, h) end
function love.keypressed(k) game.keypressed(k) end
function love.mousemoved(x, y, dx, dy) game.mousemoved(x, y, dx, dy) end
function love.wheelmoved(dx, dy) game.wheelmoved(dx, dy) end
