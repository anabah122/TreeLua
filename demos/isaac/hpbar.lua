-- Проекция мировых координат на экран и отрисовка 2D HP-баров поверх 3D-сцены.
local Vector3 = require "engine.math.vec3"

local HpBar = {}

local scratch = Vector3:new()

-- Возвращает screenX, screenY, visible (false, если точка позади камеры).
-- Тонкая обёртка над Camera:worldToScreen (см. TODO.md) -- сама проекция
-- теперь часть движка, а не ручной код игры.
function HpBar.worldToScreen(x, y, z, camera)
    return camera:worldToScreen(scratch:set(x, y, z))
end

-- Рисует полоску HP с центром в (screenX, screenY), шириной barW.
function HpBar.draw(screenX, screenY, ratio, barW)
    barW = barW or 50
    local barH = 6
    local x = screenX - barW / 2
    local y = screenY - barH / 2

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 1, y - 1, barW + 2, barH + 2)

    love.graphics.setColor(0.25, 0.05, 0.05, 1)
    love.graphics.rectangle("fill", x, y, barW, barH)

    ratio = math.max(0, math.min(1, ratio))
    if ratio > 0 then
        local r, g = 1 - ratio, ratio
        love.graphics.setColor(r, g, 0.15, 1)
        love.graphics.rectangle("fill", x, y, barW * ratio, barH)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return HpBar
