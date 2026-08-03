-- three/loaders/ColladaLoader.lua — Collada (.dae)
--
--   local loader = ColladaLoader:new()
--   local dae = loader:load("assets/model/Dancing.dae")
--   scene:add(dae.scene)
--
-- three.js's ColladaLoader returns { scene, animations, kinematics, library }.
-- The first two carry the same meaning here; `upAxis` is added because Collada
-- files declare one and it is worth surfacing rather than burying.
--
-- The importer folds the file's <unit meter="..."> into the root transform at
-- load time, so a Collada scene arrives in metres like a glTF one and needs no
-- scale fudge from the caller.

local Loader    = require "engine.loaders.Loader"
local dae       = require "engine.importer.dae"
local animation = require "engine.importer.dae.animation"

local ColladaLoader = Loader:extend("ColladaLoader")

function ColladaLoader:new()
    local l = Loader.new(self)
    l.type = "ColladaLoader"
    l.withTextures = true
    l.anisotropy   = 1
    return l
end

function ColladaLoader:isColladaLoader()
    return true
end

function ColladaLoader:setTextures(enabled)
    self.withTextures = enabled ~= false
    return self
end

function ColladaLoader:setAnisotropy(value)
    self.anisotropy = value or 1
    return self
end

function ColladaLoader:load(url, onLoad, onProgress, onError)
    local path = self:resolveURL(url)

    local ok, data = pcall(function()
        return dae:load{
            path       = path,
            mesh       = true,
            tex        = self.withTextures,
            anisotropy = self.anisotropy,
        }
    end)

    if not ok then
        if onError then onError(data) return nil end
        error(data, 0)
    end

    local result = self:_assemble(data, animation)
    result.scene.name = "collada"
    result.upAxis     = data.upAxis

    if onProgress then onProgress{ loaded = 1, total = 1 } end
    if onLoad then onLoad(result) end

    return result
end

function ColladaLoader:loadSync(url)
    return self:load(url)
end

return ColladaLoader
