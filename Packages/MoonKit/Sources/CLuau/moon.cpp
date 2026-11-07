#include "moon.h"

#include <cstdlib>
#include <cstring>
#include <string>

#include "luacode.h"
#include "lualib.h"

namespace {

struct Host {
    std::string chunk;
    size_t used = 0;
    size_t memory = 0;
    uint64_t ticks = 0;
    uint64_t budget = 0;
    // The cap binds only inside moon_call: there a failed allocation is
    // caught, while outside it would throw into Swift.
    bool armed = false;
    moon_log_fn log = nullptr;
    void* context = nullptr;
};

Host* host(lua_State* L) {
    return static_cast<Host*>(lua_callbacks(L)->userdata);
}

void* allocate(void* data, void* block, size_t before, size_t after) {
    auto* state = static_cast<Host*>(data);
    if (after == 0) {
        std::free(block);
        state->used -= before;
        return nullptr;
    }
    if (state->armed && after > before && state->used + (after - before) > state->memory) {
        return nullptr;
    }
    void* grown = std::realloc(block, after);
    if (grown != nullptr) {
        state->used += after - before;
    }
    return grown;
}

void interrupt(lua_State* L, int gc) {
    Host* state = host(L);
    if (gc >= 0 || !state->armed) {
        return;
    }
    if (++state->ticks > state->budget) {
        state->ticks = 0;
        luaL_error(L, "ran out of instructions; is there an endless loop?");
    }
}

constexpr int kMaxFrames = 64;

// The line of the module's own file running further up the stack: where a
// `ui` call was made or, from inside a component, where the mod used it.
int caller_line(lua_State* L) {
    const std::string& chunk = host(L)->chunk;
    lua_Debug frame = {};
    for (int level = 1; level < kMaxFrames && lua_getinfo(L, level, "sl", &frame); ++level) {
        if (frame.source != nullptr && chunk == frame.source + 1 && frame.currentline > 0) {
            lua_pushinteger(L, frame.currentline);
            return 1;
        }
    }
    return 0;
}

int log_line(lua_State* L) {
    Host* state = host(L);
    std::string line;
    int count = lua_gettop(L);
    for (int index = 1; index <= count; ++index) {
        size_t length = 0;
        const char* text = luaL_tolstring(L, index, &length);
        line.append(index > 1 ? " " : "").append(text, length);
        lua_pop(L, 1);
    }
    if (state->log != nullptr) {
        state->log(line.c_str(), line.size(), state->context);
    }
    return 0;
}

// Code loading, environments and the collector stay out of a module's reach.
constexpr const char* kRemoved[] = {
    "collectgarbage", "gcinfo", "getfenv", "loadstring", "newproxy", "print", "require", "setfenv",
};

} // namespace

extern "C" {

lua_State* moon_open(const char* chunk, size_t memory, uint64_t budget, moon_log_fn log, void* context) {
    auto* state = new Host();
    state->chunk = chunk;
    state->memory = memory;
    state->budget = budget;
    state->log = log;
    state->context = context;

    lua_State* L = lua_newstate(allocate, state);
    if (L == nullptr) {
        delete state;
        return nullptr;
    }
    lua_callbacks(L)->userdata = state;
    lua_callbacks(L)->interrupt = interrupt;

    const luaL_Reg libraries[] = {
        {"", luaopen_base},
        {LUA_TABLIBNAME, luaopen_table},
        {LUA_STRLIBNAME, luaopen_string},
        {LUA_MATHLIBNAME, luaopen_math},
        {LUA_BITLIBNAME, luaopen_bit32},
        {LUA_UTF8LIBNAME, luaopen_utf8},
        {LUA_BUFFERLIBNAME, luaopen_buffer},
    };
    for (const luaL_Reg& library : libraries) {
        lua_pushcfunction(L, library.func, nullptr);
        lua_pushstring(L, library.name);
        lua_call(L, 1, 0);
    }
    for (const char* name : kRemoved) {
        lua_pushnil(L);
        lua_setglobal(L, name);
    }
    lua_pushcfunction(L, caller_line, "__caller_line");
    lua_setglobal(L, "__caller_line");
    lua_pushcfunction(L, log_line, "log");
    lua_setglobal(L, "log");
    return L;
}

void moon_close(lua_State* L) {
    Host* state = host(L);
    lua_close(L);
    delete state;
}

int moon_load(lua_State* L, const char* name, const char* source, size_t length) {
    size_t size = 0;
    char* bytecode = luau_compile(source, length, nullptr, &size);
    std::string chunk = std::string("=") + name;
    int status = luau_load(L, chunk.c_str(), bytecode, size, 0);
    std::free(bytecode);
    return status;
}

int moon_call(lua_State* L, int arguments, int results) {
    Host* state = host(L);
    state->ticks = 0;
    state->armed = true;
    int status = lua_pcall(L, arguments, results, 0);
    state->armed = false;
    return status;
}

void moon_seal(lua_State* L) {
    luaL_sandbox(L);
}

size_t moon_memory(lua_State* L) {
    return host(L)->used;
}

} // extern "C"
