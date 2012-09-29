
local max_line_length = 200
local max_lines = 3

config = config or {}

require 'posix'

local function lua_handler(msg, arg)
    if (not irc.ischanname(msg.args[1])) and (not config.enable_private) then
        bot.reply(msg, msg.sender.nick..': The lua command isn\'t available for private use')
        return
    end
    if config.channel_whitelist and irc.ischanname(msg.args[1]) then
        local match = false
        for _, i in ipairs(config.channel_whitelist) do
            if msg.client:nameeq(i, msg.args[1]) then
                match = true
                break
            end
        end
        if not match then
            bot.reply(msg, msg.sender.nick..': The lua command isn\'t available for this channel')
            return
        end
    end
    if #arg == 0 then
        bot.reply(msg, msg.sender.nick..': Usage: lua <code>')
        return
    end
    arg = arg:gsub('^%s*=', 'return ')
    local outrd, outwr = posix.pipe()
    local errrd, errwr = posix.pipe()
    assert(posix.fcntl(outrd, posix.F_SETFL, posix.O_NONBLOCK))
    assert(posix.fcntl(errrd, posix.F_SETFL, posix.O_NONBLOCK))
    local pid = posix.fork()
    if pid == -1 then -- failure
        error('failed to fork')
    elseif pid == 0 then -- child
        pcall(function ()
            posix.close(1)
            posix.close(2)
            posix.dup(outwr)
            posix.dup(errwr)
            assert(posix.chdir(bot.plugindir))
            -- XXX replace "tuxbot" in the next line with the user account to setuid to XXX
            assert(posix.exec('./sandbox', 'tmpdir', 'tuxbot', arg))
        end)
        os.exit(1)
    else -- parent
        posix.wait(pid)
        local output = posix.read(outrd, 1000) or ''
        local errmsg = posix.read(errrd, 50) or ''
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

bot.commands['lua'] = {lua_handler, help='lua <code> -- Execute a line of Lua code and print the result.'}

