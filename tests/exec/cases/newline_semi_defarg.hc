// A default argument inside a control header, which is where the newline rule lost its place.
//
// `Blink` here is a bare call to a function with a default argument. The compiler lexes the
// default text by PUSHING it as a string and holding the current token back until it is
// exhausted. That pushed frame used to carry only the source position, so the brackets inside
// the default expression were counted against THIS file: the `if` header's bracket tracking was
// cleared by the `)` in the default text, the newline after the real `)` then ended the `if` as
// an empty statement, and the `else` under it was orphaned with "Expected expression".
//
// Found in tos/Apps/Psalmody/PsalmodyDraw.HC:65, which is `if (Blink || psm.playing)`.
// The shape is checked for every control header, since they share the tracking.
Bool Blink(F64 hz = 2.5)
{
  return hz > 0;
}

I64 TwoArgs(I64 a = 1, I64 b = 2)
{
  return a + b;
}
I64 flag;
Bool IfCase()
{
  if (Blink || flag)
    return TRUE;
  else
    return FALSE;
}

I64 WhileCase()
{
  I64 n = 0;
  while (Blink && n < 3)
    n++;
  return n;
}

I64 ForCase()
{
  I64 i, n = 0;
  for (i = 0; i < TwoArgs; i++)
    n += i;
  return n;
}

I64 SwitchCase()
{
  I64 n = 0;
  switch (TwoArgs) {
    case 3 :
    n = 1;
    break;
    default:
    n = 2;
  }
  return n;
}
// Nested: a default argument whose own text is an expression in parentheses.
I64 Outer(I64 v = (1 + 2) * 3)
{
  return v;
}

Bool NestedCase()
{
  if (Outer || flag)
    return TRUE;
  else
    return FALSE;
}

U0 main()
{
  IfCase;
  WhileCase;
  ForCase;
  SwitchCase;
  NestedCase;
}
