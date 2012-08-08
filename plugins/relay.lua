
local issendingrealy = false

local function nickhash(nick)
    local num = 0
    for i = 1, #nick do num = num + nick:byte(i, i) end
    return num
end

local function isrelayed(msg, originchan)
    originchan = originchan or msg.args[1]
    local netname = bot.clients[msg.client].name
    for _, relaygroup in ipairs(config) do
        for _, chan in ipairs(relaygroup) do
            if chan[1] == netname and msg.client:nameeq(chan[2], originchan) then
                return {group=relaygroup, origin=chan}
            end
        end
    end
    return nil
end

local function relay(text, info, how)
    for _, chan in ipairs(info.group) do
        if chan ~= info.origin then
            issendingrelay = true
            if not how then
                bot.clientsbyname[chan[1]]:sendprivmsg(chan[2], text)
            elseif how == 'notice' then
                bot.clientsbyname[chan[1]]:sendnotice(chan[2], text)
            elseif how == 'me' then
                bot.clientsbyname[chan[1]]:sendctcp(chan[2], 'ACTION', text)
            end
            issendingrelay = false
        end
    end
end

local active_members = {}

local function on_active(nick, channel, client)
    local active_members_key = ('%s %s %s'):format(irc.lower(nick), irc.lower(channel), bot.clients[client].name)
    local timer = active_members[active_members_key]
    if timer then timer:cancel() end
    active_members[active_members_key] = bot.eventloop:timer(8 * 60 * 60, function () active_members[active_members_key] = nil end)
end

local msg_handlers = {
    ['PRIVMSG'] = function (msg)
        if not (msg.sender.nick and irc.isnick(msg.sender.nick) and irc.ischanname(msg.args[1]) and msg.args[2]) then return end
        local relayinfo = isrelayed(msg)
        if relayinfo then
            on_active(msg.sender.nick, msg.args[1], msg.client)
            local hash = (nickhash(msg.sender.nick) % #config.nickfmts) + 1
            local text = ('%s<%s%s%s>%s %s'):format(config.nickfmts[hash],
                                                    msg.sender.nick,
                                                    relayinfo.group.showchanname and '@'..relayinfo.origin[2] or '',
                                                    relayinfo.group.shownetname and '@'..relayinfo.origin[1] or '',
                                                    config.nickfmts.endfmt,
                                                    msg.args[2])
            relay(text, relayinfo)
        end
    end,
    ['NOTICE'] = function (msg)
        if not (msg.sender.nick and irc.isnick(msg.sender.nick) and irc.ischanname(msg.args[1]) and msg.args[2]) then return end
        local relayinfo = isrelayed(msg)
        if relayinfo then
            on_active(msg.sender.nick, msg.args[1], msg.client)
            local hash = (nickhash(msg.sender.nick) % #config.nickfmts) + 1
            local text = ('%s-%s%s%s-%s %s'):format(config.nickfmts[hash],
                                                    msg.sender.nick,
                                                    relayinfo.group.showchanname and '@'..relayinfo.origin[2] or '',
                                                    relayinfo.group.shownetname and '@'..relayinfo.origin[1] or '',
                                                    config.nickfmts.endfmt,
                                                    msg.args[2])
            relay(text, relayinfo)
        end
    end,
    [':CTCP'] = function (msg)
        if not (msg.sender.nick and irc.isnick(msg.sender.nick) and irc.ischanname(msg.args[1]) and msg.args[2] == 'ACTION' and msg.args[3]) then return end
        local relayinfo = isrelayed(msg)
        if relayinfo then
            on_active(msg.sender.nick, msg.args[1], msg.client)
            local hash = (nickhash(msg.sender.nick) % #config.nickfmts) + 1
            local text = ('* %s%s%s%s%s %s'):format(config.nickfmts[hash],
                                                    msg.sender.nick,
                                                    relayinfo.group.showchanname and '@'..relayinfo.origin[2] or '',
                                                    relayinfo.group.shownetname and '@'..relayinfo.origin[1] or '',
                                                    config.nickfmts.endfmt,
                                                    msg.args[3])
            relay(text, relayinfo)
        end
    end,
    ['KICK'] = function (msg)
        local relayinfo = isrelayed(msg)
        if relayinfo then
            local text = ('\0036* \002%s\002 has kicked \002%s\002 on \002%s@%s\002'):format(msg.sender.nick, msg.args[2], relayinfo.origin[2], relayinfo.origin[1])
            if msg.args[3] then text = ('%s (%s)'):format(text, msg.args[3]) end
            text = text..'\015'
            relay(text, relayinfo)
        end
    end,
    ['TOPIC'] = function (msg)
        local relayinfo = isrelayed(msg)
        if relayinfo then
            local text = ('\0036* \002%s\002 has changed the topic of \002%s@%s\002 to:\015 %s'):format(msg.sender.nick, relayinfo.origin[2], relayinfo.origin[1], msg.args[2])
            relay(text, relayinfo)
        end
    end,
    --[[['MODE'] = function (msg)
        local relayinfo = isrelayed(msg)
        if relayinfo then
            local text = ('\0036* \002%s\002 has set mode [\002%s\002] on \002%s@%s\002\015'):format(msg.sender.nick, table.concat(msg.args, ' ', 2), relayinfo.origin[2], relayinfo.origin[1])
            relay(text, relayinfo)
        end
    end,]]
    ['JOIN'] = function (msg)
        local active_members_key = ('%s %s %s'):format(irc.lower(msg.sender.nick), irc.lower(msg.args[1]), bot.clients[msg.client].name)
        local timer = active_members[active_members_key]
        if timer then
            local relayinfo = isrelayed(msg)
            if relayinfo then
                local text = ('\0036* \002%s\002 has joined \002%s@%s\002'):format(msg.sender.nick, relayinfo.origin[2], relayinfo.origin[1])
                relay(text, relayinfo)
            end
        end
    end,
    ['PART'] = function (msg)
        local active_members_key = ('%s %s %s'):format(irc.lower(msg.sender.nick), irc.lower(msg.args[1]), bot.clients[msg.client].name)
        local timer = active_members[active_members_key]
        if timer then
            local relayinfo = isrelayed(msg)
            if relayinfo then
                local text = ('\0036* \002%s\002 has left \002%s@%s\002'):format(msg.sender.nick, relayinfo.origin[2], relayinfo.origin[1])
                if msg.args[2] then text = ('%s (%s)'):format(text, msg.args[2]) end
                relay(text, relayinfo)
            end
        end
    end,
    ['QUIT'] = function (msg)
        for _, chanstate in pairs(bot.clients[msg.client].tracker.chanstates) do
            local active_members_key = ('%s %s %s'):format(irc.lower(msg.sender.nick), irc.lower(chanstate.name), bot.clients[msg.client].name)
            local timer = active_members[active_members_key]
            if timer then
                local relayinfo = isrelayed(msg, chanstate.name)
                if relayinfo then
                    local text = ('\0036* \002%s\002 has quit on \002%s\002'):format(msg.sender.nick, relayinfo.origin[1])
                    if msg.args[1] then text = ('%s (%s)'):format(text, msg.args[1]) end
                    relay(text, relayinfo)
                end
            end
        end
    end,
    ['331'] = function (msg)
        local relayinfo = isrelayed(msg, msg.args[2])
        if relayinfo then
            local text = ('\0036* \002%s@%s\002 has no topic.'):format(relayinfo.origin[2], relayinfo.origin[1])
            relay(text, relayinfo)
        end
    end,
    ['332'] = function (msg)
        local relayinfo = isrelayed(msg, msg.args[2])
        if relayinfo then
            local text = ('\0036* The topic of \002%s@%s\002 is:\015 %s'):format(relayinfo.origin[2], relayinfo.origin[1], msg.args[2])
            relay(text, relayinfo)
        end
    end,
    ['324'] = function (msg)
        local relayinfo = isrelayed(msg, msg.args[2])
        if relayinfo then
            local text = ('\0036* The mode of \002%s@%s\002 is %s'):format(relayinfo.origin[2], relayinfo.origin[1], msg.args[3])
            relay(text, relayinfo)
        end
    end,
}

local function msg_handler(_, msg)
    local handler = msg_handlers[msg.cmd]
    if handler then handler(msg) end
end

local function sent_handler(isnotice, client, to, senttext, time)
    if issendingrelay then return end
    for _, relaygroup in ipairs(config) do
        local match = nil
        for _, chan in ipairs(relaygroup) do
            if chan[1] == bot.clients[client].name and client:nameeq(chan[2], to) then
                match = chan
                break
            end
        end
        if match then
            local hash = (nickhash(client:get_nick()) % #config.nickfmts) + 1
            local text = config.nickfmts[hash]..(isnotice and '-' or '<')..client:get_nick()
            if relaygroup.showchanname then text = text..'@'..match[2] end
            if relaygroup.shownetname then text = text..'@'..match[1] end
            text = text..(isnotice and '-' or '>')..config.nickfmts.endfmt..' '..senttext
            for _, chan in ipairs(relaygroup) do
                if chan ~= match then
                    issendingrelay = true
                    if isnotice then
                        bot.clientsbyname[chan[1]]:sendnotice(chan[2], text)
                    else
                        bot.clientsbyname[chan[1]]:sendprivmsg(chan[2], text)
                    end
                    issendingrelay = false
                end
            end
        end
    end
end

local function sent_privmsg_handler(...)
    sent_handler(false, ...)
end

local function sent_notice_handler(...)
    sent_handler(true, ...)
end

bot.event_handlers['tracker_receivedmessage'] = msg_handler
bot.event_handlers['sentprivmsg'] = sent_privmsg_handler
bot.event_handlers['sentnotice'] = sent_notice_handler

--[=[local helptext = '*** "\002relay\002" command help ***\
The relay command lets you get info about and moderate other channels in a\
relay group. To use it follow it with a command followed by the args required\
by that command. Here is the list of commands:\
\002help\002 -- Show this help message.\
\002topic <channel> [<new topic>]\002 -- Get/set the channel topic.\
\002mode <channel> [<flags>]\002 -- Get/set the channel mode.\
\002kick <channel> <nick> [<reason>]\002 -- Kick a member.\
\002list\002 -- List the channels in the relay group.\
\002names [<channel>]\002 -- List the members in all the channels (or in a specific\
    channel, if provided).\
(Note that where you need to specify a channel, you can use only the channel\
name if all the channel names in the group are different, or only the network\
name if the group does not have more than one channel on the same network.\
Otherwise, you have to use "\002#channel@Network\002".)\
Note that the \002relay\002 command doesn\'t have a way to remotely use ChanServ. To\
use it, you must join the network yourself or use the \002raw\002 command.\
*** end of "\002relay\002" command help ***'

local function parse_channel_name(msg, str)
    local chan, net = str:match('.+@.+')
    if chan and not irc.ischanname(chan) then return nil end
    if not chan then
        if irc.ischanname(str) then
            chan = str
        else
            net = str
        end
    end
end

local function relay_cmd_handler(msg, arg)
    local args = {}
    for i in arg:gmatch('[^ ]+') do args[#args+1] = i end
    if args[1] then args[1] = args[1]:lower() end
    if #args == 0 or args[1] == 'help' then
        for line in helptext:gmatch('[^\n]+') do
            msg.client:sendnotice(msg.sender.nick, line)
        end
    elseif args[1] == 'topic' then
        if args[2] then
            local chan = parse_channel_name(msg, args[2])
            if chan then
                if args[3] then
                    --bot.clientsbyname[chan[1]]:sendmessage('TOPIC', chan[2], args[3])
                else
                    bot.clientsbyname[chan[1]]:sendmessage('TOPIC', chan[2])
                end
            else
                bot.reply(msg, ('%s: Invalid or ambiguous channel name.'):format(msg.sender.nick))
            end
        else
            bot.reply(msg, ('%s: Usage: relay topic <channel> [<new topic>]'):format(msg.sender.nick))
        end
    elseif args[1] == 'mode' then
        if args[2] then
            local chan = parse_channel_name(msg, args[2])
            if chan then
                if args[3] then
                    --bot.clientsbyname[chan[1]]:sendmessage('MODE', chan[2], unpack(args, 3))
                else
                    bot.clientsbyname[chan[1]]:sendmessage('MODE', chan[2])
                end
            else
                bot.reply(msg, ('%s: Invalid or ambiguous channel name.'):format(msg.sender.nick))
            end
        else
            bot.reply(msg, ('%s: Usage: relay mode <channel> [<flags>]'):format(msg.sender.nick))
        end
    else
        bot.reply(msg, ('%s: "%s": unknown relay command'):format(msg.sender.nick, args[1]))
    end
end

bot.commands['relay'] = {relay_cmd_handler, help='Get info about and moderate other channels in a relay group. Run with no args to get a help message.'}
]=]
