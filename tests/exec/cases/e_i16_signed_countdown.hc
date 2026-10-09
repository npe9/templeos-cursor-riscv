// **THE FIRST `int16` LOCAL IN THE WHOLE cFS PORT, AND NASA SHOUTS ABOUT IT.**
//
// `sc_state.c`'s SC_GetNextRtsTime opens with
//
//     int16 i;   /* loop counter MUST be SIGNED !*/
//
// and that comment is the only one of its kind in any source this port has translated -- a grep
// for "MUST be SIGNED" across all of vendor/ returns exactly that line. It is there because the
// loop runs DOWNWARDS and ends by going negative:
//
//     for (i = SC_NUMBER_OF_RTS - 1; i >= 0; i--)
//
// With an unsigned counter `i--` at 0 gives 65535, `i >= 0` is still true, and the body indexes
// the RTS info table at 65535 -- forever. NASA walks backwards on purpose (lower RTS numbers have
// higher priority, and `<=` in the body means the LOWEST-numbered RTS wins a tie), so the
// direction is not negotiable and the signedness carries it.
//
// **AND `I16` HAD NEVER APPEARED AS A LOCAL IN THIS TRANSLATION BEFORE.** Every narrow local in
// the port so far is a `U16`, measured by `e_u16_wrap_insert.hc`. That case proves UNSIGNED
// 16-bit lvalues wrap; it says nothing about whether a SIGNED one sign-extends when loaded, which
// is a different question about a different type and the one this loop's termination rests on. A
// wrong answer hangs the app on the first wakeup cycle, inside a function whose job is to pick the
// next RTS -- so it would present as "SC does nothing" rather than as a type bug.
//
// ### WHAT IS PINNED, AND WHY EACH LINE IS NOT THE PREVIOUS ONE
//
//   1. the descending loop itself: exactly 64 iterations, and `i` ends at **-1**;
//   2. `(U16)` of that -1, which is 65535 -- because `SC_RTS_IDX_C(i)` is applied to this same
//      counter and `SC_INVALID_RTS_INDEX` is `(SC_RtsIndex_t){-1}`, so the sentinel and the
//      exhausted counter have to be the same value;
//   3. **the unsigned twin as a VALUE rather than as a hang**: `u = 0; u--;` is 65535 and
//      `u >= 0` is true. That is NASA's comment, demonstrated without an infinite loop;
//   4. sign extension on widening: `I16 i = -2; I32 w = i;` must be -2 and not 65534;
//   5. signed 16-bit overflow: `i = 32767; i++;` must be **-32768**. Nothing in SC does this --
//      it is here because it is the one form that distinguishes a real 16-bit signed lvalue from
//      an I32 that merely holds small numbers, and a compiler that got the first four right by
//      storing wide would fail only this one.
//
// ### EXPECTED VALUE FROM C
//
// A C twin (`int16_t`, `uint16_t`, the same five steps, the same fold) printed
//
//     n=64 end_i=-1 u=65535 w=-2 i=-32768
//     fold = 00009305494f8f79
//
// ### MUTATIONS
//
//   | mutation | result |
//   |---|---|
//   | `I16 i` to `I32 i`  | **FAIL** `0000930549508f79` -- step 5 gives 32768 |
//   | `I32 w` to `U32 w`  | **FAIL** `0000d548494f8f79` -- step 4 gives 65534 |
//   | `I32 w` to `I16 w`  | PASSED |
//   | `Fold(r, i)` to `Fold(r, i + 0)` | PASSED -- the intended no-op control |
//
// **THE `I16 w` MUTATION WAS WRITTEN AS A SECOND DISCRIMINATOR AND IS NOT ONE.** -2 fits in
// sixteen signed bits, so narrowing the DESTINATION of `w = i` changes nothing; what step 4 is
// about is the sign of the extension, so the mutation that breaks it has to change the
// destination's SIGNEDNESS, not its width. `U32 w` makes the same assignment read 65534 and the
// case fails. The dead mutation is left in the table because the first version of this header
// claimed it failed, and a mutation table that only lists the ones that worked is not evidence of
// anything.
//
// The unsigned-COUNTER mutation is deliberately absent: it does not produce a wrong answer, it
// produces an infinite loop, and a gate that fails by hanging fails slowly and ambiguously. Step 3
// pins the same fact as a value instead.
I64 main();

// SC's index algebra, from Kernel/Cfs/sc/sc_tbl.HC.
#define IDX_FROM_UINT(a) ((a)(U16))
#define IDX_AS_UINT(a)   ((a)(U32))
// **NOT SC's CONFIGURED VALUE.** `SC_NUMBER_OF_RTS` is 4 in this configuration, and four
// iterations is a thin probe: a loop that happened to run twice, or once, would fold to a
// different value but would not exercise a counter far from its sentinel. 64 is used here so the
// descending walk covers a real range before it goes negative. What must match SC exactly is the
// SHAPE of the loop and the type of its counter, not its bound -- so the bound is the probe's and
// the rest is NASA's. An earlier version of this comment claimed this was sc_cfg.HC's number; it
// is not, and the difference is why it now says so.
#define SC_NUMBER_OF_RTS 64

I64 Fold(I64 r, I64 v)
{
  return (r * 1000003 + v) & 0xFFFFFFFFFFFF;
}

I64 main()
{
  I64 r = 0;
  I16 i;
  I64 n = 0;
  U16 u;
  I32 w;

  // ---- 1. NASA's descending loop, written as a while so the counter is visible after it -------
  i = SC_NUMBER_OF_RTS - 1;
  while (i >= 0) {
    r = Fold(r, i);
    n++;
    i--;
  }
  r = Fold(r, n); // 64
  r = Fold(r, i); // -1

  // ---- 2. and -1 through SC's index cast is the invalid-index sentinel ------------------------
  r = Fold(r, IDX_AS_UINT(IDX_FROM_UINT(i)));

  // ---- 3. THE UNSIGNED TWIN, as a value. This is NASA's comment --------------------------------
  u = 0;
  u--;
  r = Fold(r, u);               // 65535, not -1
  r = Fold(r, (u >= 0) != 0);   // 1 -- the loop would never have ended

  // ---- and the sentinel spelled the way sc_state.c spells it ----------------------------------
  r = Fold(r, IDX_FROM_UINT(-1));
  r = Fold(r, (IDX_AS_UINT(IDX_FROM_UINT(-1)) < SC_NUMBER_OF_RTS) != 0); // 0: rejected

  // ---- 4. sign extension on widening ----------------------------------------------------------
  i = -2;
  w = i;
  r = Fold(r, w); // -2, not 65534

  // ---- 5. signed 16-bit overflow, the form only a real I16 gets right -------------------------
  i = 32767;
  i++;
  r = Fold(r, i); // -32768

  return r;
}
