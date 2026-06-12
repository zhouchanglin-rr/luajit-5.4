/*
** UTF-8 library.
** Provides the Lua 5.3/5.4 'utf8' standard library for this LuaJIT-5.4 port.
**
** Adapted from the reference Lua 5.4 lutf8lib.c (Copyright (C) 1994-2024
** Lua.org, PUC-Rio; see Copyright Notice in lua.h), with LuaJIT-specific
** adjustments: no lprefix.h, no '%U' format (UTF-8 is encoded directly),
** luaL_pushfail -> lua_pushnil, and lua_Unsigned -> size_t.
*/

#include <limits.h>
#include <string.h>

#define lib_utf8_c
#define LUA_LIB

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define MAXUNICODE	0x10FFFFu
#define MAXUTF		0x7FFFFFFFu

#define MSGInvalid	"invalid UTF-8 code"

/* Integer type for decoded UTF-8 values; MAXUTF needs 31 bits. */
#if (UINT_MAX >> 30) >= 1
typedef unsigned int utfint;
#else
typedef unsigned long utfint;
#endif

#define iscont(c)	(((c) & 0xC0) == 0x80)
#define iscontp(p)	iscont(*(p))

/* Translate a relative string position: negative means back from end. */
static lua_Integer u_posrelat(lua_Integer pos, size_t len)
{
  if (pos >= 0) return pos;
  else if (0u - (size_t)pos > len) return 0;
  else return (lua_Integer)len + pos + 1;
}

/*
** Decode one UTF-8 sequence, returning NULL if the byte sequence is invalid.
** 'limits' stores the minimum value for each sequence length, to reject
** overlong encodings.
*/
static const char *utf8_decode(const char *s, utfint *val, int strict)
{
  static const utfint limits[] =
    { ~(utfint)0, 0x80, 0x800, 0x10000u, 0x200000u, 0x4000000u };
  unsigned int c = (unsigned char)s[0];
  utfint res = 0;
  if (c < 0x80) {  /* ascii? */
    res = c;
  } else {
    int count = 0;  /* number of continuation bytes */
    for (; c & 0x40; c <<= 1) {
      unsigned int cc = (unsigned char)s[++count];
      if (!iscont(cc)) return NULL;  /* not a continuation byte? */
      res = (res << 6) | (cc & 0x3F);
    }
    res |= ((utfint)(c & 0x7F) << (count * 5));
    if (count > 5 || res > MAXUTF || res < limits[count]) return NULL;
    s += count;
  }
  if (strict) {
    if (res > MAXUNICODE || (0xD800u <= res && res <= 0xDFFFu)) return NULL;
  }
  if (val) *val = res;
  return s + 1;  /* +1 to include first byte */
}

/* utf8.len(s [, i [, j [, lax]]]) */
static int utflen(lua_State *L)
{
  lua_Integer n = 0;
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  lua_Integer posi = u_posrelat(luaL_optinteger(L, 2, 1), len);
  lua_Integer posj = u_posrelat(luaL_optinteger(L, 3, -1), len);
  int lax = lua_toboolean(L, 4);
  luaL_argcheck(L, 1 <= posi && --posi <= (lua_Integer)len, 2,
		"initial position out of bounds");
  luaL_argcheck(L, --posj < (lua_Integer)len, 3,
		"final position out of bounds");
  while (posi <= posj) {
    const char *s1 = utf8_decode(s + posi, NULL, !lax);
    if (s1 == NULL) {  /* conversion error? */
      lua_pushnil(L);  /* return fail ... */
      lua_pushinteger(L, posi + 1);  /* ... and current position */
      return 2;
    }
    posi = s1 - s;
    n++;
  }
  lua_pushinteger(L, n);
  return 1;
}

/* utf8.codepoint(s [, i [, j [, lax]]]) */
static int codepoint(lua_State *L)
{
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  lua_Integer posi = u_posrelat(luaL_optinteger(L, 2, 1), len);
  lua_Integer pose = u_posrelat(luaL_optinteger(L, 3, posi), len);
  int lax = lua_toboolean(L, 4);
  int n;
  const char *se;
  luaL_argcheck(L, posi >= 1, 2, "out of bounds");
  luaL_argcheck(L, pose <= (lua_Integer)len, 3, "out of bounds");
  if (posi > pose) return 0;  /* empty interval; return no values */
  if (pose - posi >= INT_MAX)  /* (lua_Integer -> int) overflow? */
    return luaL_error(L, "string slice too long");
  n = (int)(pose - posi) + 1;
  luaL_checkstack(L, n, "string slice too long");
  n = 0;
  se = s + pose;
  for (s += posi - 1; s < se;) {
    utfint code;
    s = utf8_decode(s, &code, !lax);
    if (s == NULL) return luaL_error(L, MSGInvalid);
    lua_pushinteger(L, code);
    n++;
  }
  return n;
}

/* Encode codepoint at arg 'arg' as UTF-8 and push as a string.
** Replaces the reference's lua_pushfstring(L, "%U", ...), which LuaJIT's
** lua_pushfstring does not support. */
static void pushutfchar(lua_State *L, int arg)
{
  size_t code = (size_t)luaL_checkinteger(L, arg);
  char buff[8];
  int n = 1;
  luaL_argcheck(L, code <= MAXUTF, arg, "value out of range");
  if (code < 0x80) {  /* ascii? */
    buff[7] = (char)code;
  } else {  /* need continuation bytes */
    unsigned int mfb = 0x3f;  /* maximum that fits in first byte */
    do {
      buff[8 - (n++)] = (char)(0x80 | (code & 0x3f));
      code >>= 6;
      mfb >>= 1;
    } while (code > mfb);
    buff[8 - n] = (char)((~mfb << 1) | code);  /* add first byte */
  }
  lua_pushlstring(L, buff + 8 - n, (size_t)n);
}

/* utf8.char(n1, n2, ...) */
static int utfchar(lua_State *L)
{
  int n = lua_gettop(L);
  if (n == 1) {  /* common case: single char */
    pushutfchar(L, 1);
  } else {
    int i;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (i = 1; i <= n; i++) {
      pushutfchar(L, i);
      luaL_addvalue(&b);
    }
    luaL_pushresult(&b);
  }
  return 1;
}

/*
** utf8.offset(s, n [, i]) -> index where the n-th character (counting from
** position 'i') starts; 0 means the character at 'i'.
*/
static int byteoffset(lua_State *L)
{
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  lua_Integer n = luaL_checkinteger(L, 2);
  lua_Integer posi = (n >= 0) ? 1 : (lua_Integer)len + 1;
  posi = u_posrelat(luaL_optinteger(L, 3, posi), len);
  luaL_argcheck(L, 1 <= posi && --posi <= (lua_Integer)len, 3,
		"position out of bounds");
  if (n == 0) {
    while (posi > 0 && iscontp(s + posi)) posi--;
  } else {
    if (iscontp(s + posi))
      return luaL_error(L, "initial position is a continuation byte");
    if (n < 0) {
      while (n < 0 && posi > 0) {
	do { posi--; } while (posi > 0 && iscontp(s + posi));
	n++;
      }
    } else {
      n--;
      while (n > 0 && posi < (lua_Integer)len) {
	do { posi++; } while (iscontp(s + posi));
	n--;
      }
    }
  }
  if (n == 0)
    lua_pushinteger(L, posi + 1);
  else
    lua_pushnil(L);
  return 1;
}

static int iter_aux(lua_State *L, int strict)
{
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  size_t n = (size_t)lua_tointeger(L, 2);
  if (n < len) {
    while (iscontp(s + n)) n++;  /* go to next character */
  }
  if (n >= len) {  /* (also handles original 'n' being negative) */
    return 0;
  } else {
    utfint code;
    const char *next = utf8_decode(s + n, &code, strict);
    if (next == NULL || iscontp(next)) return luaL_error(L, MSGInvalid);
    lua_pushinteger(L, (lua_Integer)n + 1);
    lua_pushinteger(L, code);
    return 2;
  }
}

static int iter_auxstrict(lua_State *L) { return iter_aux(L, 1); }
static int iter_auxlax(lua_State *L) { return iter_aux(L, 0); }

static int iter_codes(lua_State *L)
{
  int lax = lua_toboolean(L, 2);
  const char *s = luaL_checkstring(L, 1);
  luaL_argcheck(L, !iscontp(s), 1, MSGInvalid);
  lua_pushcfunction(L, lax ? iter_auxlax : iter_auxstrict);
  lua_pushvalue(L, 1);
  lua_pushinteger(L, 0);
  return 3;
}

/* Pattern to match a single UTF-8 character. */
#define UTF8PATT	"[\0-\x7F\xC2-\xFD][\x80-\xBF]*"

static const luaL_Reg utf8_lib[] = {
  { "offset",    byteoffset },
  { "codepoint", codepoint },
  { "char",      utfchar },
  { "len",       utflen },
  { "codes",     iter_codes },
  { NULL, NULL }
};

LUALIB_API int luaopen_utf8(lua_State *L)
{
  /* Use luaL_register so the module self-registers into the global table, as
  ** LuaJIT's luaL_openlibs expects (it calls luaopen_utf8(name) with 0 results). */
  luaL_register(L, LUA_UTF8LIBNAME, utf8_lib);
  lua_pushlstring(L, UTF8PATT, sizeof(UTF8PATT)/sizeof(char) - 1);
  lua_setfield(L, -2, "charpattern");
  return 1;
}
