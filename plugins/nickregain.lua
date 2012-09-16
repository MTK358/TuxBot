local execafter = config and config.execafter or {} -- if no "execafter" commands are specified in the configuration, we use an empty table.

local function nickregain_handler(msg)
    local wantednick = msg.client.identinfo.nicks[1] -- what nick do we want to regain? It might be different on every network
    if  msg.client:get_nick() ~= wantednick then  -- we need to check if we are already using the nick specified in the configuration file
        msg.client:set_nick(wantednick) -- if we are not using it at the moment, we try to get that nick
        for _, line in ipairs(execafter) do -- and execute the "execafter" commands
            msg.client:sendmessageline(line)
        end
        
        msg.client:sendmessageline(execafter)
    end
end

bot.commands['regain'] = {nickregain_handler, help='regain -- Try to regain the nick specified in the configuration file and execute \'execafter\''}