/* HolyC runtime exported to compiled code. One list, three users: the AOT compiler declares
 * these as externs (calls go through import slots), the REPL registers the C entry points,
 * and the exec harness resolves the blob's import directory by name.  X(name, argc) */
#ifndef HOLY_RT_NAMES_H
#define HOLY_RT_NAMES_H
#define HOLY_RT_NAMES(X) \
  X(Print, 1) X(PutS, 1) X(PutChars, 1) \
  X(MAlloc, 1) X(CAlloc, 1) X(Free, 1) \
  X(StrLen, 1) X(StrCpy, 2) X(StrCmp, 2) X(StrCat, 2) X(StrNew, 1) \
  X(MemCpy, 3) X(MemSet, 3) X(MemCmp, 3) X(MemSetI64, 3) \
  X(AbsI64, 1) X(MaxI64, 2) X(MinI64, 2) X(ToUpper, 1) X(ToLower, 1) \
  X(RandU16, 0) X(RandI64, 0) X(Seed, 1) X(YorN, 0) X(tS, 0) X(D, 2) \
  X(Pow, 2) X(Sqrt, 1) X(Exp, 1) X(Ln, 1) X(Log10, 1) X(Log2, 1) \
  X(Floor, 1) X(Ceil, 1) X(Round, 1) X(Trunc, 1) X(Sin, 1) X(Cos, 1) X(Tan, 1) X(ATan, 1) \
  X(Abs, 1) X(Sign, 1) \
  X(Bt, 2) X(Bts, 2) X(Btr, 2) X(Btc, 2) X(LBts, 2) X(LBtr, 2) X(LBtc, 2) X(Bsf, 1) X(Bsr, 1) \
  X(BEqu, 3) X(BFieldOrU32, 3) X(SwapI64, 2) X(LXchgI64, 2) X(SqrI64, 1) X(ClampI64, 3) X(MSize, 1) X(MSize2, 1) \
  X(InU8, 1) X(OutU8, 2) X(InU16, 1) X(OutU16, 2) X(InU32, 1) X(OutU32, 2) X(RepInU32, 3) X(RepOutU32, 3) \
  X(GetRAX, 0) X(GetRBP, 0) X(GetRFlags, 0) X(SetRFlags, 1) X(CPUId, 2) X(InvlPg, 1) X(SysHlt, 0) X(GetTSC, 0) X(Caller, 1) \
  X(QueInit, 1) X(QueIns, 2) X(QueInsRev, 2) X(QueRem, 1) X(StrMatch, 3) X(StrIMatch, 3) X(StrICmp, 2) X(Pow10, 1) \
  X(HashStr, 1) X(HashFind, 3) X(HashSingleTableFind, 3) X(HashAdd, 2) X(HashRemDel, 3) X(StrNCmp, 3) X(ModU64, 2) X(LBEqu, 3) \
  X(BFieldExtU32, 3) X(RepInU16, 3) X(GetRSP, 0) X(SaveExceptRegs, 0) X(Call, 1) X(FarCall32, 4) X(Yield, 0) X(TaskEndNow, 0) X(RVTaskSwitch, 2) X(RVTrapInit, 0) X(RVTimerArm, 1) X(RVGetTicks, 0) X(RVPreemptInit, 1) X(RVPreemptSpawn, 2) X(RVPreemptExit, 0) X(RVCritEnter, 0) X(RVCritLeave, 1) X(RVSleep, 1) X(RVUartIrqInit, 0) X(RVUartHasInput, 0) X(RVUartGetBuffered, 0) X(RVBlkInit, 0) X(RVBlkRead, 2) X(RVBlkWrite, 2) X(RVCtxSw, 2) X(RVYieldInit, 1) X(RVPreemptReal, 1) X(RVJiffies, 0) X(RVJiffiesInit, 1) X(RVTrapDiag, 0) X(RVRunBlob, 2)

/* F64 typing of the runtime (arguments and results travel as raw 64-bit patterns): the
 * compiler converts call arguments per the mask and types the result. */
static int holy_rt_streq(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }
static int HolyRtRetF64(const char *n) {
  static const char *f64[] = { "tS", "Pow", "Sqrt", "Exp", "Ln", "Log10", "Log2", "Floor", "Ceil", "Round", "Trunc", "Sin", "Cos", "Tan", "ATan", "Abs", "Pow10", 0 };
  for (int i = 0; f64[i]; i++) if (holy_rt_streq(n, f64[i])) return 1;
  return 0;
}
static unsigned HolyRtF64Mask(const char *n) {
  if (holy_rt_streq(n, "Pow")) return 3;
  static const char *one[] = { "Sqrt", "Exp", "Ln", "Log10", "Log2", "Floor", "Ceil", "Round", "Trunc", "Sin", "Cos", "Tan", "ATan", "Abs", "Sign", "Pow10", 0 };
  for (int i = 0; one[i]; i++) if (holy_rt_streq(n, one[i])) return 1;
  return 0;
}
#endif
