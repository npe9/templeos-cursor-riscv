// Wide li must materialize full U32 (not just sign-extended lo12).
I64 main()
{
  asm {
	li a0, 0x81396868
	mv s1, a0
	li a2, 42
	mv a0, s1
  }
}
