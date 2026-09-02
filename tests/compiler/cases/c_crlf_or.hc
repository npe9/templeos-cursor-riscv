// CR/LF oracle: if (x=='\r' || x=='\n') must compare-and-branch, not bool stack.
// Pattern gate in run_compiler_stress.sh (insn budget + beq imm).
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
