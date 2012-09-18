
local socket = require 'socket'
local ssl = nil

-- Enable SSL support.
-- By default this module only depends on LuaSocket, calling this function
-- requires LuaSec. If you try to use SSL without calling this function first,
-- an error will be thrown.
local function enable_ssl()--{{{
    ssl = require 'ssl'
end--}}}

-- Convert a sender prefix string into a table.
-- For example, "a!b@c" is converted to {nick='a', user='b', host='c',
-- str='a!b@c'}. Non-'*!*@*' strings are converted like this: 'example' ->
-- {nick=nil, user=nil, host='example', str='example'}.
local function sender_prefix_to_table(str)--{{{
    local nick, user, host = str:match('^(.+)!(.+)@(.+)$')
    if not nick then return {host = str, str = str} end
    return {nick = nick, user = user, host = host, str = str}
end--}}}

local lowlevel_quote_table = {--{{{
    ['\0'] = '\0160',
    ['\n'] = '\016n',
    ['\r'] = '\016r',
    ['\016'] = '\016\016'
}--}}}

-- Quote a message string to prepare it for sending.
local function lowlevel_quote(str)--{{{
    return string.gsub(str, '[%z\n\r\016]', lowlevel_quote_table)
end--}}}

local lowlevel_dequote_table = {--{{{
    ['\0160'] = '\0',
    ['\016n'] = '\n',
    ['\016r'] = '\r',
    ['\016\016'] = '\016'
}--}}}

setmetatable(lowlevel_dequote_table,
             {__index = function (t, k) return k:sub(2, 2) end})

-- Dequote a received message string.
local function lowlevel_dequote(str)--{{{
    return string.gsub(str, '\016.', lowlevel_dequote_table)
end--}}}

-- Quote any CTCP special chars in a string.
local function ctcp_quote(str)--{{{
    return string.gsub(str, '[\001\\]', '\\%1')
end--}}}

-- Dequote any CTCP special chars in a string.
local function ctcp_dequote(str)--{{{
    return string.gsub(str, '\\([\\\001])', '%1')
end--}}}

-- Convert a message line into a table representation of it. The contents of
-- the table are:
--
-- * client: The Client that received the message.
-- * time: What os.time() returned when the message was received.
-- * sender: The sender prefix, as a table (see sender_prefix_to_table)
--   (or nil, of the message had no prefix). It has these fields, which may
--   be nil:
--   * nick The nick part.
--   * user The user part.
--   * host The host part.
--   * str: The original string.
-- * cmd: The command.
-- * args: The list of args.
--
-- For PRIVMSG and NOTICE messages, this function checks if they're CTCP,
-- and if so, changes the cmd field to ':CTCP' (for PRIVMSG) or
-- ':CTCPREPLY' (for NOTICE), the args[2] field to the CTCP command, and
-- the args[3] field to the CTCP arg (if any). If they're not CTCP messages,
-- only simple CTCP dequoting is preformed. Also, note that this function
-- doesn't support multiple CTCP messages in a single line.
--
-- The mynick arg is to fill in the sender prefix if it's not in the line, and
-- the client arg fills the client field of the table.
local function message_line_to_table(line, mynick, client)--{{{
    local time = os.time()
    local prefix, remaining = line:match('^:([^ ]+) +(.*)')
    remaining = remaining or line
    local cmdtype = remaining:match('^(%w+)$') or remaining:match('^(%w+) ')
    if cmdtype then remaining = remaining:sub(#cmdtype+1) else return nil end
    cmdtype = cmdtype:upper()
    local argstr, last = remaining:match('^(.-) :(.*)$')
    local args = {}
    for i in (argstr or remaining):gmatch('[^ ]+') do args[#args+1] = i end
    args[#args+1] = last
    if (cmdtype == 'PRIVMSG' or cmdtype == 'NOTICE') and #args >= 2 then
        if args[2]:match('^\001.+\001$') then
            cmdtype = cmdtype == 'PRIVMSG' and ':CTCP' or ':CTCPREPLY'
            local s = ctcp_dequote(args[2]:sub(2, -2))
            local c, a = s:match('^([^ ]+) (.*)$')
            if c then
                args[2] = c:upper()
                args[3] = a
                args[4] = nil
            else
                args[2] = s:upper()
                args[3] = nil
            end
        end
    end
    return {
        time = time,
        line = line,
        client = client,
        sender = prefix and sender_prefix_to_table(prefix) or {nick=mynick},
        cmd = cmdtype,
        args = args,
    }
end--}}}

-- Check whether a command is a numeric reply.
local function isnumreply(cmd)--{{{
    return string.match(cmd, '%d%d%d')
end--}}}

-- Check whether a command is a numeric error reply.
local function iserrreply(cmd)--{{{
    return string.match(cmd, '[45]%d%d')
end--}}}

local rfc1459_upper, rfc1459_lower, strict_rfc1459_upper, strict_rfc1459_lower--{{{
do
    local rfc1459_upper_table = {['{']='[', ['|']='\\', ['}']=']', ['^']='~'}
    function rfc1459_upper(str)
        return string.gsub(string.upper(str), '[{|}^]', rfc1459_upper_table)
    end

    local rfc1459_lower_table = {['[']='{', ['\\']='|', [']']='}', ['~']='^'}
    function rfc1459_lower(str)
        return string.gsub(string.lower(str), '[%[\\%]~]', rfc1459_lower_table)
    end

    local strict_rfc1459_upper_table = {['{']='[', ['|']='\\', ['}']=']'}
    function strict_rfc1459_upper(str)
        return string.gsub(string.upper(str), '[{|}]', strict_rfc1459_upper_table)
    end

    local strict_rfc1459_lower_table = {['[']='{', ['\\']='|', [']']='}'}
    function strict_rfc1459_lower(str)
        return string.gsub(string.lower(str), '[%[\\%]]', strict_rfc1459_lower_table)
    end
end--}}}

local function rfc1459_nameeq(a, b)--{{{
    return a == b or rfc1459_lower(a) == rfc1459_lower(b)
end--}}}

local function strict_rfc1459_nameeq(a, b)--{{{
    return a == b or strict_rfc1459_lower(a) == strict_rfc1459_lower(b)
end--}}}

local function ascii_nameeq(a, b)--{{{
    return a == b or string.lower(a) == string.lower(b)
end--}}}

local rfc1459_name_key_metatable = {--{{{
    __index = function (tbl, key)
        return rawget(tbl, type(key)=='string' and rfc1459_lower(key) or key)
    end,
    __newindex = function (tbl, key, val)
        rawset(tbl, type(key)=='string' and rfc1459_lower(key) or key, val)
    end,
}--}}}

local strict_rfc1459_name_key_metatable = {--{{{
    __index = function (tbl, key)
        return rawget(tbl, type(key)=='string' and strict_rfc1459_lower(key) or key)
    end,
    __newindex = function (tbl, key, val)
        rawset(tbl, type(key)=='string' and strict_rfc1459_lower(key) or key, val)
    end,
}--}}}

local ascii_name_key_metatable = {--{{{
    __index = function (tbl, key)
        return rawget(tbl, type(key)=='string' and string.lower(key) or key)
    end,
    __newindex = function (tbl, key, val)
        rawset(tbl, type(key)=='string' and string.lower(key) or key, val)
    end,
}--}}}

-- See if a string is a valid channel name.
local function ischanname(str)--{{{
    return str:match('^[&#+!][^%z\007\r\n ,:]+$')
end--}}}

-- See if a string is a valid nick.
local function isnick(str)--{{{
    return str:match('^%a[%a%d[%]\\`_^{|}-]*$')
end--}}}

-- Apply a mode string to another.
-- If the diff doesn't start with a '+' or '-', '+' is assumed.  The chars in
-- the returned string are sorted alphabetically, except for the '+' or '-'
-- prefix.
-- Examples:
-- applymode('+abc', '+bd') --> '+abcd'
-- applymode('+abc', '-bd') --> '+ac'
-- applymode('bca', 'd') --> '+abcd'
local function applymode(str, diff)--{{{
    local negative = false
    if #diff > 0 then
        local match
        match = diff:match('^%+(.*)')
        if match then
            diff = match
        else
            match = diff:match('^%-(.*)')
            if match then
                negative = true
                diff = match
            end
        end
    end
    diff = diff:gsub('[-+]', '')
    for c in diff:gmatch('.') do
        if negative then
            str = str:gsub(c:gsub('(%p)', '%%%1'), '')
        else
            if not str:find(c, 1, true) then str = str .. c end
        end
    end
    local prefix = str:match('^[+-]')
    if prefix then str = str:sub(2) else prefix = '+' end
    local chars = {}
    for i in str:gmatch('.') do chars[#chars+1] = i end
    table.sort(chars)
    return prefix..table.concat(chars)
end--}}}

-- Manage a connection to an IRC network.
local Client = {}--{{{
Client.__index = Client
setmetatable(Client, {__call = function (t, ...) return Client.new(...) end})

-- default settings. You can override these in the "netinfo" table passed to the Client constructor
local default_defaults = {--{{{
    conn_timeout = 60,                   -- the amount of time to wait for the socket to connect before autoreconnecting
    ssl_handshake_timeout = 30,          -- the amount of time to wait for the SSL handshake to complete before autoreconnecting
    registering_timeout = 120,           -- the amount of time to wait for the 001 (RPL_WELCOME) reply before autoreconnecting
    ping_interval = 105,                 -- the interval between pings
    ping_timeout = 15,                   -- how long to wait for a ping rely before autoreconnecting
    reconnection_interval_reset_time = 5*60,   -- how long to wait after connection to reset autoreconnect interval to minimum
    initial_reconnection_interval = 5,   -- the initial amount of time to wait between autoreconnect attempts (nil for no autoreconnect)
    reconnection_interval_scale = 1.2,   -- multiply the interval by this amount after every autoreconnect attempt
    max_reconnection_interval = 30 * 60, -- the max amount of time to wait between autoreconnect attempts

    -- used by AutoJoiner
    initial_rejoin_interval = 3,         -- the initial amount of time to wait between autorejoin attempts (nil for no autorejoin)
                                         -- note that when kicked, Client first waits for the interval instead of JOINing immediately
    rejoin_interval_scale = 1.5,         -- multiply the interval by this amount after every autorejoin attempt
    max_rejoin_interval = 30 * 60,       -- the max amount of time to wait between autorejoin attempts
    autoknock = false,                   -- whether to automatically send a "KNOCK" command when a channel is invite-only

    -- used by ChannelTracker
    send_names_on_join = false,          -- send a NAMES command on joining a channel (most servers send a NAMES reply automatically)
    send_mode_on_join = true,            -- send a MODE command when joining a channel (some servers don't send a channel mode reply automatically)
    send_topic_on_join = false,          -- send a TOPIC command when joining a channel (some servers don't send a channel topic reply automatically)
}--}}}

-- create a new Client
-- eventloop: the event loop.
-- netinfo: the network info table
-- identinfo: the identity info table
-- defaults: the settings table. Fields in this table can be overwritten by
--           fields in netinfo. Set this to nil to use the default settings.
--
-- The "state" field contains the current state. It is one of:
-- disconnected: The Client is not connected. This is also the initial state.
-- connecting: Called the connect function on the socket, waiting for the first read/write event
-- sslhandshake: (only for SSL connections) Doing the SSL handshake.
-- registering: Sent the USER and NICK commands, waiting for 001 (RPL_WELCOME).
-- connected: Successfully connected to the IRC network. You can now send/receive any command, join channels, etc.
-- reconnecting: Waiting to try to connect again after an error.
--
-- The "connstate" field is a table containing info about the server and your membership:
-- mode: Your current mode.
-- prefixes: The set of nick prefixes the server supports. The keys hold the prefix and the values hold the mode character.
-- ping: The time it took for the last ping to be replied to.
function Client.new(eventloop, netinfo, identinfo, defaults, chantracker)--{{{
    local self = {}
    setmetatable(self, Client)
    self.state = 'disconnected'
    self.netinfo = netinfo
    self.identinfo = identinfo
    self._nick = self.identinfo.nick or self.identinfo.nicks[1]
    self.defaults = defaults or default_defaults
    self._eventloop = eventloop
    self.eventloop = eventloop
    self._eventhandlers = {
        ['statechanged'] = {},
        ['nickchanged'] = {},
        ['connstatechanged'] = {},
        ['sentmessage'] = {},
        ['sentprivmsg'] = {},
        ['sentnotice'] = {},
        ['sentctcp'] = {},
        ['sentctcpreply'] = {},
        ['receivedmessage_pre'] = {},
        ['receivedmessage_post'] = {},
    }
    for k, v in pairs(self._eventhandlers) do setmetatable(v, {__mode='k'}) end
    function self:upper(str) return rfc1459_upper(str) end
    function self:lower(str) return rfc1459_lower(str) end
    function self:nameeq(a, b) return rfc1459_nameeq(a, b) end
    return self
end--}}}

-- Create a metatable that makes keys lowercase
function Client:name_key_metatable()--{{{
    return {
        __index = function (tbl, key)
            return rawget(tbl, type(key)=='string' and self:lower(key) or key)
        end,
        __newindex = function (tbl, key, val)
            rawset(tbl, type(key)=='string' and self:lower(key) or key, val)
        end,
    }
end--}}}

-- Change your nick. Unlike sending a NICK command, this also works if the
-- Client is not connected. If the Client is registering, the change doesn't
-- work immediately, the nick will only really be cahnged once the client
-- enters the connected state.
function Client:set_nick(nick)--{{{
    if self.state == 'connected' or self.state == 'registering' then
        self:sendmessage('NICK', nick)
    elseif isnick(nick) then
        self._nick = nick
        self:_trigger_event_handlers('nick-changed', self._nick)
    end
end--}}}

-- Get your current nick.
function Client:get_nick()--{{{
    return self._nick
end--}}}

-- Send a PRIVMSG. Unlike manually sending a PRIVMSG, this quotes any CTCP
-- special characters.
function Client:sendprivmsg(to, text)--{{{
    self:sendmessage('PRIVMSG', to, text)
    self:_trigger_event_handlers('sentprivmsg', to, text, os.time())
end--}}}

-- Send a NOTICE. Unlike manually sending a NOTICE, this quotes any CTCP
-- special characters.
function Client:sendnotice(to, text)--{{{
    self:sendmessage('NOTICE', to, text)
    self:_trigger_event_handlers('sentnotice', to, text, os.time())
end--}}}

-- Send a CTCP.
function Client:sendctcp(to, cmd, arg)--{{{
    self:sendmessage('PRIVMSG', to, '\001'..ctcp_quote(cmd..(arg and ' '..arg or ''))..'\001')
    self:_trigger_event_handlers('sentctcp', to, cmd, arg, os.time())
end--}}}

-- Send a CTCP reply.
function Client:sendctcpreply(to, cmd, arg)--{{{
    self:sendmessage('NOTICE', to, '\001'..ctcp_quote(cmd..(arg and ' '..arg or ''))..'\001')
    self:_trigger_event_handlers('sentctcpreply', to, cmd, arg, os.time())
end--}}}

-- Send a message.
--  Except for the last one, the args may not contain whitespace or start with
--  a ":" character.
function Client:sendmessage(cmd, ...)--{{{
    assert(self.state == 'connected' or self.state == 'registering',
           'irc.Client.sendmessage can only be caled in the "connected" and "registering" states')
    local line, argcount = cmd, select('#', ...)
    for i = 1, argcount do
        local arg = select(i, ...)
        if not arg then break end
        line = line..(i == argcount and ' :' or ' ')..arg
    end
    self:_trigger_event_handlers('sentmessage', line, os.time())
    self:_send(lowlevel_quote(line)..'\r\n')
end--}}}

-- Send a pre-formatted message line. In most cases, you should use
-- Client:sendmessage instead.
function Client:sendmessageline(line)--{{{
    assert(self.state == 'connected' or self.state == 'registering',
           'irc.Client.sendmessage can only be caled in the "connected" and "registering" states')
    self:_trigger_event_handlers('sentmessage', line, os.time())
    self:_send(lowlevel_quote(line)..'\r\n')
end--}}}

-- Get the prefix for a mode letter
function Client:getmodeprefix(mode)--{{{
    for _, pair in ipairs(self.isupport.prefixes) do
        if mode:find(pair[2], 1, true) then
            return pair[1]
        end
    end
    return nil
end--}}}

-- Add an event handler. This is the list of possible events:
--
-- statechanged: The state changed. Args: <new state>[, <disconnect reason>[, <reconnect timer>]]
-- nickchanged: The nick changed. Args: <new nick>, <old nick>
-- connstatechanged: The connstate table (see Client:get_connstate) changed. Args: <name of changed field>, <value of changed field>
-- sentmessage: A message was sent. Args: <to>, <text>, <time>
-- sentprivmsg: A PRIVMSG was sent using Client:sendprivmsg. Args: <to>, <text>, <time>
-- sentnotice: A NOTICE was sent using Client:sendnotice. Args: <to>, <cmd>, <arg>, <time>
-- sentctcp: A CTCP PRIVMSG was sent using Client:sendctcp. Args: <to>, <cmd>, <arg>, <time>
-- sentctcpreply: A CTCP reply NOTICE was sent using Client:sendctcpreply. Resume args: 'irc.Client.ctcpreplysent', <to>, <cmd>, <arg>.
-- receivedmessage_pre: Received a message, triggered _before_ the state is updated. Args: <message table>
-- receivedmessage_post: Received a message, triggered _after_ the state is updated. Args: <message table>
--
-- Note that all events have an arg that contains the Client before the rest of
-- the args.
function Client:add_callback(event, cb)--{{{
    self._eventhandlers[event][cb] = true
end--}}}

function Client:remove_callback(event, cb)--{{{
    self._eventhandlers[event][cb] = nil
end--}}}

Client.add_event_handler = Client.add_callback
Client.remove_event_handler = Client.remove_callback

-- (private) clean up the current connection and reconnect after an interval
function Client:_reconnect(reason)--{{{
    self._timer:cancel()
    self._eventloop:remove_readable_handler(self._conn, self._rhandler)
    self._eventloop:remove_writable_handler(self._conn, self._whandler)
    self._conn:close()
    self._conn = nil
    if not self._reconnecttime then
        self._reconnecttime = self.netinfo.initial_reconnection_interval or self.defaults.initial_reconnection_interval
    else
        if self._time_last_connected then
            local diff = os.difftime(os.time(), self._time_last_connected)
            local resettime = self.netinfo.reconnection_interval_reset_time or self.defaults.reconnection_interval_reset_time
            if diff > resettime then
                self._reconnecttime = self.netinfo.initial_reconnection_interval or self.defaults.initial_reconnection_interval
            else
                self._reconnecttime = self._reconnecttime * (self.netinfo.reconnection_interval_scale or self.defaults.reconnection_interval_scale)
                local max =  self.netinfo.max_reconnection_interval or self.defaults.max_reconnection_interval
                if self._reconnecttime > max then self._reconnecttime = max end
            end
        else
            self._reconnecttime = self._reconnecttime * (self.netinfo.reconnection_interval_scale or self.defaults.reconnection_interval_scale)
            local max =  self.netinfo.max_reconnection_interval or self.defaults.max_reconnection_interval
            if self._reconnecttime > max then self._reconnecttime = max end
        end
    end
    self.state = 'reconnecting'
    self:_trigger_event_handlers('statechanged', self.state, reason, self._reconnecttime)
    self._timer = self._eventloop:timer(self._reconnecttime, function () self:connect() end)
end--}}}

-- Connect to the network.
-- If in the reconnecting state, connect now.
function Client:connect()--{{{
    assert(self.state == 'disconnected' or self.state == 'reconnecting')
    self._intentionally_quit = false
    if self._timer then self._timer:cancel() end
    self._conn = socket.tcp()
    self._conn:settimeout(0)
    self._rhandler = function () return self:_on_readable() end
    self._whandler = function () return self:_on_writable() end
    self._eventloop:add_readable_handler(self._conn, self._rhandler)
    self._eventloop:add_writable_handler(self._conn, self._whandler)
    self._conn:connect(self.netinfo.address, self.netinfo.port or 6667)
    self.state = 'connecting'
    self:_trigger_event_handlers('statechanged', self.state)
    self._timer = self._eventloop:timer(self.netinfo.conn_timeout or self.defaults.conn_timeout, function () self:_reconnect('connectingtimeout') end)
end--}}}

-- Disconnect.
-- If in the reconnecting state, cancel reconnection.
function Client:disconnect(msg)--{{{
    if self.state == 'disconnected' then return end
    if self.state == 'reconnecting' then
        self._timer:cancel()
        self._reconnecttime = nil
    else
        if self.state == 'connected' then
            if msg == false then
                msg = nil
            elseif msg then
                msg = self.identinfo.quitmessage
            end
            local line = 'QUIT'..(msg and ' :'..msg or '')
            self:_trigger_event_handlers('sentmessage', line)
            self._conn:send('\r\n'..line..'\r\n')
        end
        self._timer:cancel()
        self._eventloop:remove_readable_handler(self._conn, self._rhandler)
        self._eventloop:remove_writable_handler(self._conn, self._whandler)
        self._conn:close()
        self._conn = nil
        self.state = 'disconnected'
        self:_trigger_event_handlers('statechanged', self.state)
    end
end--}}}

-- (private) call when the socket is connected (first r/w event)
function Client:_on_socket_connected()--{{{
    self._timer:cancel()
    if self.netinfo.ssl then
        self._eventloop:remove_readable_handler(self._conn, self._rhandler)
        self._eventloop:remove_writable_handler(self._conn, self._whandler)
        self._conn = ssl.wrap(self._conn, {mode='client', protocol='tlsv1'})
        self._conn:settimeout(0)
        self._eventloop:add_readable_handler(self._conn, self._rhandler)
        self._eventloop:add_writable_handler(self._conn, self._whandler)
        self.state = 'sslhandshake'
        self:_trigger_event_handlers('statechanged', self.state)
        self._timer = self._eventloop:timer(self.netinfo.ssl_handshake_timeout or self.defaults.ssl_handshake_timeout, function () self:_reconnect('sslhandshaketimeout') end)
        self:_do_ssl_handshake()
    else
        self:_on_ssl_handshake_done()
    end
end--}}}

-- (private) resume the SSL handshake
function Client:_do_ssl_handshake()--{{{
    local success, errmsg = self._conn:dohandshake()
    if success then 
        self:_on_ssl_handshake_done()
    elseif errmsg == 'wantread' then
        -- wait for next readable event
    elseif errmsg == 'wantwrite' then
        self._eventloop:add_writable_handler(self._conn, self._whandler)
    elseif errmsg == 'closed' then
        self:_reconnect('closed')
    else
        self:_reconnect('sslerror '..errmsg)
    end
end--}}}

-- (private) call when the SSL handshake is done (or on connection, if SSL is
-- not used)
function Client:_on_ssl_handshake_done()--{{{
    self._timer:cancel()
    self._recvbuf = ''
    self._sendbuf = ''
    self.state = 'registering'
    self.connstate = {
        mode = '+',
        ping = nil,
    }
    self.isupport = {
        prefixes = {
            {'@', 'o'},
            {'+', 'v'},
        },
        modesforprefix = {['@'] = 'o', ['+'] = 'v'},
        prefixesformode = {['o'] = '@', ['v'] = '+'},
        chanmodes = {
            a = 'eIbq',
            b = 'k',
            c = 'l',
            d = 'CFLMOPcgimnprstz',
        },
    }
    self:_trigger_event_handlers('statechanged', self.state)
    local modemask = 0
    if self.netinfo.receive_wallops then modemask = modemask + 4 end
    if not self.netinfo.visible then modemask = modemask + 8 end
    self:sendmessage('USER', self.identinfo.username, tostring(modemask), '*', self.identinfo.realname)
    self:sendmessage('NICK', self._nick)
    self._timer = self._eventloop:timer(self.netinfo.registering_timeout or self.defaults.registering_timeout, function () self:_reconnect('registeringtimeout') end)
end--}}}

-- Ping the server.
function Client:ping()--{{{
    self._timer:cancel()
    self._pingtime = socket.gettime()
    self:sendmessage('PING', tostring(self._pingtime))
    self._timer = self._eventloop:timer(self.netinfo.ping_timeout or self.defaults.ping_timeout, function () self:_reconnect('pingtimeout') end)
end--}}}

-- (private) socket readable callback
function Client:_on_readable()--{{{
    if self.state == 'connecting' then
        self:_on_socket_connected()
    elseif self.state == 'sslhandshake' then
        self:_do_ssl_handshake()
    else
        local data, err, part = self._conn:receive('*a')--8192)
        if not data then data = part else err = 'closed' end
        if data then
            self._recvbuf = self._recvbuf..data
            while true do
                local match, line = self._recvbuf:match('^([\r\n]*(..-)[\r\n])')
                if not match then break end
                self._recvbuf = self._recvbuf:sub(#match+1)
                line = lowlevel_dequote(line)
                local msg = message_line_to_table(line, self._nick, self)
                if msg then
                    self:_trigger_event_handlers('receivedmessage_pre', msg)
                    if msg.cmd == '001' and #msg.args >= 1 and self.state == 'registering' then
                        self._timer:cancel()
                        self._time_last_connected = os.time()
                        if msg.args[1] ~= self._nick then
                            self:_trigger_event_handlers('nickchanged', msg.args[1], self._nick)
                            self._nick = msg.args[1]
                        end
                        for _, line in ipairs(self.netinfo.autorun or {}) do
                            self:sendmessageline(line)
                        end
                        self.state = 'connected'
                        self:_trigger_event_handlers('statechanged', self.state)
                        if msg.sender.host then
                            self.connstate.serveraddress = msg.sender.host
                            self:_trigger_event_handlers('connstatechanged', 'serveraddress', msg.sender.host)
                        end
                        self:ping()
                    elseif msg.cmd == '005' and #msg.args >= 2 then
                        for key, val in table.concat(msg.args, ' ', 2):gmatch('(%a+)=([^ ]*)') do
                            key = key:upper()
                            if key == 'PREFIX' then
                                local modes, prefixes = val:match('%((%a+)%)([^ ]+)')
                                if modes and #modes == #prefixes then
                                    self.isupport.prefixes, self.isupport.prefixesformode, self.isupport.modesforprefix = {}, {}, {}
                                    for i = 1, #modes do
                                        self.isupport.prefixes[#self.isupport.prefixes+1] = {prefixes:sub(i, i), modes:sub(i, i)}
                                        self.isupport.prefixesformode[modes:sub(i, i)] = prefixes:sub(i, i)
                                        self.isupport.modesforprefix[prefixes:sub(i, i)] = modes:sub(i, i)
                                    end
                                end
                            elseif key == 'CHANMODES' then
                                local a, b, c, d = val:match('^(%a*),(%a*),(%a*),(%a*)$')
                                if a then
                                    self.isupport.chanmodes = {}
                                    self.isupport.chanmodes.a,
                                    self.isupport.chanmodes.b,
                                    self.isupport.chanmodes.c,
                                    self.isupport.chanmodes.d = a, b, c, d
                                end
                            elseif key == 'CASEMAPPING' then
                                if val == 'ascii' then
                                    function self:upper(str) return string.upper(str) end
                                    function self:lower(str) return string.lower(str) end
                                    function self:nameeq(a, b) return ascii_nameeq(a, b) end
                                elseif val == 'strict-rfc1459' then
                                    function self:upper(str) return strict_rfc1459_upper(str) end
                                    function self:lower(str) return strict_rfc1459_lower(str) end
                                    function self:nameeq(a, b) return strict_rfc1459_nameeq(a, b) end
                                else -- rfc1459
                                    function self:upper(str) return rfc1459_upper(str) end
                                    function self:lower(str) return rfc1459_lower(str) end
                                    function self:nameeq(a, b) return rfc1459_nameeq(a, b) end
                                end
                            end
                        end
                    elseif msg.cmd == 'PONG' and #msg.args >= 2 and tostring(self._pingtime) == msg.args[2] and self.state == 'connected' then
                        local lag = socket.gettime() - self._pingtime
                        self.connstate.ping = lag
                        self:_trigger_event_handlers('connstatechanged', 'ping', lag)
                        self._timer:cancel()
                        self._timer = self._eventloop:timer(self.netinfo.ping_interval or self.defaults.ping_interval, function () self:ping() end)
                    elseif msg.cmd == 'MODE' and #msg.args == 2 and self:nameeq(msg.args[1], self._nick) then
                        self.connstate.mode = applymode(self.connstate.mode, msg.args[2])
                        self:_trigger_event_handlers('connstatechanged', 'mode', self.connstate.mode)
                    elseif msg.cmd == 'PING' and (self.state == 'connected' or self.state == 'registering') then
                        if #msg.args >= 1 then
                            self:sendmessage('PONG', msg.args[1])
                        else
                            self:sendmessage('PONG')
                        end
                    elseif msg.cmd == 'NICK' and msg.sender.nick and #msg.args >= 1 then
                        if self:nameeq(msg.sender.nick, self._nick) then
                            self:_trigger_event_handlers('nickchanged', msg.args[1], self._nick)
                            self._nick = msg.args[1]
                        end
                    elseif msg.cmd == 'QUIT' and msg.sender.nick and self:nameeq(msg.sender.nick, self._nick) then
                        self._intentionally_quit = true
                    elseif msg.cmd == ':CTCP' then
                        if msg.args[2] == 'FINGER' then
                            self:sendctcpreply(msg.sender.nick, 'FINGER', ':FINGER is not supported, try USERINFO instead')
                        elseif msg.args[2] == 'VERSION' then
                            self:sendctcpreply(msg.sender.nick, 'VERSION', self.userversion and ':'..self.userversion..' (using TuxBot lua IRC lib)' or ':TuxBot lua IRC lib')
                        elseif msg.args[2] == 'SOURCE' then
                            self:sendctcpreply(msg.sender.nick, 'SOURCE', self.usersource and ':'..self.usersource..' (using ???)' or ':???')
                        elseif msg.args[2] == 'USERINFO' then
                            self:sendctcpreply(msg.sender.nick, 'USERINFO', ':'..(self.identinfo.userinfo or ''))
                        elseif msg.args[2] == 'ERRMSG' then
                            self:sendctcpreply(msg.sender.nick, 'ERROR', (msg.args[3] or '')..' :No error has occured')
                        elseif msg.args[2] == 'PING' then
                            self:sendctcpreply(msg.sender.nick, 'PONG', msg.args[3])
                        elseif msg.args[2] == 'TIME' then
                            self:sendctcpreply(msg.sender.nick, 'TIME', ':'..os.date('%A %Y-%m-%d %H:%M:%S %Z (%z)'))
                        elseif msg.args[2] == 'CLIENTINFO' then
                            if msg.args[3] then
                                if msg.args[3] == 'FINGER' then
                                    self:sendctcpreply(msg.sender.nick, 'CLIENTINFO', ':FINGER This command is not supported, and returns a message asking the user to try USERINFO instead.')
                                elseif msg.args[3] == 'VERSION' then
                                    self:sendctcpreply(msg.sender.nick, 'CLIENTINFO', ':VERSION get the name of this client. Since this client is a library, it has its own message, and users of the library can add their own text to be shown with it.')
                                elseif msg.args[3] == 'SOURCE' then
                                    self:sendctcpreply(msg.sender.nick, 'CLIENTINFO', ':SOURCE Get a link to the source code of this client. Since this client is a library, it has its own message, and users of the library can add their own text to be shown with it.')
                                elseif msg.args[3] == 'USERINFO' then
                                    self:sendctcpreply(msg.sender.nick, 'CLIENTINFO', ':USERINFO Return a string set by the user. If the user did not set a USERINFO string, an empty reply is returned.')
                                elseif msg.args[3] == 'ERRMSG' then
                                    self:sendctcpreply(msg.sender.nick, 'CLIENTINFO', ':ERRMSG Return the supplied string, plus a message saying there was no error.')
                                elseif msg.args[3] == 'PING' then
                                    self:sendctcpreply(msg.sender.nick, 'CLIENTINFO', ':PING Return the supplied string.')
                                elseif msg.args[3] == 'TIME' then
                                    self:sendctcpreply(msg.sender.nick, 'CLIENTINFO', ':TIME Return the system time and timezone of the client.')
                                elseif msg.args[3] == 'CLIENTINFO' then
                                    self:sendctcpreply(msg.sender.nick, 'CLIENTINFO', ':CLIENTINFO Get info about CTCP commands supported by this client. Try using CLIENTINFO with no argument for the full info.')
                                else
                                    self:sendctcpreply(msg.sender.nick, 'CLIENTINFO', ':"'..msg.args[3]..'": Unknown CTCP command')
                                end
                            else
                                self:sendctcpreply(msg.sender.nick, 'CLIENTINFO', ':To get info about a certain CTCP command, use "CLIENTINFO <command>". Note that this client does not support multiple extended messages or having both extended and normal data in the same PRIVMSG or NOTICE. Default known commands: FINGER VERSION SOURCE USERINFO CLIENTINFO ERRMSG PING TIME')
                            end
                        elseif msg.args[2] ~= 'ACTION' then
                            self:sendctcpreply(msg.sender.nick, 'ERROR', (msg.args[2])..' :Unknown CTCP command')
                        end
                    end
                    self:_trigger_event_handlers('receivedmessage_post', msg)
                end
            end
        end
        if err == 'closed' then
            if self._intentionally_quit then
                self.state = 'disconnected'
                self:_trigger_event_handlers('statechanged', self.state)
                self._eventloop:remove_readable_handler(self._conn, self._rhandler)
                self._eventloop:remove_writable_handler(self._conn, self._whandler)
            else
                self:_reconnect('closed')
            end
        end
    end
    return true
end--}}}

-- (private) socket writable callback
function Client:_on_writable()--{{{
    if self.state == 'connecting' then
        self:_on_socket_connected()
    elseif self.state == 'sslhandshake' then
        self:_do_ssl_handshake()
    else
        if #self._sendbuf ~= 0 then
            local success, err, bytessent = self._conn:send(self._sendbuf)
            if err == 'timeout' then
                self._sendbuf = self._sendbuf:sub(bytessent+1)
                self._eventloop:add_writable_handler(self._conn, self._whandler)
            --elseif err == 'closed' then
                --self:_reconnect('closed')
            else
                self._sendbuf = ''
            end
        end
    end
    return false
end--}}}

-- (private) send data from the socket, buffering it if needed
function Client:_send(str)--{{{
    if #self._sendbuf == 0 then
        local success, err, bytessent = self._conn:send(str)
        if err == 'timeout' then
            self._sendbuf = self._sendbuf..str:sub(bytessent+1)
            self._eventloop:add_writable_handler(self._conn, self._whandler)
        --elseif err == 'closed' then
            --self:_reconnect('closed')
        end
    else
        self._sendbuf = self._sendbuf..str
        self._eventloop:add_writable_handler(self._conn, self._whandler)
    end
end--}}}

-- (private) trigger an event handler
function Client:_trigger_event_handlers(event, ...)--{{{
    for cb in pairs(self._eventhandlers[event]) do
        local success, errmsg = pcall(cb, self, ...)
        if not success then
            io.stderr:write(('error in irc.Client "%s" event handler: %s\n'):format(event, tostring(errmsg)))
        end
    end
end--}}}
--}}}

-- Keep track of the channels a Client is in, and their members.
-- Contains a field called 'chanstates', which is a table organized like this:
--
-- chanstates = { -- has name_key_metatable
--     ['#example'] = {
--         name = '#Example', -- the real name of the channel, since name_key_metatable makes keys lowercase
--         topic = 'This is an example', -- may be nil if unknown
--         mode = '+ntl', -- may be nil if unknown
--         modeparams = { -- mode parameters
--             ['l'] = '10',
--         },
--         members = { -- has name_key_metatable
--             ['someone'] = {
--                 mode = '+v',
--                 prefix = {
--                     nick = 'Someone', -- use this to get the nick instead of the key of the members entry, since name_key_metatable makes keys lowercase
--                     user = 'example', -- may be nil if unknown
--                     host = '12.34.56.78', -- may be nil if unknown
--                     str = 'Someone!example@12.34.56.78', -- may be nil if unknown
--                 },
--             },
--         },
--     },
-- }

local ChannelTracker = {}--{{{
ChannelTracker.__index = ChannelTracker
setmetatable(ChannelTracker, {__call = function (t, ...) return ChannelTracker.new(...) end})

function ChannelTracker.new(client)--{{{
    local self = {}
    setmetatable(self, ChannelTracker)
    self._client = client
    self.netinfo = client.netinfo
    self.identinfo = client.identinfo
    self.defaults = client.defaults
    self._unknownprefixes = {}
    setmetatable(self._unknownprefixes, client:name_key_metatable())
    self.chanstates = {}
    setmetatable(self.chanstates, client:name_key_metatable())
    self._eventhandlers = {
        ['joinedchannel'] = {},
        ['leftchannel'] = {},
        ['memberadded'] = {},
        ['memberleft'] = {},
        ['membernick'] = {},
        ['membermode'] = {},
        ['memberprefix'] = {},
        ['channeltopic'] = {},
        ['channelmode'] = {},
        ['receivedmessage'] = {},
    }
    for k, v in pairs(self._eventhandlers) do setmetatable(v, {__mode='k'}) end
    self._msghandler = function (client, msg)
        if self._unknownprefixes[msg.sender.nick] and msg.sender.host then
            self._unknownprefixes[msg.sender.nick] = nil
            for k, v in pairs(self.chanstates) do
                local member = v.members[msg.sender.nick]
                if member then
                    member.prefix = msg.sender
                    self:_trigger_event_handlers('memberprefix', v.name, member.prefix.nick, member.prefix)
                end
            end
        end
        self:_trigger_event_handlers('receivedmessage', msg)
        local f = ChannelTracker._msghandlers[msg.cmd]
        if f then f(self, msg) end
    end
    self._statehandler = function (client, state)
        if state == 'connected' then
            self._unknownprefixes = {}
            setmetatable(self._unknownprefixes, client:name_key_metatable())
            self.chanstates = {}
            setmetatable(self.chanstates, client:name_key_metatable())
        end
    end
    client:add_event_handler('receivedmessage_pre', self._msghandler)
    client:add_event_handler('statechanged', self._statehandler)
    return self
end--}}}

function ChannelTracker:_trigger_event_handlers(event, ...)--{{{
    for cb in pairs(self._eventhandlers[event]) do
        local success, errmsg = pcall(cb, self, ...)
        if not success then
            io.stderr:write(('error in irc.Client "%s" event handler: %s\n'):format(event, tostring(errmsg)))
        end
    end
end--}}}

function ChannelTracker:add_callback(event, cb)--{{{
    self._eventhandlers[event][cb] = true
end--}}}

function ChannelTracker:remove_callback(event, cb)--{{{
    self._eventhandlers[event][cb] = nil
end--}}}

ChannelTracker.add_event_handler = ChannelTracker.add_callback
ChannelTracker.remove_event_handler = ChannelTracker.remove_callback

function ChannelTracker:_remove_from_unknownprefixes(nick)--{{{
    for _, chan in pairs(self.chanstates) do
        if chan.members[nick] then return end
    end
    self._unknownprefixes[nick] = nil
end--}}}

ChannelTracker._msghandlers = {--{{{
    ['JOIN'] = function (self, msg)--{{{
        if not (#msg.args >= 1 and ischanname(msg.args[1]) and msg.sender and msg.sender.nick) then return end
        if self._client:nameeq(self._client:get_nick(), msg.sender.nick) then
            local chan = {
                name = msg.args[1],
                members = {},
                modeparams = {},
                -- mode = nil
            }
            setmetatable(chan.members, msg.client:name_key_metatable())
            chan.members[self._client:get_nick()] = {prefix={nick=self._client:get_nick()}, mode='+'}
            self.chanstates[msg.args[1]] = chan
            self:_trigger_event_handlers('joinedchannel', msg.args[1], chan)
            if self.netinfo.send_names_on_join or self.defaults.send_names_on_join then self._client:sendmessage('NAMES', msg.args[1]) end
            if self.netinfo.send_mode_on_join or self.defaults.send_mode_on_join then self._client:sendmessage('MODE', msg.args[1]) end
            if self.netinfo.send_topic_on_join or self.defaults.send_topic_on_join then self._client:sendmessage('TOPIC', msg.args[1]) end
        else
            local chan = self.chanstates[msg.args[1]]
            if chan then
                chan.members[msg.sender.nick] = {
                    mode = '+',
                    prefix = msg.sender,
                }
                self:_trigger_event_handlers('memberadded', msg.args[1], msg.sender.nick, 'JOIN')
            end
        end
    end,--}}}
    ['PART'] = function (self, msg)--{{{
        if not (#msg.args >= 1 and msg.sender and msg.sender.nick) then return end
        if self._client:nameeq(self._client:get_nick(), msg.sender.nick) then
            local chan = self.chanstates[msg.args[1]]
            if chan then
                for k, v in pairs(chan.members) do
                    chan.members[k] = nil
                    self:_remove_from_unknownprefixes(k)
                end
                self.chanstates[msg.args[1]] = nil
                self:_trigger_event_handlers('memberleft', msg.args[1], msg.sender.nick, '*PART')
                self:_trigger_event_handlers('leftchannel', msg.args[1], 'PART')
            end
        else
            local chan = self.chanstates[msg.args[1]]
            if chan then
                chan.members[msg.sender.nick] = nil
                self:_remove_from_unknownprefixes(msg.sender.nick)
                self:_trigger_event_handlers('memberleft', msg.args[1], msg.sender.nick, 'PART')
            end
        end
    end,--}}}
    ['KICK'] = function (self, msg)--{{{
        if not (#msg.args >= 2) then return end
        if self._client:nameeq(self._client:get_nick(), msg.args[2]) then
            local chan = self.chanstates[msg.args[1]]
            if chan then
                for k, v in pairs(chan.members) do
                    chan.members[k] = nil
                    self:_remove_from_unknownprefixes(k)
                end
                self.chanstates[msg.args[1]] = nil
                self:_trigger_event_handlers('memberleft', msg.args[1], msg.args[2], '*KICK')
                self:_trigger_event_handlers('leftchannel', msg.args[1], 'KICK')
            end
        else
            local chan = self.chanstates[msg.args[1]]
            if chan then
                chan.members[msg.args[2]] = nil
                self:_remove_from_unknownprefixes(msg.args[2])
                self:_trigger_event_handlers('memberleft', msg.args[1], msg.args[2], 'KICK')
            end
        end
    end,--}}}
    ['QUIT'] = function (self, msg)--{{{
        if not (msg.sender and msg.sender.nick) then return end
        self._unknownprefixes[msg.sender.nick] = nil
        if not self._client:nameeq(self._client:get_nick(), msg.sender.nick) then
            for channame, chan in pairs(self.chanstates) do
                if chan.members[msg.sender.nick] then
                    chan.members[msg.sender.nick] = nil
                    self:_trigger_event_handlers('memberleft', channame, msg.sender.nick, 'QUIT')
                end
            end
        end
    end,--}}}
    ['NICK'] = function (self, msg)--{{{
        if not (#msg.args >= 1 and msg.sender and msg.sender.nick) then return end
        for channame, chan in pairs(self.chanstates) do
            if chan.members[msg.sender.nick] then
                chan.members[msg.args[1]], chan.members[msg.sender.nick] = chan.members[msg.sender.nick], nil
                chan.members[msg.args[1]].prefix.nick = msg.args[1]
                self:_trigger_event_handlers('membernick', channame, msg.sender.nick, msg.args[1])
            end
        end
    end,--}}}
    ['TOPIC'] = function (self, msg)--{{{
        if not (#msg.args >= 2) then return end
        local chan = self.chanstates[msg.args[1]]
        if chan then
            chan.topic = msg.args[2]
            self:_trigger_event_handlers('channeltopic', msg.args[1], chan.topic, true)
        end
    end,--}}}
    ['MODE'] = function (self, msg)--{{{
        if not (#msg.args >= 2) then return end
        local chan = self.chanstates[msg.args[1]]
        if chan then
            local argnum = 2
            while argnum <= #msg.args do -- because a for loop doesn't let you modify the number in the body of the loop
                local positive = true
                for char in msg.args[argnum]:gmatch('.') do
                    if char == '+' then
                        positive = true
                    elseif char == '-' then
                        positive = false
                    elseif char:match('%w') then
                        local hasparam, ismembermode, modetype = false, false, 'd'
                        if self._client.isupport.prefixesformode[char] then
                            hasparam, ismembermode, modetype = 'nick', true, 'a'
                        elseif self._client.isupport.chanmodes.a:find(char, 1, true) then
                            hasparam, ismembermode, modetype = 'nick', true, 'a'
                        elseif self._client.isupport.chanmodes.b:find(char, 1, true) then
                            hasparam, modetype = true, 'b'
                        elseif self._client.isupport.chanmodes.c:find(char, 1, true) then
                            hasparam, modetype = positive, 'c'
                        end
                        if hasparam then
                            argnum = argnum + 1
                            if ismembermode then
                                local arg = msg.args[argnum]
                                if arg then
                                    local member = chan.members[arg]
                                    if member then
                                        member.mode = applymode(member.mode, (positive and '+' or '-')..char)
                                        self:_trigger_event_handlers('membermode', msg.args[1], arg, member.mode)
                                    end
                                end
                            end
                        end
                        if (not ismembermode) and hasparam ~= 'nick' then
                            chan.mode = applymode(chan.mode or '+', (positive and '+' or '-')..char)
                            if modetype == 'c' then
                                chan.modeparams[char] = positive and msg.args[argnum] or nil
                            end
                            self:_trigger_event_handlers('channelmode', chan.name, chan.mode, true)
                        end
                    end
                end
                argnum = argnum + 1
            end
        end
    end,--}}}
    ['353'] = function (self, msg) -- RPL_NAMREPLY--{{{
        if not (#msg.args >= 4) then return end
        local chan = self.chanstates[msg.args[3]]
        if chan then
            for member in msg.args[4]:gmatch('[^ ]+') do
                local nick, mode = nil, '+'
                if #member >= 2 and self._client.isupport.modesforprefix[member:sub(1, 1)] then
                    nick = member:sub(2, -1)
                    mode = '+'..self._client.isupport.modesforprefix[member:sub(1, 1)]
                else
                    nick = member
                end
                if (not chan.members[nick]) and isnick(nick) then
                    chan.members[nick] = {mode = mode, prefix = {nick=nick}}
                    self:_trigger_event_handlers('memberadded', msg.args[3], nick, 'NAMES')
                    self._unknownprefixes[nick] = true
                elseif chan.members[nick] then
                    chan.members[nick].mode = mode
                end
            end
        end
    end,--}}}
    ['324'] = function (self, msg) -- RPL_CHANNELMODEIS--{{{
        if not (#msg.args >= 3) then return end
        local chan = self.chanstates[msg.args[2]]
        if chan then
            chan.mode = msg.args[3]
            self:_trigger_event_handlers('channelmode', msg.args[2], chan.mode, false)
        end
    end,--}}}
    ['332'] = function (self, msg) -- RPL_TOPIC--{{{
        if not (#msg.args >= 3) then return end
        local chan = self.chanstates[msg.args[2]]
        if chan then
            chan.topic = msg.args[3]
            self:_trigger_event_handlers('channeltopic', msg.args[2], chan.topic, false)
        end
    end,--}}}
}--}}}
--}}}

local AutoJoiner = {}--{{{
AutoJoiner.__index = AutoJoiner
setmetatable(AutoJoiner, {__call = function (t, ...) return AutoJoiner.new(...) end})

function AutoJoiner.new(client)--{{{
    local self = {}
    setmetatable(self, AutoJoiner)
    self._client = client
    self._netinfo = client.netinfo
    self._defaults = client.defaults
    self.rejoining_channels = {}
    setmetatable(self.rejoining_channels, client:name_key_metatable())
    self.on_channels = {}
    setmetatable(self.on_channels, client:name_key_metatable())
    for _, i in ipairs(self._netinfo.autojoin or {}) do self.rejoining_channels[i] = {} end

    local function timer_cb(channel)
        if self.rejoining_channels[channel] then
            self._client:sendmessage('JOIN', channel)
        end
    end

    self._on_statechanged = function (client, state)
        if state == 'connected' then
            for k, v in pairs(self.rejoining_channels) do
                self._client:sendmessage('JOIN', k) -- FIXME client might not have correct CASEMAPPING settings yet
            end
            client:add_event_handler('receivedmessage_pre', self._on_message)
        elseif state == 'disconnected' or state == 'reconnecting' then
            for k, v in pairs(self.on_channels) do
                self.rejoining_channels[k] = {}
            end
            client:remove_event_handler('receivedmessage_pre', self._on_message)
        end
    end

    self._on_message = function (client, msg)
        if msg.cmd == 'JOIN' and msg.sender.nick and self._client:nameeq(msg.sender.nick, client:get_nick()) then
            self.on_channels[msg.args[1]] = true
            if self.rejoining_channels[msg.args[1]] then
                local timer = self.rejoining_channels[msg.args[1]]._timer
                if timer then timer:cancel() end
                self.rejoining_channels[msg.args[1]] = nil
            end
        elseif msg.cmd == 'PART' and msg.sender.nick and self._client:nameeq(msg.sender.nick, client:get_nick()) then
            self.on_channels[msg.args[1]] = nil
            local rejoininfo = self.rejoining_channels[msg.args[1]]
            if rejoininfo and rejoininfo._timer then rejoininfo._timer:cancel() end
            self.rejoining_channels[msg.args[1]] = nil
        elseif msg.cmd == 'KICK' and #msg.args >= 2 and self._client:nameeq(msg.args[2], client:get_nick()) then
            self.on_channels[msg.args[1]] = nil
            local rejoininfo = self.rejoining_channels[msg.args[1]]
            if rejoininfo and rejoininfo._timer then rejoininfo._timer:cancel() end
            rejoininfo = {}
            rejoininfo._interval = self._netinfo.initial_rejoin_interval or self._defaults.initial_rejoin_interval
            rejoininfo._timer = self._client.eventloop:timer(rejoininfo._interval, function () timer_cb(msg.args[1]) end)
            self.rejoining_channels[msg.args[1]] = rejoininfo
        elseif (msg.cmd == '471' or
                msg.cmd == '474' or
                msg.cmd == '437') and #msg.args >= 2 and self.rejoining_channels[msg.args[2]] then
            self.on_channels[msg.args[1]] = nil
            local rejoininfo = self.rejoining_channels[msg.args[1]] or {}
            if rejoininfo._timer then rejoininfo._timer:cancel() end
            if rejoininfo._interval then
                rejoininfo._interval = rejoininfo._interval * (self._netinfo.rejoin_interval_scale or self._defaults.rejoin_interval_scale)
                local max = self._netinfo.max_rejoin_interval or self._defaults.max_rejoin_interval
                if rejoininfo._interval > max then rejoininfo._interval = max end
            else
                rejoininfo._interval = self._netinfo.initial_rejoin_interval or self._defaults.initial_rejoin_interval
            end
            rejoininfo._timer = self._client.eventloop:timer(rejoininfo._interval, function () timer_cb(msg.args[2]) end)
            self.rejoining_channels[msg.args[1]] = rejoininfo
        elseif (msg.cmd == '403' or
                msg.cmd == '475' or
                msg.cmd == '473' or
                msg.cmd == '476') and #msg.args >= 2 and self.rejoining_channels[msg.args[2]] then
            local rejoininfo = self.rejoining_channels[msg.args[1]]
            if rejoininfo and rejoininfo._timer then rejoininfo._timer:cancel() end
            self.rejoining_channels[msg.args[1]] = nil
        end
    end

    client:add_event_handler('statechanged', self._on_statechanged)

    return self
end--}}}

function AutoJoiner:addchannel(chan)
    self.rejoining_channels[chan] = {}
    self._client:sendmessage('JOIN', chan)
end--}}}

-- stuff available to users of this module
return {--{{{
    enable_ssl = enable_ssl,
    sender_prefix_to_table = sender_prefix_to_table,
    message_line_to_table = message_line_to_table,
    rfc1459_lower = rfc1459_lower,
    rfc1459_upper = rfc1459_upper,
    rfc1459_nameeq = rfc1459_nameeq,
    strict_rfc1459_lower = strict_rfc1459_lower,
    strict_rfc1459_upper = strict_rfc1459_upper,
    strict_rfc1459_nameeq = strict_rfc1459_nameeq,
    rfc1459_name_key_metatable = rfc1459_name_key_metatable,
    strict_rfc1459_name_key_metatable = strict_rfc1459_name_key_metatable,
    ascii_name_key_metatable = ascii_name_key_metatable,
    ascii_nameeq = ascii_nameeq,
    isnumreply = isnumreply,
    iserrreply = iserrreply,
    ischanname = ischanname,
    isnick = isnick,
    applymode = applymode,
    Client = Client,
    ChannelTracker = ChannelTracker,
    AutoJoiner = AutoJoiner,
}--}}}

