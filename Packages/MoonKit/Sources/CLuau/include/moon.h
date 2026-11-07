// The seam between Swift and Luau. Luau raises errors as C++ exceptions, which
// must never unwind through Swift frames, so everything that can raise while
// Luau code runs lives in moon.cpp: the interrupt, the allocator's cap, and
// the host functions. Swift only calls in through moon_call, which catches.
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "lua.h"

#ifdef __cplusplus
extern "C" {
#endif

// Luau's pseudo-indices are macro expressions Swift can't import.
enum {
    MOON_REGISTRY = LUA_REGISTRYINDEX,
    MOON_GLOBALS = LUA_GLOBALSINDEX,
};

typedef void (*moon_log_fn)(const char* line, size_t length, void* context);

/// A sealed-to-be state: safe libraries only, `memory` bytes, and `budget`
/// interrupts per moon_call. `chunk` names the file `__caller_line` looks for.
lua_State* moon_open(const char* chunk, size_t memory, uint64_t budget, moon_log_fn log, void* context);
void moon_close(lua_State* L);

/// Compiles source text and pushes the function, or pushes the error and
/// returns non-zero. Always text: Luau bytecode is not verified when loaded.
int moon_load(lua_State* L, const char* name, const char* source, size_t length);

/// A protected call with a fresh instruction budget and the memory cap armed;
/// outside it allocation never fails, so Swift can push values safely.
/// Returns 0, or non-zero with the error message on the stack.
int moon_call(lua_State* L, int arguments, int results);

/// Freezes the globals. Call once the prelude is in place.
void moon_seal(lua_State* L);

/// Bytes the state holds.
size_t moon_memory(lua_State* L);

#ifdef __cplusplus
}
#endif
