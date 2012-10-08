
local irc = require 'irc'
local EventLoop = require 'eventloop'

irc.enable_ssl()

-- initialize math.random in case plugins use it
math.randomseed(os.time())

local eventloop = EventLoop()
local configfile = arg[1] or 'config.lua'
local plugindir = arg[2] or 'plugins'
local socket = require 'socket'
local config
local clients = {}
local clientsbyname = {}
local plugins, pluginenvs = {}, {}

local eventhandlers = {}
setmetatable(eventhandlers, {__mode='v'})

local function isignored(msg)--{{{
    local ignorelist = msg.client.netinfo._ignore
    if ignorelist then
        for _, i in pairs(ignorelist) do
            if msg.sender.str and msg.sender.str:match(i) then return true end
        end
    end
    return false
end--}}}

local function run_next_queued(client)--{{{
    if not clients[client] then return end -- the client was removed
    if socket.gettime() < clients[client].queue.next_item_time then return end
    local cmdinfo = table.remove(clients[client].queue, 1)
    if not cmdinfo then return end
    local success, err = pcall(cmdinfo.func)
    if not success then print(('***** error in queued function: %s'):format(tostring(err))) end
    clients[client].queue.next_item_time = socket.gettime() + cmdinfo.interval
    eventloop:timer(cmdinfo.interval, function () run_next_queued(client) end)
end--}}}

local function queue(client, interval, func)--{{{
    if not func then
        func = interval
        interval = config.default_min_queue_interval
    elseif not interval then
        interval = config.default_min_queue_interval
    end
    if #clients[client].queue < config.max_queue_size then
        table.insert(clients[client].queue, {
            client = client,
            interval = interval,
            func = func,
        })
        run_next_queued(client)
    end
end--}}}

local function send_multiline(msg, lines, notice)--{{{
    if type(lines) == 'string' then
        local tbl = {}
        for line in lines:gmatch('[^\n]+') do tbl[#tbl+1] = line end
        lines = tbl
    end
    local i = 1
    local function sendnext()
        msg.client[notice=='notice'and'sendnotice'or'sendprivmsg'](msg.client, irc.ischanname(msg.args[1]) or msg.sender.nick, lines[i])
        i = i + 1
        if lines[i] then queue(msg.client, sendnext) end
    end
    queue(msg.client, sendnext)
end--}}}

local function create_plugin_env(plugin, config)--{{{
    plugin.event_handlers = {}
    plugin.commands = {}
    local env = {
        irc = irc,
        config = config,
        socket = socket,
        bot = {
            eventloop = eventloop,
            commands = plugin.commands,
            event_handlers = plugin.event_handlers,
            event_callbacks = plugin.event_handlers,
            clients = clients,
            clientsbyname = clientsbyname,
            plugininfo = plugins,
            plugins = pluginenvs,
            isignored = isignored,
            queue = queue,
            send_multiline = send_multiline,
            reply = function (msg, text)
                msg.client:sendprivmsg(irc.ischanname(msg.args[1]) or msg.sender.nick, text)
            end
        },
    }
    for k, v in pairs(_G) do env[k] = v end
    setmetatable(env, {__index=_G})
    plugin.env = env
    return env
end--}}}

local function send_event_to_plugins(event, ...)--{{{
    for k, v in pairs(plugins) do
        local handler = v.event_handlers[event]
        if type(handler) == 'function' then
            local success, err = pcall(handler, ...)
            if not success then print(('***** error in "%s" plugin: %s'):format(k, err)) end
        elseif type(handler) == 'table' then
            for _, f in pairs(handler) do
                if type(f) == 'function' then
                    local success, err = pcall(handler, ...)
                    if not success then print(('***** error in "%s" plugin: %s'):format(k, err)) end
                end
            end
        end
    end
end--}}}

local function process_prefixed_command(msg, line)--{{{
    local cmdname = line:match('^([^ ]+)')
    if not cmdname then return end
    cmdname = cmdname:lower()
    local found = false
    for k, v in pairs(plugins) do
        if v.commands[cmdname] then
            found = true
            queue(msg.client, v.commands[cmdname].mininterval, function ()
                v.commands[cmdname][1](msg, line:sub(#cmdname+1))
            end)
            break
        end
    end
    if #clients[msg.client].queue < config.max_queue_size and not found then
        queue(msg.client, function ()
            msg.client:sendprivmsg((irc.ischanname(msg.args[1]) and msg.args[1] or msg.sender.nick) or '', config.no_command_message:format(cmdname))
        end)
    end
end--}}}

local function add_client(net, ident)--{{{
    local client = irc.Client(eventloop, net, ident, config.netdefaults)
    local nickattempt, nickattemptstate
    local tbl = {
        name = net.name,
        client=client,
        tracker=irc.ChannelTracker(client),
        autojoiner=irc.AutoJoiner(client),
        sentcolor = net._sentcolor,
        receivedcolor = net._receivedcolor,
        queue = {next_item_time = socket.gettime()},
        tracker_receivedmessage_cb = function (tracker, msg)
            if client.state == 'registering' then
                if msg.cmd == '433' then -- nick in use
                    local nick = client:get_nick()
                    if not nickattempt then nickattempt = nick end
                    if nickattemptstate == false then
                        if nickattempt:match('_$') then
                            nickattempt = nickattempt:sub(1, -2)
                        else
                            nickattemptstate = true
                            nickattempt = nick..'_'
                        end
                    else
                        nickattempt = nickattempt..'_'
                    end
                    client:sendmessage('NICK', nickattempt)
                end
            end
            local line = msg.line:gsub('[%z\001-\031%%]', function (c) return '%'..(c=='%' and '%' or string.char(c:byte()+('@'):byte())) end)
            if clients[client].receivedcolor then
                print(('\027[%s- %s: %s\027[0m'):format(clients[client].receivedcolor, clients[client].name, line))
            else
                print(('- %s: %s'):format(clients[client].name, line))
            end
            local ignored = isignored(msg)
            send_event_to_plugins('tracker_receivedmessage', tracker, msg, ignored)
        end,
        receivedmessage_pre_cb = function (client, msg)
            local ignored = isignored(msg)
            send_event_to_plugins('receivedmessage_pre', client, msg, ignored)
        end,
        receivedmessage_post_cb = function (client, msg)
            local ignored = isignored(msg)
            if msg.cmd == 'PRIVMSG' and not ignored and #msg.args >= 2 then
                local chanconfig = net._channels[msg.args[1]]
                local cmdprefixes = chanconfig and chanconfig.command_prefixes or (net._command_prefixes or config.command_prefixes)
                for _, prefix in ipairs(cmdprefixes) do
                    local match = msg.args[2]:match('^'..prefix)
                    if match then
                        process_prefixed_command(msg, msg.args[2]:sub(#match+1))
                        break
                    end
                end
            end
            send_event_to_plugins('receivedmessage_post', client, msg, ignored)
        end,
        sentmessage_cb = function (client, line, time)
            send_event_to_plugins('sentmessage', client, msg)
            line = line:gsub('[%z\001-\031%%]', function (c) return '%'..(c=='%' and '%' or string.char(c:byte()+('@'):byte())) end)
            if clients[client].sentcolor then
                print(('\027[%s< %s: %s\027[0m'):format(clients[client].sentcolor, clients[client].name, line))
            else
                print(('< %s: %s'):format(clients[client].name, line))
            end
        end,
        statechanged_cb = function (client, state, ...)
            send_event_to_plugins('statechanged', client, state, ...)
            nickattempt, nickattemptstate = nil, nil
            print(('* %s: %s%s'):format(clients[client].name, state, ((...) and ' ('..table.concat({...}, ' ')..')' or '')))
        end,
    }
    tbl.tracker:add_callback('receivedmessage', tbl.tracker_receivedmessage_cb)
    client:add_callback('receivedmessage_post', tbl.receivedmessage_post_cb)
    client:add_callback('receivedmessage_pre', tbl.receivedmessage_pre_cb)
    client:add_callback('sentmessage', tbl.sentmessage_cb)
    client:add_callback('statechanged', tbl.statechanged_cb)
    function add_client_event_relay(client, event)
        tbl[event..'_cb'] = function (...)
            send_event_to_plugins(event, ...)
        end
        client:add_callback(event, tbl[event..'_cb'])
    end
    function add_tracker_event_relay(tracker, event)
        local n = 'tracker_'..event
        tbl['tracker_'..event..'_cb'] = function (...)
            send_event_to_plugins(n, ...)
        end
        tracker:add_callback(event, tbl['tracker_'..event..'_cb'])
    end
    add_client_event_relay(client, 'sentprivmsg')
    add_client_event_relay(client, 'sentnotice')
    add_client_event_relay(client, 'sentctcp')
    add_client_event_relay(client, 'sentctcpreply')
    add_client_event_relay(client, 'connstatechanged')
    add_tracker_event_relay(tbl.tracker, 'joinedchannel')
    add_tracker_event_relay(tbl.tracker, 'leftchannel')
    add_tracker_event_relay(tbl.tracker, 'memberadded')
    add_tracker_event_relay(tbl.tracker, 'memberleft')
    add_tracker_event_relay(tbl.tracker, 'membernick')
    add_tracker_event_relay(tbl.tracker, 'membermode')
    add_tracker_event_relay(tbl.tracker, 'channeltopic')
    add_tracker_event_relay(tbl.tracker, 'channelmode')
    clients[client] = tbl
    clientsbyname[tbl.name] = client
    client:connect()
end--}}}

local function load_config()--{{{
    local success, newconfig = pcall(dofile, configfile)
    if config then
        if success then
            config = newconfig
        else
            print(('***** error in config file: %s'):format(newconfig))
            return
        end
    else
        assert(success, newconfig)
        config = newconfig
    end

    config.default_min_queue_interval = config.default_min_queue_interval or 0.4
    config.max_queue_size = config.max_queue_size or 40

    for name, ident in pairs(config.identities) do
        ident.name = name
    end

    local removed_clients = {}
    for client, tbl in pairs(clients) do removed_clients[tbl.name] = client end
    for name, info in pairs(config.networks) do
        removed_clients[name] = nil
        if not clientsbyname[name] then
            info.name = name
            info._channels, info.channels = info.channels, nil
            info._sentcolor, info.sentcolor = info.sentcolor, nil
            info._receivedcolor, info.receivedcolor = info.receivedcolor, nil
            info._commandprefixes, info.commandprefixes = info.commandprefixes, nil
            info._ignore, info.ignore = info.ignore, nil
            info.autojoin = {}
            for k, v in pairs(info._channels) do
                info.autojoin[#info.autojoin+1] = type(k)=='string' and k or v
            end
            add_client(info, assert(config.identities[info.identity], ('no identity "%s" (needed by network "%s")'):format(info.identity, name)))
        end
    end
    for name, client in pairs(removed_clients) do client:disconnect(); clients[client] = nil; clientsbyname[name] = nil end

    local removed_plugins = {}
    for name in pairs(plugins) do removed_plugins[name] = true end
    for name, info in pairs(config.plugins) do
        removed_plugins[name] = nil
        if not plugins[name] then
            local f, err = loadfile(plugindir..'/'..info[1])
            if f then
                local plugintbl = {}
                local env = create_plugin_env(plugintbl, info[2])
                local namedirpart = info[1]:match('.+/')
                env.bot.plugindir = namedirpart and plugindir..'/'..namedirpart or plugindir
                setfenv(f, env)
                local success, err = pcall(f)
                if success then
                    plugins[name] = plugintbl
                    pluginenvs[name] = env
                else
                    print(('***** error in "%s" plugin: %s'):format(name, err))
                end
            else
                print(('***** failed to load "%s" plugin (filename: "%s", error: "%s")'):format(name, info[1], err))
            end
        end
    end
    for name in pairs(removed_plugins) do plugins[name], pluginenvs[name] = nil, nil end
end--}}}

local function show_command_ref()--{{{
    io.stdout:write [[
***** command reference *****
h -- show this reference
q -- quit
c -- reload config
r <name> -- reload plugin
s <network> <line> -- send a raw line to a server. <network> may be abbreviated
to the first few characters of the network name, or "*" to send to all
networks. "%" escape sequences can be used to send control characters
***** end of command reference *****
]]
end--}}}

local stdin_commands = {--{{{
    ['^%s*h%s*$'] = function () show_command_ref() end,
    ['^%s*q%s*$'] = function ()
        for name, tbl in pairs(clients) do
            tbl.client:disconnect()
        end
        eventloop:exit()
    end,
    ['^%s*c%s*$'] = function () load_config() end,
    ['^%s*r%s+(%S.*)$'] = function (name)
        if not plugins[name] then
            print(name..': no such plugin')
            return
        end
        local f, err = loadfile(plugindir..'/'..config.plugins[name][1])
        if f then
            local plugintbl = {}
            local env = create_plugin_env(plugintbl, config.plugins[name][2])
            local namedirpart = config.plugins[name][1]:match('.+/')
            env.bot.plugindir = namedirpart and plugindir..'/'..namedirpart or plugindir
            setfenv(f, env)
            local success, err = pcall(f)
            if success then
                plugins[name] = plugintbl
                pluginenvs[name] = env
                print('successfully reloaded plugin')
            else
                print(('***** error in "%s" plugin: %s'):format(name, err))
            end
        else
            print(('***** failed to load "%s" plugin (filename: "%s", error: "%s")'):format(name, info.filename, err))
        end
    end,
    ['^%s*s%s+(%S+)%s+(%S.*)$'] = function (net, line)
        line = line:gsub('%[A-Za-z%%]', function (c)
            if c == '%' then return '%' end
            return string.char(c:upper():byte()-string.byte('@'))
        end)
        if net == '*' then
            for client, tbl in pairs(clients) do
                client:sendmessageline(line)
            end
        else
            local clientinfo
            for client, tbl in pairs(clients) do
                if tbl.name:lower() == net:lower() then
                    clientinfo = tbl
                    break
                end
            end
            if not clientinfo then
                for client, tbl in pairs(clients) do
                    if tbl.name:sub(1, #net):lower() == net:lower() then
                        clientinfo = tbl
                        break
                    end
                end
            end
            if clientinfo then
                clientinfo.client:sendmessageline(line)
            end
        end
    end,
}--}}}

local luasocket_stdin_kludge = {getfd = function () return 0 end}
local function stdin_handler()--{{{
    local line = io.stdin:read('*l')
    if line then
        for pattern, func in pairs(stdin_commands) do
            local matches = {line:match(pattern)}
            if matches[1] then
                func(unpack(matches))
                break
            end
        end
    end
    return true
end--}}}
eventloop:add_readable_handler(luasocket_stdin_kludge, stdin_handler)

show_command_ref()
load_config()

eventloop:run()

