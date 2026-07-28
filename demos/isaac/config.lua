-- Общие константы игры.
return {
    roomHalfW      = 8,
    roomHalfD      = 6,
    wallHeight     = 2,

    playerSpeed    = 4.5,
    playerRadius   = 0.35,
    playerHp       = 100,
    playerFireRate = 0.25,   -- seconds between shots
    playerInvuln   = 1.0,    -- seconds of invulnerability after being hit

    tearSpeed      = 9,
    tearRadius     = 0.12,
    tearLife       = 2.0,

    enemySpeed     = 1.6,
    enemyRadius    = 0.4,
    enemyHp        = 2,
    enemyContactDmg = 1,
    enemyTouchCooldown = 0.8,

    camHeight      = 9,
    camBack        = 6,

    eyeHeight      = 1.6, -- высота камеры от пола в FPS-режиме
}
