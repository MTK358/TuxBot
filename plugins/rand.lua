local function rand_handler(msg, arg)
    local choice = math.random(0, arg)
    bot.reply(msg, msg.sender.nick..': '..choice)
end

bot.commands['rand'] = {rand_handler, help='rand x -- Get a random number between 0 and x'}
