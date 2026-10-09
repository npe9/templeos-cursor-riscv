// **SC_Insert SORTS BY RUNNING AN INDEX OFF BOTH ENDS OF A uint16, AND NOTHING PINNED THAT.**
//
// `sc_loads.c`'s SC_Insert is SC's only sort. It walks the time-ordered list downwards and relies
// on 16-bit wraparound TWICE, in a way that is load-bearing rather than incidental:
//
//     TimeBufIndex = SC_SEQUENCE_IDX_C(ListLength - 1);          // 0 - 1 must become 65535
//     while (SC_IDX_WITHIN_LIMIT(TimeBufIndex, ListLength)) {    // and 65535 must FAIL this
//         ...
//         SC_IDX_DECREMENT(TimeBufIndex);                        // 0 - 1 again, mid-walk
//     }
//     SC_IDX_INCREMENT(TimeBufIndex);                            // 65535 + 1 must become 0
//
// NASA's own comment on the decrement is "back up to previous list entry (ok if -1)". It is "ok"
// because the value comes back to 0 through the increment below, and the loop guard is a
// comparison that 65535 cannot pass. Both halves of that have to hold.
//
// ### WHY A MEASUREMENT AND NOT A READING OF THE COMPILER
//
// HolyC has no `uint16_t`; `U16` is the translation's spelling, `SC_IDX_FROM_UINT(arg)` is
// `(arg)(U16)`, and a HolyC cast RELABELS rather than converting (memory: HolyC semantics
// gotchas). Whether a *relabel* of -1 masks to 65535, and whether `++`/`--` on a U16 LVALUE wrap
// at 16 bits rather than at 64, are two different questions about the same type -- and a wrong
// answer to either does not fail loudly:
//
//   * if `--` on 0 gave 0xFFFFFFFFFFFFFFFF, `SC_IDX_AS_UINT` would make it 0xFFFFFFFF, the
//     guard would still fail, the increment would still produce 0x100000000 -> 0, and **the sort
//     would still work** -- so this probe would pass while the stored INDEX in a wider field
//     somewhere else was wrong;
//   * if `++` on 65535 gave 65536, the first command of every ATS would be written to list slot
//     65536 -- past a 1000-entry array, into whatever follows SC_OperData.
//
// So the four forms are pinned separately AND the sort is run.
//
// ### FOUR MUTATIONS WERE RUN AGAINST THIS CASE AND **TWO OF THEM PASSED**
//
// A case that goes green on its first run asserts nothing until something has been broken on
// purpose. These four were:
//
//   | mutation                                        | result |
//   |---|---|
//   | `CompareAbsTime` to `a >= b` (unstable sort)    | **FAIL** `0000e06fe0f815cd` -- order 2 3 1 0 |
//   | `U16 b` to `I64 b` (the `++` form)              | **FAIL** `0000cc3dd6b65f41` |
//   | `U16 a` to `I64 a` (the `--` form)              | **FAIL** `00002c40edf25f41` |
//   | `U16 TimeBufIndex` to `I64 TimeBufIndex`        | PASSED |
//   | `SC_IDX_WITHIN_LIMIT` to a signed `(I64) <`     | PASSED |
//
// **THE TWO PASSES ARE A FINDING ABOUT SC_Insert, NOT A HOLE IN THIS CASE.** Widening the sort's
// own index changes nothing because every mask in the walk comes from one of SC's CASTS and not
// from the variable's declared type: `SC_SEQUENCE_IDX_C` masks the initial `ListLength - 1` to 16
// bits on the way in, and `SC_IDX_AS_UINT` inside the guard masks to 32 on every test. An I64
// index therefore holds 65535 after the decrement, fails the guard for the same reason, and comes
// back to 0 through the increment. And the guard's signedness is moot for the same reason -- a
// value that has been masked to 16 bits is positive in any width, so `<` signed and `<` unsigned
// agree on every value the walk can produce.
//
// What that means for the port: **the sort is the WEAKER of the two halves of this case.** It pins
// the comparison's strictness and the composed walk; the four isolated forms are what pin the
// narrow-type arithmetic, and only they fail when it breaks. Had the sort been the whole case, a
// compiler whose `U16 ++` did not wrap would have passed it.
//
// ### EVERY EXPECTED VALUE CAME FROM C
//
// A C twin of this file (uint16_t, the same macros, the same four inserts) printed
//
//     a=65535 b=0 c=65535 d=65535
//     order = 2 1 3 0
//     fold = 0000de9e37155f41
//
// and 0000de9e37155f41 is this case's pinned value. `order = 2 1 3 0` is the sort's output for
// times 30, 20, 10, 20 -- ascending, and **command 1 before command 3 although they share time
// 20**, which is the stability that NASA's strictly-greater `SC_CompareAbsTime` buys. A `>=`
// there would print `2 3 1 0` and change the fold, so the pin covers the comparison too.
I64 main();

// SC's index algebra, copied from Kernel/Cfs/sc/sc_tbl.HC rather than approximated -- a probe that
// spells the macro differently from the code it is about proves something about the probe.
#define SC_IDX_AS_UINT(arg)           ((arg)(U32))
#define SC_IDX_FROM_UINT(arg)         ((arg)(U16))
#define SC_IDX_INCREMENT(arg)         (++(arg))
#define SC_IDX_DECREMENT(arg)         (--(arg))
#define SC_IDX_WITHIN_LIMIT(arg, lim) (SC_IDX_AS_UINT(arg) < (lim))
#define SC_SEQUENCE_IDX_C(i)          (SC_IDX_FROM_UINT(i))

// The two parallel arrays SC_Insert works on, four slots instead of a thousand.
U16 SeqList[4];  // the time-sorted list: command indices, in execution order
U32 CmdTime[4];  // execution time per command index

I64 Fold(I64 r, I64 v)
{
  return (r * 1000003 + v) & 0xFFFFFFFFFFFF;
}

// NASA's SC_CompareAbsTime, reduced to the comparison -- STRICTLY greater, which is what makes the
// sort stable. The real one goes through CFE_TIME_Compare; the sign convention is all that is
// under test here.
I64 CompareAbsTime(U32 a, U32 b)
{
  return a > b;
}

// SC_Insert with the table accessors inlined and the validation dropped. The index arithmetic and
// the loop structure are NASA's line for line.
U0 Insert(U16 NewCmdIndex, U32 ListLength)
{
  U32 NewCmdTime = 0;
  U32 ListCmdTime;
  U16 TimeBufIndex;
  U16 NextIndex;

  if (ListLength > 0)
    NewCmdTime = CmdTime[NewCmdIndex];

  // WRAP #1: ListLength is a U32, so `ListLength - 1` is 0xFFFFFFFF here, and the (U16) must mask.
  TimeBufIndex = SC_SEQUENCE_IDX_C(ListLength - 1);

  while (SC_IDX_WITHIN_LIMIT(TimeBufIndex, ListLength)) {
    ListCmdTime = CmdTime[SeqList[TimeBufIndex]];
    if (CompareAbsTime(ListCmdTime, NewCmdTime)) {
      NextIndex = TimeBufIndex;
      SC_IDX_INCREMENT(NextIndex);
      SeqList[NextIndex] = SeqList[TimeBufIndex];
      // WRAP #2: on the last iteration this takes 0 to 65535, which is how the loop ends.
      SC_IDX_DECREMENT(TimeBufIndex);
    } else {
      break;
    }
  }

  // WRAP #3: and this brings 65535 back to 0, which is how slot 0 gets written.
  SC_IDX_INCREMENT(TimeBufIndex);
  SeqList[TimeBufIndex] = NewCmdIndex;
}

I64 main()
{
  I64 r = 0;
  U16 a;
  U16 b;
  U16 c;
  U16 d;
  U32 len;
  I64 i;

  // ---- THE FOUR LVALUE FORMS, each the one a line of SC_Insert performs ----------------------
  a = 0;
  a--;                     // `SC_IDX_DECREMENT` on 0
  r = Fold(r, a);
  b = 65535;
  b++;                     // `SC_IDX_INCREMENT` on 65535
  r = Fold(r, b);
  len = 0;
  c = len - 1;             // `SC_SEQUENCE_IDX_C(ListLength - 1)`, the U32 subtraction
  r = Fold(r, c);
  d = -1(U16);             // the cast on its own, which is what SC_SEQUENCE_IDX_FIRST's sibling
  r = Fold(r, d);          // SC_ENTRY_OFFSET_INVALID is spelled with

  // ---- AND THE GUARD 65535 MUST FAIL, which is the half a value check cannot show -----------
  //
  // Both of these must be 0. The first is the empty-list case -- the loop body must not run at
  // all; the second is the mid-walk case against a real list length.
  r = Fold(r, SC_IDX_WITHIN_LIMIT(SC_SEQUENCE_IDX_C(len - 1), len) != 0);
  r = Fold(r, SC_IDX_WITHIN_LIMIT(SC_SEQUENCE_IDX_C(65535), 3) != 0);

  // ---- THE SORT ITSELF -----------------------------------------------------------------------
  //
  // Four commands whose times make every branch run: an insert into an EMPTY list (the 65535
  // guard), one that walks down one slot, one that walks all the way to the front through 0, and
  // one that stops immediately on an EQUAL time.
  CmdTime[0] = 30;
  CmdTime[1] = 20;
  CmdTime[2] = 10;
  CmdTime[3] = 20;
  Insert(0, 0);
  Insert(1, 1);
  Insert(2, 2);
  Insert(3, 3);
  i = 0;
  while (i < 4) {
    r = Fold(r, SeqList[i]);
    i++;
  }

  return r;
}
