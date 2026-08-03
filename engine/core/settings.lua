-- three/settings.lua — global engine-wide settings, not tied to one scene or
-- renderer instance
--
--   local TL = require "init"
--   TL.settings.shadowSoftness = 2   -- 5x5 PCF kernel instead of the default 3x3
--
-- Per-scene/per-renderer knobs (clearColor, diffuseWrap, frustumCulling, ...)
-- stay constructor params on WebGLRenderer, as three.js keeps them on its
-- renderer instance. This module is for the handful of things that are
-- meaningfully global instead -- there is one GPU, one shadow filtering
-- quality a game wants everywhere, not a different softness per light.

local settings = {}

-- PCF sample radius for shadow edges, in texels each direction: 1 means the
-- 3x3 kernel shader/parts/shadow.lua has always used, 2 means 5x5, and so on.
-- Higher softens the edge further at the cost of (2*n+1)^2 texture samples
-- per shaded fragment.
settings.shadowSoftness = 1

return settings
