local event = {
    mousepressed ={},
    mousereleased={},
    wheelmoved   ={},

    keypressed ={},
    keyreleased={},

    update={},
    draw  ={},
}

local function execQueue( queue, args )
    local meta = { queue = queue }
    for k,fu in pairs( queue ) do 
        meta.queueKey = k
        meta.fu = fu 
        fu( args, meta )
    end
end

function love.mousepressed(x, y, button, istouch)
	execQueue(event.mousepressed,{x=x, y=y, button=button, istouch=istouch})
end

function love.mousereleased(x, y, button)
	execQueue(event.mousereleased,{x=x, y=y, button=button})
end

function love.wheelmoved(x, y)
	execQueue(event.wheelmoved,{x=x, y=y})
end

function love.keypressed(key, scancode, isrepeat)
	execQueue(event.keypressed,{key=key, scancode=scancode, isrepeat=isrepeat})
end

function love.keyreleased(key)
	execQueue(event.keyreleased,{key=key})
end

function love.update(dt)
    execQueue(event.update,{dt=dt})
end

function love.draw()
    execQueue(event.draw,{})
end


return event