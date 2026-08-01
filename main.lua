-- Entry point: delegates to demos/shadows, the test scene built on top
-- of TreeEngine (used strictly as a library — engine files are not modified).

for _, a in ipairs(arg or {}) do
    if a == "--tests" then
        require "tests.main"
        return
    end
end

local TL = require "init"

TL.baseCallbacks(require "demos.shadows.init")
