// A STATEMENT MAY START WITH AN ALL-UPPER-CASE VARIABLE NAME.
//
// HolyC lets an x86 instruction be written bare in source (`MOV U64 [RSI],R13`), and parser.c
// recognises one at statement start by its shape: an all-upper-case name whose next token is not
// one of `( = ; . -> , )`. That test swallowed the whole line for ANY all-upper-case variable
// followed by anything else -- so
//
//     Y++;        was discarded, silently, with a clean exit
//     Y += 5;     likewise
//     Y = Y + 1;  worked, because `=` is in the list
//
// Lower-case and mixed-case names were never affected, which is why it survived: almost nothing
// in the kernel names a variable in capitals.
//
// WHAT FOUND IT was not a test. cFE's CFE_TIME_UnixToCalendar walks a year at a time from the
// UNIX epoch with `Y++`, and with the increment gone every year was 365 days, so the walk ended
// where it started and CFE_TIME_Print rendered 1970-003 where glibc's strftime renders 1980-001.
// The differential transcript compared those two strings and the date was simply wrong -- a
// plausible date, not a crash. docs/HOLYC_STRUCT_LIMITS.md #14.
//
// This case pins both halves of the fix:
//
//   - every modifying operator that can follow a name: ++ -- += -= *= /= &= |= ^= <<= >>= %=
//   - a name the compiler already knows as a VARIABLE is not an instruction, which is the
//     general guard and the reason a future operator added to the lexer does not reopen this
//
// EITHER HALF REPAIRS `Y++` ON ITS OWN, so the operators alone witness neither. What separates
// them is the all-caps LOCAL ARRAY below: `[` is in neither list, so only the symbol-table guard
// saves `ARR[0] = 7;`, and removing that guard alone makes THIS case fail -- it returned a word
// of uninitialised stack. The other half is witnessed by a refusal instead, in
// tests/holyc/refused/upper_name_undeclared.hc: a bare `FOO++` on a name nothing declared must
// be a parse ERROR, and with the operator list gone it is a silently skipped line and a
// successful compile. Between the two, each half has a gate that fails when only it is removed.
//   - single letters AND longer all-caps names (`AB`, `A1`), because the shape test is about the
//     whole identifier and not its length
//   - and a check that the feature the branch exists for still works: a `CLD` statement, which
//     is a real x86 opcode with no RISC-V meaning, is still skipped rather than treated as an
//     undeclared variable.
#define XUART 0x10000000
// GLOBALS, which were NEVER AFFECTED -- and that is the point of having them here. A global has
// a hash entry and never reaches the x86-statement branch at all; only a LOCAL does. Measured,
// not assumed: against the pre-fix compiler `GCTR++`, `GARR[0] = 7` and a global struct-array
// member all gave the right answer while the two LOCAL shapes below gave 10 instead of 11 and a
// word of uninitialised stack. These three lines record the BOUNDARY of the bug, so a later
// reader does not have to re-derive which side of it they are on.
I64 GCTR;
I64 GARR[3];
U0 S(U8 *s)
{
  U8 *u = XUART;
  while (*s)
    *u = *s++;
}

I64 Fold(I64 r, I64 v)
{
  return r * 100 + v;
}
// A loop whose counter is an upper-case name, which is the real-world shape: the year walk in
// CFE_TIME_UnixToCalendar.
I64 YearWalk(I64 Days)
{
  I64 Y = 1970;
  I64 YearLen;
  while (TRUE) {
    YearLen = 365;
    if (Y % 400 == 0)
      YearLen = 366;
    else if (Y % 100 == 0)
      YearLen = 365;
    else if (Y % 4 == 0)
      YearLen = 366;
    if (Days < YearLen)
      break;
    Days -= YearLen;
    Y++;
  }
  return Y;
}

I64 main()
{
  I64 r = 0;
  I64 Y = 10;
  I64 AB = 10;
  I64 A1 = 10;
  I64 zz = 10;
  I64 ARR[3];
  // every operator that can follow a name at statement start
  Y++;
  r = Fold(r, Y);
  // 11
  Y--;
  r = Fold(r, Y);
  // 10
  Y += 5;
  r = Fold(r, Y);
  // 15
  Y -= 3;
  r = Fold(r, Y);
  // 12
  Y *= 2;
  r = Fold(r, Y);
  // 24
  Y /= 4;
  r = Fold(r, Y);
  // 6
  Y &= 3;
  r = Fold(r, Y);
  // 2
  Y |= 8;
  r = Fold(r, Y);
  // 10
  Y ^= 1;
  r = Fold(r, Y);
  // 11
  Y <<= 2;
  r = Fold(r, Y);
  // 44
  Y >>= 1;
  r = Fold(r, Y);
  // 22
  Y %= 7;
  r = Fold(r, Y);
  // 1
  // longer all-caps names, not just single letters
  AB++;
  A1 += 2;
  r = Fold(r, AB);
  // 11
  r = Fold(r, A1);
  // 12
  // and a lower-case one, which always worked, so a fix that broke it would show
  zz++;
  r = Fold(r, zz);
  // 11
  // AN ALL-CAPS ARRAY NAME, which is what makes the two halves of the fix separable. `[` is not
  // an operator, so it is not in the list below the symbol check in parser.c, and it was never
  // in the shape test's own list either -- so ONLY the symbol-table guard keeps these three
  // lines from being discarded. Remove that guard and this case fails on its own; the operator
  // list alone cannot save it.
  ARR[0] = 7;
  ARR[1] = 8;
  ARR[2] = ARR[0] + ARR[1];
  r = Fold(r, ARR[2]);
  // 15
  // THE SAME THREE SHAPES ON GLOBALS. These passed before the fix too; they are here to pin the
  // boundary, not as a witness.
  GCTR = 10;
  GCTR++;
  r = Fold(r, GCTR);
  // 11
  GCTR += 5;
  r = Fold(r, GCTR);
  // 16
  GARR[0] = 7;
  GARR[1] = 8;
  GARR[2] = GARR[0] + GARR[1];
  r = Fold(r, GARR[2]);
  // 15
  // 3652 days after 1970-01-01 is 1980-001: ten years including the 1972 and 1976 leap days.
  // This is the cFS loop, and the number it must produce is the one glibc's gmtime_r produces.
  r = r * 10000 + YearWalk(3652);
  // 1980
  r = r * 10000 + YearWalk(0);
  // 1970
  r = r * 10000 + YearWalk(365);
  // 1971
  // The x86-statement feature itself: CLD is a real opcode with no RISC-V meaning and is skipped
  // with a note. If the fix above had disabled the branch, this would be a parse error.
  CLD S("");
  return r & 0xFFFFFFFFFFFF;
}
