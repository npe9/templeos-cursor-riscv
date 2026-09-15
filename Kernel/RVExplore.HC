// RVExplore.HC - RISC-V exploration tooling for the guest-compiler REPL.
// Ported from the retired thin-JIT seed (bootstrap/seed/{asm_doc,csr}.hc): the same
// instruction catalog + CSR decoders, but callable HolyC functions planted through the
// compiler (RVExePubs). UartStr/PutCh -> Print; ternaries -> helpers (HolyC has no ?:).
// Duplication note: the RISC-V mnemonic set also lives in Compiler/Asm_RV.HC (parser) and
// Kernel/RVDisasm.HC (formatter); AsmDocRaw here is the *documentation* table (mnemonic +
// operand template + notes) - a different shape/consumer, not redundant. See
// docs/STOCK_PARITY.md and the AsmList<->assembler drift test.

#define ASM_DOC_MN 32
#define ASM_DOC_TPL 64
#define ASM_DOC_ENC 8
#define ASM_DOC_IMM 24
#define ASM_DOC_GNU 64
#define ASM_DOC_NOTE 96
U8 *rv_asm_doc_raw;
U0 RVAsmDocRawInit()
{
  rv_asm_doc_raw = "add|add rd, rs, rs|R|||R-type add;" "addi|addi rd, rs, imm|I|-2048..2047||12-bit signed immediate;" "sub|sub rd, rs, rs|R|||R-type subtract;" "and|and rd, rs, rs|R|||R-type AND;" "andi|andi rd, rs, imm|I|-2048..2047||bitwise AND immediate;" "or|or rd, rs, rs|R|||R-type OR;" "ori|ori rd, rs, imm|I|-2048..2047||bitwise OR immediate;" "xor|xor rd, rs, rs|R|||R-type XOR;" "xori|xori rd, rs, imm|I|-2048..2047||bitwise XOR immediate;" "sll|sll rd, rs, rs|R|||shift left logical;" "slli|slli rd, rs, shamt|I|0..63||shift amount in low 6 bits;" "srl|srl rd, rs, rs|R|||shift right logical;" "srli|srli rd, rs, shamt|I|0..63||logical shift right immediate;" "sra|sra rd, rs, rs|R|||shift right arithmetic;" "srai|srai rd, rs, shamt|I|0..63||arithmetic shift right immediate;" "slt|slt rd, rs, rs|R|||set less than (signed);" "slti|slti rd, rs, imm|I|-2048..2047||set less than immediate;" "sltu|sltu rd, rs, rs|R|||set less than unsigned;" "mul|mul rd, rs, rs|R|||M-extension multiply;" "div|div rd, rs, rs|R|||signed divide;" "divu|divu rd, rs, rs|R|||unsigned divide;" "rem|rem rd, rs, rs|R|||signed remainder;" "remu|remu rd, rs, rs|R|||unsigned remainder;" "lui|lui rd, imm|U|0..0xFFFFF||load upper immediate (20-bit field);" "auipc|auipc rd, imm|U|0..0xFFFFF||PC-relative upper immediate;" "li|li rd, imm|pseudo||+/-2047 addi; else GNU as lui+addiw|load immediate (wide matches GNU as lui+addiw);" "mv|mv rd, rs|pseudo||addi rd, rs, 0|move register;" "not|not rd, rs|pseudo||xori rd, rs, -1|bitwise NOT;" "neg|neg rd, rs|pseudo||sub rd, zero, rs|two's-complement negation;" "seqz|seqz rd, rs|pseudo||sltiu rd, rs, 1|set if equal to zero;" "snez|snez rd, rs|pseudo||sltu rd, zero, rs|set if not equal to zero;" "ld|ld rd, imm(rs)|I|-2048..2047||load doubleword;" "lw|lw rd, imm(rs)|I|-2048..2047||load word;" "lwu|lwu rd, imm(rs)|I|-2048..2047||load word unsigned;" "lh|lh rd, imm(rs)|I|-2048..2047||load halfword;" "lhu|lhu rd, imm(rs)|I|-2048..2047||load halfword unsigned;" "lb|lb rd, imm(rs)|I|-2048..2047||load byte;" "lbu|lbu rd, imm(rs)|I|-2048..2047||load byte unsigned;" "sd|sd rs, imm(rd)|S|-2048..2047||store doubleword;" "sw|sw rs, imm(rd)|S|-2048..2047||store word;" "sh|sh rs, imm(rd)|S|-2048..2047||store halfword;" "sb|sb rs, imm(rd)|S|-2048..2047||store byte;" "jalr|jalr rd, imm(rs)|I|-2048..2047||jump and link register (short: jalr rs -> jalr ra,0(rs));" "j|j label|pseudo||jal x0, label|unconditional jump;" "jr|jr rs|pseudo||jalr zero, 0(rs)|jump register;" "call|call label|pseudo||auipc+jalr|PC-relative call;" "ret|ret|pseudo||jalr zero, ra, 0|return from call;" "beq|beq rs1, rs2, label|B|+/-4KiB||branch if equal;" "bne|bne rs1, rs2, label|B|+/-4KiB||branch if not equal;" "blt|blt rs1, rs2, label|B|+/-4KiB||branch if signed less;" "bge|bge rs1, rs2, label|B|+/-4KiB||branch if signed greater/equal;" "bltu|bltu rs1, rs2, label|B|+/-4KiB||branch if unsigned less;" "bgeu|bgeu rs1, rs2, label|B|+/-4KiB||branch if unsigned greater/equal;" "beqz|beqz rs, label|pseudo||beq rs, zero, label|branch if zero;" "bnez|bnez rs, label|pseudo||bne rs, zero, label|branch if non-zero;" "nop|nop|pseudo||addi zero, zero, 0|no operation;" "wfi|wfi|I|||wait for interrupt;" "mret|mret|I|||return from M-mode trap;" "sret|sret|I|||return from S-mode trap;" "ecall|ecall|I|||environment call;" "ebreak|ebreak|I|||breakpoint;" "fencei|fence.i rd, rs, imm|I|||instruction fence;" "fence.i|fence.i rd, rs, imm|I|||instruction fence (dotted alias);" "csrr|csrr rd, csr|I|||CSR read;" "csrw|csrw csr, rs|I|||CSR write;" "csrs|csrs csr, rs|I|||CSR set bits;" "csrc|csrc csr, rs|I|||CSR clear bits;" "csrrw|csrrw rd, csr, rs|I|||atomic CSR exchange;" "csrrs|csrrs rd, csr, rs|I|||atomic CSR read-set;" "csrrc|csrrc rd, csr, rs|I|||atomic CSR read-clear;" "csrrwi|csrrwi rd, csr, imm|I|0..31||CSR exchange immediate;" "csrrsi|csrrsi rd, csr, imm|I|0..31||CSR read-set immediate;" "csrrci|csrrci rd, csr, imm|I|0..31||CSR read-clear immediate;" "csrwi|csrwi csr, imm|I|0..31||CSR write immediate;" "csrsi|csrsi csr, imm|I|0..31||CSR set immediate;" "csrci|csrci csr, imm|I|0..31||CSR clear immediate;" "rdtime|rdtime rd|pseudo||csrr rd, time|read time CSR;" "sfencevma|sfence.vma rs1, rs2|R|||SFENCE.VMA (dotted: sfencevma);" "lifp|lifp rd, imm|I|||HolyC label-in-function-pointer (host asm);" "lr.d|lr.d rd, (rs)|A|||load-reserved doubleword;" "lr.w|lr.w rd, (rs)|A|||load-reserved word;" "lrd|lrd rd, (rs)|A|||lr.d alias (no dot);" "lrw|lrw rd, (rs)|A|||lr.w alias;" "sc.d|sc.d rd, rs, (rt)|A|||store-conditional doubleword;" "sc.w|sc.w rd, rs, (rt)|A|||store-conditional word;" "scd|scd rd, rs, (rt)|A|||sc.d alias;" "scw|scw rd, rs, (rt)|A|||sc.w alias;" "amoswap.d|amoswap.d rd, rs, (rt)|A|||atomic swap doubleword;" "amoadd.d|amoadd.d rd, rs, (rt)|A|||atomic add doubleword;" "amoxor.d|amoxor.d rd, rs, (rt)|A|||atomic XOR doubleword;" "amoand.d|amoand.d rd, rs, (rt)|A|||atomic AND doubleword;" "amoor.d|amoor.d rd, rs, (rt)|A|||atomic OR doubleword;" "amomin.d|amomin.d rd, rs, (rt)|A|||atomic signed min doubleword;" "amomax.d|amomax.d rd, rs, (rt)|A|||atomic signed max doubleword;" "amominu.d|amominu.d rd, rs, (rt)|A|||atomic unsigned min doubleword;" "amomaxu.d|amomaxu.d rd, rs, (rt)|A|||atomic unsigned max doubleword;" "amoswap.w|amoswap.w rd, rs, (rt)|A|||atomic swap word;" "amoadd.w|amoadd.w rd, rs, (rt)|A|||atomic add word;" "amoxor.w|amoxor.w rd, rs, (rt)|A|||atomic XOR word;" "amoand.w|amoand.w rd, rs, (rt)|A|||atomic AND word;" "amoor.w|amoor.w rd, rs, (rt)|A|||atomic OR word;" "amomin.w|amomin.w rd, rs, (rt)|A|||atomic signed min word;" "amomax.w|amomax.w rd, rs, (rt)|A|||atomic signed max word;" "amominu.w|amominu.w rd, rs, (rt)|A|||atomic unsigned min word;" "amomaxu.w|amomaxu.w rd, rs, (rt)|A|||atomic unsigned max word;" "amoswapd|amoswapd rd, rs, (rt)|A|||amoswap.d alias;" "amoaddd|amoaddd rd, rs, (rt)|A|||amoadd.d alias;" "amoxord|amoxord rd, rs, (rt)|A|||amoxor.d alias;" "amoandd|amoandd rd, rs, (rt)|A|||amoand.d alias;" "amoord|amoord rd, rs, (rt)|A|||amoor.d alias;" "amomind|amomind rd, rs, (rt)|A|||amomin.d alias;" "amomaxd|amomaxd rd, rs, (rt)|A|||amomax.d alias;" "amominud|amominud rd, rs, (rt)|A|||amominu.d alias;" "amomaxud|amomaxud rd, rs, (rt)|A|||amomaxu.d alias;" "amoswapw|amoswapw rd, rs, (rt)|A|||amoswap.w alias;" "amoaddw|amoaddw rd, rs, (rt)|A|||amoadd.w alias;" "amoxorw|amoxorw rd, rs, (rt)|A|||amoxor.w alias;" "amoandw|amoandw rd, rs, (rt)|A|||amoand.w alias;" "amoorw|amoorw rd, rs, (rt)|A|||amoor.w alias;" "amominw|amominw rd, rs, (rt)|A|||amomin.w alias;" "amomaxw|amomaxw rd, rs, (rt)|A|||amomax.w alias;" "amominuw|amominuw rd, rs, (rt)|A|||amominu.w alias;" "amomaxuw|amomaxuw rd, rs, (rt)|A|||amomaxu.w alias;" "fsqrtd|fsqrt.d fd, fs|R|||D-extension square root;" "faddd|fadd.d fd, fs1, fs2|R|||double add;" "fsubd|fsub.d fd, fs1, fs2|R|||double subtract;" "fmuld|fmul.d fd, fs1, fs2|R|||double multiply;" "fdivd|fdiv.d fd, fs1, fs2|R|||double divide;" "fled|fle.d rd, fs1, fs2|R|||double less-or-equal;" "fltd|flt.d rd, fs1, fs2|R|||double less-than;" "feqd|feq.d rd, fs1, fs2|R|||double equal;" "fmvdx|fmv.d.x fd, rs|R|||move GPR to FPR;" "fmvxd|fmv.x.d rd, fs|R|||move FPR to GPR;" "fcvtdl|fcvt.d.l fd, rs|R|||convert long to double;" "fcvtld_rtz|fcvt.l.d rd, fs|R|||convert double to long (RTZ);" "fcvtld_rdn|fcvt.l.d rd, fs|R|||convert double to long (RDN);" "fcvtld_rmm|fcvt.l.d rd, fs|R|||convert double to long (RMM);";
}

I64 RVAsmDocChEq(I64 a, I64 b)
{
  if (a >= 'A' && a <= 'Z')
    a += 32;
  if (b >= 'A' && b <= 'Z')
    b += 32;
  return a == b;
}

I64 RVAsmDocMnEq(U8 *rec, U8 *mn)
{
  U8 *r, *m;
  if (!rec || !mn)
    return 0;
  r = rec;
  m = mn;
  while (*m) {
    if (*r == '|' || *r == ';' || !*r)
      return 0;
    if (!RVAsmDocChEq(*r, *m))
      return 0;
    r++;
    m++;
  }
  return *r == '|';
}

U8 *RVAsmDocField(U8 *rec, I64 idx, U8 *buf, I64 bufsz)
{
  U8 *p, *dst, *end;
  I64 f;
  if (!rec || !buf || bufsz < 2)
    return 0;
  p = rec;
  f = 0;
  end = buf + bufsz - 1;
  while (*p && *p != ';') {
    if (f == idx) {
      dst = buf;
      while (*p && *p != '|' && *p != ';' && dst < end) {
        *dst = *p;
        dst++;
        p++;
      }
      *dst = 0;
      return buf;
    }
    while (*p && *p != '|' && *p != ';')
      p++;
    if (*p == '|')
      p++;
    f++;
  }
  buf[0] = 0;
  return 0;
}

U8 *RVAsmDocFindRec(U8 *mn)
{
  U8 *p;
  if (!mn || !*mn)
    return 0;
  if (!rv_asm_doc_raw)
    RVAsmDocRawInit;
  p = rv_asm_doc_raw;
  while (*p) {
    if (RVAsmDocMnEq(p, mn))
      return p;
    while (*p && *p != ';')
      p++;
    if (*p == ';')
      p++;
  }
  return 0;
}

U8 g_rv_asm_doc_buf[ASM_DOC_NOTE];
U8 g_rv_asm_doc_tpl[ASM_DOC_TPL];

U0 RVAsmDocPrintField(U8 *label, U8 *val)
{
  if (!val || !*val)
    return;
  Print("%s%s\n", label, val);
}

public U0 AsmDoc(U8 *mn)
{
  //Structured docs for one asm{} mnemonic: template, encoding, imm range, GNU expansion,
  // note. Case-insensitive. See AsmList(); Man("Asm");.
  U8 *rec, *s;
  if (!mn || !*mn) {
    Print("AsmDoc: need mnemonic - AsmList(); e.g. AsmDoc(\"addi\");\n");
    return;
  }
  rec = RVAsmDocFindRec(mn);
  if (!rec) {
    Print("AsmDoc: unknown '%s' - AsmList(); Tab-complete inside asm{};\n", mn);
    return;
  }
  s = RVAsmDocField(rec, 0, g_rv_asm_doc_buf, ASM_DOC_MN);
  Print("AsmDoc %s\n", s);
  RVAsmDocPrintField("  template  ", RVAsmDocField(rec, 1, g_rv_asm_doc_buf, ASM_DOC_TPL));
  RVAsmDocPrintField("  encoding  ", RVAsmDocField(rec, 2, g_rv_asm_doc_buf, ASM_DOC_ENC));
  RVAsmDocPrintField("  imm       ", RVAsmDocField(rec, 3, g_rv_asm_doc_buf, ASM_DOC_IMM));
  RVAsmDocPrintField("  gnu       ", RVAsmDocField(rec, 4, g_rv_asm_doc_buf, ASM_DOC_GNU));
  RVAsmDocPrintField("  note      ", RVAsmDocField(rec, 5, g_rv_asm_doc_buf, ASM_DOC_NOTE));
}

public U0 AsmList()
{
  //One line per catalog entry (mnemonic + operand template). AsmDoc("name") for detail.
  U8 *p, *s, *tpl;
  I64 n = 0;
  if (!rv_asm_doc_raw)
    RVAsmDocRawInit;
  p = rv_asm_doc_raw;
  Print("AsmList - documented asm{} mnemonics:\n");
  while (*p) {
    s = RVAsmDocField(p, 0, g_rv_asm_doc_buf, ASM_DOC_MN);
    tpl = RVAsmDocField(p, 1, g_rv_asm_doc_tpl, ASM_DOC_TPL);
    if (!tpl)
      tpl = "";
    if (s && *s) {
      Print("  %s  %s\n", s, tpl);
      n++;
    }
    while (*p && *p != ';')
      p++;
    if (*p == ';')
      p++;
  }
  Print("(%d documented. AsmDoc(\"name\") for detail.)\n", n);
  Print("Note: this is the doc catalog. What the asm{} assembler ACCEPTS is a subset\n");
  Print("  (I+M+A+Zicsr; no float, no branches/jumps) - test live: asm{ <ins> };\n");
  Print("  The HolyC compiler EMITS more than asm{} accepts (F/D). See docs/RISCV_INVENTORY.md\n");
}

public U0 MemMap()
{
  //RISC-V (QEMU virt) physical memory map - devices + kernel image regions. Constants
  // from Kernel/RVAutoConf.HH so this tracks the actual build.
  Print("RISC-V memory map (QEMU virt):\n");
  Print("  0x%08X  SiFive test finisher\n", CONFIG_SIFIVE_TEST_BASE);
#ifdef CONFIG_HAS_CLINT
  Print("  0x%08X  CLINT (mtime +0x%X, mtimecmp +0x%X)\n", CONFIG_CLINT_BASE,
    CONFIG_CLINT_MTIME_OFF, CONFIG_CLINT_MTIMECMP_OFF);
#endif
#ifdef CONFIG_HAS_PLIC
  Print("  0x%08X  PLIC (enable +0x%X, threshold +0x%X)\n", CONFIG_PLIC_BASE,
    CONFIG_PLIC_ENABLE_OFF, CONFIG_PLIC_THRESHOLD_OFF);
#endif
  Print("  0x%08X  UART 16550 (irq %d)\n", CONFIG_UART_BASE, CONFIG_UART_IRQ);
  Print("  0x%08X  DRAM base (%d MiB)\n", CONFIG_DRAM_BASE, CONFIG_DRAM_SIZE >> 20);
  Print("    0x%08X  kernel link addr\n", CONFIG_KERNEL_LINK_ADDR);
  Print("    0x%08X  guest blob\n", CONFIG_GUEST_BLOB_ADDR);
  Print("    0x%08X  compiler slot\n", CONFIG_COMPILER_SLOT_ADDR);
  Print("    0x%08X  heap base\n", CONFIG_HEAP_BASE);
  Print("    0x%08X  framebuffer (soft)\n", CONFIG_FB_SOFT_BASE);
  Print("    0x%08X  host slots\n", CONFIG_HOST_SLOTS_BASE);
  Print("    0x%08X  MemFS base\n", CONFIG_MEMFS_BASE);
  Print("    0x%08X  stack base\n", CONFIG_STACK_BASE);
  Print("  0x%08X  DRAM top\n", CONFIG_DRAM_BASE + CONFIG_DRAM_SIZE);
}

U8 *RVCsrStateName(I64 x)
{
  if (x == 1)
    return "Initial";
  if (x == 2)
    return "Clean";
  if (x == 3)
    return "Dirty";
  return "?";
}

U0 RVCsrDecodeMstatus(I64 v)
{
  I64 mpp, fs, xs, vs;
  if (v & 8)
    Print("   MIE=1 (machine interrupts enabled)\n");
  else
    Print("   MIE=0 (machine interrupts disabled)\n");
  if (v & 2)
    Print("   SIE=1 (supervisor interrupts enabled)\n");
  if (v & 128)
    Print("   MPIE=1 (machine prior IE)\n");
  if (v & 32)
    Print("   SPIE=1 (supervisor prior IE)\n");
  if (v & 256)
    Print("   SPP=1 (prior privilege S-mode)\n");
  vs = (v >> 9) & 3;
  if (vs)
    Print("   VS=%d (%s)\n", vs, RVCsrStateName(vs));
  mpp = (v >> 11) & 3;
  if (mpp == 1)
    Print("   MPP=01 (S-mode)\n");
  else if (mpp == 3)
    Print("   MPP=11 (M-mode)\n");
  else if (mpp == 2)
    Print("   MPP=10 (reserved)\n");
  else
    Print("   MPP=00 (U-mode)\n");
  fs = (v >> 13) & 3;
  if (fs)
    Print("   FS=%d (%s)\n", fs, RVCsrStateName(fs));
  xs = (v >> 15) & 3;
  if (xs)
    Print("   XS=%d (%s)\n", xs, RVCsrStateName(xs));
  if (v & 0x20000)
    Print("   MPRV=1 (loads/stores at MPP privilege)\n");
  if (v & 0x40000)
    Print("   SUM=1 (supervisor may access user pages)\n");
  if (v & 0x80000)
    Print("   MXR=1 (executable pages readable)\n");
  if (v & 0x200000)
    Print("   TW=1 (trap WFI from S-mode)\n");
  if (v & 0x8000000000000000)
    Print("   SD=1 (some state dirty)\n");
}

U8 *RVMcauseName(I64 v)
{
  I64 intr, code;
  intr = (v >> 63) & 1;
  code = v & 0x7FFFFFFFFFFFFFFF;
  if (intr) {
    if (code == 1)  return "supervisor soft interrupt";
    if (code == 3)  return "machine soft interrupt";
    if (code == 5)  return "supervisor timer interrupt";
    if (code == 7)  return "machine timer interrupt";
    if (code == 9)  return "supervisor external interrupt";
    if (code == 11) return "machine external interrupt";
    return "interrupt";
  }
  if (code == 0)  return "insn address misaligned";
  if (code == 1)  return "insn access fault";
  if (code == 2)  return "illegal instruction";
  if (code == 3)  return "breakpoint";
  if (code == 4)  return "load address misaligned";
  if (code == 5)  return "load access fault";
  if (code == 6)  return "store address misaligned";
  if (code == 7)  return "store access fault";
  if (code == 8)  return "ecall from U-mode";
  if (code == 9)  return "ecall from S-mode";
  if (code == 11) return "ecall from M-mode";
  if (code == 12) return "insn page fault";
  if (code == 13) return "load page fault";
  if (code == 15) return "store page fault";
  return "exception";
}

public U0 Mstatus()
{
  //Read and decode the current mstatus CSR (interrupt-enable + privilege bits).
  I64 v = RVWinCsrrMstatus();
  Print("mstatus=0x%X\n", v);
  RVCsrDecodeMstatus(v);
}

public U0 Mcause()
{
  //Read and decode the current mcause CSR (last trap cause).
  I64 v = RVWinCsrrMcause();
  I64 intr = (v >> 63) & 1, code = v & 0x7FFFFFFFFFFFFFFF;
  U8 *kind = "Exception";
  if (intr)
    kind = "Interrupt";
  Print("mcause=0x%X  %s code=%d (%s)\n", v, kind, code, RVMcauseName(v));
}
