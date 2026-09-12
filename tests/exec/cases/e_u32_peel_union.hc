// Host AOT: local `U32 *` peel must use 4-byte load/store when U32 is `U32i union U32`
// (KernelA shape). Prior bug: INTERNAL U32i shadowed KW → scalar base dropped → RT_I64
// pointee → 8-byte ld/sd; member `body[i]` was already ScalarTypeForSize'd.
U32i union U32
{
  U8i u8[4];
};

class CDC
{
  U32 *body;
  I64 width_internal;
};

I64 main()
{
  U32 buf[4];
  CDC dc;
  U32 *sp;
  I64 r = 0;
  buf[0] = 0x11111111;
  buf[1] = 0x22222222;
  buf[2] = 0x33333333;
  buf[3] = 0x44444444;
  dc.body = buf;
  dc.width_internal = 2;
  if (dc.body[0 * dc.width_internal + 1] == 0x22222222)
    r |= 1;
  if (dc.body[1] == 0x22222222)
    r |= 2;
  sp = dc.body;
  if (sp[1] == 0x22222222)
    r |= 4;
  sp[0] = 0xAAAAAAAA;
  if (sp[1] == 0x22222222)
    r |= 8;
  if (dc.body[1] == 0x22222222)
    r |= 16;
  dc.body[1] = 0xBBBBBBBB;
  if (sp[1] == 0xBBBBBBBB)
    r |= 32;
  if (buf[2] == 0x33333333)
    r |= 64;
  return r;
  // 127
}
