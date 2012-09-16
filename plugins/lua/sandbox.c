
#include <lua.h>
#include <lauxlib.h>
#include <stdio.h>
//#undef NDEBUG
#define NDEBUG
#include <assert.h>

#define rawgetl(L, index, key) lua_pushliteral(L, key); lua_rawget(L, index>0?index:index-1);
#define rawsetl(L, index, key) lua_pushliteral(L, key); lua_insert(L, -2); lua_rawset(L, index>0?index:index-1);
#define moveback(name) rawgetl(L, -2, name); assert(lua_gettop(L)!=100); rawsetl(L, -2, name);

int printfunc(lua_State *L);

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    const char *code = argv[1];

    lua_State *L = luaL_newstate();

    // load the libs and put them in a separate table
    luaL_openlibs(L);
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    lua_newtable(L);
    lua_pushvalue(L, -1);
    lua_replace(L, LUA_GLOBALSINDEX);
    assert(lua_gettop(L) == 2);

    lua_pushvalue(L, -1);
    lua_setglobal(L, "_G");

    // move the safe functions to the new global table
    moveback("assert");
    assert(lua_gettop(L) == 2);
    moveback("collectgarbage");
    assert(lua_gettop(L) == 2);
    moveback("error");
    moveback("getfenv");
    moveback("getmetatable");
    moveback("ipairs");
    moveback("load");
    moveback("loadstring");
    moveback("module");
    moveback("next");
    moveback("pairs");
    moveback("pcall");
    moveback("rawequal");
    moveback("rawget");
    moveback("rawset");
    moveback("select");
    moveback("setfenv");
    moveback("setmetatable");
    moveback("tonumber");
    moveback("tostring");
    moveback("type");
    moveback("unpack");
    moveback("xpcall");
    moveback("_VERSION");

    rawgetl(L, -2, "coroutine");
    lua_newtable(L);
    lua_pushvalue(L, -1);
    rawsetl(L, -4, "coroutine");
    assert(lua_gettop(L) == 4);
    moveback("create");
    assert(lua_gettop(L) == 4);
    moveback("resume");
    assert(lua_gettop(L) == 4);
    moveback("running");
    moveback("status");
    moveback("wrap");
    moveback("yield");
    lua_pop(L, 2);
    assert(lua_gettop(L) == 2);

    rawgetl(L, -2, "debug");
    lua_newtable(L);
    lua_pushvalue(L, -1);
    rawsetl(L, -4, "debug");
    moveback("getfenv");
    moveback("gethook");
    moveback("getinfo");
    moveback("getmetatable");
    moveback("sethook");
    moveback("setmetatable");
    moveback("traceback");
    lua_pop(L, 2);

    rawgetl(L, -2, "math");
    lua_newtable(L);
    lua_pushvalue(L, -1);
    rawsetl(L, -4, "math");
    moveback("abs");
    moveback("acos");
    moveback("asin");
    moveback("atan");
    moveback("atan2");
    moveback("ceil");
    moveback("cos");
    moveback("cosh");
    moveback("deg");
    moveback("exp");
    moveback("floor");
    moveback("fmod");
    moveback("frexp");
    moveback("huge");
    moveback("ldexp");
    moveback("log");
    moveback("log10");
    moveback("max");
    moveback("min");
    moveback("modf");
    moveback("pi");
    moveback("pow");
    moveback("rad");
    moveback("random");
    moveback("randomseed");
    moveback("sin");
    moveback("sinh");
    moveback("sqrt");
    moveback("tan");
    moveback("tanh");
    lua_pop(L, 2);

    rawgetl(L, -2, "os");
    lua_newtable(L);
    lua_pushvalue(L, -1);
    rawsetl(L, -4, "os");
    moveback("clock");
    moveback("date");
    moveback("difftime");
    moveback("time");
    lua_pop(L, 2);

    rawgetl(L, -2, "string");
    lua_newtable(L);
    lua_pushvalue(L, -1);
    rawsetl(L, -4, "string");
    moveback("byte");
    moveback("char");
    moveback("dump");
    moveback("find");
    moveback("format");
    moveback("gmatch");
    moveback("gsub");
    moveback("len");
    moveback("lower");
    moveback("match");
    moveback("rep");
    moveback("reverse");
    moveback("sub");
    moveback("upper");
    lua_pop(L, 2);

    rawgetl(L, -2, "table");
    lua_newtable(L);
    lua_pushvalue(L, -1);
    rawsetl(L, -4, "table");
    moveback("concat");
    moveback("insert");
    moveback("maxn");
    moveback("remove");
    moveback("sort");
    lua_pop(L, 2);
    assert(lua_gettop(L) == 2);

    // run the script
    lua_newtable(L);
    lua_pushvalue(L, -1);
    lua_getglobal(L, "tostring");
    lua_pushcclosure(L, &printfunc, 2);
    lua_setglobal(L, "print");
    int oldstack = lua_gettop(L);
    luaL_loadstring(L, code);
    int success = lua_pcall(L, 0, LUA_MULTRET, 0);
    if (success == 0) {
        int newstack = lua_gettop(L);
        if (newstack != oldstack) {
            int i;
            for (i=oldstack+1; i<=newstack; ++i) {
                lua_getglobal(L, "tostring");
                lua_pushvalue(L, i);
                lua_call(L, 1, 1);
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

int printfunc(lua_State *L) {
    int nargs = lua_gettop(L);
    int i;
    for (i=1; i<=nargs; ++i) {
        lua_pushvalue(L, lua_upvalueindex(2));
        lua_pushvalue(L, i);
        lua_call(L, 1, 1);
        size_t len = lua_objlen(L, lua_upvalueindex(1));
        lua_rawseti(L, lua_upvalueindex(1), len+1);
        if (i == nargs) lua_pushliteral(L, "\n"); else lua_pushliteral(L, " ");
        lua_rawseti(L, lua_upvalueindex(1), len+2);
    }
}

