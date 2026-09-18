// The BCPL rule: a newline ends a statement that has plainly finished. This is
// tests/exec/cases/newline_semi_semis.hc with the semicolons removed. Compiled with
// HOLYC_NL_SEMI=1 it must produce the same bytes as that one does without it.
//
// One semicolon stays: the body of a do..while. `a = a + 1` followed by a line starting with
// `while` is genuinely ambiguous — it is either the end of a do, or a statement followed by a
// loop — and the rule cannot tell without looking further ahead than it does. It keeps the
// do..while reading, so the body needs its own semicolon. Everything else here does not.
U0 NlWork(I64 *out)
{
  I64 a = 1
  I64 b = 2
  a = a + b
  if (a > 2)
    b = b + 1
  while (b < 6)
    b = b + 1
  do
    a = a + 1;
  while (a < 5);
  out[0] = a
  out[1] = b
}

I64 main()
{
  I64 r[2]
  NlWork(r)
  return r[0] + r[1]
}
