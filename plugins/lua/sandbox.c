
#include "luasrc/lua.h"
#include "luasrc/lauxlib.h"
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <pwd.h>
//#undef NDEBUG
#define NDEBUG
#include <assert.h>

static void tostring (lua_State *L, int index);

static int printfunc(lua_State *L);

static void sigxcpu_handler(int signum) {
    fprintf(stderr, "cpulimit");
    exit(1);
}

int main(int argc, char **argv) {
    if (argc != 4) return 1;
    const char *tmpdir = argv[1];
    const char *username = argv[2];
    const char *code = argv[3];

    struct passwd *userinfo = getpwnam(username);

    if (userinfo == NULL) {
        fprintf(stderr, "sandbox: getpwnam failed\n");
        return 1;
    }

    if (chdir(tmpdir) != 0) {
        fprintf(stderr, "sandbox: failed to chdir into temporary dir\n");
        return 1;
    }

    if (chroot(".") != 0) {
        fprintf(stderr, "sandbox: failed to chroot into temporary dir\n");
        return 1;
    }

    if (setgid(userinfo->pw_gid) != 0) {
        fprintf(stderr, "sandbox: setgid failed\n");
        return 1;
    }

    if (setuid(userinfo->pw_uid) != 0) {
        fprintf(stderr, "sandbox: setuid failed\n");
        return 1;
    }

    signal(SIGXCPU, &sigxcpu_handler);

    struct rlimit cpulimit, memlimit;
    cpulimit.rlim_cur = 1;
    cpulimit.rlim_max = 2;
    memlimit.rlim_cur = 10000000;
    memlimit.rlim_max = 20000000;

    if (setrlimit(RLIMIT_CPU, &cpulimit)) {
        fprintf(stderr, "sandbox: setrlimit for cpu failed\n");
        return 1;
    }
    if (setrlimit(RLIMIT_AS, &memlimit)) {
        fprintf(stderr, "sandbox: setrlimit for memory falise\n");
        return 1;
    }

    // run the script
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    lua_newtable(L);
    lua_pushvalue(L, -1);
    lua_pushcclosure(L, &printfunc, 1);
    lua_setglobal(L, "print");
    int oldstack = lua_gettop(L);
    luaL_loadstring(L, code);
    int success = lua_pcall(L, 0, LUA_MULTRET, 0);
    if (success == 0) {
        int newstack = lua_gettop(L);
        if (newstack != oldstack) {
            int i;
            for (i=oldstack+1; i<=newstack; ++i) {
                tostring(L, i);
                size_t len = lua_objlen(L, oldstack);
                lua_rawseti(L, oldstack, len+1);
                if (i == newstack) lua_pushliteral(L, "\n"); else lua_pushliteral(L, " ");
                lua_rawseti(L, oldstack, len+2);
            }
        }
        luaL_Buffer outbuf;
        luaL_buffinit(L, &outbuf);
        size_t count = lua_objlen(L, oldstack);
        assert(lua_type(L, oldstack) == LUA_TTABLE);
        size_t i;
        for (i=1; i<=count; ++i) {
            lua_rawgeti(L, oldstack, i);
            luaL_addvalue(&outbuf);
        }
        luaL_pushresult(&outbuf);
    }
    size_t outlen;
    const char *outstr = lua_tolstring(L, -1, &outlen);
    fwrite(outstr, outlen, 1, stdout);

    return 0;
}

static int printfunc(lua_State *L) {
    int nargs = lua_gettop(L);
    int i;
    for (i=1; i<=nargs; ++i) {
        tostring(L, i);
        size_t len = lua_objlen(L, lua_upvalueindex(1));
        lua_rawseti(L, lua_upvalueindex(1), len+1);
        if (i == nargs) lua_pushliteral(L, "\n"); else lua_pushliteral(L, " ");
        lua_rawseti(L, lua_upvalueindex(1), len+2);
    }
}

// modified from the standard Lua library tostring implementation
static void tostring (lua_State *L, int index) {
  if (luaL_callmeta(L, index, "__tostring"))  /* is there a metafield? */
    return;  /* use its value */
  switch (lua_type(L, index)) {
    case LUA_TNUMBER:
      lua_pushvalue(L, index);
      lua_tostring(L, -1);
      break;
    case LUA_TSTRING:
      lua_pushvalue(L, index);
      break;
    case LUA_TBOOLEAN:
      lua_pushstring(L, (lua_toboolean(L, index) ? "true" : "false"));
      break;
    case LUA_TNIL:
      lua_pushliteral(L, "nil");
      break;
    default:
      lua_pushfstring(L, "%s: %p", luaL_typename(L, index), lua_topointer(L, index));
      break;
  }
}

