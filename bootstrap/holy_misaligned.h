/* M-mode emulation of misaligned loads and stores (mcause 4 = load, 6 = store/AMO).
 *
 * QEMU performs misaligned accesses natively, so nothing in this file ever runs under -M virt or
 * -M sifive_u. The SiFive U74 traps them, and OpenSBI emulates them only for S/U-mode: a kernel
 * that owns M-mode is on its own. TempleOS classes are packed — the first one found on the
 * HiFive Unmatched was an I64 at offset 100 of CBlkDev (BlkDevLock+0x114, mtval=0x82044834) —
 * so this is the whole codebase, not one call site, and the fix belongs in the trap handler.
 *
 * Pure C except the FP register moves (guarded by __riscv, stubbed on the host), so the decoder
 * and the byte-wise execution are unit-tested on the Mac by tests/host/misaligned_emu_test.c
 * against a fake frame and buffer. The frame layout is HolyTrapVector's: xN at frame[N], x2 (sp)
 * not stored. AMOs are not emulated: they cannot be done atomically byte-wise, so they fall
 * through to the crash path as before. */
#ifndef HOLY_MISALIGNED_H
#define HOLY_MISALIGNED_H

typedef struct {
  int is_store, is_fp, width, sign_ext, reg, len;
} HolyMisInsn;

/* Decode a 32-bit or 16-bit instruction. Returns 0 for anything that is not a plain load/store. */
static int HolyMisDecode(unsigned int insn, HolyMisInsn *d) {
  d->is_store = 0; d->is_fp = 0; d->sign_ext = 0; d->width = 0; d->reg = 0;
  if ((insn & 3) == 3) {
    unsigned op = insn & 0x7f, f3 = (insn >> 12) & 7;
    d->len = 4;
    if (op == 0x03 || op == 0x07) {                 /* LOAD, LOAD-FP */
      d->reg = (insn >> 7) & 31;
      d->is_fp = (op == 0x07);
      switch (f3) {
        case 0: d->width = 1; d->sign_ext = 1; break;   /* lb  */
        case 1: d->width = 2; d->sign_ext = 1; break;   /* lh  / (no flh) */
        case 2: d->width = 4; d->sign_ext = 1; break;   /* lw  / flw */
        case 3: d->width = 8; break;                    /* ld  / fld */
        case 4: d->width = 1; break;                    /* lbu */
        case 5: d->width = 2; break;                    /* lhu */
        case 6: d->width = 4; break;                    /* lwu */
        default: return 0;
      }
      if (d->is_fp) { if (f3 != 2 && f3 != 3) return 0; d->sign_ext = 0; }
      return 1;
    }
    if (op == 0x23 || op == 0x27) {                 /* STORE, STORE-FP */
      d->is_store = 1;
      d->reg = (insn >> 20) & 31;                     /* rs2 = the data register */
      d->is_fp = (op == 0x27);
      if (f3 > 3) return 0;
      d->width = 1 << f3;
      if (d->is_fp && f3 < 2) return 0;
      return 1;
    }
    return 0;
  }
  {
    unsigned q = insn & 3, f3 = (insn >> 13) & 7;
    d->len = 2;
    if (q == 0) {                                   /* quadrant 0: rd'/rs2' in bits 4:2 */
      unsigned r = 8 + ((insn >> 2) & 7);
      switch (f3) {
        case 1: d->is_fp = 1; d->width = 8; d->reg = r; return 1;                  /* c.fld */
        case 2: d->width = 4; d->sign_ext = 1; d->reg = r; return 1;               /* c.lw  */
        case 3: d->width = 8; d->reg = r; return 1;                                /* c.ld  */
        case 5: d->is_store = 1; d->is_fp = 1; d->width = 8; d->reg = r; return 1; /* c.fsd */
        case 6: d->is_store = 1; d->width = 4; d->reg = r; return 1;               /* c.sw  */
        case 7: d->is_store = 1; d->width = 8; d->reg = r; return 1;               /* c.sd  */
        default: return 0;
      }
    }
    if (q == 2) {                                   /* quadrant 2: stack-pointer forms */
      unsigned rd = (insn >> 7) & 31, rs2 = (insn >> 2) & 31;
      switch (f3) {
        case 1: d->is_fp = 1; d->width = 8; d->reg = rd; return 1;                   /* c.fldsp */
        case 2: if (!rd) return 0; d->width = 4; d->sign_ext = 1; d->reg = rd; return 1; /* c.lwsp */
        case 3: if (!rd) return 0; d->width = 8; d->reg = rd; return 1;              /* c.ldsp  */
        case 5: d->is_store = 1; d->is_fp = 1; d->width = 8; d->reg = rs2; return 1; /* c.fsdsp */
        case 6: d->is_store = 1; d->width = 4; d->reg = rs2; return 1;               /* c.swsp  */
        case 7: d->is_store = 1; d->width = 8; d->reg = rs2; return 1;               /* c.sdsp  */
        default: return 0;
      }
    }
    return 0;
  }
}

static unsigned long long HolyMisLoadBytes(unsigned long addr, int width) {
  volatile unsigned char *p = (volatile unsigned char *)addr;
  unsigned long long v = 0;
  int i;
  for (i = width - 1; i >= 0; i--) v = (v << 8) | p[i];
  return v;
}
static void HolyMisStoreBytes(unsigned long addr, int width, unsigned long long v) {
  volatile unsigned char *p = (volatile unsigned char *)addr;
  int i;
  for (i = 0; i < width; i++) p[i] = (unsigned char)(v >> (8 * i));
}

#ifdef __riscv
#define HOLY_MIS_FR(n) case n: __asm__ volatile("fmv.x.d %0, f" #n : "=r"(v)); break;
#define HOLY_MIS_FW(n) case n: __asm__ volatile("fmv.d.x f" #n ", %0" :: "r"(v)); break;
#define HOLY_MIS_F32(M) M(0) M(1) M(2) M(3) M(4) M(5) M(6) M(7) M(8) M(9) M(10) M(11) M(12) M(13) M(14) M(15) \
  M(16) M(17) M(18) M(19) M(20) M(21) M(22) M(23) M(24) M(25) M(26) M(27) M(28) M(29) M(30) M(31)
static unsigned long long HolyMisFpRead(int r) { unsigned long long v = 0; switch (r) { HOLY_MIS_F32(HOLY_MIS_FR) } return v; }
static void HolyMisFpWrite(int r, unsigned long long v) { switch (r) { HOLY_MIS_F32(HOLY_MIS_FW) } }
#else
/* Host unit test: the FP file is an array. */
static unsigned long long holy_mis_host_f[32];
static unsigned long long HolyMisFpRead(int r) { return holy_mis_host_f[r & 31]; }
static void HolyMisFpWrite(int r, unsigned long long v) { holy_mis_host_f[r & 31] = v; }
#endif

static unsigned long long holy_mis_count;   /* emulated accesses, for a REPL to report */

/* Emulate the misaligned access at epc that faulted on addr. Returns the instruction length to
 * skip (2 or 4) or 0 to decline, in which case the caller treats it as an ordinary fault. */
static int HolyMisalignedEmu(long long *frame, unsigned long epc, unsigned long addr) {
  unsigned int insn = *(volatile unsigned short *)epc;
  HolyMisInsn d;
  if ((insn & 3) == 3) insn |= (unsigned int)*(volatile unsigned short *)(epc + 2) << 16;
  if (!HolyMisDecode(insn, &d)) return 0;
  if (!d.is_fp && d.reg == 2) return 0;   /* sp is not in the frame; never seen from a compiler */
  if (d.is_store) {
    unsigned long long v = d.is_fp ? HolyMisFpRead(d.reg) : (d.reg ? (unsigned long long)frame[d.reg] : 0);
    HolyMisStoreBytes(addr, d.width, v);
  } else {
    unsigned long long v = HolyMisLoadBytes(addr, d.width);
    if (d.sign_ext && d.width < 8) { int sh = 64 - 8 * d.width; v = (unsigned long long)(((long long)(v << sh)) >> sh); }
    if (d.is_fp) { if (d.width == 4) v |= 0xffffffff00000000ULL; HolyMisFpWrite(d.reg, v); }   /* NaN-box flw */
    else if (d.reg) frame[d.reg] = (long long)v;
  }
  holy_mis_count++;
  return d.len;
}
#endif
