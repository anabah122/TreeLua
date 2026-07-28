-- Entry point: delegates entirely to game_test, the test project built on
-- top of TreeEngine (used strictly as a library — engine files are not modified).

for _, a in ipairs(arg or {}) do
    if a == "--tests" then
        require "tests.main"
        return
    end
end

local game = require "game_test.init"

function love.load()    game.init() end
function love.update(dt) game.update(dt) end
function love.draw()    game.draw() end
function love.resize(w, h) game.resize(w, h) end
function love.keypressed(k) game.keypressed(k) end
function love.keyreleased(k) game.keyreleased(k) end
function love.mousemoved(x, y, dx, dy) game.mousemoved(x, y, dx, dy) end
function love.wheelmoved(dx, dy) game.wheelmoved(dx, dy) end
