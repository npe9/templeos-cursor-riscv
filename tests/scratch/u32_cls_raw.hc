U32i union U32 { U8i u8[4]; };
class S { U32 a; U32 b; };
I64 main()
{
  S s;
  s.a = 0x11111111;
  s.b = 0x22222222;
  s.a = 0xAAAAAAAA;
  I64 r = 0;
  if (s.b == 0x22222222) r |= 1; // 4-byte member store
  if (s.b == 0) r |= 2; // 8-byte clobber
  return r;
}
