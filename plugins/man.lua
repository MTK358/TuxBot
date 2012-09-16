
local function getsyn(msg, section, name)
    local conn = socket.tcp()
    conn:settimeout(0)

    local thiscoro, event = coroutine.running(), nil
    local function onr() if coroutine.status(thiscoro) == 'dead' then return false end; local success, err = coroutine.resume(thiscoro) if not success then error(err) end; return true end
    local function onw() if coroutine.status(thiscoro) == 'dead' then return false end; local success, err = coroutine.resume(thiscoro) if not success then error(err) end; return false end
    bot.eventloop:add_readable_handler(conn, onr)
    bot.eventloop:add_writable_handler(conn, onw)
    local timer = bot.eventloop:timer(15, function () coroutine.resume(thiscoro, 'timeout') end)

    local title, reply, contenttype, responsecode = nil, '', nil, nil
    print'1'

    repeat
        conn:connect('linux.die.net', 80)

        event = coroutine.yield()
        if event == 'timeout' then break end

        conn:send(('GET /man/%s/%s HTTP/1.1\n'):format(section, name))
        conn:send('Host: linux.die.net\n\n')

        local redirect = false

        while true do
            event = coroutine.yield()
            if event == 'timeout' then break end

            local data, err, partial = conn:receive(2048)
            reply = reply..(data or partial or '')

            if not responsecode then
                responsecode = reply:match('^HTTP/[%d.]+ +(%d%d%d)')
                if responsecode and responsecode ~= '200' then break end
            end

            local syn = reply:match('<h2>Synopsis</h2>(.-)<h2>')
            if syn then
                syn = syn:gsub('^%s*(.-)%s*$', '%1'):gsub('%s+', ' '):gsub('<br%s*/?>', '\n'):gsub('<.->', ''):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&amp;', '&')
                local linecount = 1
                for line in syn:gmatch('[^\r\n]+') do
                    if linecount == 5 then
                        bot.reply(msg, msg.sender.nick..': (further lines not shown)')
                        break
                    else
                        bot.reply(msg, msg.sender.nick..': '..(#line > 200 and line:sub(1, 195)..'\002(...)\002' or line))
                    end
                    linecount = linecount + 1
                end
                break
            end

            -- give up after a certain amount has been downloaded, not to waste resources
            if err == 'closed' or #reply >= 10000 then break end
        end
    until true

    bot.eventloop:remove_readable_handler(conn, onr)
    bot.eventloop:remove_writable_handler(conn, onw)
    timer:cancel()
    conn:close()
end

local function msghandler(client, msg)
    if msg.cmd == 'PRIVMSG' then
        local section, name = arg:match(' *(%d) +(.+)')
        if not section then
            bot.reply(msg, msg.sender.nick..': Usage: synopsis <section> <name>')
        else
            local c = coroutine.create(getsyn)
            coroutine.resume(c, section, name)
        end
    end
end

local function man_handler(msg, arg)
    local section, name = arg:match(' *(%d) +(.+)')
    if not section then
        bot.reply(msg, msg.sender.nick..': Usage: man <section> <name>')
        return
    end
    bot.reply(msg, ('%s: http://linux.die.net/man/%s/%s'):format(msg.sender.nick, section, name))
end

local function synopsis_handler(msg, arg)
    local section, name = arg:match(' *(%d) +(.+)')
    if not section then
        bot.reply(msg, msg.sender.nick..': Usage: synopsis <section> <name>')
        return
    end
    local c = coroutine.create(getsyn)
    coroutine.resume(c, msg, section, name)
end

bot.commands['man'] = {man_handler, help='man <section> <name> -- Get a link to a man page.'}
bot.commands['synopsis'] = {synopsis_handler, help='synopsis <section> <name> -- Get the synopsis section of a man page.', mininterval=8}
bot.commands['syn'] = {synopsis_handler, help='syn <section> <name> -- same as "synopsis"', mininterval=8}

