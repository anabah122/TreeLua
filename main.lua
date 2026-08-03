-- Entry point: delegates to demos/mariatest, the test scene built on top
-- of TreeEngine (used strictly as a library — engine files are not modified).

for _, a in ipairs(arg or {}) do
    if a == "--tests" then
        require "tests.main"
        return
    end
end

local TL = require "init"

local demoName = "collisiontest"
for _, a in ipairs(arg or {}) do
    if a == "--maria" then demoName = "mariatest" end
    if a == "--shadows" then demoName = "shadows" end
end

TL.baseCallbacks(require("demos." .. demoName .. ".init"))
