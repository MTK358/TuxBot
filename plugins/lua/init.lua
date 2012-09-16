
require 'posix'

local max_line_length = 200
local max_lines = 3

local function sh_quote(str)
    return "'"..str:gsub("'", [['"'"']]).."'"
end

local function runcmd(cmd, ...)

end

local function lua_handler(msg, arg)
    if #arg == o then
        bot.reply(msg, msg.sender.nick..': Usage: lua <code>')
        return
    end
    msg = msg:gsub('^%s*=', 'return ')
    local quoteddir = sh_quote(bot.plugindir)
    -- TODO use a proper library for this instead of relying on shell quoting
    local stream = io.popen(('cd %s; ulimit -t1 -v10000000; ./sandbox %s'):format(quoteddir, sh_quote(arg)))
    local result = stream:read('*a')
    stream:close()
    local lines = {}
    for line in result:gmatch('[^\n]+') do
        if #line > max_line_length then line = line:sub(1, max_line_length-3)..'...' end
        lines[#lines+1] = line
    end
    if #lines > max_lines then
        lines[max_lines] = '('..((#lines-max_lines)+1)..' more lines)'
        lines[max_lines+1] = nil
    end
    for _, line in ipairs(lines) do
        bot.reply(msg, msg.sender.nick..': '..line)
    end
end

bot.commands['lua'] = {lua_handler, help='lua <code> -- Execute a line of Lua code and print the result.', mininterval = max_lines+0.5}

