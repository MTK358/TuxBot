
local dbfile = bot.plugindir..'/'..(config and config.dbfile or 'db.txt')

local cache = {}

do
    local f = io.open(dbfile, 'r')
    if f then
        for line in f:lines() do
            local key, text = line:match('^([^ ]+) ([^ ].*)')
            if key then cache[key] = text end
        end
        f:close()
    end
end

local function writedb()
    local f = assert(io.open(dbfile, 'w'))
    for key, text in pairs(cache) do
        f:write(('%s %s\n'):format(key, text))
    end
    f:close()
end

local function sethelp(key, text)
    if text then
        if cache[key] then
            cache[key] = text
            writedb()
        else
            cache[key] = text
            local f = assert(io.open(dbfile, 'a'))
            f:write(('%s %s\n'):format(key, text))
            f:close()
        end
    elseif cache[key] then
        cache[key] = nil
        writedb()
    end
end

local function gethelp(key)
    return cache[key]
end

local function search(keywords, max)
    max = max or math.huge
    local results = {}
    for i, keyword in ipairs(keywords) do
        if cache[keyword] then
            table.insert(results, keyword)
            if #results >= max then return results end
        end
    end
    if #results < max then
        for key, text in pairs(cache) do
            for i, keyword in ipairs(keywords) do
                if text:find(keyword, 0, true) then
                    table.insert(results, key)
                    if #results >= max then return results end
                    break
                end
            end
        end
    end
    return results
end

local function help_handler(msg, arg)
    local key = arg:match('^ *([^ ]+) *$')
    if not key then
        bot.reply(msg, msg.sender.nick..': Usage: help <key> -- you can also try "searchhelp <keywords>"')
        return
    end
    key = key:lower()
    local text = gethelp(key)
    if text then
        bot.reply(msg, msg.sender.nick..': '..text)
    else
        local matches = search({key}, 15)
        if #matches ~= 0 then
            bot.reply(msg, msg.sender.nick..': (No exact match, maybe look at: '..table.concat(matches, ' ')..')')
        else
            bot.reply(msg, msg.sender.nick..': (No match)')
        end
    end
end

local function searchhelp_handler(msg, arg)
    local keywords = {}
    for i in arg:gmatch('[^ ]+') do keywords[#keywords+1] = i:lower() end
    if #keywords == 0 then
        bot.reply(msg, msg.sender.nick..': Usage: searchhelp <keywords>')
        return
    end
    local matches = search(keywords, 42)
    if #matches ~= 0 then
        if #matches > 41 then
            matches[41] = ('(and %d more)'):format(#matches - 40)
            matches[42] = nil
        end
        bot.reply(msg, msg.sender.nick..': '..table.concat(matches, ' '))
    else
        bot.reply(msg, msg.sender.nick..': No matches')
    end
end

local function sethelp_handler(msg, arg)
    if not bot.plugins.perms.check('helpedit', msg.client, msg.args[1], msg.sender.nick) then
        bot.reply(msg, msg.sender.nick..': You are not permitted to use this command.')
        return
    end
    local key, text = arg:match('^ *([^ ]+) +([^ ].*)')
    if not key then
        bot.reply(msg, msg.sender.nick..': Usage: sethelp <key> <text>')
        return
    end
    key = key:lower()
    sethelp(key, text)
end

local function rmhelp_handler(msg, arg)
    if not bot.plugins.perms.check('helpedit', msg.client, msg.args[1], msg.sender.nick) then
        bot.reply(msg, msg.sender.nick..': You are not permitted to use this command.')
        return
    end
    local key = arg:match('^ *([^ ]+) *$')
    if not key then
        bot.reply(msg, msg.sender.nick..': Usage: rmhelp <key>')
        return
    end
    key = key:lower()
    sethelp(key, nil)
end

bot.commands['help'] = {help_handler, help='help <key> -- Get help about <key>', mininterval=1}
bot.commands['searchhelp'] = {searchhelp_handler, help='searchhelp <keywords> -- Search for help messages containing <keywords>', mininterval=1}
bot.commands['sethelp'] = {sethelp_handler, help='sethelp <key> <text> -- Set the help message for <key>', mininterval=1}
bot.commands['rmhelp'] = {rmhelp_handler, help='rmhelp <key> -- Remove the help message for <key>', mininterval=1}

