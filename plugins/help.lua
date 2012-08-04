
local function help_handler(msg, arg)
    local key = arg:match('^ *([^ ]+) *$')
    if not key then
        bot.reply(msg, msg.sender.nick..': Usage: help <key>')
        return
    end
    key = key:lower()
    if not config.entries[key] then
        bot.reply(msg, msg.sender.nick..': No help message found for "'..key..'"')
        local matches = {}
        for k, v in pairs(config.entries) do
            if v:find(key, 1, true) then
                matches[#matches+1] = k
            end
        end
        if #matches ~= 0 then
            if #matches > 15 then
                matches[16] = ('and %d more entries'):format(#matches - 15)
                matches[17] = nil
            end
            bot.reply(msg, ('Entries containing the word "%s" include: %s.'):format(key, table.concat(matches, ', ')))
        end
    else
        bot.reply(msg, msg.sender.nick..': '..config.entries[key])
    end
end

bot.commands['help'] = {help_handler, help='help <key> -- Get help about <key>'}

