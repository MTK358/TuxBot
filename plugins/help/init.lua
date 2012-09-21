
local luasql = require 'luasql.sqlite3'

local dbenv = assert(luasql.sqlite3())
local dbconn = assert(dbenv:connect(bot.plugindir..'/database.sqlite3'))

-- this just fails if the table exists, it would be nice to check, though
dbconn:execute('CREATE TABLE help(key VARCHAR(50), text VARCHAR(1000));')

local function sqlquote(str)
    return "'"..str:gsub("'", "''").."'"
end

local function search(keywords)
    local results = {}

    local query = 'SELECT key FROM help WHERE ('
    for i, keyword in ipairs(keywords) do
        if i ~= 1 then query = query..' OR ' end
        query = query..'key = '..sqlquote(keyword)
    end
    local cur = assert(dbconn:execute(query..');'))
    cur:fetch(results)
    cur:close()

    local query = 'SELECT key FROM help WHERE ('
    for i, keyword in ipairs(keywords) do
        if i ~= 1 then query = query..' AND ' end
        query = query..'text GLOB '..sqlquote('*'..keyword..'*')
    end
    local cur = assert(dbconn:execute(query..');'))
    while true do local i = cur:fetch() if i then results[#results+1] = i else break end end
    cur:close()

    return results
end

local function help_handler(msg, arg)
    local key = arg:match('^ *([^ ]+) *$')
    if not key then
        bot.reply(msg, msg.sender.nick..': Usage: help <key> -- you can also try "searchhelp <keywords>"')
        return
    end
    key = key:lower()
    local cur = assert(dbconn:execute(('SELECT text FROM help WHERE key = %s;'):format(sqlquote(key))))
    local text = cur:fetch()
    cur:close()
    if text then
        bot.reply(msg, msg.sender.nick..': '..text)
    else
        local matches = search({key})
        if #matches ~= 0 then
            if #matches > 15 then
                matches[16] = nil
            end
            bot.reply(msg, msg.sender.nick..': No exact match, maybe look at: '..table.concat(matches, ' '))
        else
            bot.reply(msg, msg.sender.nick..': No match')
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
    local matches = search(keywords)
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
    local cs = bot.clients[msg.client].tracker.chanstates[msg.args[1]]
    if cs then
        if not (cs.members[msg.sender.nick] and cs.members[msg.sender.nick].mode:match('o')) then
            bot.reply(msg, msg.sender.nick..': You are not permitted to use this command.')
            return
        end
    end
    local key, text = arg:match('^ *([^ ]+) +([^ ].*)')
    if not key then
        bot.reply(msg, msg.sender.nick..': Usage: sethelp <key> <text>')
        return
    end
    key = key:lower()
    local cur = assert(dbconn:execute(('SELECT text FROM help WHERE key = %s;'):format(sqlquote(key))))
    if cur:fetch() then
        assert(dbconn:execute(('UPDATE help SET text = %s WHERE key = %s;'):format(sqlquote(text), sqlquote(key))))
    else
        assert(dbconn:execute(('INSERT INTO help(key, text) VALUES (%s, %s);'):format(sqlquote(key), sqlquote(text))))
    end
    cur:close()
end

local function rmhelp_handler(msg, arg)
    local cs = bot.clients[msg.client].tracker.chanstates[msg.args[1]]
    if cs then
        if not (cs.members[msg.sender.nick] and cs.members[msg.sender.nick].mode:match('o')) then
            bot.reply(msg, msg.sender.nick..': You are not permitted to use this command.')
            return
        end
    end
    local key = arg:match('^ *([^ ]+) *$')
    if not key then
        bot.reply(msg, msg.sender.nick..': Usage: rmhelp <key>')
        return
    end
    key = key:lower()
    local cur = assert(dbconn:execute(('SELECT text FROM help WHERE key = %s;'):format(sqlquote(key))))
    if cur then
        assert(dbconn:execute(('DELETE FROM help WHERE key = %s;'):format(sqlquote(key))))
    end
    cur:close()
end

bot.commands['help'] = {help_handler, help='help <key> -- Get help about <key>'}
bot.commands['searchhelp'] = {searchhelp_handler, help='searchhelp <keywords> -- Search for help messages containing <keywords>'}
bot.commands['sethelp'] = {sethelp_handler, help='sethelp <key> <text> -- Set the help message for <key>'}
bot.commands['rmhelp'] = {rmhelp_handler, help='rmhelp <key> -- Remove the help message for <key>'}

