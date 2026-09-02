// Absolute U32 VA with bit31 set (e.g. RAM @ 0x8000_xxxx).
// EmitLoadImm64 / RVLi intentionally emit lui + slli;srli 32 so the VA stays
// zero-extended (not 0xffff_ffff_8000_xxxx). That pair is expected — not a fail.
// Pattern suite documents this; do not hard-forbid slli;srli on this case.
I64 main()
{
  *(I64 *)0x80001000 = 0;
  return 0;
}
