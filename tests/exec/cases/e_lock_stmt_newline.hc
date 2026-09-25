// `lock` takes a STATEMENT, and stock TempleOS writes that statement on the NEXT line:
//
//     for (i=0;i<CNT;i++)
//         lock  //Can be used without {}
//           glbl++;
//
// The newline-semicolon rule used to end the statement right after `lock`, so the two AMOs
// (amoswap.d.aq / amoswap.d.rl) sat back to back bracketing NOTHING, and the guarded statement
// moved out of the loop and ran once. Demo/MultiCore/Lock.HC printed `Actual Cnt:2` instead of
// `2000000` for exactly that, and it only became visible once Kernel/RVJob.HC made JobQue work.
//
// Both spellings must increment four times, and the increment must be on the GLOBAL — the wrong
// codegen incremented the loop counter instead, because what survived was the `for`'s own `i++`.
I64 glbl;

U0 OwnLine()
{
  I64 i;
  for (i = 0; i < 4; i++)
    lock  //Can be used without {}
      glbl++;
}

U0 SameLine()
{
  I64 i;
  for (i = 0; i < 4; i++)
    lock glbl++;
}

U0 Braced()
{
  I64 i;
  for (i = 0; i < 4; i++)
    lock {
      glbl++;
    }
}

I64 main()
{
  glbl = 0;
  OwnLine;
  if (glbl != 4)
    return 1;
  glbl = 0;
  SameLine;
  if (glbl != 4)
    return 2;
  glbl = 0;
  Braced;
  if (glbl != 4)
    return 3;
  return 0x2b;
}
