/* rv32_lift.c — RV32 backend: lift the emitter's virtual rv64 word stream to rv32.
 *
 * host/compiler.c lowers ICs to rv64 words and funnels every one through RvEmitWord. On
 * --target rv32 each word comes here instead and is rewritten to rv32 words that keep the
 * full HolyC I64 semantics with REGISTER PAIRS (docs: templeos-riscv/RV32.md §3):
 *
 *     lo  a0  t0  t1  t2      (the only registers the emitter computes values in)
 *     hi  a1  t3  t4  t5      (x28-x30: never used by the emitter)
 *
 * Every 8-byte slot (eval stack, frame, struct member, global) holds {lo @+0, hi @+4}, so the
 * frozen 8-byte slot stride of the rv64 layout is unchanged. Any other register (sp, s0, ra,
 * a1-a7 as argument registers, a5 scratch) is a 32-bit "plain" register whose high half reads
 * as zero (addresses are zero-extended). Scratch: t6 and a7. a7 is only a live argument
 * between a call's arg loads and its jalr, where only loads, auipc/addi (t6-only) and jalr
 * are emitted. Call arguments are pairs a_i : s(1+i) (see rv32_lift.h).
 *
 * Invariant the AOT sizing loop depends on: the NUMBER of words a virtual word expands to is
 * a function of its opcode, funct fields, registers and shift amount only — never of an
 * immediate or branch offset (those differ between the sizing and emit passes). CompileAOT
 * reports "emit size != sized" if this is ever broken.
 *
 * div/divu/rem/remu call rv32_divmod (host/rv32_divmod.S), appended once per blob.
 * fcvt.l.d (F64 -> I64) calls it too (op 4). Not yet: fcvt.lu.d beyond 32 bits; mulh*.
 */
#include "rv32_lift.h"
#include <stdio.h>
#include "rv32_stubs.inc"

#define X_ZERO 0
#define X_RA 1
#define X_SP 2
#define X_T0 5
#define X_T1 6
#define X_T2 7
#define X_A0 10
#define X_A1 11
#define X_A7 17
#define X_S1 9
#define X_S2 18
#define X_T3 28
#define X_T4 29
#define X_T5 30
#define X_T6 31
#define SC1 X_T6   /* scratch */
#define SC2 X_A7   /* scratch */

typedef struct { Rv32EmitFn emit; void *ctx; int n; const Rv32LiftEnv *env; } Out;
static void W(Out *o, uint32_t w) { o->emit(o->ctx, w); o->n++; }

static uint32_t R(uint32_t f7, int rs2, int rs1, uint32_t f3, int rd, uint32_t op) {
  return (f7 << 25) | ((uint32_t)rs2 << 20) | ((uint32_t)rs1 << 15) | (f3 << 12) | ((uint32_t)rd << 7) | op;
}
static uint32_t I(int32_t imm, int rs1, uint32_t f3, int rd, uint32_t op) {
  return (((uint32_t)imm & 0xFFF) << 20) | ((uint32_t)rs1 << 15) | (f3 << 12) | ((uint32_t)rd << 7) | op;
}
static uint32_t S(int32_t imm, int rs2, int rs1, uint32_t f3, uint32_t op) {
  uint32_t u = (uint32_t)imm;
  return ((u >> 5 & 0x7F) << 25) | ((uint32_t)rs2 << 20) | ((uint32_t)rs1 << 15) | (f3 << 12) | ((u & 0x1F) << 7) | op;
}
static uint32_t B(int32_t imm, int rs2, int rs1, uint32_t f3) {
  uint32_t u = (uint32_t)imm;
  return ((u >> 12 & 1) << 31) | ((u >> 5 & 0x3F) << 25) | ((uint32_t)rs2 << 20) | ((uint32_t)rs1 << 15) |
         (f3 << 12) | ((u >> 1 & 0xF) << 8) | ((u >> 11 & 1) << 7) | 0x63;
}
#define ADDI(rd, rs, imm) I(imm, rs, 0, rd, 0x13)
#define MV(rd, rs)        ADDI(rd, rs, 0)
#define LI0(rd)           ADDI(rd, X_ZERO, 0)
#define ADD(rd, a, b)     R(0, b, a, 0, rd, 0x33)
#define SUB(rd, a, b)     R(0x20, b, a, 0, rd, 0x33)
#define SLTU(rd, a, b)    R(0, b, a, 3, rd, 0x33)
#define OR(rd, a, b)      R(0, b, a, 6, rd, 0x33)
#define XOR(rd, a, b)     R(0, b, a, 4, rd, 0x33)

/* High partner of a value register, -1 for a plain 32-bit register (hi reads as zero). */
static int Hi(int r) {
  switch (r) {
  case X_A0: return X_A1;
  case X_T0: return X_T3;
  case X_T1: return X_T4;
  case X_T2: return X_T5;
  default:   return -1;
  }
}
static int ArgHi(int a) { return a == X_A0 ? X_S1 : X_S2 + (a - X_A1); }  /* s1, s2..s8 */
static int IsArg(int r) { return r >= X_A0 && r <= X_A7; }
static int HiRd(int r) { int h = Hi(r); return h < 0 ? X_ZERO : h; }  /* as an operand */

static int g_warned;
static void Unsupported(Out *o, uint32_t w, const char *what) {
  if (!g_warned) {
    fprintf(stderr, "holyc-riscv: rv32: no lowering for %s (word 0x%08x); emitted as-is\n", what, w);
    g_warned = 1;
  }
  W(o, w);
}

/* 32-bit load/store at off and off+4 from base. Offsets are frame/member offsets (fixed per
 * site); off+4 past the 12-bit range goes through scratch so the shape stays per-site fixed. */
static int PairOffBase(Out *o, int base, int32_t *off) {
  if (*off + 4 > 2047) {
    W(o, ADDI(SC1, base, *off));
    *off = 0;
    return SC1;
  }
  return base;
}

static void LiftLoad(Out *o, uint32_t w, int mode) {
  int rd = (w >> 7) & 31, base = (w >> 15) & 31;
  uint32_t f3 = (w >> 12) & 7;
  int32_t off = (int32_t)w >> 20;
  int hd = Hi(rd);
  if ((mode & RV32_ARG_LOAD) && f3 == 3 && IsArg(rd)) hd = ArgHi(rd);
  if (f3 == 3 || f3 == 6) w = (w & ~(7u << 12)) | (2u << 12);  /* ld/lwu -> lw (low word) */
  if (hd < 0) { W(o, w); return; }
  switch (f3) {
  case 3: {                                                     /* ld: both halves */
    int b = PairOffBase(o, base, &off);
    if (rd == b) {
      W(o, I(off + 4, b, 2, hd, 0x03));
      W(o, I(off, b, 2, rd, 0x03));
    } else {
      W(o, I(off, b, 2, rd, 0x03));
      W(o, I(off + 4, b, 2, hd, 0x03));
    }
    return;
  }
  case 0: case 1: case 2:                                       /* lb/lh/lw: sign-extend */
    W(o, w);
    W(o, I(31, rd, 5, hd, 0x13) | (0x20u << 25));               /* srai hd, rd, 31 */
    return;
  default:                                                      /* lbu/lhu/lwu: zero-extend */
    W(o, w);
    W(o, LI0(hd));
    return;
  }
}

static void LiftStore(Out *o, uint32_t w, int mode) {
  int src = (w >> 20) & 31, base = (w >> 15) & 31;
  uint32_t f3 = (w >> 12) & 7;
  if (f3 != 3) { W(o, w); return; }
  int32_t off = (int32_t)(((w >> 25) << 5) | ((w >> 7) & 31));
  if (off & 0x800) off -= 0x1000;
  int hs = ((mode & RV32_ARG_SPILL) && IsArg(src)) ? ArgHi(src) : HiRd(src);
  int b = PairOffBase(o, base, &off);
  W(o, S(off, src, b, 2, 0x23));
  W(o, S(off + 4, hs, b, 2, 0x23));
}

/* Branch on a pair compare. The emitter's forward branches only skip the following `jal`
 * (+8), so a forward offset stays relative to the final branch word; backward targets are
 * already placed and get corrected for the words emitted in front. */
static void LiftBranch(Out *o, uint32_t w) {
  uint32_t f3 = (w >> 12) & 7;
  int x = (w >> 15) & 31, y = (w >> 20) & 31;
  int32_t off = (int32_t)(((w >> 31) << 12) | (((w >> 7) & 1) << 11) | (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1));
  if (off & 0x1000) off -= 0x2000;
  if (Hi(x) < 0 && Hi(y) < 0) { W(o, w); return; }
  int hx = HiRd(x), hy = HiRd(y);
  int final_f3;
  if (f3 == 0 || f3 == 1) {                                    /* beq/bne */
    W(o, XOR(SC1, x, y));
    W(o, XOR(SC2, hx, hy));
    W(o, OR(SC1, SC1, SC2));
    final_f3 = f3;                                              /* beq/bne SC1, zero */
  } else {                                                      /* blt/bge (u): SC1 = x < y */
    uint32_t sl = (f3 >= 6) ? 3 : 2;
    W(o, R(0, hy, hx, sl, SC1, 0x33));                          /* slt(u) sc1, hx, hy */
    W(o, B(8, hy, hx, 1));                                      /* bne hx, hy, +8 */
    W(o, SLTU(SC1, x, y));
    final_f3 = (f3 == 4 || f3 == 6) ? 1 : 0;                    /* lt: bne sc1,0  ge: beq sc1,0 */
  }
  if (off < 0) off -= 4 * 3;
  W(o, B(off, X_ZERO, SC1, (uint32_t)final_f3));
}

/* Call the appended helper: 64-bit div/rem (x, y integer registers) or, with fx >= 0,
 * F64 register fx -> I64 (op 4). Fixed shape per form; see rv32_divmod.S. */
static void LiftHelperCall(Out *o, int rd, int hd, int x, int y, int fx, int op) {
  W(o, ADDI(X_SP, X_SP, -32));
  if (fx >= 0) {
    W(o, S(0, fx, X_SP, 3, 0x27));                                         /* fsd fx, 0(sp) */
  } else {
    W(o, S(0, x, X_SP, 2, 0x23));
    W(o, S(4, HiRd(x), X_SP, 2, 0x23));
    W(o, S(8, y, X_SP, 2, 0x23));
    W(o, S(12, HiRd(y), X_SP, 2, 0x23));
  }
  W(o, ADDI(SC1, X_ZERO, op));
  int64_t rel = o->env->divmod_addr - (o->env->rip + 4 * (int64_t)o->n);
  int64_t hi = (rel + 0x800) >> 12, lo = rel - (hi << 12);
  W(o, (((uint32_t)hi & 0xFFFFF) << 12) | ((uint32_t)SC2 << 7) | 0x17);   /* auipc a7, hi */
  W(o, I((int32_t)lo, SC2, 0, SC2, 0x67));                                 /* jalr a7, lo(a7) */
  W(o, I(16, X_SP, 2, rd, 0x03));
  W(o, I(20, X_SP, 2, hd, 0x03));
  W(o, ADDI(X_SP, X_SP, 32));
}

/* Integer register-register op (0x33). */
static void LiftOp(Out *o, uint32_t w) {
  int rd = (w >> 7) & 31, x = (w >> 15) & 31, y = (w >> 20) & 31;
  uint32_t f3 = (w >> 12) & 7, f7 = w >> 25;
  int hd = Hi(rd);
  if (hd < 0 || rd == X_ZERO) { W(o, w); return; }             /* plain dest: low word is exact */
  int hx = HiRd(x), hy = HiRd(y);
  if (f7 == 0x01) {                                             /* M extension */
    switch (f3) {
    case 0:                                                     /* mul: 64-bit low product */
      W(o, R(1, y, x, 3, SC2, 0x33));                           /* mulhu sc2, x, y */
      W(o, R(1, hy, x, 0, SC1, 0x33));                          /* mul sc1, x, hy */
      W(o, ADD(SC2, SC2, SC1));
      W(o, R(1, y, hx, 0, SC1, 0x33));                          /* mul sc1, hx, y */
      W(o, ADD(SC2, SC2, SC1));
      W(o, R(1, y, x, 0, SC1, 0x33));                           /* mul sc1, x, y */
      W(o, MV(rd, SC1));
      W(o, MV(hd, SC2));
      return;
    case 4: case 5: case 6: case 7:                             /* div divu rem remu -> op 0..3 */
      LiftHelperCall(o, rd, hd, x, y, -1, (int)f3 - 4);
      return;
    default:
      Unsupported(o, w, "mulh");
      return;
    }
  }
  switch (f3) {
  case 0:
    if (f7 == 0x20) {                                           /* sub */
      W(o, SLTU(SC2, x, y));                                    /* borrow */
      W(o, SUB(SC1, x, y));
      W(o, SUB(SC2, hx, SC2));
      W(o, SUB(SC2, SC2, hy));
    } else {                                                    /* add */
      W(o, ADD(SC1, x, y));
      W(o, SLTU(SC2, SC1, x));                                  /* carry (x+y wrapped iff < x) */
      W(o, ADD(SC2, SC2, hx));
      W(o, ADD(SC2, SC2, hy));
    }
    W(o, MV(rd, SC1));
    W(o, MV(hd, SC2));
    return;
  case 4: case 6: case 7:                                       /* xor/or/and: per half */
    W(o, R(0, y, x, f3, SC1, 0x33));
    W(o, R(0, hy, hx, f3, SC2, 0x33));
    W(o, MV(rd, SC1));
    W(o, MV(hd, SC2));
    return;
  case 2: case 3:                                               /* slt/sltu: 64-bit compare */
    W(o, R(0, hy, hx, f3, SC1, 0x33));
    W(o, B(8, hy, hx, 1));                                      /* bne hx, hy, +8 */
    W(o, SLTU(SC1, x, y));
    W(o, MV(rd, SC1));
    W(o, LI0(hd));
    return;
  case 1: case 5: {                                             /* sll/srl/sra by y & 63 */
    int left = (f3 == 1), arith = (f7 == 0x20);
    W(o, I(63, y, 7, SC2, 0x13));                               /* andi sc2, y, 63 */
    W(o, ADDI(SC2, SC2, -32));                                  /* sc2 = n - 32 */
    W(o, B(4 * 6, X_ZERO, SC2, 4));                             /* blt sc2, zero, small */
    /* n >= 32 (4 words) */
    if (left) {
      W(o, R(0, SC2, x, 1, SC1, 0x33));                         /* sc1 = x << (n-32) */
      W(o, MV(hd, SC1));
      W(o, LI0(rd));
      W(o, ADDI(X_ZERO, X_ZERO, 0));                            /* nop: fixed 4 */
    } else {
      W(o, R(arith ? 0x20 : 0, SC2, hx, 5, SC1, 0x33));         /* sc1 = hx >> (n-32) */
      if (arith) W(o, I(31, hx, 5, hd, 0x13) | (0x20u << 25)); else W(o, LI0(hd));
      W(o, MV(rd, SC1));
      W(o, ADDI(X_ZERO, X_ZERO, 0));
    }
    W(o, B(4 * 9, X_ZERO, X_ZERO, 0));                          /* beq zero, zero, end */
    /* small: n in 0..31, sc2 = n - 32 (low 5 bits == n); ~sc2 == 31 - n (8 words) */
    if (left) {
      W(o, I(1, x, 5, SC1, 0x13));                              /* srli sc1, x, 1 */
      W(o, I(-1, SC2, 4, SC2, 0x13));                           /* not sc2 */
      W(o, R(0, SC2, SC1, 5, SC1, 0x33));                       /* sc1 = x >> (32-n), 0 at n=0 */
      W(o, I(-1, SC2, 4, SC2, 0x13));                           /* not sc2 */
      W(o, R(0, SC2, hx, 1, hd, 0x33));                         /* hd = hx << n */
      W(o, OR(hd, hd, SC1));
      W(o, R(0, SC2, x, 1, rd, 0x33));                          /* rd = x << n */
      W(o, ADDI(X_ZERO, X_ZERO, 0));                            /* nop: fixed 8 */
    } else {
      W(o, I(1, hx, 1, SC1, 0x13));                             /* slli sc1, hx, 1 */
      W(o, I(-1, SC2, 4, SC2, 0x13));
      W(o, R(0, SC2, SC1, 1, SC1, 0x33));                       /* sc1 = hx << (32-n), 0 at n=0 */
      W(o, I(-1, SC2, 4, SC2, 0x13));
      W(o, R(0, SC2, x, 5, rd, 0x33));                          /* rd = x >> n (x read before hd write) */
      W(o, OR(rd, rd, SC1));
      W(o, R(arith ? 0x20 : 0, SC2, hx, 5, hd, 0x33));          /* hd = hx >> n */
      W(o, ADDI(X_ZERO, X_ZERO, 0));
    }
    return;
  }
  }
  Unsupported(o, w, "op");
}

/* Integer register-immediate op (0x13). */
static void LiftOpImm(Out *o, uint32_t w) {
  int rd = (w >> 7) & 31, x = (w >> 15) & 31;
  uint32_t f3 = (w >> 12) & 7;
  int32_t imm = (int32_t)w >> 20;
  int hd = Hi(rd);
  if (hd < 0 || rd == X_ZERO) {                                 /* plain dest */
    if (f3 == 1 || f3 == 5) {
      unsigned k = (w >> 20) & 63;
      uint32_t sra = w & (0x20u << 25);
      int hx = HiRd(x);
      if (k >= 32) {                                            /* 64-bit-only shift amount */
        if (f3 == 1) W(o, LI0(rd));
        else W(o, I((int32_t)(k - 32), hx, 5, rd, 0x13) | sra); /* rd = hx >> (k-32) */
        return;
      }
      if (f3 == 5 && k && Hi(x) >= 0) {                         /* low word needs hx's bits */
        W(o, I((int32_t)(32 - k), hx, 1, SC1, 0x13));
        W(o, I((int32_t)k, x, 5, rd, 0x13));
        W(o, OR(rd, rd, SC1));
        return;
      }
    }
    W(o, w);
    return;
  }
  int hx = HiRd(x);
  int32_t sx = imm < 0 ? -1 : 0;
  switch (f3) {
  case 0:
    if (x == X_ZERO) {                                          /* li */
      W(o, w);
      W(o, ADDI(hd, X_ZERO, sx));
      return;
    }
    if (imm == 0 && rd != x) {                                  /* mv: only mv sites use imm 0 with rd != x */
      W(o, MV(rd, x));
      W(o, MV(hd, hx));
      return;
    }
    /* Uses only t6: this form also materializes call targets after the args are loaded. */
    if (rd == x) {
      W(o, ADDI(SC1, x, imm));
      W(o, B(8, x, SC1, 7));                                    /* bgeu t6, x, +8: no carry */
      W(o, ADDI(hd, hd, 1));
      W(o, ADDI(hd, hd, sx));
      W(o, MV(rd, SC1));
    } else {
      W(o, MV(hd, hx));
      W(o, ADDI(rd, x, imm));
      W(o, B(8, x, rd, 7));                                     /* bgeu rd, x, +8 */
      W(o, ADDI(hd, hd, 1));
      W(o, ADDI(hd, hd, sx));
    }
    return;
  case 2: case 3:                                               /* slti/sltiu vs sext(imm) */
    W(o, ADDI(SC1, X_ZERO, sx));
    W(o, R(0, SC1, hx, f3, SC2, 0x33));                         /* slt(u) sc2, hx, sx */
    W(o, B(8, SC1, hx, 1));                                     /* bne hx, sx, +8 */
    W(o, I(imm, x, 3, SC2, 0x13));                              /* sltiu sc2, x, imm */
    W(o, MV(rd, SC2));
    W(o, LI0(hd));
    return;
  case 4: case 6: case 7:                                       /* xori/ori/andi */
    W(o, I(imm, x, f3, SC1, 0x13));
    W(o, I(sx, hx, f3, hd, 0x13));
    W(o, MV(rd, SC1));
    return;
  case 1: case 5: {                                             /* slli/srli/srai by k */
    unsigned k = (w >> 20) & 63;
    int arith = (w >> 30) & 1;
    uint32_t sra = arith ? (0x20u << 25) : 0;
    if (k == 0) {
      W(o, MV(rd, x));
      W(o, MV(hd, hx));
      return;
    }
    if (f3 == 1) {
      if (k >= 32) {
        W(o, I((int32_t)(k - 32), x, 1, hd, 0x13));             /* hd = x << (k-32) */
        W(o, LI0(rd));
      } else {
        W(o, I((int32_t)(32 - k), x, 5, SC1, 0x13));            /* sc1 = x >> (32-k) */
        W(o, I((int32_t)k, hx, 1, SC2, 0x13));                  /* sc2 = hx << k */
        W(o, OR(hd, SC2, SC1));
        W(o, I((int32_t)k, x, 1, rd, 0x13));
      }
      return;
    }
    if (k >= 32) {
      W(o, I((int32_t)(k - 32), hx, 5, SC1, 0x13) | sra);       /* sc1 = hx >> (k-32) */
      if (arith) W(o, I(31, hx, 5, hd, 0x13) | (0x20u << 25)); else W(o, LI0(hd));
      W(o, MV(rd, SC1));
    } else {
      W(o, I((int32_t)(32 - k), hx, 1, SC1, 0x13));             /* sc1 = hx << (32-k) */
      W(o, I((int32_t)k, x, 5, SC2, 0x13));                     /* sc2 = x >> k */
      W(o, OR(rd, SC2, SC1));
      W(o, I((int32_t)k, hx, 5, hd, 0x13) | sra);
    }
    return;
  }
  }
  Unsupported(o, w, "op-imm");
}

/* F64 bits <-> a register pair go through an 8-byte stack slot (rv32 has no fmv.x.d). */
static void PairToF(Out *o, int x, int fd) {
  W(o, ADDI(X_SP, X_SP, -8));
  W(o, S(0, x, X_SP, 2, 0x23));
  W(o, S(4, HiRd(x), X_SP, 2, 0x23));
  W(o, I(0, X_SP, 3, fd, 0x07));                                /* fld fd, 0(sp) */
  W(o, ADDI(X_SP, X_SP, 8));
}
static void FToPair(Out *o, int fs, int rd) {
  int hd = Hi(rd);
  W(o, ADDI(X_SP, X_SP, -8));
  W(o, S(0, fs, X_SP, 3, 0x27));                                /* fsd fs, 0(sp) */
  W(o, I(0, X_SP, 2, rd, 0x03));
  W(o, I(4, X_SP, 2, hd < 0 ? X_ZERO : hd, 0x03));
  W(o, ADDI(X_SP, X_SP, 8));
}

static void LiftFp(Out *o, uint32_t w) {
  uint32_t f7 = w >> 25, f3 = (w >> 12) & 7;
  int rd = (w >> 7) & 31, r1 = (w >> 15) & 31, r2 = (w >> 20) & 31;
  int hd = Hi(rd);
  switch (f7) {
  case 0x79:                                                    /* fmv.d.x fd, x */
    PairToF(o, r1, rd);
    return;
  case 0x71:
    if (f3 == 0) { FToPair(o, r1, rd); return; }                /* fmv.x.d rd, fs */
    W(o, w);                                                    /* fclass */
    if (hd >= 0) W(o, LI0(hd));
    return;
  case 0x69:                                                    /* fcvt.d.{w,wu,l,lu} fd, x */
    if (r2 >= 2) {                                              /* I64: hi * 2^32 + (U32)lo */
      W(o, R(0x69, r2 == 3 ? 1 : 0, HiRd(r1), 7, rd, 0x53));    /* fcvt.d.w(u) fd, hx */
      W(o, (0x80000u << 12) | ((uint32_t)SC1 << 7) | 0x37);     /* lui sc1, 0x80000 */
      W(o, R(0x69, 1, SC1, 7, 1, 0x53));                        /* fcvt.d.wu ft1, sc1 (2^31) */
      W(o, R(0x01, 1, 1, 7, 1, 0x53));                          /* fadd.d ft1, ft1, ft1 (2^32) */
      W(o, R(0x09, 1, rd, 7, rd, 0x53));                        /* fmul.d fd, fd, ft1 */
      W(o, R(0x69, 1, r1, 7, 1, 0x53));                         /* fcvt.d.wu ft1, x */
      W(o, R(0x01, 1, rd, 7, rd, 0x53));                        /* fadd.d fd, fd, ft1 */
      return;
    }
    W(o, w);
    return;
  case 0x61:                                                    /* fcvt.{w,wu,l,lu}.d rd, fs */
    if (r2 == 2) {                                              /* I64 (rtz, as the emitter uses) */
      LiftHelperCall(o, rd, hd < 0 ? X_ZERO : hd, 0, 0, r1, 4);
      return;
    }
    if (r2 >= 2) w = (w & ~(31u << 20)) | ((uint32_t)(r2 - 2) << 20);  /* 32-bit range (PR-8) */
    W(o, w);
    if (hd >= 0) {
      if (r2 == 0 || r2 == 2) W(o, I(31, rd, 5, hd, 0x13) | (0x20u << 25));
      else W(o, LI0(hd));
    }
    return;
  case 0x51:                                                    /* feq/flt/fle */
    W(o, w);
    if (hd >= 0) W(o, LI0(hd));
    return;
  default:
    W(o, w);
    return;
  }
}

int Rv32Lift(uint32_t w, const Rv32LiftEnv *env, Rv32EmitFn emit, void *ctx) {
  Out o = { emit, ctx, 0, env };
  int mode = env->mode;
  uint32_t op = w & 0x7F;
  int rd = (w >> 7) & 31, hd = Hi(rd);
  switch (op) {
  case 0x03: LiftLoad(&o, w, mode); break;
  case 0x23: LiftStore(&o, w, mode); break;
  case 0x13: LiftOpImm(&o, w); break;
  case 0x33: LiftOp(&o, w); break;
  case 0x63: LiftBranch(&o, w); break;
  case 0x53: LiftFp(&o, w); break;
  case 0x37:                                                    /* lui: rv64 sign-extends */
    W(&o, w);
    if (hd >= 0) W(&o, I(31, rd, 5, hd, 0x13) | (0x20u << 25));
    break;
  case 0x17: case 0x6F: case 0x67:                              /* auipc / jal / jalr: addresses */
    W(&o, w);
    if (hd >= 0) W(&o, LI0(hd));
    break;
  case 0x73:                                                    /* csr ops */
    W(&o, w);
    if (hd >= 0 && ((w >> 12) & 7)) W(&o, LI0(hd));
    break;
  case 0x2F:                                                    /* A: .d -> .w (lock word is 0/1) */
    if (((w >> 12) & 7) == 3) w = (w & ~(7u << 12)) | (2u << 12);
    W(&o, w);
    if (hd >= 0) W(&o, LI0(hd));
    break;
  case 0x1B: case 0x3B:
    Unsupported(&o, w, "rv64 *w op");
    break;
  default:                                                      /* fld/fsd, fence, … */
    W(&o, w);
    break;
  }
  return o.n;
}

void Rv32LiftReset(void) { g_warned = 0; }

const uint32_t *Rv32DivmodWords(int *count) {
  *count = (int)(sizeof kRv32DivmodWords / sizeof kRv32DivmodWords[0]);
  return kRv32DivmodWords;
}
