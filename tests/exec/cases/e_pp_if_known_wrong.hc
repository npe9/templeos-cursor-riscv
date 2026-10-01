// KNOWN WRONG, PINNED ON PURPOSE: `#if <expr>` IS UNCONDITIONALLY TRUE IN THIS COMPILER.
//
// READ THIS BEFORE RE-PINNING. The expected value in oracle_manifest.tsv for this case is the
// value the compiler produces TODAY, and that value is WRONG. If this case starts failing,
// `#if` has probably been implemented -- which is the point -- and the right response is to
// change the expected value to 0000000000000004c6 (1222) and delete this file's "known wrong"
// framing, NOT to make the compiler reproduce 0x457 again.
//
//   what it does now    1 + 10 + 100 + 1000 = 1111 = 0x457   every #if branch taken
//   what C would do     2 + 20 + 200 + 1000 = 1222 = 0x4c6
//
// host/lexer.c's directive handler says so in as many words -- "#if — only literal 0 / non-zero"
// -- so `#if 0` works and `#if ANYTHING_ELSE` is true, including an undefined name and including
// `#if (MACRO == 1)` where MACRO is 0. The `#else` branch is correctly skipped, which is what
// makes the failure silent: the code compiles, one branch runs, and it is the wrong one.
// `#ifdef` and `#ifndef` are evaluated properly; this is only `#if`.
//
// WHY IT MATTERS BEYOND cFS. Stock TempleOS uses the directive, and this port inherited it:
// Kernel/KernelA.HH:2785 says `#define _CFG_HEAP_DBG FALSE` and then `#if _CFG_HEAP_DBG` picks
// between two layouts of CMemUsed and CMemUnused -- the heap allocator's own headers. The FALSE
// is ignored, so this kernel is built in heap-debug mode with 48-byte headers instead of 16, and
// the matching `#if _CFG_HEAP_DBG` blocks in Kernel/Mem/MAllocFree.HC maintain the debug queue
// that goes with them. It is self-consistent and it boots, which is why nobody noticed; it is
// also not what the configuration says. docs/HOLYC_STRUCT_LIMITS.md #15.
#define Z 0
#define F FALSE
I64 main()
{
  I64 r = 0;
  // A macro defined as 0.
#if Z
  r += 1;
#else
  r += 2;
#endif
  // A macro defined as FALSE, which is how the kernel spells it.
#if F
  r += 10;
#else
  r += 20;
#endif
  // A name nothing defines at all.
#if NOPE
  r += 100;
#else
  r += 200;
#endif
  // And the one that is genuinely true, so a "fix" that made every #if FALSE would be caught.
#if 1
  r += 1000;
#else
  r += 2000;
#endif
  return r;
}
