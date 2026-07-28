-- three/loaders/GLTFLoader.lua — glTF 2.0 / GLB
--
--   local loader = GLTFLoader:new()
--   loader:load("assets/model/hero.glb", function(gltf)
--       scene:add(gltf.scene)
--       mixer:clipAction(gltf.animations[1]):play()
--   end)
--
-- three.js loads over the network and so is callback-driven; LÖVE reads from
-- disk synchronously. Both spellings work here: pass a callback and it fires
-- immediately, or ignore it and use the return value.

local Loader    = require "three.loaders.Loader"
local gltf      = require "importer.gltf"
local animation = require "importer.gltf.animation"

local GLTFLoader = Loader:extend("GLTFLoader")

function GLTFLoader:new()
    local l = Loader.new(self)
    l.type = "GLTFLoader"
    -- passed through to the importer
    l.withTextures = true
    l.anisotropy   = 1
    return l
end

function GLTFLoader:isGLTFLoader()
    return true
end

function GLTFLoader:setTextures(enabled)
    self.withTextures = enabled ~= false
    return self
end

function GLTFLoader:setAnisotropy(value)
    self.anisotropy = value or 1
    return self
end

-- Returns { scene, animations, userData }. onError catches a bad file rather
-- than letting the error escape, matching three.js's third argument.
function GLTFLoader:load(url, onLoad, onProgress, onError)
    local path = self:resolveURL(url)

    local ok, data = pcall(function()
        return gltf:load{
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
    result.scene.name = "gltf"

    -- three.js also exposes the parsed asset block
    result.asset = data.json and data.json.asset or nil

    if onProgress then onProgress{ loaded = 1, total = 1 } end
    if onLoad then onLoad(result) end

    return result
end

-- three.js's synchronous-looking spelling, for callers who prefer it.
function GLTFLoader:loadSync(url)
    return self:load(url)
end

return GLTFLoader
