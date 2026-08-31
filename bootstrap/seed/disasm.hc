// disasm.hc -- a RISC-V disassembler in HolyC. Disasm("Name") (or DisasmAt(addr)) prints a
// 28-instruction window; Src() falls back to it for a function with no source. Decodes base
// RV64IM, D-extension floats (incl. fsgnj/fmin/fmax and the RVC float loads/stores), and RVC,
// resolves jal/branch targets from the PC, and shows the raw bytes of anything it cant decode.
// Edit it: Src("DisasmOne"). HolyC wont take a bare no-arg "str"; as an if-body, so Pm(s) prints
// a mnemonic and otherwise the mnemonic goes into a variable printed once with args.
U8 *RN[32] = {"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"};
U8 *FRN[32] = {"ft0", "ft1", "ft2", "ft3", "ft4", "ft5", "ft6", "ft7", "fs0", "fs1", "fa0", "fa1", "fa2", "fa3", "fa4", "fa5", "fa6", "fa7", "fs2", "fs3", "fs4", "fs5", "fs6", "fs7", "fs8", "fs9", "fs10", "fs11", "ft8", "ft9", "ft10", "ft11"};
// Pm -- Pm(s)
// NAME
//   Pm - print a mnemonic string.
// SYNOPSIS
//   Pm(s)
// DESCRIPTION
//   print a mnemonic string.
// INPUTS
//   s - argument
// OUTPUTS
//   print a mnemonic string.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Pm(U8 *s)
{
  "%s", s;
}
// DiImm -- DiImm(v)
// NAME
//   DiImm - print a signed immediate.
// SYNOPSIS
//   DiImm(v)
// DESCRIPTION
//   print a signed immediate.
// INPUTS
//   v - argument
// OUTPUTS
//   print a signed immediate.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 DiImm(I64 v)
{
  if (v < 0) {
    PutCh('-');
    v = -v;
  }
  "0x%X", v;
}
// CSR number -> ABI name (the M-mode set we actually touch), or 0 if unknown.
// CsrN -- CsrN(csr)
// NAME
//   CsrN - CSR number to ABI name string, or NULL.
// SYNOPSIS
//   CsrN(csr)
// DESCRIPTION
//   CSR number to ABI name string, or NULL.
// INPUTS
//   csr - argument
// OUTPUTS
//   CSR number to ABI name string, or NULL.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U8 *CsrN(I64 c)
{
  if (c == 0x300)
    return "mstatus";
  if (c == 0x301)
    return "misa";
  if (c == 0x304)
    return "mie";
  if (c == 0x305)
    return "mtvec";
  if (c == 0x340)
    return "mscratch";
  if (c == 0x341)
    return "mepc";
  if (c == 0x342)
    return "mcause";
  if (c == 0x343)
    return "mtval";
  if (c == 0x344)
    return "mip";
  if (c == 0x180)
    return "satp";
  if (c == 0xF14)
    return "mhartid";
  if (c == 0xB00)
    return "mcycle";
  if (c == 0xB02)
    return "minstret";
  if (c == 0xC00)
    return "cycle";
  if (c == 0xC01)
    return "time";
  if (c == 0xC02)
    return "instret";
  if (c == 0xF11)
    return "mvendorid";
  if (c == 0xF12)
    return "marchid";
  if (c == 0xF13)
    return "mimpid";
  return 0;
}
// PCsr -- PCsr(c)
// NAME
//   PCsr - print a CSR name or hex.
// SYNOPSIS
//   PCsr(c)
// DESCRIPTION
//   print a CSR name or hex.
// INPUTS
//   c - argument
// OUTPUTS
//   print a CSR name or hex.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 PCsr(I64 c)
{
  U8 *n;
  n = CsrN(c);
  if (n)
    Pm(n);
  else
    DiImm(c);
}
// MMIO base -> region name (this board’s MEM_* map), or 0.
// MmN -- MmN(addr)
// NAME
//   MmN - MMIO base address to region name, or NULL.
// SYNOPSIS
//   MmN(addr)
// DESCRIPTION
//   MMIO base address to region name, or NULL.
// INPUTS
//   addr - argument
// OUTPUTS
//   MMIO base address to region name, or NULL.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U8 *MmN(I64 a)
{
  if (a == MEM_CLINT)
    return "CLINT";
  if (a == MEM_PLIC)
    return "PLIC";
  if (a == MEM_UART)
    return "UART0";
  if (a == MEM_VIRTIO)
    return "VIRTIO";
  if (a == MEM_RAM)
    return "DRAM";
  if (a == 0x00001000)
    return "BOOTROM";
  return 0;
}
// " <Name+0xoff>" for a code address that lands in a known function (reverse hash-table lookup).
// Sym -- Sym(addr)
// NAME
//   Sym - print a symbolized address.
// SYNOPSIS
//   Sym(addr)
// DESCRIPTION
//   print a symbolized address.
// INPUTS
//   addr - argument
// OUTPUTS
//   print a symbolized address.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Sym(I64 addr)
{
  U8 *nm;
  I64 base;
  nm = SymName(addr);
  if (!nm)
    return;
  base = SymBase(addr);
  if (addr - base >= 0x4000)
    return;
  // too far past any entry: a heap buffer, not this function
  " <%s+", nm;
  DiImm(addr - base);
  PutCh('>');
}
// " <REGION>" for an upper-immediate that names a known MMIO base.
// MmTag -- MmTag(a)
// NAME
//   MmTag - print MMIO region tag if any.
// SYNOPSIS
//   MmTag(a)
// DESCRIPTION
//   print MMIO region tag if any.
// INPUTS
//   a - argument
// OUTPUTS
//   print MMIO region tag if any.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 MmTag(I64 a)
{
  U8 *m;
  m = MmN(a);
  if (m) {
    " <%s>", m;
  }
}
// Known-constant tracking: HolyC calls are `jalr ra, 0(t0)` with t0 built by lui/addi/slli/ori,
// so symbolizing calls means simulating those chains. KV[r]/KOk[r] = the value register r would
// hold if it came from a tracked constant chain; any other write clears it. DisasmAt resets per
// window and clears everything on a compressed insn (C code; HolyC JIT output is all 32-bit).
I64 KV[32], KOk[32];
// Furthest forward intra-function control-flow target seen during a DisasmAt walk. A ret only
// ends the function if nothing seen so far branches past it -- handles multiple rets (early
// returns in C builtins or hand asm; the JIT itself is single-exit, early returns jump to one
// epilogue). Only intra-function flow updates it: conditional branches, jal zero (goto), c.j,
// c.beqz/c.bnez. jal ra / jalr are calls and dont count.
I64 DisHi;
// DisasmOne -- DisasmOne(addr,w)
// NAME
//   DisasmOne - disassemble one 32-bit insn at addr.
// SYNOPSIS
//   DisasmOne(addr,w)
// DESCRIPTION
//   disassemble one 32-bit insn at addr.
// INPUTS
//   addr - argument
//   w - argument
// OUTPUTS
//   disassemble one 32-bit insn at addr.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 DisasmOne(I64 addr, I64 w)
{
  I64 op, rd, f3, rs1, rs2, f7, immI, immS, csr, jt;
  U8 *mn;
  op = w & 0x7F;
  rd = (w >> 7) & 0x1F;
  f3 = (w >> 12) & 7;
  rs1 = (w >> 15) & 0x1F;
  rs2 = (w >> 20) & 0x1F;
  f7 = (w >> 25) & 0x7F;
  csr = (w >> 20) & 0xFFF;
  immI = (w >> 20) & 0xFFF;
  if (immI & 0x800)
    immI |= ~0xFFF;
  immS = (((w >> 25) & 0x7F) << 5) | ((w >> 7) & 0x1F);
  if (immS & 0x800)
    immS |= ~0xFFF;
  if (w == 0x00000013)
    Pm("nop");
  else if (w == 0x30200073)
    Pm("mret");
  else if (w == 0x10500073)
    Pm("wfi");
  else if (w == 0x0000100F)
    Pm("fence.i");
  else if (w == 0x00008067)
    Pm("ret");
  else if (op == 0x37) {
    "lui %s, ", RN[rd];
    DiImm(w & 0xFFFFF000);
    MmTag(w & 0xFFFFF000);
  } else if (op == 0x17) {
    "auipc %s, ", RN[rd];
    DiImm(w & 0xFFFFF000);
  } else if (op == 0x6F) {
    jt = (((w >> 31) & 1) << 20) | (((w >> 12) & 0xFF) << 12) | (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1);
    if (jt & 0x100000)
      jt |= ~0x1FFFFF;
    "jal %s, 0x%08X", RN[rd], addr + jt;
    Sym(addr + jt);
    if (rd == 0 && addr + jt > DisHi)
      DisHi = addr + jt;
  } else if (op == 0x67) {
    "jalr %s, ", RN[rd];
    DiImm(immI);
    "(%s)", RN[rs1];
    if (KOk[rs1])
      Sym(KV[rs1] + immI);
  } else if (op == 0x13) {
    if (f3 == 0 && rs1 == 0) {
      "li %s, ", RN[rd];
      DiImm(immI);
    } else {
      if (f3 == 0)
        mn = "addi";
      else if (f3 == 1)
        mn = "slli";
      else if (f3 == 2)
        mn = "slti";
      else if (f3 == 3)
        mn = "sltiu";
      else if (f3 == 4)
        mn = "xori";
      else if (f3 == 5) {
        if (f7 & 0x20)
          mn = "srai";
        else
          mn = "srli";
      } else if (f3 == 6)
        mn = "ori";
      else
        mn = "andi";
      "%s %s, %s, ", mn, RN[rd], RN[rs1];
      if (f3 == 1 || f3 == 5)
        DiImm ((w >> 20) & 0x3F);
      else
        DiImm(immI);
    }
  } else if (op == 0x1B) {
    if (f3 == 0)
      mn = "addiw";
    else if (f3 == 1)
      mn = "slliw";
    else
      mn = "srliw";
    "%s %s, %s, ", mn, RN[rd], RN[rs1];
    if (f3 == 0)
      DiImm(immI);
    else
      DiImm(rs2);
  } else if (op == 0x33) {
    if (f7 == 0x20) {
      if (f3 == 0)
        mn = "sub";
      else
        mn = "sra";
    } else if (f7 == 1) {
      if (f3 == 0)
        mn = "mul";
      else if (f3 == 4)
        mn = "div";
      else if (f3 == 5)
        mn = "divu";
      else if (f3 == 6)
        mn = "rem";
      else
        mn = "remu";
    } else {
      if (f3 == 0)
        mn = "add";
      else if (f3 == 1)
        mn = "sll";
      else if (f3 == 2)
        mn = "slt";
      else if (f3 == 3)
        mn = "sltu";
      else if (f3 == 4)
        mn = "xor";
      else if (f3 == 5)
        mn = "srl";
      else if (f3 == 6)
        mn = "or";
      else
        mn = "and";
    }
    "%s %s, %s, %s", mn, RN[rd], RN[rs1], RN[rs2];
  } else if (op == 0x03) {
    if (f3 == 0)
      mn = "lb";
    else if (f3 == 1)
      mn = "lh";
    else if (f3 == 2)
      mn = "lw";
    else if (f3 == 3)
      mn = "ld";
    else if (f3 == 4)
      mn = "lbu";
    else if (f3 == 5)
      mn = "lhu";
    else
      mn = "lwu";
    "%s %s, ", mn, RN[rd];
    DiImm(immI);
    "(%s)", RN[rs1];
  } else if (op == 0x23) {
    if (f3 == 0)
      mn = "sb";
    else if (f3 == 1)
      mn = "sh";
    else if (f3 == 2)
      mn = "sw";
    else
      mn = "sd";
    "%s %s, ", mn, RN[rs2];
    DiImm(immS);
    "(%s)", RN[rs1];
  } else if (op == 0x63) {
    if (f3 == 0)
      mn = "beq";
    else if (f3 == 1)
      mn = "bne";
    else if (f3 == 4)
      mn = "blt";
    else if (f3 == 5)
      mn = "bge";
    else if (f3 == 6)
      mn = "bltu";
    else
      mn = "bgeu";
    jt = (((w >> 31) & 1) << 12) | (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1) | (((w >> 7) & 1) << 11);
    if (jt & 0x1000)
      jt |= ~0x1FFF;
    "%s %s, %s, 0x%08X", mn, RN[rs1], RN[rs2], addr + jt;
    Sym(addr + jt);
    if (addr + jt > DisHi)
      DisHi = addr + jt;
  } else if (op == 0x73) {
    if (f3 == 1)
      mn = "csrrw";
    else if (f3 == 2)
      mn = "csrrs";
    else if (f3 == 3)
      mn = "csrrc";
    else
      mn = "";
    if (mn[0]) {
      "%s %s, ", mn, RN[rd];
      PCsr(csr);
      ", %s", RN[rs1];
    } else {
      if (w == 0x73)
        Pm("ecall");
      else
        Pm("system");
    }
  } else if (op == 0x07 && f3 == 3) {
    "fld %s, ", FRN[rd];
    DiImm(immI);
    "(%s)", RN[rs1];
  } else if (op == 0x27 && f3 == 3) {
    "fsd %s, ", FRN[rs2];
    DiImm(immS);
    "(%s)", RN[rs1];
  } else if (op == 0x53) {
    if (f7 == 0x01) {
      "fadd.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2];
    } else if (f7 == 0x05) {
      "fsub.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2];
    } else if (f7 == 0x09) {
      "fmul.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2];
    } else if (f7 == 0x0D) {
      "fdiv.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2];
    } else if (f7 == 0x2D) {
      "fsqrt.d %s, %s", FRN[rd], FRN[rs1];
    } else if (f7 == 0x11) {
      if (rs1 == rs2) {
        if (f3 == 0)
          mn = "fmv.d";
        else if (f3 == 1)
          mn = "fneg.d";
        else
          mn = "fabs.d";
        "%s %s, %s", mn, FRN[rd], FRN[rs1];
      } else {
        if (f3 == 0)
          mn = "fsgnj.d";
        else if (f3 == 1)
          mn = "fsgnjn.d";
        else
          mn = "fsgnjx.d";
        "%s %s, %s, %s", mn, FRN[rd], FRN[rs1], FRN[rs2];
      }
    } else if (f7 == 0x15) {
      if (f3 == 0)
        mn = "fmin.d";
      else
        mn = "fmax.d";
      "%s %s, %s, %s", mn, FRN[rd], FRN[rs1], FRN[rs2];
    } else if (f7 == 0x51) {
      if (f3 == 0)
        mn = "fle.d";
      else if (f3 == 1)
        mn = "flt.d";
      else
        mn = "feq.d";
      "%s %s, %s, %s", mn, RN[rd], FRN[rs1], FRN[rs2];
    } else if (f7 == 0x79) {
      "fmv.d.x %s, %s", FRN[rd], RN[rs1];
    } else if (f7 == 0x71) {
      if (f3 == 0)
        mn = "fmv.x.d";
      else
        mn = "fclass.d";
      "%s %s, %s", mn, RN[rd], FRN[rs1];
    } else if (f7 == 0x61) {
      if (rs2 == 2)
        mn = "fcvt.l.d";
      else if (rs2 == 3)
        mn = "fcvt.lu.d";
      else if (rs2 == 0)
        mn = "fcvt.w.d";
      else
        mn = "fcvt.wu.d";
      "%s %s, %s", mn, RN[rd], FRN[rs1];
    } else if (f7 == 0x69) {
      if (rs2 == 2)
        mn = "fcvt.d.l";
      else if (rs2 == 3)
        mn = "fcvt.d.lu";
      else if (rs2 == 0)
        mn = "fcvt.d.w";
      else
        mn = "fcvt.d.wu";
      "%s %s, %s", mn, FRN[rd], RN[rs1];
    } else {
      "fp.op f7=";
      DiImm(f7);
      " raw=";
      DiImm(w & 0xFFFFFFFF);
    }
  } else {
    ".word ";
    DiImm(w & 0xFFFFFFFF);
  }
  // Track constant chains for jalr symbolization (see KV/KOk above). lui/auipc sign-extend bit 31.
  if (rd) {
    if (op == 0x37) {
      KV[rd] = w & 0xFFFFF000;
      if (KV[rd] & 0x80000000)
        KV[rd] |= 0xFFFFFFFF00000000;
      KOk[rd] = 1;
    } else if (op == 0x17) {
      jt = w & 0xFFFFF000;
      if (jt & 0x80000000)
        jt |= 0xFFFFFFFF00000000;
      KV[rd] = addr + jt;
      KOk[rd] = 1;
    } else if (op == 0x13 && f3 == 0) {
      if (rs1 == 0) {
        KV[rd] = immI;
        KOk[rd] = 1;
      } else if (KOk[rs1]) {
        KV[rd] = KV[rs1] + immI;
        KOk[rd] = 1;
      } else
        KOk[rd] = 0;
    } else if (op == 0x13 && f3 == 1) {
      if (KOk[rs1]) {
        KV[rd] = KV[rs1] << ((w >> 20) & 0x3F);
        KOk[rd] = 1;
      } else
        KOk[rd] = 0;
    } else if (op == 0x13 && f3 == 5 && !(f7 & 0x20)) {
      // srli is a LOGICAL shift but HolyC >> on I64 is arithmetic -- mask off the smeared sign bits.
      if (KOk[rs1]) {
        jt = (w >> 20) & 0x3F;
        KV[rd] = KV[rs1] >> jt;
        if (jt)
          KV[rd] &= (1 << (64 - jt)) - 1;
        KOk[rd] = 1;
      } else
        KOk[rd] = 0;
    } else if (op == 0x03 && f3 == 3) {
      // ld from a tracked address: we are IN the live system, so peek the actual memory -- this is
      // how a call through an import slot (`ld t0,0(t0); jalr ra,0(t0)`) gets its real target name.
      if (KOk[rs1] && KV[rs1] + immI >= 0x80000000 && KV[rs1] + immI < 0x88000000) {
        KV[rd] = *(I64 *)(KV[rs1] + immI);
        KOk[rd] = 1;
      } else
        KOk[rd] = 0;
    } else if (op == 0x13 && f3 == 6) {
      if (KOk[rs1]) {
        KV[rd] = KV[rs1] | (immI & 0xFFF);
        KOk[rd] = 1;
      } else
        KOk[rd] = 0;
    } else if (op == 0x23 || op == 0x63 || op == 0x27) {
    }
    // stores/branches: rd bits are immediate, no write
    else KOk[rd] = 0;
    // anything else that writes rd kills the chain
  }
  "\n";
}
// DisasmC -- DisasmC(addr,w)
// NAME
//   DisasmC - disassemble one RVC insn at addr.
// SYNOPSIS
//   DisasmC(addr,w)
// DESCRIPTION
//   disassemble one RVC insn at addr.
// INPUTS
//   addr - argument
//   w - argument
// OUTPUTS
//   disassemble one RVC insn at addr.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 DisasmC(I64 addr, I64 w)
{
  I64 op, f3, rd, rs2, rdp, rs1p, imm, u, sh, f2, ff, b12, jt;
  U8 *mn;
  op = w & 3;
  f3 = (w >> 13) & 7;
  rd = (w >> 7) & 0x1F;
  rs2 = (w >> 2) & 0x1F;
  rdp = ((w >> 2) & 7) + 8;
  rs1p = ((w >> 7) & 7) + 8;
  if (w == 0x0000)
    Pm("illegal");
  else if (w == 0x0001)
    Pm("c.nop");
  else if (w == 0x9002)
    Pm("c.ebreak");
  else if (op == 0) {
    if (f3 == 0) {
      u = ((w >> 7) & 0x30) | ((w >> 1) & 0x3C0) | ((w >> 4) & 4) | ((w >> 2) & 8);
      "c.addi4spn %s, sp, ", RN[rdp];
      DiImm(u);
    } else if (f3 == 1) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0xC0);
      "c.fld %s, ", FRN[rdp];
      DiImm(u);
      "(%s)", RN[rs1p];
    } else if (f3 == 2) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0x40) | ((w >> 4) & 4);
      "c.lw %s, ", RN[rdp];
      DiImm(u);
      "(%s)", RN[rs1p];
    } else if (f3 == 3) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0xC0);
      "c.ld %s, ", RN[rdp];
      DiImm(u);
      "(%s)", RN[rs1p];
    } else if (f3 == 5) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0xC0);
      "c.fsd %s, ", FRN[rdp];
      DiImm(u);
      "(%s)", RN[rs1p];
    } else if (f3 == 6) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0x40) | ((w >> 4) & 4);
      "c.sw %s, ", RN[rdp];
      DiImm(u);
      "(%s)", RN[rs1p];
    } else if (f3 == 7) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0xC0);
      "c.sd %s, ", RN[rdp];
      DiImm(u);
      "(%s)", RN[rs1p];
    } else {
      ".chalf ";
      DiImm(w & 0xFFFF);
    }
  } else if (op == 1) {
    imm = ((w >> 2) & 0x1F) | ((w >> 7) & 0x20);
    if (imm & 0x20)
      imm |= ~0x3F;
    if (f3 == 0) {
      if (rd == 0)
        Pm("c.nop");
      else {
        "c.addi %s, ", RN[rd];
        DiImm(imm);
      }
    } else if (f3 == 1) {
      "c.addiw %s, ", RN[rd];
      DiImm(imm);
    } else if (f3 == 2) {
      "c.li %s, ", RN[rd];
      DiImm(imm);
    } else if (f3 == 3) {
      if (rd == 2) {
        imm = ((w >> 3) & 0x200) | ((w << 4) & 0x180) | ((w << 1) & 0x40) | ((w << 3) & 0x20) | ((w >> 2) & 0x10);
        if (imm & 0x200)
          imm |= ~0x3FF;
        "c.addi16sp sp, ";
        DiImm(imm);
      } else {
        imm = (((w >> 2) & 0x1F) << 12) | (((w >> 12) & 1) << 17);
        if (imm & 0x20000)
          imm |= ~0x3FFFF;
        "c.lui %s, ", RN[rd];
        DiImm(imm);
      }
    } else if (f3 == 4) {
      f2 = (w >> 10) & 3;
      sh = ((w >> 2) & 0x1F) | ((w >> 7) & 0x20);
      if (f2 == 0) {
        "c.srli %s, ", RN[rs1p];
        DiImm(sh);
      } else if (f2 == 1) {
        "c.srai %s, ", RN[rs1p];
        DiImm(sh);
      } else if (f2 == 2) {
        imm = sh;
        if (imm & 0x20)
          imm |= ~0x3F;
        "c.andi %s, ", RN[rs1p];
        DiImm(imm);
      } else {
        ff = (w >> 5) & 3;
        if ((w >> 12) & 1) {
          if (ff == 0)
            mn = "c.subw";
          else
            mn = "c.addw";
        } else {
          if (ff == 0)
            mn = "c.sub";
          else if (ff == 1)
            mn = "c.xor";
          else if (ff == 2)
            mn = "c.or";
          else
            mn = "c.and";
        }
        "%s %s, %s", mn, RN[rs1p], RN[rdp];
      }
    } else if (f3 == 5) {
      jt = (((w >> 12) & 1) << 11) | (((w >> 11) & 1) << 4) | (((w >> 9) & 3) << 8) | (((w >> 8) & 1) << 10) | (((w >> 7) & 1) << 6) | (((w >> 6) & 1) << 7) | (((w >> 3) & 7) << 1) | (((w >> 2) & 1) << 5);
      if (jt & 0x800)
        jt |= ~0xFFF;
      "c.j 0x%08X", addr + jt;
      if (addr + jt > DisHi)
        DisHi = addr + jt;
    } else {
      jt = (((w >> 12) & 1) << 8) | (((w >> 10) & 3) << 3) | (((w >> 5) & 3) << 6) | (((w >> 3) & 3) << 1) | (((w >> 2) & 1) << 5);
      if (jt & 0x100)
        jt |= ~0x1FF;
      if (f3 == 6) {
        "c.beqz %s, 0x%08X", RN[rs1p], addr + jt;
      } else {
        "c.bnez %s, 0x%08X", RN[rs1p], addr + jt;
      }
      if (addr + jt > DisHi)
        DisHi = addr + jt;
    }
  } else if (op == 2) {
    if (f3 == 0) {
      sh = ((w >> 2) & 0x1F) | ((w >> 7) & 0x20);
      "c.slli %s, ", RN[rd];
      DiImm(sh);
    } else if (f3 == 1) {
      u = ((w >> 7) & 0x20) | ((w >> 2) & 0x18) | ((w << 4) & 0x1C0);
      "c.fldsp %s, ", FRN[rd];
      DiImm(u);
      "(sp)";
    } else if (f3 == 2) {
      u = ((w >> 7) & 0x20) | ((w >> 2) & 0x1C) | ((w << 4) & 0xC0);
      "c.lwsp %s, ", RN[rd];
      DiImm(u);
      "(sp)";
    } else if (f3 == 3) {
      u = ((w >> 7) & 0x20) | ((w >> 2) & 0x18) | ((w << 4) & 0x1C0);
      "c.ldsp %s, ", RN[rd];
      DiImm(u);
      "(sp)";
    } else if (f3 == 4) {
      b12 = (w >> 12) & 1;
      if (!b12) {
        if (rs2 == 0) {
          "c.jr %s", RN[rd];
        } else {
          "c.mv %s, %s", RN[rd], RN[rs2];
        }
      } else {
        if (rd == 0 && rs2 == 0)
          Pm("c.ebreak");
        else if (rs2 == 0) {
          "c.jalr %s", RN[rd];
        } else {
          "c.add %s, %s", RN[rd], RN[rs2];
        }
      }
    } else if (f3 == 5) {
      u = ((w >> 7) & 0x38) | ((w >> 1) & 0x1C0);
      "c.fsdsp %s, ", FRN[rs2];
      DiImm(u);
      "(sp)";
    } else if (f3 == 6) {
      u = ((w >> 7) & 0x3C) | ((w >> 1) & 0xC0);
      "c.swsp %s, ", RN[rs2];
      DiImm(u);
      "(sp)";
    } else {
      u = ((w >> 7) & 0x38) | ((w >> 1) & 0x1C0);
      "c.sdsp %s, ", RN[rs2];
      DiImm(u);
      "(sp)";
    }
  } else {
    ".chalf ";
    DiImm(w & 0xFFFF);
  }
  "\n";
}
// DisasmAt(addr, max=2000) -- disassemble from addr until the functions ret (0x8067 or the
// compressed c.ret 0x8082), capped at max instructions. The default cap makes Disasm("Name")
// cover a whole function; pass a small max for a fixed window (DisasmAt(a, 28)).
// DisasmAt -- DisasmAt(addr,max,end)
// NAME
//   DisasmAt - disassemble a window at addr.
// SYNOPSIS
//   DisasmAt(addr,max,end)
// DESCRIPTION
//   disassemble a window at addr.
// INPUTS
//   addr - argument
//   max - argument
//   end - argument
// OUTPUTS
//   disassemble a window at addr.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 DisasmAt(I64 addr, I64 max = 2000, I64 end = 0)
{
  I64 i, lo, w, k;
  for (k = 0; k < 32; k++)
    KOk[k] = 0;
  DisHi = 0;
  "; disassembly @ 0x%08X\n", addr;
  i = 0;
  while (i < max) {
    if (end && addr >= end)
      return;
    // exact bound (Uf: the hash entrys recorded size)
    lo = *(U16 *)addr;
    "0x%08X:  ", addr;
    if ((lo & 3) != 3) {
      DisasmC(addr, lo);
      if (lo == 0x8082 && addr >= DisHi)
        return;
      // c.ret ends the fn unless a branch jumps past it
      addr += 2;
      for (k = 0; k < 32; k++)
        KOk[k] = 0;
    } else {
      w = *(U32 *)addr;
      DisasmOne(addr, w);
      if (w == 0x00008067 && addr >= DisHi)
        return;
      // ret ends the fn unless a branch jumps past it
      addr += 4;
    }
    i++;
  }
}
// Uf("Name") -- unassemble a function, TempleOS style: the hash entry records the code size, so
// the walk is exact. A C builtin has size 0 (the compiler never saw it); fall back to the
// ret-stop heuristic there. U(addr, n=28) is the raw-address window. Disasm stays as an alias.
// Uf -- Uf(name)
// NAME
//   Uf - disassemble a named function.
// SYNOPSIS
//   Uf(name)
// DESCRIPTION
//   disassemble a named function.
// INPUTS
//   name - argument
// OUTPUTS
//   disassemble a named function.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Uf(U8 *name)
{
  I64 a, n;
  a = FnAddr(name);
  if (!a) {
    "Uf: no such function: %s\n", name;
    return;
  }
  n = FnSize(name);
  if (n) {
    "; %s (%d bytes):\n", name, n;
    DisasmAt(a, 100000, a + n);
  } else {
    "; %s:\n", name;
    DisasmAt(a);
  }
}
// U -- U(addr,n)
// NAME
//   U - disassemble n insns at addr.
// SYNOPSIS
//   U(addr,n)
// DESCRIPTION
//   disassemble n insns at addr.
// INPUTS
//   addr - argument
//   n - argument
// OUTPUTS
//   disassemble n insns at addr.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 U(I64 addr, I64 n = 28)
{
  DisasmAt(addr, n);
}
// Disasm -- Disasm(name)
// NAME
//   Disasm - alias of Uf.
// SYNOPSIS
//   Disasm(name)
// DESCRIPTION
//   alias of Uf.
// INPUTS
//   name - argument
// OUTPUTS
//   alias of Uf.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Disasm(U8 *name)
{
  Uf(name);
}
