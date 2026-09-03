// Native RISC-V asm: a byte-fill loop with local labels and a branch, assembled directly to RV64.
// RvFill(dst,val,cnt) writes cnt copies of val at dst (RISC-V calling convention).
U8 *RvFill(U8 *p, I64 v, I64 n);
asm {
	RvFill::
	mv	t0,a0
	loop:
	beq	a2,zero,done
	sb	a1,0(t0)
	addi	t0,t0,1
	addi	a2,a2,-1
	j	loop
	done:
	ret
}

I64 main()
{
  U8 buf[8];
  I64 i;
  for (i = 0; i < 8; i++)
    buf[i] = 0;
  RvFill(buf, 'A', 5);
  return buf[0] << 16 | buf[4] << 8 | buf[5];
  // 0x414100
}
