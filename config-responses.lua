return {
    [ [[{('hi'/'hello'/'hey'/'good '('morning'/'afternoon'/'evening'/ 'night'))}' tuxbot']] ] = {
        '%1 %s',
    },
    [ [[('i '('hate'/'don'"'"?'t like')' tuxbot') / ('tuxbot '('sucks'/'is '('useless'/'dumb'/'stupid')))]] ] = {
        'Shut up!',
        'Really? :(',
        'Why?',
        'You do not have to like me =P',
        'You must be kidding! O.O',
    },
    [ [[a<-('tuxbot 'b/b' tuxbot') b<-('how are you'' doing'?/'how do you do')]] ] = {
        "I'm fine.",
        "I'm fine, thanks. ;)",
        "Could be better... :/",
        "I'm okay, thanks for asking! :D",
        "I'm great! :DD",
    },
    [ [[a<-b/[^ ]+' '+b b<-('cu'/'see you'/'bye'/'goodbye')(&' '/!.)]] ] = {
        'May the source be with you.',
    },
}

