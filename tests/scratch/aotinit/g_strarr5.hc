// Raw pointer value of slot 0 vs slot 1 — equal means the table is not per-slot.
U8 *g_n[2] = {"zero", "ra"};
I64 main()
{
  return g_n[1] - g_n[0];
}
