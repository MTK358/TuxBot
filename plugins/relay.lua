
local infocolor = config.infocolor or '\029'

local issendingrelay = false

local relaymsgs = {}

local function clear_relaymsgs()--{{{
    if next(relaymsgs) then relaymsgs = {} end
    bot.eventloop:timer(15, clear_relaymsgs)
end--}}}
bot.eventloop:timer(15, clear_relaymsgs)

local function nickhash(nick)--{{{
    local num = 0
    for i = 1, #nick do num = num + nick:byte(i, i) end
    return num
end--}}}

local function isrelayed(msg, originchan)--{{{
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
end--}}}

local function relay(text, info, how)--{{{
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
    local client = bot.clientsbyname[info.origin[1]]
    relaymsgs[{client, client:lower(info.origin[2]), text}] = true
end--}}}

local function feedbackcheck(msg, net, chan, text)--{{{
    for sent in pairs(relaymsgs) do
        if sent[1] == msg.client and sent[2] == msg.client:lower(chan) then
            if text:match(sent[3]:gsub('[^%w_]', '%%%1')) then
                if bot.plugins.tmpban then
                    bot.plugins.tmpban.env.tmpban(msg.client, chan, msg.sender.nick, 60, 'Relay feedback loop')
                else
                    msg.client:sendmessage('KICK', chan, msg.sender.nick, 'Relay feedback loop')
                end
            end
        end
    end
end--}}}

local active_members = {}

local function on_active(nick, channel, client)--{{{
    local active_members_key = ('%s %s %s'):format(client:lower(nick), client:lower(channel), bot.clients[client].name)
    local timer = active_members[active_members_key]
    if timer then timer:cancel() end
    active_members[active_members_key] = bot.eventloop:timer(8 * 60 * 60, function () active_members[active_members_key] = nil end)
end--}}}

local msg_handlers = {--{{{
    ['PRIVMSG'] = function (msg)--{{{
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
            feedbackcheck(msg, relayinfo.origin[1], relayinfo.origin[2], msg.args[2])
        end
    end,--}}}
    ['NOTICE'] = function (msg)--{{{
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
            feedbackcheck(msg, relayinfo.origin[1], relayinfo.origin[2], msg.args[2])
        end
    end,--}}}
    [':CTCP'] = function (msg)--{{{
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
            feedbackcheck(msg, relayinfo.origin[1], relayinfo.origin[2], msg.args[3])
        end
    end,--}}}
    ['KICK'] = function (msg)--{{{
        local relayinfo = isrelayed(msg)
        if relayinfo then
            local text = (infocolor..'* %s has kicked %s on %s@%s'):format(msg.sender.nick, msg.args[2], relayinfo.origin[2], relayinfo.origin[1])
            if msg.args[3] then text = ('%s (%s)'):format(text, msg.args[3]) end
            text = text..'\015'
            relay(text, relayinfo)
        end
    end,--}}}
    ['TOPIC'] = function (msg)--{{{
        local relayinfo = isrelayed(msg)
        if relayinfo then
            local text = (infocolor..'* %s has changed the topic of %s@%s to:\015 %s'):format(msg.sender.nick, relayinfo.origin[2], relayinfo.origin[1], msg.args[2])
            relay(text, relayinfo)
        end
    end,--}}}
    --[[['MODE'] = function (msg)--{{{
        local relayinfo = isrelayed(msg)
        if relayinfo then
            local text = (infocolor..'* %s has set mode [%s] on %s@%s\015'):format(msg.sender.nick, table.concat(msg.args, ' ', 2), relayinfo.origin[2], relayinfo.origin[1])
            relay(text, relayinfo)
        end
    end,]]--}}}
    ['JOIN'] = function (msg)--{{{
        local active_members_key = ('%s %s %s'):format(msg.client:lower(msg.sender.nick), msg.client:lower(msg.args[1]), bot.clients[msg.client].name)
        local timer = active_members[active_members_key]
        if timer then
            local relayinfo = isrelayed(msg)
            if relayinfo then
                local text = (infocolor..'* %s has joined %s@%s'):format(msg.sender.nick, relayinfo.origin[2], relayinfo.origin[1])
                relay(text, relayinfo)
            end
        end
    end,--}}}
    ['PART'] = function (msg)--{{{
        local active_members_key = ('%s %s %s'):format(msg.client:lower(msg.sender.nick), msg.client:lower(msg.args[1]), bot.clients[msg.client].name)
        local timer = active_members[active_members_key]
        if timer then
            local relayinfo = isrelayed(msg)
            if relayinfo then
                local text = (infocolor..'* %s has left %s@%s'):format(msg.sender.nick, relayinfo.origin[2], relayinfo.origin[1])
                if msg.args[2] then text = ('%s (%s)'):format(text, msg.args[2]) end
                relay(text, relayinfo)
            end
        end
    end,--}}}
    ['QUIT'] = function (msg)--{{{
        for _, chanstate in pairs(bot.clients[msg.client].tracker.chanstates) do
            local active_members_key = ('%s %s %s'):format(msg.client:lower(msg.sender.nick), msg.client:lower(chanstate.name), bot.clients[msg.client].name)
            local timer = active_members[active_members_key]
            if timer then
                local relayinfo = isrelayed(msg, chanstate.name)
                if relayinfo then
                    local text = (infocolor..'* %s has quit on %s'):format(msg.sender.nick, relayinfo.origin[1])
                    if msg.args[1] then text = ('%s (%s)'):format(text, msg.args[1]) end
                    relay(text, relayinfo)
                end
            end
        end
    end,--}}}
    ['NICK'] = function (msg)--{{{
        for _, chanstate in pairs(bot.clients[msg.client].tracker.chanstates) do
            local active_members_key = ('%s %s %s'):format(msg.client:lower(msg.sender.nick), msg.client:lower(chanstate.name), bot.clients[msg.client].name)
            local timer = active_members[active_members_key]
            if not timer then
                active_members_key = ('%s %s %s'):format(msg.client:lower(msg.args[1]), msg.client:lower(chanstate.name), bot.clients[msg.client].name)
                timer = active_members[active_members_key]
            end
            if timer then
                local relayinfo = isrelayed(msg, chanstate.name)
                if relayinfo then
                    local text = (infocolor..'* %s is now known as %s on %s'):format(msg.sender.nick, msg.args[1], relayinfo.origin[1])
                    if msg.args[1] then text = ('%s (%s)'):format(text, msg.args[1]) end
                    relay(text, relayinfo)
                end
            end
        end
    end,--}}}
    ['331'] = function (msg)--{{{
        local relayinfo = isrelayed(msg, msg.args[2])
        if relayinfo then
            local text = (infocolor..'* %s@%s has no topic.'):format(relayinfo.origin[2], relayinfo.origin[1])
            relay(text, relayinfo)
        end
    end,--}}}
    ['332'] = function (msg)--{{{
        local relayinfo = isrelayed(msg, msg.args[2])
        if relayinfo then
            local text = (infocolor..'* The topic of %s@%s is:\015 %s'):format(relayinfo.origin[2], relayinfo.origin[1], msg.args[2])
            relay(text, relayinfo)
        end
    end,--}}}
    ['324'] = function (msg)--{{{
        local relayinfo = isrelayed(msg, msg.args[2])
        if relayinfo then
            local text = (infocolor..'* The mode of %s@%s is %s'):format(relayinfo.origin[2], relayinfo.origin[1], msg.args[3])
            relay(text, relayinfo)
        end
    end,--}}}
}--}}}

local function msg_handler(_, msg)--{{{
    local handler = msg_handlers[msg.cmd]
    if handler then handler(msg) end
end--}}}

local function sent_handler(isnotice, client, to, senttext, time)--{{{
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
end--}}}

local function sent_privmsg_handler(...)--{{{
    sent_handler(false, ...)
end--}}}

local function sent_notice_handler(...)--{{{
    sent_handler(true, ...)
end--}}}

bot.event_handlers['tracker_receivedmessage'] = msg_handler
bot.event_handlers['sentprivmsg'] = sent_privmsg_handler
bot.event_handlers['sentnotice'] = sent_notice_handler

local function parse_channel_name(msg, str)--{{{
    local chanstr, netstr = str:match('(.+)@(.+)')
    local group
    for _, relaygroup in ipairs(config) do
        for _, chan in ipairs(relaygroup) do
            if chan[1] == msg.client.netinfo.name and msg.client:nameeq(chan[2], msg.args[1]) then
                group = relaygroup
                break
            end
        end
        if group then break end
    end
    if not group then return end
    if netstr then
        for _, chan in ipairs(group) do
            if chan[1]:lower() == netstr:lower() and msg.client:nameeq(chan[2], chanstr) then
                return bot.clientsbyname[chan[1]], chan[2]
            end
        end
    else
        -- TODO
    end
end--}}}

local function is_sender_trusted(msg, client, channame)--{{{
    local cs = bot.clients[msg.client].tracker.chanstates[msg.args[1]]
    if cs then
        return cs.members[msg.sender.nick] and cs.members[msg.sender.nick].mode:match('o')
    end
    return false
end--}}}

local relay_cmds--{{{
relay_cmds = {
    ['help'] = {--{{{
        usage = 'relay help [<subcommand>] -- get help about the relay command',
        func = function (msg, arg)
            local cmdname = arg:match('[^ ]+')
            if cmdname then
                if relay_cmds[cmdname] then
                    bot.reply(msg, ('%s: %s'):format(msg.sender.nick, relay_cmds[cmdname].usage))
                else
                    bot.reply(msg, ('%s: relay: no such command: %s'):format(msg.sender.nick, cmd))
                end
            else
                local str = msg.sender.nick..': relay commands: '
                for name, info in pairs(relay_cmds) do
                    str = str..name..' '
                end
                str = str..'-- try "relay help <cmd>" for help about a command'
                bot.reply(msg, str)
            end
        end,
    },--}}}
    ['topic'] = {--{{{
        usage = 'relay topic <channel> [<new topic>] -- get/set the topic of another channel',
        func = function (msg, arg)
            local chan, newtopic = arg:match('^ *([^ ]+) +([^ ].-)$')
            if not chan then chan = arg:match('[^ ]+') end
            if not chan then
                bot.reply(msg, ('%s: Usage: relay topic <channel> [<new topic>]'):format(msg.sender.nick))
                return
            end
            local client, channame = parse_channel_name(msg, chan)
            if not client then
                bot.reply(msg, ('%s: invalid channel name: %s'):format(msg.sender.nick, chan))
                return
            end
            local chanstate = bot.clients[client].tracker.chanstates[channame]
            if chanstate then
                if newtopic then
                    if is_sender_trusted(msg, client, channame) then
                        msg.client:sendmessage('TOPIC', channame, newtopic)
                    else
                        bot.reply(msg, ('%s: you are not permitted to use that command'):format(msg.sender.nick))
                    end
                else
                    bot.reply(msg, ('%s: %s'):format(msg.sender.nick, chanstate.topic or '(the channel doesn\'t have a topic)'))
                end
            else
                bot.reply(msg, ('%s: (I am not on that channel)'):format(msg.sender.nick))
            end
        end,
    },--}}}
    ['mode'] = {--{{{
        usage = 'relay mode <channel> [<mode>] -- get/set the mode of another channel',
        func = function (msg, arg)
            local chan, newmode = arg:match('^ *([^ ]+) +([^ ].-)$')
            if not chan then chan = arg:match('[^ ]+') end
            if not chan then
                bot.reply(msg, ('%s: Usage: relay mode <channel> [<mode>]'):format(msg.sender.nick))
                return
            end
            if newmode then
                local modeargs = {}
                for i in newmode:gmatch('[^ ]+') do modeargs[#modeargs+1] = i end
                newmode = modeargs
            end
            local client, channame = parse_channel_name(msg, chan)
            if not client then
                bot.reply(msg, ('%s: invalid channel name: %s'):format(msg.sender.nick, chan))
                return
            end
            local chanstate = bot.clients[client].tracker.chanstates[channame]
            if chanstate then
                if newtopic then
                    if is_sender_trusted(msg, client, channame) then
                        msg.client:sendmessage('MODE', channame, unpack(newmode))
                    else
                        bot.reply(msg, ('%s: you are not permitted to use that command'):format(msg.sender.nick))
                    end
                else
                    bot.reply(msg, ('%s: %s'):format(msg.sender.nick, chanstate.mode or '(channel mode unknown)'))
                end
            else
                bot.reply(msg, ('%s: (I am not on that channel)'):format(msg.sender.nick))
            end
        end,
    },--}}}
    ['kick'] = {--{{{
        usage = 'relay kick <channel> <nick> [<message>] -- kick a member from another channel',
        func = function (msg, arg)
            local chan, nick, message = arg:match('^ *([^ ]+) +([^ ]+) +([^ ].-)$')
            if not chan then chan, nick = arg:match('([^ ]+) +([^ ]+)') end
            if not chan then
                bot.reply(msg, ('%s: Usage: relay mode <channel> <nick> [<message>]'):format(msg.sender.nick))
                return
            end
            local client, channame = parse_channel_name(msg, chan)
            if not client then
                bot.reply(msg, ('%s: invalid channel name: %s'):format(msg.sender.nick, chan))
                return
            end
            local chanstate = bot.clients[client].tracker.chanstates[channame]
            if chanstate then
                if is_sender_trusted(msg, client, channame) then
                    msg.client:sendmessage('KICK', channame, nick, message)
                else
                    bot.reply(msg, ('%s: you are not permitted to use that command'):format(msg.sender.nick))
                end
            else
                bot.reply(msg, ('%s: (I am not on that channel)'):format(msg.sender.nick))
            end
        end,
    },--}}}
    ['ison'] = {--{{{
        usage = 'relay ison [<channel@network>] <nick> -- check if a member is in another channel in the relay group',
        func = function (msg, arg)
            local chan, nick = arg:match('^ *([^ ]+) +([^ ]+) *$')
            if not chan then
                local nick = arg:match('^ *([^ ]+) *$')
                if not nick then
                    bot.reply(msg, ('%s: Usage: relay ison <channel> <nick>'):format(msg.sender.nick))
                    return
                end
            end
            if chan then
                local client, channame = parse_channel_name(msg, chan)
                if not client then
                    bot.reply(msg, ('%s: invalid channel name: %s'):format(msg.sender.nick, chan))
                    return
                end
                local chanstate = bot.clients[client].tracker.chanstates[channame]
                if chanstate then
                    if chanstate.members[nick] then
                        bot.reply(msg, ('%s: %s is on %s'):format(msg.sender.nick, nick, chan))
                    else
                        bot.reply(msg, ('%s: %s is not on %s'):format(msg.sender.nick, nick, chan))
                    end
                else
                    bot.reply(msg, ('%s: (I am not on that channel)'):format(msg.sender.nick))
                end
            else
                local relayinfo = isrealyed(msg)
                if not relayinfo then
                    bot.reply(msg, ('%s: this channel is not in a relay group'):format(msg.sender.nick))
                else
                    local on = {}
                    for _, chan in ipairs(relaygroup) do
                        local chanstate = bot.clientsbyname[chan[1]].tracker.chanstates[chan[2]]
                        if chanstate and chanstate.members[nick] then
                            table.insert(on, chanstate.name..'@'..chan[1])
                        end
                    end
                    if #on == 0 then
                        bot.reply(msg, ('%s: %s in not on any channel in this relay group'):format(msg.sender.nick, nick))
                    else
                        bot.reply(msg, ('%s: %s is on: %s'):format(msg.sender.nick, nick, table.conclat(on, ' ')))
                    end
                end
            end
        end,
    },--}}}
}
if bot.plugins.tmpban then--{{{
    relay_cmds['tmpban'] = {
        usage = 'relay tmpban <channel> <nick> <seconds> [<message>] -- temporarily ban a member from another channel',
        func = function (msg, arg)
            local chan, nick, time, message = arg:match('^ *([^ ]+) +([^ ]+) +([^ ]+) +([^ ].-)$')
            if not chan then chan, time, nick = arg:match('([^ ]+) +([^ ]+) +([^ ]+)') end
            if not chan then
                bot.reply(msg, ('%s: Usage: relay mode <channel> <nick> [<message>]'):format(msg.sender.nick))
                return
            end
            local client, channame = parse_channel_name(msg, chan)
            if not client then
                bot.reply(msg, ('%s: invalid channel name: %s'):format(msg.sender.nick, chan))
                return
            end
            local chanstate = bot.clients[client].tracker.chanstates[channame]
            if chanstate then
                if is_sender_trusted(msg, client, channame) then
                    bot.plugins.tmpban.env.tmpban(msg.client, channame, nick, time, message)
                else
                    bot.reply(msg, ('%s: you are not permitted to use that command'):format(msg.sender.nick))
                end
            else
                bot.reply(msg, ('%s: (I am not on that channel)'):format(msg.sender.nick))
            end
        end,
    }
end--}}}
--}}}

local function relay_cmd_handler(msg, arg)--{{{
    local cmd, other = arg:match('^ *([^ ]+)(.-)$')
    if not cmd then
        bot.reply(msg, ('%s: Usage: relay <command> [<args>] -- Try "relay help" for a list of commands.'):format(msg.sender.nick))
        return
    end
    local cmdinfo = relay_cmds[cmd]
    if not cmdinfo then
        bot.reply(msg, ('%s: relay: no such command: %s'):format(msg.sender.nick, cmd))
        return
    end
    cmdinfo.func(msg, other)
end--}}}

bot.commands['relay'] = {relay_cmd_handler, help='Get info about and moderate other channels in a relay group. Run with no args to get a help message.'}

