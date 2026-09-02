// NinePCodec.HC — 9P message field helpers (shared by client + transports).
#ifndef NINEP_CODEC_HC
#define NINEP_CODEC_HC
U0 NinePPutU8(U8 *p, I64 off, U8 v)
{
  p[off] = v;
}

U0 NinePPutU16(U8 *p, I64 off, U16 v)
{
  p[off] = v & 0xFF;
  p[off + 1] = (v >> 8) & 0xFF;
}

U0 NinePPutU32(U8 *p, I64 off, U32 v)
{
  p[off] = v & 0xFF;
  p[off + 1] = (v >> 8) & 0xFF;
  p[off + 2] = (v >> 16) & 0xFF;
  p[off + 3] = (v >> 24) & 0xFF;
}

U32 NinePGetU32(U8 *p, I64 off)
{
  return p[off] | (p[off + 1] << 8) | (p[off + 2] << 16) | (p[off + 3] << 24);
}

U16 NinePGetU16(U8 *p, I64 off)
{
  return p[off] | (p[off + 1] << 8);
}

I64 NinePPutStr(U8 *p, I64 off, U8 *s)
{
  I64 n = 0;
  if (!s)
    s = "";
  while (s[n])
    n++;
  NinePPutU16(p, off, n);
  off += 2;
  MemCpy(p + off, s, n);
  return off + n;
}
#endif
