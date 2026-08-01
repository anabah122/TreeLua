-- importer/formats/obj.lua
-- Парсит OBJ + MTL. Возвращает меши сгруппированные по материалу.
--
-- load(objPath) -> { groups }
--   group: { name, textureName, verts, indices }
--   verts: массив { x,y,z, nx,ny,nz, u,v }   (u,v — оригинальные из OBJ, 0..1)

local M = {}

local function parseMtl(path)
    local src = love.filesystem.read(path)
    if not src then return {} end

    local mats = {}
    local cur  = nil
    for line in (src .. '\n'):gmatch('([^\n]*)\n') do
        local w = line:match('^%s*newmtl%s+(.+)$')
        if w then
            cur = w:match('^%s*(.-)%s*$')
            mats[cur] = {}
        end
        local tex = line:match('^%s*map_Kd%s+(.+)$')
        if tex and cur then
            -- берём только имя файла без расширения как имя тайла
            local name = tex:match('^%s*(.-)%s*$')
            name = name:match('([^/\\]+)$') or name   -- basename
            name = name:match('^(.+)%..+$') or name   -- без расширения
            mats[cur].textureName = name
        end
    end
    return mats
end

function M.load(objPath)
    local src = assert(love.filesystem.read(objPath), 'OBJ not found: ' .. objPath)

    -- MTL рядом с OBJ
    local dir = objPath:match('^(.+)[/\\]') or ''
    local mats = {}

    local positions = {}  -- {x,y,z}
    local normals   = {}  -- {nx,ny,nz}
    local texcoords = {}  -- {u,v}

    local groups  = {}
    local cur     = nil   -- текущая группа

    local function newGroup(name, matName)
        cur = { name = name, matName = matName, verts = {}, indices = {}, lookup = {} }
        groups[#groups+1] = cur
    end

    local function addFaceVert(vi, ti, ni)
        local p = positions[vi]
        local n = normals[ni]   or { 0, 1, 0 }
        local t = texcoords[ti] or { 0, 0 }
        local key = vi .. '/' .. (ti or 0) .. '/' .. (ni or 0)
        local idx = cur.lookup[key]
        if not idx then
            local vv = cur.verts
            idx = #vv + 1
            vv[idx] = { p[1], p[2], p[3], n[1], n[2], n[3], t[1], t[2] }
            cur.lookup[key] = idx
        end
        return idx
    end

    local curMat = nil

    for line in (src .. '\n'):gmatch('([^\n]*)\n') do
        local tag, rest = line:match('^%s*(%S+)%s*(.*)')
        if not tag then goto continue end

        if tag == 'mtllib' then
            local f = rest:match('^%s*(.-)%s*$')
            local p = (dir ~= '' and (dir .. '/' .. f) or f)
            mats = parseMtl(p)

        elseif tag == 'v' then
            local x,y,z = rest:match('(%S+)%s+(%S+)%s+(%S+)')
            positions[#positions+1] = { tonumber(x), tonumber(y), tonumber(z) }

        elseif tag == 'vn' then
            local x,y,z = rest:match('(%S+)%s+(%S+)%s+(%S+)')
            normals[#normals+1] = { tonumber(x), tonumber(y), tonumber(z) }

        elseif tag == 'vt' then
            local u,v = rest:match('(%S+)%s+(%S+)')
            texcoords[#texcoords+1] = { tonumber(u), 1 - tonumber(v) }  -- flip V

        elseif tag == 'usemtl' then
            curMat = rest:match('^%s*(.-)%s*$')
            -- новая группа на каждый смене материала
            newGroup(curMat, curMat)

        elseif tag == 'g' or tag == 'o' then
            if not cur then newGroup(rest, curMat) end

        elseif tag == 'f' then
            if not cur then newGroup('default', curMat) end
            -- разбиваем полигон на треугольники (fan)
            local fverts = {}
            for token in rest:gmatch('%S+') do
                local vi, ti, ni = token:match('^(%d+)/?(%d*)/?(%d*)$')
                vi = tonumber(vi)
                ti = tonumber(ti) or nil
                ni = tonumber(ni) or nil
                fverts[#fverts+1] = addFaceVert(vi, ti, ni)
            end
            for i = 2, #fverts - 1 do
                local idxs = cur.indices
                idxs[#idxs+1] = fverts[1]
                idxs[#idxs+1] = fverts[i]
                idxs[#idxs+1] = fverts[i+1]
            end
        end

        ::continue::
    end

    -- прикрепляем имя текстуры к группам
    for _, g in ipairs(groups) do
        g.lookup = nil  -- освобождаем
        local m = mats[g.matName]
        g.textureName = (m and m.textureName) or g.matName
    end

    return groups
end

return M
