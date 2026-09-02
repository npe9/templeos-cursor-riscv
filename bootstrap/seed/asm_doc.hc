// asm_doc.hc -- structured RISC-V asm{} instruction catalog (docs + Tab hints).
// Loaded after asm_complete.hc, before complete.hc. Records in AsmDocRaw:
//   mnemonic|template|encoding|imm_range|gnu_equiv|note;
// Keep mnemonics in sync with AsmCompOps / host TryAssembleRiscV / gnu_diff.jsonl.
// Man("Asm");  AsmDoc("addi");  AsmList();  Tab inside asm{} shows templates.
#define ASM_DOC_MN 32
#define ASM_DOC_TPL 64
#define ASM_DOC_ENC 8
#define ASM_DOC_IMM 24
#define ASM_DOC_GNU 64
#define ASM_DOC_NOTE 96
U8 *AsmDocRaw = "add|add rd, rs, rs|R|||R-type add;" "addi|addi rd, rs, imm|I|-2048..2047||12-bit signed immediate;" "sub|sub rd, rs, rs|R|||R-type subtract;" "and|and rd, rs, rs|R|||R-type AND;" "andi|andi rd, rs, imm|I|-2048..2047||bitwise AND immediate;" "or|or rd, rs, rs|R|||R-type OR;" "ori|ori rd, rs, imm|I|-2048..2047||bitwise OR immediate;" "xor|xor rd, rs, rs|R|||R-type XOR;" "xori|xori rd, rs, imm|I|-2048..2047||bitwise XOR immediate;" "sll|sll rd, rs, rs|R|||shift left logical;" "slli|slli rd, rs, shamt|I|0..63||shift amount in low 6 bits;" "srl|srl rd, rs, rs|R|||shift right logical;" "srli|srli rd, rs, shamt|I|0..63||logical shift right immediate;" "sra|sra rd, rs, rs|R|||shift right arithmetic;" "srai|srai rd, rs, shamt|I|0..63||arithmetic shift right immediate;" "slt|slt rd, rs, rs|R|||set less than (signed);" "slti|slti rd, rs, imm|I|-2048..2047||set less than immediate;" "sltu|sltu rd, rs, rs|R|||set less than unsigned;" "mul|mul rd, rs, rs|R|||M-extension multiply;" "div|div rd, rs, rs|R|||signed divide;" "divu|divu rd, rs, rs|R|||unsigned divide;" "rem|rem rd, rs, rs|R|||signed remainder;" "remu|remu rd, rs, rs|R|||unsigned remainder;" "lui|lui rd, imm|U|0..0xFFFFF||load upper immediate (20-bit field);" "auipc|auipc rd, imm|U|0..0xFFFFF||PC-relative upper immediate;" "li|li rd, imm|pseudo||±2047 addi; else GNU as lui+addiw|load immediate (wide matches GNU as lui+addiw);" "mv|mv rd, rs|pseudo||addi rd, rs, 0|move register;" "not|not rd, rs|pseudo||xori rd, rs, -1|bitwise NOT;" "neg|neg rd, rs|pseudo||sub rd, zero, rs|two's-complement negation;" "seqz|seqz rd, rs|pseudo||sltiu rd, rs, 1|set if equal to zero;" "snez|snez rd, rs|pseudo||sltu rd, zero, rs|set if not equal to zero;" "ld|ld rd, imm(rs)|I|-2048..2047||load doubleword;" "lw|lw rd, imm(rs)|I|-2048..2047||load word;" "lwu|lwu rd, imm(rs)|I|-2048..2047||load word unsigned;" "lh|lh rd, imm(rs)|I|-2048..2047||load halfword;" "lhu|lhu rd, imm(rs)|I|-2048..2047||load halfword unsigned;" "lb|lb rd, imm(rs)|I|-2048..2047||load byte;" "lbu|lbu rd, imm(rs)|I|-2048..2047||load byte unsigned;" "sd|sd rs, imm(rd)|S|-2048..2047||store doubleword;" "sw|sw rs, imm(rd)|S|-2048..2047||store word;" "sh|sh rs, imm(rd)|S|-2048..2047||store halfword;" "sb|sb rs, imm(rd)|S|-2048..2047||store byte;" "jalr|jalr rd, imm(rs)|I|-2048..2047||jump and link register (short: jalr rs → jalr ra,0(rs));" "j|j label|pseudo||jal x0, label|unconditional jump;" "jr|jr rs|pseudo||jalr zero, 0(rs)|jump register;" "call|call label|pseudo||auipc+jalr|PC-relative call;" "ret|ret|pseudo||jalr zero, ra, 0|return from call;" "beq|beq rs1, rs2, label|B|±4KiB||branch if equal;" "bne|bne rs1, rs2, label|B|±4KiB||branch if not equal;" "blt|blt rs1, rs2, label|B|±4KiB||branch if signed less;" "bge|bge rs1, rs2, label|B|±4KiB||branch if signed greater/equal;" "bltu|bltu rs1, rs2, label|B|±4KiB||branch if unsigned less;" "bgeu|bgeu rs1, rs2, label|B|±4KiB||branch if unsigned greater/equal;" "beqz|beqz rs, label|pseudo||beq rs, zero, label|branch if zero;" "bnez|bnez rs, label|pseudo||bne rs, zero, label|branch if non-zero;" "nop|nop|pseudo||addi zero, zero, 0|no operation;" "wfi|wfi|I|||wait for interrupt;" "mret|mret|I|||return from M-mode trap;" "sret|sret|I|||return from S-mode trap;" "ecall|ecall|I|||environment call;" "ebreak|ebreak|I|||breakpoint;" "fencei|fence.i rd, rs, imm|I|||instruction fence;" "fence.i|fence.i rd, rs, imm|I|||instruction fence (dotted alias);" "csrr|csrr rd, csr|I|||CSR read;" "csrw|csrw csr, rs|I|||CSR write;" "csrs|csrs csr, rs|I|||CSR set bits;" "csrc|csrc csr, rs|I|||CSR clear bits;" "csrrw|csrrw rd, csr, rs|I|||atomic CSR exchange;" "csrrs|csrrs rd, csr, rs|I|||atomic CSR read-set;" "csrrc|csrrc rd, csr, rs|I|||atomic CSR read-clear;" "csrrwi|csrrwi rd, csr, imm|I|0..31||CSR exchange immediate;" "csrrsi|csrrsi rd, csr, imm|I|0..31||CSR read-set immediate;" "csrrci|csrrci rd, csr, imm|I|0..31||CSR read-clear immediate;" "csrwi|csrwi csr, imm|I|0..31||CSR write immediate;" "csrsi|csrsi csr, imm|I|0..31||CSR set immediate;" "csrci|csrci csr, imm|I|0..31||CSR clear immediate;" "rdtime|rdtime rd|pseudo||csrr rd, time|read time CSR;" "sfencevma|sfence.vma rs1, rs2|R|||SFENCE.VMA (dotted: sfencevma);" "lifp|lifp rd, imm|I|||HolyC label-in-function-pointer (host asm);" "lr.d|lr.d rd, (rs)|A|||load-reserved doubleword;" "lr.w|lr.w rd, (rs)|A|||load-reserved word;" "lrd|lrd rd, (rs)|A|||lr.d alias (no dot);" "lrw|lrw rd, (rs)|A|||lr.w alias;" "sc.d|sc.d rd, rs, (rt)|A|||store-conditional doubleword;" "sc.w|sc.w rd, rs, (rt)|A|||store-conditional word;" "scd|scd rd, rs, (rt)|A|||sc.d alias;" "scw|scw rd, rs, (rt)|A|||sc.w alias;" "amoswap.d|amoswap.d rd, rs, (rt)|A|||atomic swap doubleword;" "amoadd.d|amoadd.d rd, rs, (rt)|A|||atomic add doubleword;" "amoxor.d|amoxor.d rd, rs, (rt)|A|||atomic XOR doubleword;" "amoand.d|amoand.d rd, rs, (rt)|A|||atomic AND doubleword;" "amoor.d|amoor.d rd, rs, (rt)|A|||atomic OR doubleword;" "amomin.d|amomin.d rd, rs, (rt)|A|||atomic signed min doubleword;" "amomax.d|amomax.d rd, rs, (rt)|A|||atomic signed max doubleword;" "amominu.d|amominu.d rd, rs, (rt)|A|||atomic unsigned min doubleword;" "amomaxu.d|amomaxu.d rd, rs, (rt)|A|||atomic unsigned max doubleword;" "amoswap.w|amoswap.w rd, rs, (rt)|A|||atomic swap word;" "amoadd.w|amoadd.w rd, rs, (rt)|A|||atomic add word;" "amoxor.w|amoxor.w rd, rs, (rt)|A|||atomic XOR word;" "amoand.w|amoand.w rd, rs, (rt)|A|||atomic AND word;" "amoor.w|amoor.w rd, rs, (rt)|A|||atomic OR word;" "amomin.w|amomin.w rd, rs, (rt)|A|||atomic signed min word;" "amomax.w|amomax.w rd, rs, (rt)|A|||atomic signed max word;" "amominu.w|amominu.w rd, rs, (rt)|A|||atomic unsigned min word;" "amomaxu.w|amomaxu.w rd, rs, (rt)|A|||atomic unsigned max word;" "amoswapd|amoswapd rd, rs, (rt)|A|||amoswap.d alias;" "amoaddd|amoaddd rd, rs, (rt)|A|||amoadd.d alias;" "amoxord|amoxord rd, rs, (rt)|A|||amoxor.d alias;" "amoandd|amoandd rd, rs, (rt)|A|||amoand.d alias;" "amoord|amoord rd, rs, (rt)|A|||amoor.d alias;" "amomind|amomind rd, rs, (rt)|A|||amomin.d alias;" "amomaxd|amomaxd rd, rs, (rt)|A|||amomax.d alias;" "amominud|amominud rd, rs, (rt)|A|||amominu.d alias;" "amomaxud|amomaxud rd, rs, (rt)|A|||amomaxu.d alias;" "amoswapw|amoswapw rd, rs, (rt)|A|||amoswap.w alias;" "amoaddw|amoaddw rd, rs, (rt)|A|||amoadd.w alias;" "amoxorw|amoxorw rd, rs, (rt)|A|||amoxor.w alias;" "amoandw|amoandw rd, rs, (rt)|A|||amoand.w alias;" "amoorw|amoorw rd, rs, (rt)|A|||amoor.w alias;" "amominw|amominw rd, rs, (rt)|A|||amomin.w alias;" "amomaxw|amomaxw rd, rs, (rt)|A|||amomax.w alias;" "amominuw|amominuw rd, rs, (rt)|A|||amominu.w alias;" "amomaxuw|amomaxuw rd, rs, (rt)|A|||amomaxu.w alias;" "fsqrtd|fsqrt.d fd, fs|R|||D-extension square root;" "faddd|fadd.d fd, fs1, fs2|R|||double add;" "fsubd|fsub.d fd, fs1, fs2|R|||double subtract;" "fmuld|fmul.d fd, fs1, fs2|R|||double multiply;" "fdivd|fdiv.d fd, fs1, fs2|R|||double divide;" "fled|fle.d rd, fs1, fs2|R|||double less-or-equal;" "fltd|flt.d rd, fs1, fs2|R|||double less-than;" "feqd|feq.d rd, fs1, fs2|R|||double equal;" "fmvdx|fmv.d.x fd, rs|R|||move GPR to FPR;" "fmvxd|fmv.x.d rd, fs|R|||move FPR to GPR;" "fcvtdl|fcvt.d.l fd, rs|R|||convert long to double;" "fcvtld_rtz|fcvt.l.d rd, fs|R|||convert double to long (RTZ);" "fcvtld_rdn|fcvt.l.d rd, fs|R|||convert double to long (RDN);" "fcvtld_rmm|fcvt.l.d rd, fs|R|||convert double to long (RMM);";
I64 AsmDocChEq(I64 a, I64 b)
{
  if (a >= 'A' && a <= 'Z')
    a += 32;
  if (b >= 'A' && b <= 'Z')
    b += 32;
  return a == b;
}

I64 AsmDocMnEq(U8 *rec, U8 *mn)
{
  U8 *r, *m;
  if (!rec || !mn)
    return 0;
  r = rec;
  m = mn;
  while (*m) {
    if (*r == '|' || *r == ';' || !*r)
      return 0;
    if (!AsmDocChEq (*r, *m))
      return 0;
    r++;
    m++;
  }
  if (*r != '|')
    return 0;
  return 1;
}

U8 *AsmDocField(U8 *rec, I64 idx, U8 *buf, I64 bufsz)
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

U8 *AsmDocFindRec(U8 *mn)
{
  U8 *p;
  if (!mn || !*mn)
    return 0;
  p = AsmDocRaw;
  while (*p) {
    if (AsmDocMnEq(p, mn))
      return p;
    while (*p && *p != ';')
      p++;
    if (*p == ';')
      p++;
  }
  return 0;
}
U8 g_asm_doc_tpl[ASM_DOC_TPL];
U8 *AsmDocTemplate(U8 *mn)
{
  U8 *rec;
  rec = AsmDocFindRec(mn);
  if (!rec)
    return 0;
  return AsmDocField(rec, 1, g_asm_doc_tpl, ASM_DOC_TPL);
}
U8 g_asm_doc_buf[ASM_DOC_NOTE];
U0 AsmDocPrintField(U8 *label, U8 *val)
{
  if (!val || !*val)
    return;
  UartStr(label);
  UartStr(val);
  PutCh('\n');
}
// AsmDoc -- AsmDoc("addi")
// NAME
//   AsmDoc - print structured documentation for one asm{} mnemonic
// SYNOPSIS
//   U0 AsmDoc(U8 *mn);
// DESCRIPTION
//   Shows operand template, encoding class, immediate range, GNU gas expansion
//   (for pseudos), and notes. Case-insensitive. See also Man("Asm").
// EXAMPLES
//   AsmDoc("addi");
//   AsmDoc("mv");
// SEE ALSO
//   AsmList  Man  Disasm  asm_complete
U0 AsmDoc(U8 *mn)
{
  U8 *rec, *s;
  if (!mn || !*mn) {
    UartStr("AsmDoc: need mnemonic — AsmList(); Man(\"Asm\");\n");
    return;
  }
  rec = AsmDocFindRec(mn);
  if (!rec) {
    "AsmDoc: unknown '%s' — AsmList(); Tab-complete inside asm{};\n", mn;
    return;
  }
  s = AsmDocField(rec, 0, g_asm_doc_buf, ASM_DOC_MN);
  UartStr("AsmDoc ");
  UartStr(s);
  PutCh('\n');
  AsmDocPrintField("  template  ", AsmDocField(rec, 1, g_asm_doc_buf, ASM_DOC_TPL));
  AsmDocPrintField("  encoding  ", AsmDocField(rec, 2, g_asm_doc_buf, ASM_DOC_ENC));
  AsmDocPrintField("  imm       ", AsmDocField(rec, 3, g_asm_doc_buf, ASM_DOC_IMM));
  AsmDocPrintField("  gnu       ", AsmDocField(rec, 4, g_asm_doc_buf, ASM_DOC_GNU));
  AsmDocPrintField("  note      ", AsmDocField(rec, 5, g_asm_doc_buf, ASM_DOC_NOTE));
}
// AsmList -- AsmList()
// NAME
//   AsmList - list documented asm{} mnemonics with operand templates
// SYNOPSIS
//   U0 AsmList();
// DESCRIPTION
//   One line per catalog entry (mnemonic + template). Same set as AsmCompOps
//   Tab completion inside asm{}.
// EXAMPLES
//   AsmList();
// SEE ALSO
//   AsmDoc  Man("Asm")
U0 AsmList()
{
  U8 *p, *s, *tpl;
  I64 n = 0;
  p = AsmDocRaw;
  UartStr("AsmList — documented asm{} mnemonics:\n");
  while (*p) {
    s = AsmDocField(p, 0, g_asm_doc_buf, ASM_DOC_MN);
    tpl = AsmDocField(p, 1, g_asm_doc_tpl, ASM_DOC_TPL);
    if (s && *s) {
      UartStr("  ");
      UartStr(s);
      UartStr("  ");
      if (tpl)
        UartStr(tpl);
      PutCh('\n');
      n++;
    }
    while (*p && *p != ';')
      p++;
    if (*p == ';')
      p++;
  }
  "(%d entries — AsmDoc(\"name\"); Man(\"Asm\");)\n", n;
}

U0 AsmDocHelp()
{
  UartStr("AsmDocHelp — instruction catalog for asm{} blocks\n");
  UartStr("  AsmDoc(\"addi\");   AsmList();   Man(\"Asm\");   Man(\"AsmRV\");\n");
  UartStr("  Tab inside asm{} completes mnemonics/regs/CSRs; shows operand template.\n");
  UartStr("  GNU parity cases: tests/asm/cases/gnu_diff.jsonl\n");
}
