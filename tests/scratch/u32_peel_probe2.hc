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
  sp = dc.body;
  // Encode diagnostics in return: low byte = flags, high = samples
  if (sizeof(U32) == 4) r |= 1;
  if (sp == buf) r |= 2;
  if (dc.body[1] == 0x22222222) r |= 4;
  // What does sp[1] actually see? pack low 8 bits of value into bits 8..15 if match patterns
  if (sp[0] == 0x11111111) r |= 8;
  if (sp[1] == 0x22222222) r |= 16;
  if (sp[1] == 0x33333333) r |= 32; // scale 8 → buf[2]
  if (sp[1] == 0x11111111) r |= 64; // weird
  if (sp[1] == 0) r |= 128;
  // byte distance: (sp+1) vs &buf[1]
  if ((sp + 1) == &buf[1]) r |= 256;
  if ((sp + 1) == &buf[2]) r |= 512; // +8 bytes
  return r;
}
