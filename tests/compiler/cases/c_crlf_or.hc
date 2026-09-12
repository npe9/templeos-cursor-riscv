// CR/LF oracle: if (x=='\r' || x=='\n') must compare-and-branch, not bool stack.
// Pattern gate in run_compiler_stress.sh: `li t1,13`/`li t1,10` each feeding a
// `b<cc> a0,t1`, core <=12 insns, no seqz/sub/beqz. Branch POLARITY is not pinned:
// EmitBrRsRs/EmitCondBranch emit fixed-width branches (inverted `bne` over a `j`)
// instead of range-relaxed short B-type, because +-4KB oscillation prevented AOT
// convergence on the Kernel+Compiler blobs. So `bne a0,t1` + `j` is intended here.
U0 X()
{
}

U0 Y()
{
}

U0 F(I64 x)
{
  if (x == '\r' || x == '\n')
    X();
  else
    Y();
}

I64 main()
{
  return 0;
}
