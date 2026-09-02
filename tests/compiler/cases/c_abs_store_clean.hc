// Absolute U32 VA with bit31 clear: lui alone; must NOT emit slli;srli 32 zext.
// Store-zero Tier-1 already rewrites to sd zero (not a pending peephole).
I64 main()
{
  *(I64 *)0x10000000 = 0;
  return 0;
}
