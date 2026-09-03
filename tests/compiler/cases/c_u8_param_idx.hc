// U8* parameter indexing: `!p || !p[0]` and `p[i]` must use the pointer value,
// not the param stack slot (TrapResolve / GdbParseHex-class miscompile).
U8 g_buf[8];
I64 First(U8 *name)
{
  if (!name || !name[0])
    return 0;
  return name[0];
}

I64 At(U8 *p, I64 i)
{
  return p[i];
}

I64 main()
{
  I64 a, b;
  g_buf[0] = 0x42;
  g_buf[1] = 0;
  g_buf[2] = 0x11;
  a = First(g_buf);
  b = At(g_buf, 2);
  return a + b;
}
