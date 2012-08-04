
local choices = config and config.choices or {'yes', 'no'}

local function yesno_handler(msg, arg)
    local choice = math.random(1, #choices)
    bot.reply(msg, msg.sender.nick..': '..choices[choice])
end

bot.commands['yesno'] = {yesno_handler, help='yesno [<question>] -- Get a random yes/no response'}

