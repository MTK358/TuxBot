
local function trackerinfo_handler(msg, arg)
    local nick = arg:match('^ *([^ ]+) *$')
    if nick then
        local chan = bot.clients[msg.client].tracker.chanstates[msg.args[1]]
        local member = chan.members[nick]
        if member then
            bot.reply(msg, ('%s: Mode: %s Nick: %s User: %s Host: %s'):format(msg.sender.nick,
                                                                              member.mode,
                                                                              member.prefix.nick,
                                                                              member.prefix.user or '(N/A)',
                                                                              member.prefix.host or '(N/A)'))
        else
            bot.reply(msg, ('%s: No such member: %s'):format(msg.sender.nick, nick))
        end
    else
        local chan = bot.clients[msg.client].tracker.chanstates[msg.args[1]]
        local mode = chan.mode or '(None)'
        local count = 0
        for k, v in pairs(chan.members) do count = count + 1 end
        bot.reply(msg, ('%s: Mode: %s, %s Members'):format(msg.sender.nick, mode, count))
    end
end

bot.commands['trackerinfo'] = {trackerinfo_handler, help='trackerinfo [nick] -- get the channel tracking info the bot has'}

