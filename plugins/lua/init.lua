
local max_line_length = 200
local max_lines = 3

require 'posix'

local function lua_handler(msg, arg)
    if #arg == 0 then
        bot.reply(msg, msg.sender.nick..': Usage: lua <code>')
        return
    end
    arg = arg:gsub('^%s*=', 'return ')
    local outrd, outwr = posix.pipe()
    local errrd, errwr = posix.pipe()
    local pid = posix.fork()
    if pid == -1 then -- failure
        error('failed to fork')
    elseif pid == 0 then -- child
        posix.close(1)
        posix.close(2)
        posix.dup(outwr)
        posix.dup(errwr)
        posix.chdir(bot.plugindir) -- err
        -- XXX replace "tuxbot" in the next line with the user account to setuid to XXX
        posix.exec('./sandbox', './sandbox', 'tmpdir', 'tuxbot', arg)
    else -- parent
        posix.wait(pid)
        posix.fcntl(outrd, posix.F_SETFL, posix.O_NONBLOCK)
        posix.fcntl(errrd, posix.F_SETFL, posix.O_NONBLOCK)
        local output = posix.read(outrd, 1000)
        local errmsg = posix.read(errrd, 50)
        posix.close(outrd)
        posix.close(errrd)
        local lines = {}
        if errmsg == 'cpulimit' then
            lines[1] = msg.sender.nick..': Sandbox CPU limit exceeded'
        elseif errmsg == 'not enough memory' then
            lines[1] = msg.sender.nick..': Sandbox memory limit exceeded'
        else
            for line in output:gmatch('[^\n]+') do
                if #line > max_line_length then line = line:sub(1, max_line_length-3)..'...' end
                lines[#lines+1] = msg.sender.nick..': '..line
            end
        end
        if #lines > max_lines then
            lines[max_lines] = '('..((#lines-max_lines)+1)..' more lines)'
            lines[max_lines+1] = nil
        end
        if #lines == 0 then
            bot.reply(msg, msg.sender.nick..': (No output)')
        else
            bot.send_multiline(msg, lines)
        end
    end
end

bot.commands['lua'] = {lua_handler, help='lua <code> -- Execute a line of Lua code and print the result.', mininterval = max_lines+0.5}

