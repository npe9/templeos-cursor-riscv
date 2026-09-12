// Soft tip: Kernel doldoc.hash Soft Call without Soft Call Load of Soft doldoc.
// Soft Soft-local g_doldoc would shadow Kernel Fs; Soft Call RVDocDolDocHashGet
// after host DocInit warm (+docinitkernhash). Soft Call HashFind remat Soft tip
// stays Soft Cmp-only (+docinitkernhashfind).
import I64 RVDocDolDocHashGet();
public I64 AdamLiteDocInitKernHashProbe()
{
  if (!RVDocDolDocHashGet())
    return 2;
  return 1;
}
