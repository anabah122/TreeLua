-- tests/main.lua — headless test runner
--
--     love . --tests        (from the project root)
--
-- The suite needs a graphics context, because loaders build love.Mesh objects
-- and the renderer draws for real. So this runs one frame with a window open
-- and quits, rather than disabling the graphics module.
--
-- Paths are resolved from the project root, not from tests/, since that is
-- where the asset files the suite loads actually live.

local suite = require "tests.suite"

function love.draw()
    local ok, err = pcall(function()
        return suite.run()
    end)

    if not ok then
        print("SUITE ERROR: " .. tostring(err))
        love.event.quit(1)
        return
    end

    love.event.quit(err and 0 or 1)
end
