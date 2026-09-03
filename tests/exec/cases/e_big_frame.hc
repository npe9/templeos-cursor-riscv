I64 f()
{
  U8 buf[4000];
  I64 i;
  for (i = 0; i < 4000; i++)
    buf[i] = i & 255;
  return buf[3999] + sizeof(buf);
}
f();
