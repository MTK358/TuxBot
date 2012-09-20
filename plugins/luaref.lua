
local function luaref_handler(msg, arg)
    local name = arg:match('[^ ]+')
    if name then
        if name:match('^[%d.]+$') or name:match('^luaL?_') then
            bot.reply(msg, ('%s: http://www.lua.org/manual/5.1/manual.html#%s'):format(msg.sender.nick, name))
        else
            bot.reply(msg, ('%s: http://www.lua.org/manual/5.1/manual.html#pdf-%s'):format(msg.sender.nick, name))
        end
    else
        bot.reply(msg, ('%s: http://www.lua.org/manual/5.1/manual.html'):format(msg.sender.nick))
    end
end

bot.commands['luaref'] = {luaref_handler, help='luaref [<keyword>] -- Get a link to a part of the Lua reference manual.'}

