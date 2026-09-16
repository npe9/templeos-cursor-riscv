// RVDisasm.HC — RISC-V disassembler for the win/VT kernel (Disasm/U/UA/DisasmAt).
// Ported from bootstrap/seed/disasm.hc; the seed's raw hash walker (sym.hc) is replaced by
// typed CHashTable lookups over the current task's chain (HTT_FUN exe_addr/size, plus
// HTT_EXPORT_SYS_SYM values for Kernel exports). Bare "fmt",args; statements became Print().
#help_index "Debugging/Unassemble"
extern U0 DisAsmNamesInit();

I64 RVDisFnAddr(U8 *name)
{
  CHashFun *tmpf;
  CHashExport *tmpex;
  if (!name || !Fs || !Fs->hash_table)
    return 0;
  tmpf = HashFind(name, Fs->hash_table, HTT_FUN);
  if (tmpf)
    return tmpf->exe_addr;
  tmpex = HashFind(name, Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (tmpex)
    return tmpex->val;
  return 0;
}

I64 RVDisFnSize(U8 *name)
{
  CHashFun *tmpf;
  if (!name || !Fs || !Fs->hash_table)
    return 0;
  tmpf = HashFind(name, Fs->hash_table, HTT_FUN);
  if (tmpf)
    return tmpf->size;
  return 0;
}

CHashExport *RVDisSymNearest(I64 addr)
{
  //Nearest HTT_FUN / HTT_EXPORT_SYS_SYM at or below addr, walking the task hash chain.
  CHashTable *table;
  CHashExport *tmpex, *best = NULL;
  CHashFun *tmpf;
  I64 i, ea, sz, best_ea = 0;
  if (!Fs)
    return NULL;
  table = Fs->hash_table;
  while (table) {
    for (i = 0; i <= table->mask; i++) {
      tmpex = table->body[i];
      while (tmpex) {
        ea = 0;
        sz = 0;
        if (tmpex->type & HTT_FUN) {
          tmpf = tmpex;
          ea = tmpf->exe_addr;
          sz = tmpf->size;
        } else if (tmpex->type & HTT_EXPORT_SYS_SYM)
          ea = tmpex->val;
        if (ea && ea <= addr && (!sz || addr < ea + sz) && ea > best_ea) {
          best = tmpex;
          best_ea = ea;
        }
        tmpex = tmpex->next;
      }
    }
    table = table->next;
  }
  return best;
}

I64 RVDisSymBase(I64 addr)
{
  CHashExport *e = RVDisSymNearest(addr);
  if (!e)
    return 0;
  if (e->type & HTT_FUN)
    return e(CHashFun *)->exe_addr;
  return e->val;
}

U8 *RVDisSymName(I64 addr)
{
  CHashExport *e = RVDisSymNearest(addr);
  if (!e)
    return NULL;
  return e->str;
}

// disasm.hc -- a RISC-V disassembler in HolyC. Disasm("Name") (or DisasmAt(addr)) prints a
// 28-instruction window; Src() falls back to it for a function with no source. Decodes base
// RV64IMA (incl. lr/sc/amo* atomics), D-extension floats (incl. fsgnj/fmin/fmax and the RVC
// float loads/stores), and RVC,
// resolves jal/branch targets from the PC, and shows the raw bytes of anything it cant decode.
// Edit it: Src("DisasmOne"). HolyC wont take a bare no-arg "str"; as an if-body, so Pm(s) prints
// a mnemonic and otherwise the mnemonic goes into a variable printed once with args.
U8 *RN[32] = {"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"};
U8 *FRN[32] = {"ft0", "ft1", "ft2", "ft3", "ft4", "ft5", "ft6", "ft7", "fs0", "fs1", "fa0", "fa1", "fa2", "fa3", "fa4", "fa5", "fa6", "fa7", "fs2", "fs3", "fs4", "fs5", "fs6", "fs7", "fs8", "fs9", "fs10", "fs11", "ft8", "ft9", "ft10", "ft11"};
// DisAsmMode=1 (UA): assemblable source for asm{}. Labs hold in-window branch targets.
I64 DisAsmMode;
I64 DisAsmLo;
I64 DisAsmHi;
I64 DisAsmLabs[128];
I64 DisAsmLabN;
// DisAsmLabClear -- DisAsmLabClear()
U0 DisAsmLabClear()
{
  DisAsmLabN = 0;
}
// DisAsmLabAdd -- DisAsmLabAdd(t)
U0 DisAsmLabAdd(I64 t)
{
  I64 i;
  if (t < DisAsmLo || t >= DisAsmHi)
    return;
  for (i = 0; i < DisAsmLabN; i++)
    if (DisAsmLabs[i] == t)
      return;
  if (DisAsmLabN < 128) {
    DisAsmLabs[DisAsmLabN] = t;
    DisAsmLabN++;
  }
}
// DisAsmLabHas -- DisAsmLabHas(a)
I64 DisAsmLabHas(I64 a)
{
  I64 i;
  for (i = 0; i < DisAsmLabN; i++)
    if (DisAsmLabs[i] == a)
      return 1;
  return 0;
}
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
  Print("%s", s);
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
    PutChars('-');
    v = -v;
  }
  Print("0x%X", v);
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
  if (DisAsmMode)
    return;
  nm = RVDisSymName(addr);
  if (!nm)
    return;
  base = RVDisSymBase(addr);
  if (addr - base >= 0x4000)
    return;
  // too far past any entry: a heap buffer, not this function
  Print(" <%s+", nm);
  DiImm(addr - base);
  PutChars('>');
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
  if (DisAsmMode)
    return;
  m = MmN(a);
  if (m) {
    Print(" <%s>", m);
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
  I64 op, rd, f3, rs1, rs2, f7, immI, immS, csr, jt, f5;
  U8 *mn;
  U8 *sfx;
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
  else if (w == 0x0000100F) {
    if (DisAsmMode)
      Pm("fencei");
    else
      Pm("fence.i");
  } else if (w == 0x00008067)
    Pm("ret");
  else if (op == 0x37) {
    Print("lui %s, ", RN[rd]);
    if (DisAsmMode)
      DiImm ((w >> 12) & 0xFFFFF);
    else {
      DiImm(w & 0xFFFFF000);
      MmTag(w & 0xFFFFF000);
    }
  } else if (op == 0x17) {
    Print("auipc %s, ", RN[rd]);
    if (DisAsmMode)
      DiImm ((w >> 12) & 0xFFFFF);
    else
      DiImm(w & 0xFFFFF000);
  } else if (op == 0x6F) {
    jt = (((w >> 31) & 1) << 20) | (((w >> 12) & 0xFF) << 12) | (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1);
    if (jt & 0x100000)
      jt |= ~0x1FFFFF;
    if (DisAsmMode) {
      // TryAssembleRiscV: j label (rd=0) only — no bare jal
      if (rd == 0 && DisAsmLabHas(addr + jt))
        Print("j L_%08X", addr + jt);
      else if (rd == 0) {
        Print("; j 0x%08X (outside window)\n", addr + jt);
        goto disasm_one_track;
      } else {
        Print("; jal %s, 0x%08X (use j/call)\n", RN[rd], addr + jt);
        goto disasm_one_track;
      }
    } else {
      Print("jal %s, 0x%08X", RN[rd], addr + jt);
      Sym(addr + jt);
    }
    if (rd == 0 && addr + jt > DisHi)
      DisHi = addr + jt;
  } else if (op == 0x67) {
    Print("jalr %s, ", RN[rd]);
    DiImm(immI);
    Print("(%s)", RN[rs1]);
    if (KOk[rs1])
      Sym(KV[rs1] + immI);
  } else if (op == 0x13) {
    if (f3 == 0 && rs1 == 0) {
      Print("li %s, ", RN[rd]);
      DiImm(immI);
    } else if (DisAsmMode && f3 == 0 && immI == 0) {
      Print("mv %s, %s", RN[rd], RN[rs1]);
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
      if (DisAsmMode && f3 == 3) {
        Print("; sltiu %s, %s, ", RN[rd], RN[rs1]);
        DiImm(immI);
        Print(" (no sltiu in asm{})\n");
        goto disasm_one_track;
      }
      Print("%s %s, %s, ", mn, RN[rd], RN[rs1]);
      if (f3 == 1 || f3 == 5)
        DiImm ((w >> 20) & 0x3F);
      else
        DiImm(immI);
    }
  } else if (op == 0x1B) {
    // OP-IMM-32 (RV64 word): addiw (f3=0), slliw (f3=1), srliw/sraiw (f3=5).
    if (f3 == 0)
      mn = "addiw";
    else if (f3 == 1)
      mn = "slliw";
    else if (f3 == 5) {
      if (f7 & 0x20)
        mn = "sraiw";
      else
        mn = "srliw";
    } else
      mn = "addiw";
    Print("%s %s, %s, ", mn, RN[rd], RN[rs1]);
    if (f3 == 0)
      DiImm(immI);
    else
      DiImm(rs2);
  } else if (op == 0x3B) {
    // OP-32 (RV64 word): addw/subw sllw srlw/sraw mulw divw divuw remw remuw.
    if (f7 == 0x20) {
      if (f3 == 0)
        mn = "subw";
      else
        mn = "sraw";
    } else if (f7 == 1) {
      if (f3 == 0)
        mn = "mulw";
      else if (f3 == 4)
        mn = "divw";
      else if (f3 == 5)
        mn = "divuw";
      else if (f3 == 6)
        mn = "remw";
      else
        mn = "remuw";
    } else {
      if (f3 == 0)
        mn = "addw";
      else if (f3 == 1)
        mn = "sllw";
      else
        mn = "srlw";
    }
    Print("%s %s, %s, %s", mn, RN[rd], RN[rs1], RN[rs2]);
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
    Print("%s %s, %s, %s", mn, RN[rd], RN[rs1], RN[rs2]);
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
    Print("%s %s, ", mn, RN[rd]);
    DiImm(immI);
    Print("(%s)", RN[rs1]);
  } else if (op == 0x23) {
    if (f3 == 0)
      mn = "sb";
    else if (f3 == 1)
      mn = "sh";
    else if (f3 == 2)
      mn = "sw";
    else
      mn = "sd";
    Print("%s %s, ", mn, RN[rs2]);
    DiImm(immS);
    Print("(%s)", RN[rs1]);
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
    if (DisAsmMode) {
      if (DisAsmLabHas(addr + jt))
        Print("%s %s, %s, L_%08X", mn, RN[rs1], RN[rs2], addr + jt);
      else {
        Print("; %s %s, %s, 0x%08X (outside window)\n", mn, RN[rs1], RN[rs2], addr + jt);
        goto disasm_one_track;
      }
    } else {
      Print("%s %s, %s, 0x%08X", mn, RN[rs1], RN[rs2], addr + jt);
      Sym(addr + jt);
    }
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
      Print("%s %s, ", mn, RN[rd]);
      PCsr(csr);
      Print(", %s", RN[rs1]);
    } else {
      if (w == 0x73)
        Pm("ecall");
      else
        Pm("system");
    }
  } else if (op == 0x07 && f3 == 3) {
    if (DisAsmMode) {
      Print("; fld (no fld in asm{})\n");
      goto disasm_one_track;
    }
    Print("fld %s, ", FRN[rd]);
    DiImm(immI);
    Print("(%s)", RN[rs1]);
  } else if (op == 0x27 && f3 == 3) {
    if (DisAsmMode) {
      Print("; fsd (no fsd in asm{})\n");
      goto disasm_one_track;
    }
    Print("fsd %s, ", FRN[rs2]);
    DiImm(immS);
    Print("(%s)", RN[rs1]);
  } else if (op == 0x53) {
    if (f7 == 0x01) {
      if (DisAsmMode)
        Print("faddd %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]);
      else
        Print("fadd.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]);
    } else if (f7 == 0x05) {
      if (DisAsmMode)
        Print("fsubd %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]);
      else
        Print("fsub.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]);
    } else if (f7 == 0x09) {
      if (DisAsmMode)
        Print("fmuld %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]);
      else
        Print("fmul.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]);
    } else if (f7 == 0x0D) {
      if (DisAsmMode)
        Print("fdivd %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]);
      else
        Print("fdiv.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]);
    } else if (f7 == 0x2D) {
      if (DisAsmMode)
        Print("fsqrtd %s, %s", FRN[rd], FRN[rs1]);
      else
        Print("fsqrt.d %s, %s", FRN[rd], FRN[rs1]);
    } else if (f7 == 0x11) {
      if (rs1 == rs2) {
        if (f3 == 0)
          mn = "fmv.d";
        else if (f3 == 1)
          mn = "fneg.d";
        else
          mn = "fabs.d";
        if (DisAsmMode) {
          Print("; %s (pseudo; no asm{} form)\n", mn);
          goto disasm_one_track;
        }
        Print("%s %s, %s", mn, FRN[rd], FRN[rs1]);
      } else {
        if (f3 == 0)
          mn = "fsgnj.d";
        else if (f3 == 1)
          mn = "fsgnjn.d";
        else
          mn = "fsgnjx.d";
        if (DisAsmMode) {
          Print("; %s (no asm{} form)\n", mn);
          goto disasm_one_track;
        }
        Print("%s %s, %s, %s", mn, FRN[rd], FRN[rs1], FRN[rs2]);
      }
    } else if (f7 == 0x15) {
      if (f3 == 0)
        mn = "fmin.d";
      else
        mn = "fmax.d";
      if (DisAsmMode) {
        Print("; %s (no asm{} form)\n", mn);
        goto disasm_one_track;
      }
      Print("%s %s, %s, %s", mn, FRN[rd], FRN[rs1], FRN[rs2]);
    } else if (f7 == 0x51) {
      if (f3 == 0)
        mn = "fle.d";
      else if (f3 == 1)
        mn = "flt.d";
      else
        mn = "feq.d";
      if (DisAsmMode) {
        if (f3 == 0)
          mn = "fled";
        else if (f3 == 1)
          mn = "fltd";
        else
          mn = "feqd";
        Print("%s %s, %s, %s", mn, RN[rd], FRN[rs1], FRN[rs2]);
      } else
        Print("%s %s, %s, %s", mn, RN[rd], FRN[rs1], FRN[rs2]);
    } else if (f7 == 0x79) {
      if (DisAsmMode)
        Print("fmvdx %s, %s", FRN[rd], RN[rs1]);
      else
        Print("fmv.d.x %s, %s", FRN[rd], RN[rs1]);
    } else if (f7 == 0x71) {
      if (f3 == 0)
        mn = "fmv.x.d";
      else
        mn = "fclass.d";
      if (DisAsmMode) {
        if (f3 == 0)
          Print("fmvxd %s, %s", RN[rd], FRN[rs1]);
        else {
          Print("; fclass.d (no asm{} form)\n");
          goto disasm_one_track;
        }
      } else
        Print("%s %s, %s", mn, RN[rd], FRN[rs1]);
    } else if (f7 == 0x61) {
      if (rs2 == 2)
        mn = "fcvt.l.d";
      else if (rs2 == 3)
        mn = "fcvt.lu.d";
      else if (rs2 == 0)
        mn = "fcvt.w.d";
      else
        mn = "fcvt.wu.d";
      if (DisAsmMode) {
        if (rs2 == 2)
          Print("fcvtld_rtz %s, %s", RN[rd], FRN[rs1]);
        else {
          Print("; %s (limited asm{} fcvt)\n", mn);
          goto disasm_one_track;
        }
      } else
        Print("%s %s, %s", mn, RN[rd], FRN[rs1]);
    } else if (f7 == 0x69) {
      if (rs2 == 2)
        mn = "fcvt.d.l";
      else if (rs2 == 3)
        mn = "fcvt.d.lu";
      else if (rs2 == 0)
        mn = "fcvt.d.w";
      else
        mn = "fcvt.d.wu";
      if (DisAsmMode) {
        if (rs2 == 2)
          Print("fcvtdl %s, %s", FRN[rd], RN[rs1]);
        else {
          Print("; %s (limited asm{} fcvt)\n", mn);
          goto disasm_one_track;
        }
      } else
        Print("%s %s, %s", mn, FRN[rd], RN[rs1]);
    } else {
      if (DisAsmMode) {
        Print("; fp.op f7=");
        DiImm(f7);
        Print(" raw=");
        DiImm(w & 0xFFFFFFFF);
        Print("\n");
        goto disasm_one_track;
      }
      Print("fp.op f7=");
      DiImm(f7);
      Print(" raw=");
      DiImm(w & 0xFFFFFFFF);
    }
  } else if (op == 0x2F) {
    // A extension (atomics). funct5 = bits[31:27] = f7>>2; f3 3=.d 2=.w.
    // Mirrors the assembler's RvAsmA encodings so U/Uf round-trips them.
    f5 = (f7 >> 2) & 0x1F;
    sfx = ".d";
    if (f3 == 2)
      sfx = ".w";
    mn = 0;
    if (f3 == 3 || f3 == 2) {
      if (f5 == 0x02)
        mn = "lr";
      else if (f5 == 0x03)
        mn = "sc";
      else if (f5 == 0x01)
        mn = "amoswap";
      else if (f5 == 0x00)
        mn = "amoadd";
      else if (f5 == 0x04)
        mn = "amoxor";
      else if (f5 == 0x0C)
        mn = "amoand";
      else if (f5 == 0x08)
        mn = "amoor";
      else if (f5 == 0x10)
        mn = "amomin";
      else if (f5 == 0x14)
        mn = "amomax";
      else if (f5 == 0x18)
        mn = "amominu";
      else if (f5 == 0x1C)
        mn = "amomaxu";
    }
    if (!mn) {
      if (DisAsmMode) {
        Print("; raw ");
        DiImm(w & 0xFFFFFFFF);
        Print(" (not in TryAssembleRiscV)\n");
        goto disasm_one_track;
      }
      Print(".word ");
      DiImm(w & 0xFFFFFFFF);
    } else if (f5 == 0x02) {
      // lr rd, (rs1) — no rs2 source
      Print("%s%s %s, (%s)", mn, sfx, RN[rd], RN[rs1]);
    } else {
      // sc / amo* rd, rs2, (rs1)
      Print("%s%s %s, %s, (%s)", mn, sfx, RN[rd], RN[rs2], RN[rs1]);
    }
  } else {
    if (DisAsmMode) {
      Print("; raw ");
      DiImm(w & 0xFFFFFFFF);
      Print(" (not in TryAssembleRiscV)\n");
      goto disasm_one_track;
    }
    Print(".word ");
    DiImm(w & 0xFFFFFFFF);
  }
  Print("\n");
  disasm_one_track:
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
  // UA/asm{} has no c.* forms — expand common RVC to 32-bit mnemonics TryAssembleRiscV knows.
  if (DisAsmMode) {
    op = w & 3;
    f3 = (w >> 13) & 7;
    rd = (w >> 7) & 0x1F;
    rs2 = (w >> 2) & 0x1F;
    rdp = ((w >> 2) & 7) + 8;
    rs1p = ((w >> 7) & 7) + 8;
    if (w == 0x0000) {
      Print("; illegal RVC\n");
      return;
    }
    if (w == 0x0001) {
      Pm("nop\n");
      return;
    }
    if (w == 0x9002) {
      Pm("ebreak\n");
      return;
    }
    if (op == 0) {
      if (f3 == 0) {
        u = ((w >> 7) & 0x30) | ((w >> 1) & 0x3C0) | ((w >> 4) & 4) | ((w >> 2) & 8);
        Print("addi %s, sp, ", RN[rdp]);
        DiImm(u);
        Print("\n");
        return;
      }
      if (f3 == 2) {
        u = ((w >> 7) & 0x38) | ((w << 1) & 0x40) | ((w >> 4) & 4);
        Print("lw %s, ", RN[rdp]);
        DiImm(u);
        Print("(%s)\n", RN[rs1p]);
        return;
      }
      if (f3 == 3) {
        u = ((w >> 7) & 0x38) | ((w << 1) & 0xC0);
        Print("ld %s, ", RN[rdp]);
        DiImm(u);
        Print("(%s)\n", RN[rs1p]);
        return;
      }
      if (f3 == 6) {
        u = ((w >> 7) & 0x38) | ((w << 1) & 0x40) | ((w >> 4) & 4);
        Print("sw %s, ", RN[rdp]);
        DiImm(u);
        Print("(%s)\n", RN[rs1p]);
        return;
      }
      if (f3 == 7) {
        u = ((w >> 7) & 0x38) | ((w << 1) & 0xC0);
        Print("sd %s, ", RN[rdp]);
        DiImm(u);
        Print("(%s)\n", RN[rs1p]);
        return;
      }
      Print("; RVC 0x%X (no asm{} expansion)\n", w & 0xFFFF);
      return;
    }
    if (op == 1) {
      imm = ((w >> 2) & 0x1F) | ((w >> 7) & 0x20);
      if (imm & 0x20)
        imm |= ~0x3F;
      if (f3 == 0) {
        if (rd == 0)
          Pm("nop\n");
        else {
          Print("addi %s, %s, ", RN[rd], RN[rd]);
          DiImm(imm);
          Print("\n");
        }
        return;
      }
      if (f3 == 2) {
        Print("li %s, ", RN[rd]);
        DiImm(imm);
        Print("\n");
        return;
      }
      if (f3 == 3) {
        if (rd == 2) {
          imm = ((w >> 3) & 0x200) | ((w << 4) & 0x180) | ((w << 1) & 0x40) | ((w << 3) & 0x20) | ((w >> 2) & 0x10);
          if (imm & 0x200)
            imm |= ~0x3FF;
          Print("addi sp, sp, ");
          DiImm(imm);
          Print("\n");
        } else {
          imm = (((w >> 2) & 0x1F) << 12) | (((w >> 12) & 1) << 17);
          if (imm & 0x20000)
            imm |= ~0x3FFFF;
          Print("lui %s, ", RN[rd]);
          DiImm ((imm >> 12) & 0xFFFFF);
          Print("\n");
        }
        return;
      }
      if (f3 == 4) {
        f2 = (w >> 10) & 3;
        sh = ((w >> 2) & 0x1F) | ((w >> 7) & 0x20);
        if (f2 == 0) {
          Print("srli %s, %s, ", RN[rs1p], RN[rs1p]);
          DiImm(sh);
          Print("\n");
        } else if (f2 == 1) {
          Print("srai %s, %s, ", RN[rs1p], RN[rs1p]);
          DiImm(sh);
          Print("\n");
        } else if (f2 == 2) {
          imm = sh;
          if (imm & 0x20)
            imm |= ~0x3F;
          Print("andi %s, %s, ", RN[rs1p], RN[rs1p]);
          DiImm(imm);
          Print("\n");
        } else {
          ff = (w >> 5) & 3;
          if ((w >> 12) & 1) {
            Print("; RVC W-op 0x%X\n", w & 0xFFFF);
          } else {
            if (ff == 0)
              Print("sub %s, %s, %s\n", RN[rs1p], RN[rs1p], RN[rdp]);
            else if (ff == 1)
              Print("xor %s, %s, %s\n", RN[rs1p], RN[rs1p], RN[rdp]);
            else if (ff == 2)
              Print("or %s, %s, %s\n", RN[rs1p], RN[rs1p], RN[rdp]);
            else
              Print("and %s, %s, %s\n", RN[rs1p], RN[rs1p], RN[rdp]);
          }
        }
        return;
      }
      if (f3 == 5) {
        jt = (((w >> 12) & 1) << 11) | (((w >> 11) & 1) << 4) | (((w >> 9) & 3) << 8) | (((w >> 8) & 1) << 10) | (((w >> 7) & 1) << 6) | (((w >> 6) & 1) << 7) | (((w >> 3) & 7) << 1) | (((w >> 2) & 1) << 5);
        if (jt & 0x800)
          jt |= ~0xFFF;
        if (DisAsmLabHas(addr + jt))
          Print("j L_%08X\n", addr + jt);
        else
          Print("; j 0x%08X (outside window)\n", addr + jt);
        if (addr + jt > DisHi)
          DisHi = addr + jt;
        return;
      }
      jt = (((w >> 12) & 1) << 8) | (((w >> 10) & 3) << 3) | (((w >> 5) & 3) << 6) | (((w >> 3) & 3) << 1) | (((w >> 2) & 1) << 5);
      if (jt & 0x100)
        jt |= ~0x1FF;
      if (f3 == 6)
        mn = "beq";
      else
        mn = "bne";
      if (DisAsmLabHas(addr + jt))
        Print("%s %s, zero, L_%08X\n", mn, RN[rs1p], addr + jt);
      else
        Print("; %s %s, zero, 0x%08X (outside)\n", mn, RN[rs1p], addr + jt);
      if (addr + jt > DisHi)
        DisHi = addr + jt;
      return;
    }
    if (op == 2) {
      if (f3 == 0) {
        sh = ((w >> 2) & 0x1F) | ((w >> 7) & 0x20);
        Print("slli %s, %s, ", RN[rd], RN[rd]);
        DiImm(sh);
        Print("\n");
        return;
      }
      if (f3 == 2) {
        u = ((w >> 7) & 0x20) | ((w >> 2) & 0x1C) | ((w << 4) & 0xC0);
        Print("lw %s, ", RN[rd]);
        DiImm(u);
        Print("(sp)\n");
        return;
      }
      if (f3 == 3) {
        u = ((w >> 7) & 0x20) | ((w >> 2) & 0x18) | ((w << 4) & 0x1C0);
        Print("ld %s, ", RN[rd]);
        DiImm(u);
        Print("(sp)\n");
        return;
      }
      if (f3 == 4) {
        b12 = (w >> 12) & 1;
        if (!b12) {
          if (rs2 == 0)
            Print("jalr zero, 0(%s)\n", RN[rd]);
          else
            Print("mv %s, %s\n", RN[rd], RN[rs2]);
        } else {
          if (rd == 0 && rs2 == 0)
            Pm("ebreak\n");
          else if (rs2 == 0)
            Print("jalr ra, 0(%s)\n", RN[rd]);
          else
            Print("add %s, %s, %s\n", RN[rd], RN[rd], RN[rs2]);
        }
        return;
      }
      if (f3 == 6) {
        u = ((w >> 7) & 0x3C) | ((w >> 1) & 0xC0);
        Print("sw %s, ", RN[rs2]);
        DiImm(u);
        Print("(sp)\n");
        return;
      }
      if (f3 == 7) {
        u = ((w >> 7) & 0x38) | ((w >> 1) & 0x1C0);
        Print("sd %s, ", RN[rs2]);
        DiImm(u);
        Print("(sp)\n");
        return;
      }
    }
    Print("; RVC 0x%X (no asm{} expansion)\n", w & 0xFFFF);
    return;
  }
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
      Print("c.addi4spn %s, sp, ", RN[rdp]);
      DiImm(u);
    } else if (f3 == 1) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0xC0);
      Print("c.fld %s, ", FRN[rdp]);
      DiImm(u);
      Print("(%s)", RN[rs1p]);
    } else if (f3 == 2) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0x40) | ((w >> 4) & 4);
      Print("c.lw %s, ", RN[rdp]);
      DiImm(u);
      Print("(%s)", RN[rs1p]);
    } else if (f3 == 3) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0xC0);
      Print("c.ld %s, ", RN[rdp]);
      DiImm(u);
      Print("(%s)", RN[rs1p]);
    } else if (f3 == 5) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0xC0);
      Print("c.fsd %s, ", FRN[rdp]);
      DiImm(u);
      Print("(%s)", RN[rs1p]);
    } else if (f3 == 6) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0x40) | ((w >> 4) & 4);
      Print("c.sw %s, ", RN[rdp]);
      DiImm(u);
      Print("(%s)", RN[rs1p]);
    } else if (f3 == 7) {
      u = ((w >> 7) & 0x38) | ((w << 1) & 0xC0);
      Print("c.sd %s, ", RN[rdp]);
      DiImm(u);
      Print("(%s)", RN[rs1p]);
    } else {
      Print(".chalf ");
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
        Print("c.addi %s, ", RN[rd]);
        DiImm(imm);
      }
    } else if (f3 == 1) {
      Print("c.addiw %s, ", RN[rd]);
      DiImm(imm);
    } else if (f3 == 2) {
      Print("c.li %s, ", RN[rd]);
      DiImm(imm);
    } else if (f3 == 3) {
      if (rd == 2) {
        imm = ((w >> 3) & 0x200) | ((w << 4) & 0x180) | ((w << 1) & 0x40) | ((w << 3) & 0x20) | ((w >> 2) & 0x10);
        if (imm & 0x200)
          imm |= ~0x3FF;
        Print("c.addi16sp sp, ");
        DiImm(imm);
      } else {
        imm = (((w >> 2) & 0x1F) << 12) | (((w >> 12) & 1) << 17);
        if (imm & 0x20000)
          imm |= ~0x3FFFF;
        Print("c.lui %s, ", RN[rd]);
        DiImm(imm);
      }
    } else if (f3 == 4) {
      f2 = (w >> 10) & 3;
      sh = ((w >> 2) & 0x1F) | ((w >> 7) & 0x20);
      if (f2 == 0) {
        Print("c.srli %s, ", RN[rs1p]);
        DiImm(sh);
      } else if (f2 == 1) {
        Print("c.srai %s, ", RN[rs1p]);
        DiImm(sh);
      } else if (f2 == 2) {
        imm = sh;
        if (imm & 0x20)
          imm |= ~0x3F;
        Print("c.andi %s, ", RN[rs1p]);
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
        Print("%s %s, %s", mn, RN[rs1p], RN[rdp]);
      }
    } else if (f3 == 5) {
      jt = (((w >> 12) & 1) << 11) | (((w >> 11) & 1) << 4) | (((w >> 9) & 3) << 8) | (((w >> 8) & 1) << 10) | (((w >> 7) & 1) << 6) | (((w >> 6) & 1) << 7) | (((w >> 3) & 7) << 1) | (((w >> 2) & 1) << 5);
      if (jt & 0x800)
        jt |= ~0xFFF;
      Print("c.j 0x%08X", addr + jt);
      if (addr + jt > DisHi)
        DisHi = addr + jt;
    } else {
      jt = (((w >> 12) & 1) << 8) | (((w >> 10) & 3) << 3) | (((w >> 5) & 3) << 6) | (((w >> 3) & 3) << 1) | (((w >> 2) & 1) << 5);
      if (jt & 0x100)
        jt |= ~0x1FF;
      if (f3 == 6) {
        Print("c.beqz %s, 0x%08X", RN[rs1p], addr + jt);
      } else {
        Print("c.bnez %s, 0x%08X", RN[rs1p], addr + jt);
      }
      if (addr + jt > DisHi)
        DisHi = addr + jt;
    }
  } else if (op == 2) {
    if (f3 == 0) {
      sh = ((w >> 2) & 0x1F) | ((w >> 7) & 0x20);
      Print("c.slli %s, ", RN[rd]);
      DiImm(sh);
    } else if (f3 == 1) {
      u = ((w >> 7) & 0x20) | ((w >> 2) & 0x18) | ((w << 4) & 0x1C0);
      Print("c.fldsp %s, ", FRN[rd]);
      DiImm(u);
      Print("(sp)");
    } else if (f3 == 2) {
      u = ((w >> 7) & 0x20) | ((w >> 2) & 0x1C) | ((w << 4) & 0xC0);
      Print("c.lwsp %s, ", RN[rd]);
      DiImm(u);
      Print("(sp)");
    } else if (f3 == 3) {
      u = ((w >> 7) & 0x20) | ((w >> 2) & 0x18) | ((w << 4) & 0x1C0);
      Print("c.ldsp %s, ", RN[rd]);
      DiImm(u);
      Print("(sp)");
    } else if (f3 == 4) {
      b12 = (w >> 12) & 1;
      if (!b12) {
        if (rs2 == 0) {
          Print("c.jr %s", RN[rd]);
        } else {
          Print("c.mv %s, %s", RN[rd], RN[rs2]);
        }
      } else {
        if (rd == 0 && rs2 == 0)
          Pm("c.ebreak");
        else if (rs2 == 0) {
          Print("c.jalr %s", RN[rd]);
        } else {
          Print("c.add %s, %s", RN[rd], RN[rs2]);
        }
      }
    } else if (f3 == 5) {
      u = ((w >> 7) & 0x38) | ((w >> 1) & 0x1C0);
      Print("c.fsdsp %s, ", FRN[rs2]);
      DiImm(u);
      Print("(sp)");
    } else if (f3 == 6) {
      u = ((w >> 7) & 0x3C) | ((w >> 1) & 0xC0);
      Print("c.swsp %s, ", RN[rs2]);
      DiImm(u);
      Print("(sp)");
    } else {
      u = ((w >> 7) & 0x38) | ((w >> 1) & 0x1C0);
      Print("c.sdsp %s, ", RN[rs2]);
      DiImm(u);
      Print("(sp)");
    }
  } else {
    Print(".chalf ");
    DiImm(w & 0xFFFF);
  }
  Print("\n");
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
  if (!RN[0])
    DisAsmNamesInit;
  for (k = 0; k < 32; k++)
    KOk[k] = 0;
  DisHi = 0;
  if (!DisAsmMode)
    Print("; disassembly @ 0x%08X\n", addr);
  i = 0;
  while (i < max) {
    if (end && addr >= end)
      return;
    // exact bound (Uf: the hash entrys recorded size)
    lo = *(U16 *)addr;
    if (DisAsmMode && DisAsmLabHas(addr))
      Print("L_%08X:\n", addr);
    if (!DisAsmMode)
      Print("0x%08X:  ", addr);
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
// RVUf("Name") -- unassemble a function, TempleOS style: the hash entry records the code size, so
// the walk is exact. A C builtin has size 0 (the compiler never saw it); fall back to the
// ret-stop heuristic there. U(addr, n=28) is the raw-address window. Disasm stays as an alias.
// Uf -- RVUf(name)
// NAME
//   Uf - disassemble a named function
// SYNOPSIS
//   U0 RVUf(U8 *name);
// DESCRIPTION
//   Prints RISC-V assembly for a named function (TempleOS Uf). Uses the hash size
//   when known; otherwise walks until a ret. Alias: Disasm. Raw windows: U(addr,n).
// EXAMPLES
//   RVUf("Print");
//   Disasm("Dir");
//   U(RVDisFnAddr("Print"), 8);
// SEE ALSO
//   Disasm  U  UA  FnAddr  FnSize  Src  Man
// BUGS
//   C builtins have size 0 — heuristic stop at ret.
U0 RVUf(U8 *name)
{
  I64 a, n;
  a = RVDisFnAddr(name);
  if (!a) {
    Print("Uf: no such function: %s\n", name);
    return;
  }
  n = RVDisFnSize(name);
  if (n) {
    Print("; %s (%d bytes):\n", name, n);
    DisasmAt(a, 100000, a + n);
  } else {
    Print("; %s:\n", name);
    DisasmAt(a);
  }
}
// U -- U(addr,n)
// NAME
//   U - disassemble n insns at addr
// SYNOPSIS
//   U0 U(I64 addr, I64 n=28);
// DESCRIPTION
//   Raw-address unassemble window (TempleOS U). Default 28 insns. After a fault,
//   pc (and _RIP) hold the trapped mepc — dig-down with U(pc-16); or U(_RIP);
//   like TempleOS U(_RIP-16). Named functions: RVUf("Name"). Assemblable source:
//   UA(addr) / UAsm(addr).
// EXAMPLES
//   U(RVDisFnAddr("Print"), 8);
//   U(pc-16);
//   U(_RIP);
// SEE ALSO
//   UA  UAsm  Uf  Disasm  pc  _RIP  FnAddr  Dr  Regs
// BUGS
//   pc is last trap PC, not a live sampler of the REPL eval IP.
U0 U(I64 addr, I64 n = 28)
{
  DisAsmMode = 0;
  DisasmAt(addr, n);
}
// DisAsmCollect -- walk a window and record branch/jal targets for UA labels.
U0 DisAsmCollect(I64 addr, I64 max)
{
  I64 i, lo, w, op, jt, a;
  a = addr;
  DisAsmLo = addr;
  DisAsmHi = addr + max * 4;
  DisAsmLabClear();
  i = 0;
  while (i < max) {
    lo = *(U16 *)a;
    if ((lo & 3) != 3) {
      op = lo & 3;
      if (op == 1 && ((lo >> 13) & 7) == 5) {
        jt = (((lo >> 12) & 1) << 11) | (((lo >> 11) & 1) << 4) | (((lo >> 9) & 3) << 8) | (((lo >> 8) & 1) << 10) | (((lo >> 7) & 1) << 6) | (((lo >> 6) & 1) << 7) | (((lo >> 3) & 7) << 1) | (((lo >> 2) & 1) << 5);
        if (jt & 0x800)
          jt |= ~0xFFF;
        DisAsmLabAdd(a + jt);
      } else if (op == 1 && (((lo >> 13) & 7) == 6 || ((lo >> 13) & 7) == 7)) {
        jt = (((lo >> 12) & 1) << 8) | (((lo >> 10) & 3) << 3) | (((lo >> 5) & 3) << 6) | (((lo >> 3) & 3) << 1) | (((lo >> 2) & 1) << 5);
        if (jt & 0x100)
          jt |= ~0x1FF;
        DisAsmLabAdd(a + jt);
      }
      a += 2;
    } else {
      w = *(U32 *)a;
      op = w & 0x7F;
      if (op == 0x6F) {
        jt = (((w >> 31) & 1) << 20) | (((w >> 12) & 0xFF) << 12) | (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1);
        if (jt & 0x100000)
          jt |= ~0x1FFFFF;
        DisAsmLabAdd(a + jt);
      } else if (op == 0x63) {
        jt = (((w >> 31) & 1) << 12) | (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1) | (((w >> 7) & 1) << 11);
        if (jt & 0x1000)
          jt |= ~0x1FFF;
        DisAsmLabAdd(a + jt);
      }
      a += 4;
    }
    i++;
  }
}
// UA -- UA(addr,n)
// NAME
//   UA - print assemblable RISC-V source at addr
// SYNOPSIS
//   U0 UA(I64 addr, I64 n=28);
// DESCRIPTION
//   Like U(addr,n) but emits lines meant to paste into REPL asm { … }.
//   Uses ABI register names and TryAssembleRiscV / asm_complete mnemonics
//   (li/mv/addi/ld/…, fencei, faddd…). No address prefixes or <Sym> tags.
//   In-window branches become j/beq … L_%08X with matching labels. RVC is
//   expanded to 32-bit forms where possible. Alias: UAsm.
// EXAMPLES
//   UA(RVDisFnAddr("U"), 12);
//   UA(pc-16);
//   // then wrap the printed lines in:  asm { … };
// SEE ALSO
//   U  UAsm  Uf  Disasm  asm_complete
// BUGS
//   Bare jal (rd!=0) and out-of-window branches are commented — asm{} has
//   j/call only. W-ops (addiw…), sltiu, some FP, and .word are comments.
//   Pseudo vs raw: li/mv/ret preferred; RVC float loads stay as comments.
U0 UA(I64 addr, I64 n = 28)
{
  DisAsmMode = 1;
  DisAsmCollect(addr, n);
  DisasmAt(addr, n);
  DisAsmMode = 0;
}
// UAsm -- UAsm(addr,n)
// NAME
//   UAsm - alias of UA
// SYNOPSIS
//   U0 UAsm(I64 addr, I64 n=28);
// DESCRIPTION
//   Alias of UA — assemblable disassembly for asm{}.
// EXAMPLES
//   UAsm(RVDisFnAddr("Print"), 8);
// SEE ALSO
//   UA  U
U0 UAsm(I64 addr, I64 n = 28)
{
  UA(addr, n);
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
  RVUf(name);
}
// DisAsmNamesInit -- fill RN/FRN when the braced lists above never ran.
// NAME
//   DisAsmNamesInit - populate the ABI register-name tables
// SYNOPSIS
//   U0 DisAsmNamesInit();
// DESCRIPTION
//   `U8 *RN[32] = {…}` is a file-scope store, not baked data, so a path that
//   skips top-level statements leaves it zeroed and every register disassembles
//   as "(null)". Nothing needs this on the AOT or JIT/blob paths any more —
//   keep it for a guest that loads only this file. Re-storing is harmless.
// SEE ALSO
//   U  Uf  UA  Disasm
U0 DisAsmNamesInit()
{
  RN[0] = "zero";
  RN[1] = "ra";
  RN[2] = "sp";
  RN[3] = "gp";
  RN[4] = "tp";
  RN[5] = "t0";
  RN[6] = "t1";
  RN[7] = "t2";
  RN[8] = "s0";
  RN[9] = "s1";
  RN[10] = "a0";
  RN[11] = "a1";
  RN[12] = "a2";
  RN[13] = "a3";
  RN[14] = "a4";
  RN[15] = "a5";
  RN[16] = "a6";
  RN[17] = "a7";
  RN[18] = "s2";
  RN[19] = "s3";
  RN[20] = "s4";
  RN[21] = "s5";
  RN[22] = "s6";
  RN[23] = "s7";
  RN[24] = "s8";
  RN[25] = "s9";
  RN[26] = "s10";
  RN[27] = "s11";
  RN[28] = "t3";
  RN[29] = "t4";
  RN[30] = "t5";
  RN[31] = "t6";
  FRN[0] = "ft0";
  FRN[1] = "ft1";
  FRN[2] = "ft2";
  FRN[3] = "ft3";
  FRN[4] = "ft4";
  FRN[5] = "ft5";
  FRN[6] = "ft6";
  FRN[7] = "ft7";
  FRN[8] = "fs0";
  FRN[9] = "fs1";
  FRN[10] = "fa0";
  FRN[11] = "fa1";
  FRN[12] = "fa2";
  FRN[13] = "fa3";
  FRN[14] = "fa4";
  FRN[15] = "fa5";
  FRN[16] = "fa6";
  FRN[17] = "fa7";
  FRN[18] = "fs2";
  FRN[19] = "fs3";
  FRN[20] = "fs4";
  FRN[21] = "fs5";
  FRN[22] = "fs6";
  FRN[23] = "fs7";
  FRN[24] = "fs8";
  FRN[25] = "fs9";
  FRN[26] = "fs10";
  FRN[27] = "fs11";
  FRN[28] = "ft8";
  FRN[29] = "ft9";
  FRN[30] = "ft10";
  FRN[31] = "ft11";
}

// ---- Breakpoints: Bp(addr) plants EBREAK; the trap returns to the prompt (recovery) with a
// symbolized report and every breakpoint restored (stock Bp/BpClr shape; no Step yet). ----
#define RV_BP_MAX 16
I64 rv_bp_addr[RV_BP_MAX];
I64 rv_bp_orig[RV_BP_MAX];
I64 rv_bp_n;

U0 RVBpFence()
{
  asm {FENCEI};
}

I64 RVBpFind(I64 addr)
{
  I64 i;
  for (i = 0; i < rv_bp_n; i++)
    if (rv_bp_addr[i] == addr)
      return i;
  return -1;
}

U0 RVBpSymPrint(I64 addr)
{
  U8 *nm = RVDisSymName(addr);
  if (nm)
    Print(" <%s+0x%X>", nm, addr - RVDisSymBase(addr));
}

U0 RVBpList()
{
  I64 i;
  if (!rv_bp_n)
    Print("Bp: none\n");
  for (i = 0; i < rv_bp_n; i++) {
    Print("Bp #%d %08X", i, rv_bp_addr[i]);
    RVBpSymPrint(rv_bp_addr[i]);
    Print("\n");
  }
}

I64 RVBp(I64 addr = 0)
{
  //Bp(addr): set a breakpoint (EBREAK) at a code address; Bp() lists. Returns count.
  if (!addr) {
    RVBpList;
    return rv_bp_n;
  }
  if (addr & 1 || !RVWinSerialInRam(addr)) {
    Print("Bp: bad code address %08X\n", addr);
    return -1;
  }
  if (RVBpFind(addr) >= 0)
    return rv_bp_n;
  if (rv_bp_n >= RV_BP_MAX) {
    Print("Bp: table full (%d)\n", RV_BP_MAX);
    return -1;
  }
  rv_bp_addr[rv_bp_n] = addr;
  rv_bp_orig[rv_bp_n] = *(U32 *)addr;
  rv_bp_n++;
  *(U32 *)addr = 0x00100073;   // ebreak (4 bytes: a compressed insn there loses its neighbor until restore)
  RVBpFence;
  Print("Bp set at %08X", addr);
  RVBpSymPrint(addr);
  Print("\n");
  return rv_bp_n;
}

I64 RVBpClr(I64 addr = 0)
{
  //BpClr(addr): restore one breakpoint; BpClr() restores all. Returns remaining count.
  I64 i, j;
  for (i = rv_bp_n - 1; i >= 0; i--) {
    if (addr && rv_bp_addr[i] != addr)
      continue;
    *(U32 *)rv_bp_addr[i] = rv_bp_orig[i];
    for (j = i; j < rv_bp_n - 1; j++) {
      rv_bp_addr[j] = rv_bp_addr[j + 1];
      rv_bp_orig[j] = rv_bp_orig[j + 1];
    }
    rv_bp_n--;
  }
  RVBpFence;
  return rv_bp_n;
}

U0 RVBpRestoreAll()
{
  RVBpClr(0);
}
