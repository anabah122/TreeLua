-- gltf/json.lua — tiny recursive-descent JSON parser (no deps)

local json = {}

local function skip(s, i)
    while i <= #s and s:byte(i) <= 32 do i = i + 1 end
    return i
end

local parse_value  -- forward

local function parse_string(s, i)
    assert(s:byte(i) == 34, "expected \"")
    i = i + 1
    local parts = {}
    while true do
        local j = i
        while j <= #s and s:byte(j) ~= 34 and s:byte(j) ~= 92 do j = j + 1 end
        parts[#parts+1] = s:sub(i, j-1)
        if s:byte(j) == 34 then return table.concat(parts), j+1 end
        -- escape
        local e = s:byte(j+1)
        if     e == 110 then parts[#parts+1] = "\n"
        elseif e == 116 then parts[#parts+1] = "\t"
        elseif e == 114 then parts[#parts+1] = "\r"
        elseif e == 98  then parts[#parts+1] = "\b"
        elseif e == 102 then parts[#parts+1] = "\f"
        elseif e == 92  then parts[#parts+1] = "\\"
        elseif e == 34  then parts[#parts+1] = "\""
        elseif e == 47  then parts[#parts+1] = "/"
        elseif e == 117 then
            local hex = tonumber(s:sub(j+2, j+5), 16) or 0
            parts[#parts+1] = utf8 and utf8.char(hex) or "?"
            j = j + 4
        end
        i = j + 2
    end
end

local function parse_number(s, i)
    local j = i
    if s:byte(j) == 45 then j = j + 1 end          -- -
    while j <= #s and s:byte(j) >= 48 and s:byte(j) <= 57 do j = j + 1 end
    if j <= #s and s:byte(j) == 46 then j = j + 1  -- .
        while j <= #s and s:byte(j) >= 48 and s:byte(j) <= 57 do j = j + 1 end
    end
    if j <= #s and (s:byte(j) == 101 or s:byte(j) == 69) then -- e/E
        j = j + 1
        if s:byte(j) == 43 or s:byte(j) == 45 then j = j + 1 end
        while j <= #s and s:byte(j) >= 48 and s:byte(j) <= 57 do j = j + 1 end
    end
    return tonumber(s:sub(i, j-1)), j
end

local function parse_array(s, i)
    assert(s:byte(i) == 91)  -- [
    i = skip(s, i+1)
    local arr = {}
    if s:byte(i) == 93 then return arr, i+1 end
    while true do
        local v; v, i = parse_value(s, i)
        arr[#arr+1] = v
        i = skip(s, i)
        local c = s:byte(i)
        if c == 93 then return arr, i+1 end
        assert(c == 44, "expected , or ]")
        i = skip(s, i+1)
    end
end

local function parse_object(s, i)
    assert(s:byte(i) == 123)  -- {
    i = skip(s, i+1)
    local obj = {}
    if s:byte(i) == 125 then return obj, i+1 end
    while true do
        local k; k, i = parse_string(s, i)
        i = skip(s, i)
        assert(s:byte(i) == 58, "expected :")  -- :
        i = skip(s, i+1)
        local v; v, i = parse_value(s, i)
        obj[k] = v
        i = skip(s, i)
        local c = s:byte(i)
        if c == 125 then return obj, i+1 end
        assert(c == 44, "expected , or }")
        i = skip(s, i+1)
    end
end

parse_value = function(s, i)
    i = skip(s, i)
    local c = s:byte(i)
    if c == 34  then return parse_string(s, i)
    elseif c == 91  then return parse_array(s, i)
    elseif c == 123 then return parse_object(s, i)
    elseif c == 116 then return true,  i+4   -- true
    elseif c == 102 then return false, i+5   -- false
    elseif c == 110 then return nil,   i+4   -- null  (returns nil,pos)
    else return parse_number(s, i)
    end
end

function json.decode(s)
    local v = select(1, parse_value(s, 1))
    return v
end

return json
