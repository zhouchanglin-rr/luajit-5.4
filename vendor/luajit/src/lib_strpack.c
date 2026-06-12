/*
** string.pack / string.unpack / string.packsize  (Lua 5.3/5.4)
** for this LuaJIT-5.4 port.
**
** Adapted from the reference Lua 5.4 lstrlib.c pack/unpack section
** (Copyright (C) 1994-2024 Lua.org, PUC-Rio; see Copyright Notice in lua.h),
** with LuaJIT adjustments:
**   - packs into small local buffers + luaL_addlstring (LuaJIT uses the 5.1
**     luaL_Buffer API and has no luaL_prepbuffsize);
**   - local lua_Unsigned / MAXSIZE / LUAI_MAXALIGN / l_unlikely definitions;
**   - registers into the existing global 'string' table via luaL_register.
**
** Integer width note: LuaJIT numbers are doubles (or 32-bit ints in the
** dual-number build), so packing/unpacking integers wider than 2^53 (e.g. full
** 8-byte "i8" values) loses precision. Within that range it matches Lua 5.4.
*/

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define lib_strpack_c
#define LUA_LIB

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/* ---- compatibility shims ---------------------------------------------- */
typedef uint64_t lua_UInt;       /* stand-in for Lua 5.4 lua_Unsigned */
#define l_unlikely(x)	(x)
#define MAX_SIZET	((size_t)(~(size_t)0))
#define MAXSIZE  \
	(sizeof(size_t) < sizeof(int) ? MAX_SIZET : (size_t)(INT_MAX))
#ifndef LUAI_MAXALIGN
#define LUAI_MAXALIGN	lua_Number n; double u; void *s; lua_Integer i; long l
#endif

/* maximum size for the binary representation of an integer */
#define MAXINTSIZE	16
/* number of bits in a character */
#define NB	CHAR_BIT
/* mask for one character (NB 1's) */
#define MC	((1 << NB) - 1)
/* size of a lua_Integer */
#define SZINT	((int)sizeof(lua_Integer))

#define LUAL_PACKPADBYTE	0x00

/* dummy union to get native endianness */
static const union {
  int dummy;
  char little;  /* true iff machine is little endian */
} nativeendian = { 1 };

typedef struct Header {
  lua_State *L;
  int islittle;
  int maxalign;
} Header;

typedef enum KOption {
  Kint, Kuint, Kfloat, Knumber, Kdouble,
  Kchar, Kstring, Kzstr, Kpadding, Kpaddalign, Knop
} KOption;

/* translate a relative initial position (for unpack) */
static size_t posrelatI(lua_Integer pos, size_t len)
{
  if (pos > 0) return (size_t)pos;
  else if (0u - (size_t)pos > len) return 1;
  else return len + (size_t)pos + 1;
}

static int digit(int c) { return '0' <= c && c <= '9'; }

static int getnum(const char **fmt, int df)
{
  if (!digit(**fmt)) {
    return df;
  } else {
    int a = 0;
    do {
      a = a*10 + (*((*fmt)++) - '0');
    } while (digit(**fmt) && a <= ((int)MAXSIZE - 9)/10);
    return a;
  }
}

static int getnumlimit(Header *h, const char **fmt, int df)
{
  int sz = getnum(fmt, df);
  if (l_unlikely(sz > MAXINTSIZE || sz <= 0))
    return luaL_error(h->L, "integral size (%d) out of limits [1,%d]",
		      sz, MAXINTSIZE);
  return sz;
}

static void initheader(lua_State *L, Header *h)
{
  h->L = L;
  h->islittle = nativeendian.little;
  h->maxalign = 1;
}

static KOption getoption(Header *h, const char **fmt, int *size)
{
  struct cD { char c; union { LUAI_MAXALIGN; } u; };
  int opt = *((*fmt)++);
  *size = 0;
  switch (opt) {
    case 'b': *size = sizeof(char); return Kint;
    case 'B': *size = sizeof(char); return Kuint;
    case 'h': *size = sizeof(short); return Kint;
    case 'H': *size = sizeof(short); return Kuint;
    case 'l': *size = sizeof(long); return Kint;
    case 'L': *size = sizeof(long); return Kuint;
    case 'j': *size = sizeof(lua_Integer); return Kint;
    case 'J': *size = sizeof(lua_Integer); return Kuint;
    case 'T': *size = sizeof(size_t); return Kuint;
    case 'f': *size = sizeof(float); return Kfloat;
    case 'n': *size = sizeof(lua_Number); return Knumber;
    case 'd': *size = sizeof(double); return Kdouble;
    case 'i': *size = getnumlimit(h, fmt, sizeof(int)); return Kint;
    case 'I': *size = getnumlimit(h, fmt, sizeof(int)); return Kuint;
    case 's': *size = getnumlimit(h, fmt, sizeof(size_t)); return Kstring;
    case 'c':
      *size = getnum(fmt, -1);
      if (l_unlikely(*size == -1))
	luaL_error(h->L, "missing size for format option 'c'");
      return Kchar;
    case 'z': return Kzstr;
    case 'x': *size = 1; return Kpadding;
    case 'X': return Kpaddalign;
    case ' ': break;
    case '<': h->islittle = 1; break;
    case '>': h->islittle = 0; break;
    case '=': h->islittle = nativeendian.little; break;
    case '!': {
      const int maxalign = offsetof(struct cD, u);
      h->maxalign = getnumlimit(h, fmt, maxalign);
      break;
    }
    default: luaL_error(h->L, "invalid format option '%c'", opt);
  }
  return Knop;
}

static KOption getdetails(Header *h, size_t totalsize,
			  const char **fmt, int *psize, int *ntoalign)
{
  KOption opt = getoption(h, fmt, psize);
  int align = *psize;
  if (opt == Kpaddalign) {
    if (**fmt == '\0' || getoption(h, fmt, &align) == Kchar || align == 0)
      luaL_argerror(h->L, 1, "invalid next option for option 'X'");
  }
  if (align <= 1 || opt == Kchar) {
    *ntoalign = 0;
  } else {
    if (align > h->maxalign) align = h->maxalign;
    if (l_unlikely((align & (align - 1)) != 0))
      luaL_argerror(h->L, 1, "format asks for alignment not power of 2");
    *ntoalign = (align - (int)(totalsize & (align - 1))) & (align - 1);
  }
  return opt;
}

/* Pack integer 'n' into a local buffer and append to b. */
static void packint(luaL_Buffer *b, lua_UInt n,
		    int islittle, int size, int neg)
{
  char buff[MAXINTSIZE];
  int i;
  buff[islittle ? 0 : size - 1] = (char)(n & MC);
  for (i = 1; i < size; i++) {
    n >>= NB;
    buff[islittle ? i : size - 1 - i] = (char)(n & MC);
  }
  if (neg && size > SZINT) {  /* sign-extend */
    for (i = SZINT; i < size; i++)
      buff[islittle ? i : size - 1 - i] = (char)MC;
  }
  luaL_addlstring(b, buff, (size_t)size);
}

static void copywithendian(char *dest, const char *src, int size, int islittle)
{
  if (islittle == nativeendian.little) {
    memcpy(dest, src, (size_t)size);
  } else {
    dest += size - 1;
    while (size-- != 0) *(dest--) = *(src++);
  }
}

static int str_pack(lua_State *L)
{
  luaL_Buffer b;
  Header h;
  const char *fmt = luaL_checkstring(L, 1);
  int arg = 1;
  size_t totalsize = 0;
  initheader(L, &h);
  luaL_buffinit(L, &b);
  while (*fmt != '\0') {
    int size, ntoalign;
    KOption opt = getdetails(&h, totalsize, &fmt, &size, &ntoalign);
    totalsize += ntoalign + size;
    while (ntoalign-- > 0) luaL_addchar(&b, LUAL_PACKPADBYTE);
    arg++;
    switch (opt) {
      case Kint: {
	lua_Integer n = luaL_checkinteger(L, arg);
	if (size < SZINT) {
	  lua_Integer lim = (lua_Integer)1 << ((size * NB) - 1);
	  luaL_argcheck(L, -lim <= n && n < lim, arg, "integer overflow");
	}
	packint(&b, (lua_UInt)n, h.islittle, size, (n < 0));
	break;
      }
      case Kuint: {
	lua_Integer n = luaL_checkinteger(L, arg);
	if (size < SZINT)
	  luaL_argcheck(L, (lua_UInt)n < ((lua_UInt)1 << (size * NB)),
			arg, "unsigned overflow");
	packint(&b, (lua_UInt)n, h.islittle, size, 0);
	break;
      }
      case Kfloat: {
	float f = (float)luaL_checknumber(L, arg);
	char buff[sizeof(float)];
	copywithendian(buff, (char *)&f, sizeof(f), h.islittle);
	luaL_addlstring(&b, buff, sizeof(f));
	break;
      }
      case Knumber: {
	lua_Number f = luaL_checknumber(L, arg);
	char buff[sizeof(lua_Number)];
	copywithendian(buff, (char *)&f, sizeof(f), h.islittle);
	luaL_addlstring(&b, buff, sizeof(f));
	break;
      }
      case Kdouble: {
	double f = (double)luaL_checknumber(L, arg);
	char buff[sizeof(double)];
	copywithendian(buff, (char *)&f, sizeof(f), h.islittle);
	luaL_addlstring(&b, buff, sizeof(f));
	break;
      }
      case Kchar: {
	size_t len;
	const char *s = luaL_checklstring(L, arg, &len);
	luaL_argcheck(L, len <= (size_t)size, arg,
		      "string longer than given size");
	luaL_addlstring(&b, s, len);
	while (len++ < (size_t)size) luaL_addchar(&b, LUAL_PACKPADBYTE);
	break;
      }
      case Kstring: {
	size_t len;
	const char *s = luaL_checklstring(L, arg, &len);
	luaL_argcheck(L, size >= (int)sizeof(size_t) ||
		      len < ((size_t)1 << (size * NB)),
		      arg, "string length does not fit in given size");
	packint(&b, (lua_UInt)len, h.islittle, size, 0);
	luaL_addlstring(&b, s, len);
	totalsize += len;
	break;
      }
      case Kzstr: {
	size_t len;
	const char *s = luaL_checklstring(L, arg, &len);
	luaL_argcheck(L, strlen(s) == len, arg, "string contains zeros");
	luaL_addlstring(&b, s, len);
	luaL_addchar(&b, '\0');
	totalsize += len + 1;
	break;
      }
      case Kpadding: luaL_addchar(&b, LUAL_PACKPADBYTE);  /* FALLTHROUGH */
      case Kpaddalign: case Knop:
	arg--;
	break;
    }
  }
  luaL_pushresult(&b);
  return 1;
}

static int str_packsize(lua_State *L)
{
  Header h;
  const char *fmt = luaL_checkstring(L, 1);
  size_t totalsize = 0;
  initheader(L, &h);
  while (*fmt != '\0') {
    int size, ntoalign;
    KOption opt = getdetails(&h, totalsize, &fmt, &size, &ntoalign);
    luaL_argcheck(L, opt != Kstring && opt != Kzstr, 1,
		  "variable-length format");
    size += ntoalign;
    luaL_argcheck(L, totalsize <= MAXSIZE - size, 1,
		  "format result too large");
    totalsize += size;
  }
  lua_pushinteger(L, (lua_Integer)totalsize);
  return 1;
}

static lua_Integer unpackint(lua_State *L, const char *str,
			     int islittle, int size, int issigned)
{
  lua_UInt res = 0;
  int i;
  int limit = (size <= SZINT) ? size : SZINT;
  for (i = limit - 1; i >= 0; i--) {
    res <<= NB;
    res |= (lua_UInt)(unsigned char)str[islittle ? i : size - 1 - i];
  }
  if (size < SZINT) {
    if (issigned) {
      lua_UInt mask = (lua_UInt)1 << (size*NB - 1);
      res = ((res ^ mask) - mask);
    }
  } else if (size > SZINT) {
    int mask = (!issigned || (lua_Integer)res >= 0) ? 0 : MC;
    for (i = limit; i < size; i++) {
      if (l_unlikely((unsigned char)str[islittle ? i : size - 1 - i] != mask))
	luaL_error(L, "%d-byte integer does not fit into Lua Integer", size);
    }
  }
  return (lua_Integer)res;
}

static int str_unpack(lua_State *L)
{
  Header h;
  const char *fmt = luaL_checkstring(L, 1);
  size_t ld;
  const char *data = luaL_checklstring(L, 2, &ld);
  size_t pos = posrelatI(luaL_optinteger(L, 3, 1), ld) - 1;
  int n = 0;
  luaL_argcheck(L, pos <= ld, 3, "initial position out of string");
  initheader(L, &h);
  while (*fmt != '\0') {
    int size, ntoalign;
    KOption opt = getdetails(&h, pos, &fmt, &size, &ntoalign);
    luaL_argcheck(L, (size_t)ntoalign + size <= ld - pos, 2,
		  "data string too short");
    pos += ntoalign;
    luaL_checkstack(L, 2, "too many results");
    n++;
    switch (opt) {
      case Kint:
      case Kuint: {
	lua_Integer res = unpackint(L, data + pos, h.islittle, size,
				    (opt == Kint));
	lua_pushinteger(L, res);
	break;
      }
      case Kfloat: {
	float f;
	copywithendian((char *)&f, data + pos, sizeof(f), h.islittle);
	lua_pushnumber(L, (lua_Number)f);
	break;
      }
      case Knumber: {
	lua_Number f;
	copywithendian((char *)&f, data + pos, sizeof(f), h.islittle);
	lua_pushnumber(L, f);
	break;
      }
      case Kdouble: {
	double f;
	copywithendian((char *)&f, data + pos, sizeof(f), h.islittle);
	lua_pushnumber(L, (lua_Number)f);
	break;
      }
      case Kchar: {
	lua_pushlstring(L, data + pos, size);
	break;
      }
      case Kstring: {
	size_t len = (size_t)unpackint(L, data + pos, h.islittle, size, 0);
	luaL_argcheck(L, len <= ld - pos - size, 2, "data string too short");
	lua_pushlstring(L, data + pos + size, len);
	pos += len;
	break;
      }
      case Kzstr: {
	size_t len = strlen(data + pos);
	luaL_argcheck(L, pos + len < ld, 2,
		      "unfinished string for format 'z'");
	lua_pushlstring(L, data + pos, len);
	pos += len + 1;
	break;
      }
      case Kpaddalign: case Kpadding: case Knop:
	n--;
	break;
    }
    pos += size;
  }
  lua_pushinteger(L, pos + 1);
  return n + 1;
}

static const luaL_Reg strpack_lib[] = {
  { "pack",     str_pack },
  { "packsize", str_packsize },
  { "unpack",   str_unpack },
  { NULL, NULL }
};

/* Register the three functions into the existing global 'string' table. */
LUALIB_API int luaopen_string_pack(lua_State *L)
{
  lua_getglobal(L, LUA_STRLIBNAME);
  if (lua_istable(L, -1))
    luaL_register(L, NULL, strpack_lib);
  lua_pop(L, 1);
  return 0;
}
