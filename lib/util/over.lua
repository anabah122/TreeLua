
-- TABLE 

local serpent = _G.serpent

function table.ser( t, s )
	return serpent.block( t , s or {comment=false} )
end

function table.print( t, s )
    print( serpent.block( t, s or {comment=false}) )
end

function table.random( tbl )
    return tbl[ math.random(#tbl) ]
end

function table.find( t, val )
	for k,v in pairs( t ) do 
		if v==val then 
			return k 
		end	
	end
	return false
end

function table.removeByValue( t, val )
	for k,v in pairs( t ) do 
		if v==val then 
            if type(k)=='number' then
                table.remove( t, k )
            else
                t[k]=nil
            end
            return true
		end	
	end
	return false
end

function table.map(t, func)
    local result = {}
    for k, v in pairs(t) do
        result[k] = func(v, k)
    end
    return result
end

function table.filter(t, func)
    local result = {}
    for k, v in pairs(t) do
        if func(v, k) then
            result[k] = v
        end
    end
    return result
end

function table.reduce(t, func, initial)
    local acc = initial
    for k, v in pairs(t) do
        acc = func(acc, v, k)
    end
    return acc
end

-- MATH 

function math.sign(x)
    return x < 0 and -1 or (x > 0 and 1 or 0)
end

function math.ceil(x)
    local fx = math.floor(x)
    return fx == x and fx or fx + 1
end

function math.round(x)
    return math.floor(x + 0.5)
end

function math.div(a, b)
    return math.floor(a / b)
end

function math.lerp(a, b, t)
    return a + (b - a) * t
end

function math.clamp(x, min, max)
    return x < min and min or (x > max and max or x)
end