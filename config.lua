return {
    identities = {
        ['testbot'] = {
            username = 'fsdfsf',
            realname = 'fdfsdf',
            userinfo = 'dfsfdf',
            quitmessage = 'Quit Message',
            nicks = {'test_bot'},
        },
    },

    networks = {
        --[[['Test'] = {
            address = 'irc.esper.net',
            port = 6697,
            ssl = true,
            channels = {'#test[]', '#test[]~'},
            identity = 'testbot',
            sentcolor = '1;32m',
            receivedcolor = '0;32m',
            ignore = {
                '^.*!.*@.*services%.esper%.net$',
            },
        },]]
        ['EsperNet'] = {
            address = 'irc.esper.net',
            channels = {'#linux', '#freiwuppertal', '#test[]', '#test[]~'},
            identity = 'testbot',
            sentcolor = '1;32m',
            receivedcolor = '0;32m',
            ignore = {
                '^.*!.*@.*services%.esper%.net$',
            },
        },
        ['OFTC'] = {
            address = 'irc.oftc.net',
            port = 6667,
            channels = {'#linux'},
            identity = 'testbot',
            sentcolor = '1;31m',
            receivedcolor = '0;31m',
            ignore = {
                '^.*!.*@.*services%.oftc%.net$',
            },
        },
        --[[['Rizon'] = {
            address = 'irc.oftc.net',
            port = 6667,
            channels = {'#test[]'},
            identity = 'testbot',
            sentcolor = '1;36m',
            receivedcolor = '0;36m',
            ignore = {
                '^.*!.*@%.rizon%.net$',
                '^.*!.*@Microsoft%.com$',
            },
        },
        ['Freenode'] = {
            address = 'irc.oftc.net',
            port = 6667,
            channels = {'#test[]'},
            identity = 'testbot',
            sentcolor = '1;35m',
            receivedcolor = '0;35m',
            ignore = {
                '^.*!.*@.*services%.freenode%.net$',
            },
        },]]
    },

    command_prefixes = {'!', '[Tt][Uu][Xx][Bb][Oo][Tt] *[:,] *'},
    no_command_message = '"%s": no such command',

    plugins = {
        ['echo'] = {'echo.lua'},
        ['rand'] = {'rand.lua'},
        ['yesno'] = {'yesno.lua', {
            choices = {
                "Yes.",
                "No.",
                "Yes, absolutely :D",
                "No, not really ;)",
                "Yes, why not?",
                "No!!! O.O",
                "Maybe...",
                "I don't know. :/",
                "Well, what do \002you\002 think?",
                "I am not authorized to answer a question like this.",
            },
        }},
        ['responses'] = {'responses.lua', {
            responses = dofile('config-responses.lua')},
        },
        ['luaapi'] = {'luaapi.lua'},
	['nickregain'] = {'nickregain.lua', {
	    execafter = {
	        "PRIVMSG NickServ :identify PassW0rd",
	        "PRIVMSG BotOwner :someone used @@regain on this network",
            },  
        }},
        ['time'] = {'time.lua'},
        ['commands'] = {'commands.lua'},
        ['help'] = {'help.lua', {
            entries = dofile('config-help.lua')
        }},
        ['floodkick'] = {'floodkick.lua'},
        --['urltitle'] = {'urltitle.lua'},
        ['man'] = {'man.lua'},
        ['relay'] = {'relay.lua', {
            {{'EsperNet', '#linux'}, {'OFTC', '#linux'}, shownetname=true},
            {{'EsperNet', '#test[]'}, {'EsperNet', '#test[]~'}, showchanname=true},
            nickfmts = {'\0033', '\0034', '\0035', '\0036', '\0037', '\0039', '\00310', '\00311', '\00312', '\00313', endfmt='\015'},
        }},
    },
}
