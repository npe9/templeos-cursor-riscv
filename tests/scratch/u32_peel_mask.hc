U32i union U32 { U8i u8[4]; };
I64 main()
{
  U32 buf[2];
  U32 *sp;
  buf[0] = 0x11111111;
  buf[1] = 0x22222222;
  sp = buf;
  I64 v = sp[0];
  I64 r = 0;
  if ((v & 0xFFFFFFFF) == 0x11111111) r |= 1;
  if ((v >> 32) == 0x22222222) r |= 2; // 8-byte load evidence
  if (v == 0x11111111) r |= 4; // pure 4-byte zero-ext
  return r;
}
