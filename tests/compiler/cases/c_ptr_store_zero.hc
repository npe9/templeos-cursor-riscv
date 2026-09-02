// Host O1: *p=0 with promoted pointer → sd zero (ICF_ASSIGN_ZERO).
// Pattern gate in run_compiler_stress.sh (not an exec oracle — abs VA).
U0 F()
{
  I64 *p = 0x80001000;
  *p = 0;
}

I64 main()
{
  return 0;
}
