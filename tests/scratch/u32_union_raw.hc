U32i union U32
{
  U8i u8[4];
};

class CDC { U32 *body; };

I64 main()
{
  // Non-pointer U32 local: 4-byte or 8-byte?
  U32 a;
  U32 b;
  a = 0x11111111;
  b = 0x22222222;
  a = 0xAAAAAAAA;
  // If U32 local is 8-byte slot, fine; check member pointed path vs local
  U32 buf[3];
  CDC dc;
  buf[0]=1; buf[1]=2; buf[2]=3;
  dc.body = buf;
  dc.body[0] = 0x55AA55AA; // member peel store
  I64 r = 0;
  if (buf[1] == 2) r |= 1; // member store 4-byte
  U32 *p = buf;
  p[0] = 0x66BB66BB; // local peel store
  if (buf[1] == 2) r |= 2; // local store 4-byte
  else if (buf[1] == 0) r |= 4; // local store 8-byte zero-ext
  // sizeof
  if (sizeof(U32) == 4) r |= 8;
  if (sizeof(a) == 4) r |= 16;
  if (sizeof(a) == 8) r |= 32;
  return r;
}
