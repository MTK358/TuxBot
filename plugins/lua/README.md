Warning
-------

**The sandbox process isn't 100% guaranteed to stop access to unsafe Lua
functions (but it runs in a chroot to hopefully prevent any damage from being
done). Use at your own risk.**

How it works
------------

The Lua plugin just launches a sandbox executable and reads its output. The
executable is a C program that `chroot`s into an empty directory, drops root
powers using `setuid` and `setgid`, sets resource limits using `setrlimit`,
creates a Lua state (using a modified Lua interpreter without unsafe standard
functions), and runs the script. The executable should be owned by root and
have the setuid bit set so that the bot can start it without being root
(`chroot` requires the executable to be running as root to work). It might be a
good idea to have a user account and group for the bot and make the sandbox
executable only for root and that group.

Instructions
------------

`cd` into this plugin's directory, and run:

    cd luasrc
    make linux # if not on Linux, run "make" to get a list of platforms and use the correct one
    cd ..
    make
    sudo chown root:tuxbot sandbox  # replace "tuxbot" with a group containing TuxBot's user account
    sudo chmod 4770 sandbox
    mkdir tmpdir
    sudo chown tuxbot:tuxbot tmpdir
    sudo chmod a-w tmpdir

Then open init.lua, and where is says so, enter the name of the user account to
run the sandbox as.

Also, I don't know if this would work, but maybe it's a good idea to `chmod a-w
tmpdir` to prevent the sandbox from being able to add files to it.

