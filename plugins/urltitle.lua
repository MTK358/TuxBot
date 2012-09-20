
local extension_blacklist = config and config.extension_blacklist or {'png', 'jpeg', 'jpg', 'gif', 'bmp'}
local whitelist = config and config.whitelist or error('whitelist not specified')
for k, v in pairs(extension_blacklist) do extension_blacklist[k] = ('\.%s$'):format(v) end

local function gettitle(msg, url, redirected)

    local lowerurl = url:lower()
    for _, ext in pairs(extension_blacklist) do
        if lowerurl:match(ext) then return end
    end

    local address = url:match('http://([%w.-]+)')
    if not address then return end
    local path = url:match('http://.-(/.*)') or '/'

    local conn = socket.tcp()
    conn:settimeout(0)

    local thiscoro, event = coroutine.running(), nil
    local function onr() if coroutine.status(thiscoro) == 'dead' then return false end; local success, err = coroutine.resume(thiscoro) if not success then error(err) end; return true end
    local function onw() if coroutine.status(thiscoro) == 'dead' then return false end; local success, err = coroutine.resume(thiscoro) if not success then error(err) end; return false end
    bot.eventloop:add_readable_handler(conn, onr)
    bot.eventloop:add_writable_handler(conn, onw)
    local timer = bot.eventloop:timer(15, function () coroutine.resume(thiscoro, 'timeout') end)

    local title, reply, contenttype, responsecode = nil, '', nil, nil

    repeat
        conn:connect(address, 80)

        event = coroutine.yield()
        if event == 'timeout' then break end

        conn:send('GET '..path..' HTTP/1.1\n')
        conn:send('Host: '..address..'\n\n')

        local redirect = false

        while true do
            event = coroutine.yield()
            if event == 'timeout' then break end

            local data, err, partial = conn:receive(512)
            reply = reply..(data or partial or '')

            if not responsecode then
                responsecode = reply:match('^HTTP/[%d.]+ +(%d%d%d)')
                if (not redirected) and responsecode and responsecode:match('3..') then redirect = true end
            end

            if redirect then
                local location = reply:match('[\r\n]Location: *(..-)[\r\n]')
                if location then
                    local c = coroutine.create(gettitle)
                    coroutine.resume(c, msg, location, true)
                    break
                end
            end

            -- stop if the content isn't HTML
            if not contenttype then
                contenttype = reply:match('[\r\n]Content%-Type: *([%w-_/]+)')
                if contenttype and contenttype ~= 'text/html' then break end
            end

            title = reply:match('<[Tt][Ii][Tt][Ll][Ee]>(.-)</[Tt][Ii][Tt][Ll][Ee]>')
            if title then break end

            -- give up after a certain amount has been downloaded, not to waste resources
            if err == 'closed' or #reply >= 10000 then break end
        end
    until true

    bot.eventloop:remove_readable_handler(conn, onr)
    bot.eventloop:remove_writable_handler(conn, onw)
    timer:cancel()
    conn:close()

    if title and #title > 0 and #title < 300 then
        title = title:gsub('<.->', ''):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&amp;', '&'):gsub('^%s*(.-)%s*$', '%1'):gsub('%s+', ' ')
        bot.reply(msg, title)
    end
end

local function msghandler(client, msg)
    if msg.cmd == 'PRIVMSG' then
        local url = msg.args[2]:match('https?://[^ ]+')
        if url then
            local addr = url:match('^%w+://([%w-.]+)')
            print('addr', addr)
            if addr then
                local ok = whitelist[addr]
                while not ok do
                    addr = addr:match('%.(.+)$')
                    print('addr', addr)
                    if not addr then break end
                    ok = whitelist[addr]
                end
                print('ok', ok)
                if ok then
                    local c = coroutine.create(gettitle)
                    coroutine.resume(c, msg, url)
                end
            end
        end
    end
end

bot.event_handlers['receivedmessage_post'] = msghandler

