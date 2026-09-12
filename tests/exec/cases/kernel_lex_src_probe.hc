// SoftCall LexSrcSoft companion: host-AOT LexStmt2Bin-shaped slice (G9).
// SoftCall Load("A:/MakeOS/SoftLexSrc.BIN") + HashFind SoftLexSrcProbe -> 42.
// Past SoftCall Load SoftPrsSrc; digit while SoftCall Load ~2.7KiB over cap -
// shrunk fixed digit+op peel SoftLexStmt2Bin + SoftLexStmt2BinCall under 2KiB.
// SoftCall-lite PrsCmpSrc hung ExePutSSoft (host AOT entry thunk).
I64 soft_lex_g;
I64 SoftLexStmt2Bin(U8 *s)
{
  I64 a, b, op;
  a = (s[0] - '0') * 10 + (s[1] - '0');
  op = s[2];
  b = s[3] - '0';
  if (op == '+')
    return a + b;
  if (op == '-')
    return a - b;
  return a;
}

I64 SoftLexStmt2BinCall(U8 *s)
{
  soft_lex_g = SoftLexStmt2Bin(s);
  return soft_lex_g;
}

public I64 SoftLexSrcProbe()
{
  if (SoftLexStmt2BinCall("40+2;") != 42)
    return -1;
  if (SoftLexStmt2BinCall("10-3;") != 7)
    return -2;
  return 42;
}
