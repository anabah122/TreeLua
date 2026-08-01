-- three/loaders/TextureLoader.lua — an image off disk, as a love.Image
--
--   local tex = TextureLoader:new():load("assets/wood.png")
--   local m   = MeshStandardMaterial:new{ map = tex }
--
-- three.js returns a Texture placeholder immediately and fills it in when the
-- browser finishes fetching. LOVE reads from disk synchronously, so the image
-- is complete by the time load() returns and the onLoad callback fires at once
-- -- the return value works just as well.
--
-- There is no Texture class wrapping it: LOVE's Image already carries the
-- filter and wrap state three.js keeps on Texture, and setting those on a
-- shadow object would just have to be pushed across again.

local Loader = require "three.loaders.Loader"

local TextureLoader = Loader:extend("TextureLoader")

function TextureLoader:new()
    local l = Loader.new(self)
    l.type = "TextureLoader"

    l.mipmaps    = true
    l.anisotropy = 1
    l.filter     = "linear"
    l.wrap       = "repeat"

    return l
end

function TextureLoader:isTextureLoader()
    return true
end

function TextureLoader:setAnisotropy(value)
    self.anisotropy = value
    return self
end

function TextureLoader:load(url, onLoad, onProgress, onError)
    local path = self:resolveURL(url)

    local ok, result = pcall(function()
        local image = love.graphics.newImage(path, { mipmaps = self.mipmaps })
        image:setFilter(self.filter, self.filter, self.anisotropy)
        image:setWrap(self.wrap, self.wrap)
        return image
    end)

    if not ok then
        if onError then onError(result) end
        return nil
    end

    if onProgress then onProgress({ loaded = 1, total = 1 }) end
    if onLoad then onLoad(result) end

    return result
end

return TextureLoader
