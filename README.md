A Lua-based IRC library and a rewrite of TuxBot based on it.

`irc.lua`: The IRC library.
`eventloop.lua`: Simple `socket.select`-based event loop.
`bot.lua`: Plugin-based bot using the above libraries.
`plugins/` and `config*.lua`: Configuration and plugins for `bot.lua` that do most of the functionaltiy of the original TuxBot.

The library only depends on LuaSocket (and optionally LuaSec of you want SSL). The `responses.lua` bot plugin also depends on LPeg.

## `bot.lua` Usage ##

`lua bot.lua <config file> <plugins dir>`

The config file defaults to `config.lua`, the plugin dir defaults to `plugins`.

### Configuration ###

The configuration file is a Lua script that should return a table with these fields:

* `identities` A list of identities. Keys should be strings (the identity names), and values should be tables with the following fields:
  * `username`
  * `realname`
  * `userinfo` (optional)
  * `quitmessage` (optional)
  * `nick`
* `networks` The networks to join. Keys should be strings (the network names), and values should be fables with the following fields:
  * `address`
  * `port` (optional, defaults to 6667)
  * `ssl` (optional)
  * `channels` The list of channels to join. Entries can be number keys with channel names as values, or channel name keys with table values, which have the following entries:
    * `command_prefixes` (optional) The list of command prefixes to use in this channel instead of the dafault.
  * `identity`
  * `command_prefixes` (optional) The list of command prefixes to use in this network instead of the default.
  * `ignore` (optional) A list of patterns. If a message's sender prefix matches the pattern, do not process any bot commands in the message.
  * `sentcolor` (optional) A terminal color code to use for sent messages in the console.
  * `receivedcolor` (optional) A terminal color code to use for received messages in the console.
* `command_prefixes` The list of prefixes (specified as Lua patterns) to use for bot commands.
* `no_command_message` (optional) The message to use when a bot command isn't found. "%s" is replaced with the command name.
* `plugins` A table containing plugins. Keys should be plugin id strings, values should be tables with the following entries:
  * `[1]` The filename of the plugin.
  * `[2]` (optional) The value to pass to the plugin as its configuration.


### The Plugin API ###

Each plugin has its own env table, with these fields:

* The standard library.
* `config` The plugin's config from the config file.
* `irc` The `irc` module.
* `socket` The `socket` module from LuaSocket.
* `bot`
  * `event_handlers` An originally empty table. To receive events, add a key named like the event (prefixed with `tracker_` if it's a ChannelTracker event) with a function or list of functions as the value. For `receivedmessage_pre`, `receivedmessage_post`, and `tracker_receivedmessage` events, an extra "ignored" arg is given to the function, that says if the message's sender is in the configured ignore list.
  * `plugins` A table with loaded plugin names as keys and their envs as values. This is so plugins can use functions from other plugins.
  * `eventloop` The event loop.
  * `clients` A table with `irc.Client` instances as keys, and a table with the following entries as values:
    * `name` The network name.
    * `tracker` The `irc.ChannelTracker` instance.
  * `clientsbyname` A table with network names as keys and their `irc.Client` instances as values.
  * `commands` To add bot commands, add an entry to this table with the command name as the key and the callback function as the value.
  * `reply(msg, text)` A convenience function to reply to a `PRIVMSG` message. Automatically detects whether the message was sent to a channel or private, and replies to the channel/back to the sender.
  * `plugins` A table with plugin names as keys and tables with the following entries as values:
    * `env` The plugin's global env table.
    * `commands`
      * `[1]` The handler function.
      * `help` The help message.

