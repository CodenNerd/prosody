#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include <time.h>
#include <lua.h>
#include <lauxlib.h>

static lua_Number tv2number(struct timespec *tv) {
	return tv->tv_sec + tv->tv_nsec * 1e-9;
}

static int lc_time_realtime(lua_State *L) {
	struct timespec t;
	clock_gettime(CLOCK_REALTIME, &t);
	lua_pushnumber(L, tv2number(&t));
	return 1;
}

static int lc_time_monotonic(lua_State *L) {
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	lua_pushnumber(L, tv2number(&t));
	return 1;
}

/* This function has been imported from luasocket */
static int lc_sleep(lua_State *L) {
	double n = luaL_checknumber(L, 1);
	struct timespec t, r;
	if (n < 0.0) n = 0.0;
	if (n > INT_MAX) n = INT_MAX;
	t.tv_sec = (int) n;
	n -= t.tv_sec;
	t.tv_nsec = (int) (n * 1000000000);
	if (t.tv_nsec >= 1000000000) t.tv_nsec = 999999999;
	while (nanosleep(&t, &r) != 0) {
		t.tv_sec = r.tv_sec;
		t.tv_nsec = r.tv_nsec;
	}
	return 0;
}

int luaopen_prosody_util_time(lua_State *L) {
	lua_createtable(L, 0, 2);
	{
		lua_pushcfunction(L, lc_time_realtime);
		lua_setfield(L, -2, "now");
		lua_pushcfunction(L, lc_time_monotonic);
		lua_setfield(L, -2, "monotonic");
		lua_pushcfunction(L, lc_sleep);
		lua_setfield(L, -2, "sleep");
	}
	return 1;
}
int luaopen_util_time(lua_State *L) {
	return luaopen_prosody_util_time(L);
}
