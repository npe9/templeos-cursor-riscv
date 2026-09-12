// KThinMapFatStubs.HC — RV_THIN_LOADER: drop next map fats unused on SoftCall+STAY+LoadBuf.
// TimeCal / Pow(+Exp/Ln) / QueVectU8* / Fifo* / D3* / Rand* / ScanFlags / PutExcept / Endian*
// SoftCall ExceptSoft owns real SysTry/throw/PutExcept queue shape in Kernel.BIN.
// SoftCall FifoSoft owns real FifoU8/FifoI64 ring in Kernel.BIN (→'SF').
// SoftCall QueVectSoft owns real QueVectU8 New/Put/Get/Del in Kernel.BIN (→'QV').
// SoftCall RandSoft owns real Seed+LCG RandI* in Kernel.BIN (→'RN').
// SoftCall ScanFlagsSoft owns real LstMatch+ScanFlags+StrPrintFlags in Kernel.BIN (→'SC').
// (~11 KiB + ~8 KiB D3 + ~6 KiB Fifo + ~5 KiB Rand map). Thin StrPrintJoin stays (~4.1 KiB
// %s/%d/%X). SoftCall owns real time/math/FS flags/RNG; SerialDev Fifo→SoftCall (Serial gated).
#ifndef K_THIN_MAP_FAT_STUBS_HC
#define K_THIN_MAP_FAT_STUBS_HC
I64 TimeCal()
{
  // SoftCall never calibrates; cnts.time_stamp_* stay from BSS / KBootRV.
  return CONFIG_TIMEBASE_FREQ;
}

U16 EndianU16(U16 d)
{
  return d;
}

U32 EndianU32(U32 d)
{
  return d;
}

I64 EndianI64(I64 d)
{
  return d;
}

CQueVectU8 *QueVectU8New(I64 min_idx = 0)
{
  no_warn min_idx;
  return NULL;
}

U0 QueVectU8Put(CQueVectU8 *v, I64 idx, U8 ch)
{
  no_warn v;
  no_warn idx;
  no_warn ch;
}

U0 QueVectU8Del(CQueVectU8 *v)
{
  no_warn v;
}

I64 QueVectU8Get(CQueVectU8 *v, I64 idx)
{
  no_warn v;
  no_warn idx;
  return 0;
}

CFifoU8 *FifoU8New(I64 size, CTask *mem_task = NULL)
{
  no_warn size;
  no_warn mem_task;
  return NULL;
}

U0 FifoU8Del(CFifoU8 *f)
{
  no_warn f;
}

Bool FifoU8Ins(CFifoU8 *f, U8 b)
{
  no_warn f;
  no_warn b;
  return FALSE;
}

Bool FifoU8Rem(CFifoU8 *f, U8 *_b)
{
  no_warn f;
  no_warn _b;
  return FALSE;
}

Bool FifoU8Peek(CFifoU8 *f, U8 *_b)
{
  no_warn f;
  no_warn _b;
  return FALSE;
}

U0 FifoU8Flush(CFifoU8 *f)
{
  no_warn f;
}

I64 FifoU8Cnt(CFifoU8 *f)
{
  no_warn f;
  return 0;
}

CFifoI64 *FifoI64New(I64 size, CTask *mem_task = NULL)
{
  no_warn size;
  no_warn mem_task;
  return NULL;
}

U0 FifoI64Del(CFifoI64 *f)
{
  no_warn f;
}

Bool FifoI64Ins(CFifoI64 *f, I64 q)
{
  no_warn f;
  no_warn q;
  return FALSE;
}

Bool FifoI64Rem(CFifoI64 *f, I64 *_q)
{
  no_warn f;
  no_warn _q;
  return FALSE;
}

Bool FifoI64Peek(CFifoI64 *f, I64 *_q)
{
  no_warn f;
  no_warn _q;
  return FALSE;
}

U0 FifoI64Flush(CFifoI64 *f)
{
  no_warn f;
}

I64 FifoI64Cnt(CFifoI64 *f)
{
  no_warn f;
  return 0;
}

CD3 *D3Zero(CD3 *dst)
{
  no_warn dst;
  return dst;
}

CD3 *D3Copy(CD3 *dst, CD3 *src)
{
  no_warn src;
  return dst;
}

CD3 *D3Equ(CD3 *dst, F64 x = 0, F64 y = 0, F64 z = 0)
{
  no_warn x;
  no_warn y;
  no_warn z;
  return dst;
}

CD3 *D3Add(CD3 *sum, CD3 *d1, CD3 *d2)
{
  no_warn d1;
  no_warn d2;
  return sum;
}

CD3 *D3Sub(CD3 *diff, CD3 *d1, CD3 *d2)
{
  no_warn d1;
  no_warn d2;
  return diff;
}

CD3 *D3Mul(CD3 *prod, F64 s, CD3 *d)
{
  no_warn s;
  no_warn d;
  return prod;
}

CD3 *D3Div(CD3 *quot, CD3 *d, F64 s)
{
  no_warn d;
  no_warn s;
  return quot;
}

CD3 *D3AddEqu(CD3 *sum, CD3 *d)
{
  no_warn d;
  return sum;
}

CD3 *D3SubEqu(CD3 *diff, CD3 *d)
{
  no_warn d;
  return diff;
}

CD3 *D3MulEqu(CD3 *prod, F64 s)
{
  no_warn s;
  return prod;
}

CD3 *D3DivEqu(CD3 *quot, F64 s)
{
  no_warn s;
  return quot;
}

F64 D3NormSqr(CD3 *d)
{
  no_warn d;
  return 0.0;
}

F64 D3Norm(CD3 *d)
{
  no_warn d;
  return 0.0;
}

F64 D3DistSqr(CD3 *d1, CD3 *d2)
{
  no_warn d1;
  no_warn d2;
  return 0.0;
}

F64 D3Dist(CD3 *d1, CD3 *d2)
{
  no_warn d1;
  no_warn d2;
  return 0.0;
}

F64 D3Dot(CD3 *d1, CD3 *d2)
{
  no_warn d1;
  no_warn d2;
  return 0.0;
}

CD3 *D3Cross(CD3 *prod, CD3 *d1, CD3 *d2)
{
  no_warn d1;
  no_warn d2;
  return prod;
}

CD3 *D3Unit(CD3 *d)
{
  return d;
}

I16 RandI16()
{
  return 0;
}

U16 RandU16()
{
  return 0;
}

I32 RandI32()
{
  return 0;
}

U32 RandU32()
{
  return 0;
}

I64 RandI64()
{
  return 0;
}

U64 RandU64()
{
  return 0;
}

F64 Rand()
{
  return 0.0;
}

I64 Seed(I64 seed = 0, CTask *task = NULL)
{
  no_warn seed;
  no_warn task;
  return 0;
}

U0 ScanFlags(U8 *_dst_flags, U8 *lst, U8 *src)
{
  no_warn _dst_flags;
  no_warn lst;
  no_warn src;
}

U8 *StrPrintFlags(U8 *dst, U8 *lst, I64 flags)
{
  no_warn lst;
  no_warn flags;
  if (dst)
    *dst = 0;
  return dst;
}

U0 PutExcept(Bool catch_it = TRUE)
{
  if (Fs)
    Fs->catch_except = catch_it;
}

F64 Exp(F64 d)
{
  no_warn d;
  return 0.0;
}

F64 Ln(F64 d)
{
  no_warn d;
  return 0.0;
}

F64 Log2(F64 x)
{
  no_warn x;
  return 0.0;
}

F64 Log10(F64 x)
{
  no_warn x;
  return 0.0;
}

F64 Pow10(F64 x)
{
  no_warn x;
  return 0.0;
}

F64 Pow(F64 a, F64 b)
{
  no_warn a;
  no_warn b;
  return 0.0;
}
#endif
