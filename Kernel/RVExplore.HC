// RVExplore.HC - RISC-V exploration tooling for the guest-compiler REPL.
// Ported from the retired thin-JIT seed (bootstrap/seed/{asm_doc,csr}.hc): the same
// instruction catalog + CSR decoders, but callable HolyC functions planted through the
// compiler (RVExePubs). UartStr/PutCh -> Print; ternaries -> helpers (HolyC has no ?:).
// Duplication note: the RISC-V mnemonic set also lives in Compiler/Asm_RV.HC (parser) and
// Kernel/RVDisasm.HC (formatter); AsmDocRaw here is the *documentation* table (mnemonic +
// operand template + notes) - a different shape/consumer, not redundant. See
// docs/STOCK_PARITY.md and the AsmList<->assembler drift test.

#include "/bootstrap/seed/csr_decode.hc"
// the CSR value decoders, shared with the seed image rather than forked here

#define ASM_DOC_MN 32
#define ASM_DOC_TPL 64
#define ASM_DOC_ENC 8
#define ASM_DOC_IMM 24
#define ASM_DOC_GNU 64
#define ASM_DOC_NOTE 96
U8 *rv_asm_doc_raw;
U0 RVAsmDocRawInit()
{
  rv_asm_doc_raw = "add|add rd, rs, rs|R|||R-type add|rd = rs1 + rs2;addi|addi rd, rs, imm|I|-2048..2047||12-bit signed immediate|rd = rs1 + sext(imm12);sub|sub rd, rs, rs|R|||R-type subtract|rd = rs1 - rs2;and|and rd, rs, rs|R|||R-type AND|rd = rs1 & rs2;andi|andi rd, rs, imm|I|-2048..2047||bitwise AND immediate|rd = rs1 & sext(imm12);or|or rd, rs, rs|R|||R-type OR|rd = rs1 OR rs2 (bitwise);ori|ori rd, rs, imm|I|-2048..2047||bitwise OR immediate|rd = rs1 OR sext(imm12);xor|xor rd, rs, rs|R|||R-type XOR|rd = rs1 ^ rs2;xori|xori rd, rs, imm|I|-2048..2047||bitwise XOR immediate|rd = rs1 ^ sext(imm12);sll|sll rd, rs, rs|R|||shift left logical|rd = rs1 << (rs2 & 63);slli|slli rd, rs, shamt|I|0..63||shift amount in low 6 bits|rd = rs1 << shamt;srl|srl rd, rs, rs|R|||shift right logical|rd = rs1 >> (rs2 & 63) logical;srli|srli rd, rs, shamt|I|0..63||logical shift right immediate|rd = rs1 >> shamt logical;sra|sra rd, rs, rs|R|||shift right arithmetic|rd = rs1 >> (rs2 & 63) arithmetic;srai|srai rd, rs, shamt|I|0..63||arithmetic shift right immediate|rd = rs1 >> shamt arithmetic;slt|slt rd, rs, rs|R|||set less than (signed)|rd = (rs1 <s rs2) ? 1 : 0;slti|slti rd, rs, imm|I|-2048..2047||set less than immediate|rd = (rs1 <s sext(imm)) ? 1 : 0;sltu|sltu rd, rs, rs|R|||set less than unsigned|rd = (rs1 <u rs2) ? 1 : 0;sltiu|sltiu rd, rs, imm|I|-2048..2047||set less than immediate, unsigned compare|rd = (rs1 <u sext(imm12)) ? 1 : 0;mul|mul rd, rs, rs|R|||M-extension multiply|rd = low64(rs1 * rs2);mulh|mulh rd, rs, rs|R|||multiply high, signed x signed|rd = high64(rs1 *s rs2), both signed;mulhsu|mulhsu rd, rs, rs|R|||multiply high, signed x unsigned|rd = high64(rs1 signed *s rs2 unsigned);mulhu|mulhu rd, rs, rs|R|||multiply high, unsigned x unsigned|rd = high64(rs1 *u rs2), both unsigned;div|div rd, rs, rs|R|||signed divide|rd = rs1 / rs2 (signed);divu|divu rd, rs, rs|R|||unsigned divide|rd = rs1 / rs2 (unsigned);rem|rem rd, rs, rs|R|||signed remainder|rd = rs1 %% rs2 (signed);remu|remu rd, rs, rs|R|||unsigned remainder|rd = rs1 %% rs2 (unsigned);addiw|addiw rd, rs, imm|I|-2048..2047||RV64 add word immediate, sign-extend|rd = sext32(rs1 + sext(imm12));slliw|slliw rd, rs, shamt|I|0..31||RV64 shift-left word immediate|rd = sext32(rs1[31:0] << shamt);srliw|srliw rd, rs, shamt|I|0..31||RV64 logical shift-right word immediate|rd = sext32(rs1[31:0] >> shamt logical);sraiw|sraiw rd, rs, shamt|I|0..31||RV64 arithmetic shift-right word immediate|rd = sext32(rs1[31:0] >> shamt arithmetic);addw|addw rd, rs, rs|R|||RV64 add word, sign-extend|rd = sext32(rs1 + rs2);subw|subw rd, rs, rs|R|||RV64 subtract word|rd = sext32(rs1 - rs2);sllw|sllw rd, rs, rs|R|||RV64 shift-left word|rd = sext32(rs1[31:0] << (rs2 & 31));srlw|srlw rd, rs, rs|R|||RV64 logical shift-right word|rd = sext32(rs1[31:0] >> (rs2 & 31) logical);sraw|sraw rd, rs, rs|R|||RV64 arithmetic shift-right word|rd = sext32(rs1[31:0] >> (rs2 & 31) arithmetic);mulw|mulw rd, rs, rs|R|||RV64 multiply word|rd = sext32(rs1 * rs2);divw|divw rd, rs, rs|R|||RV64 signed divide word|rd = sext32(rs1[31:0] / rs2[31:0] signed);divuw|divuw rd, rs, rs|R|||RV64 unsigned divide word|rd = sext32(rs1[31:0] / rs2[31:0] unsigned);remw|remw rd, rs, rs|R|||RV64 signed remainder word|rd = sext32(rs1[31:0] %% rs2[31:0] signed);remuw|remuw rd, rs, rs|R|||RV64 unsigned remainder word|rd = sext32(rs1[31:0] %% rs2[31:0] unsigned);lui|lui rd, imm|U|0..0xFFFFF||load upper immediate (20-bit field)|rd = sext(imm20 << 12);auipc|auipc rd, imm|U|0..0xFFFFF||PC-relative upper immediate|rd = pc + sext(imm20 << 12);li|li rd, imm|pseudo||+/-2047 addi else lui+addiw|load immediate (wide matches GNU as lui+addiw)|rd = imm (materialized);mv|mv rd, rs|pseudo||addi rd, rs, 0|move register|rd = rs1;not|not rd, rs|pseudo||xori rd, rs, -1|bitwise NOT|rd = ~rs1;neg|neg rd, rs|pseudo||sub rd, zero, rs|two's-complement negation|rd = -rs1;seqz|seqz rd, rs|pseudo||sltiu rd, rs, 1|set if equal to zero|rd = (rs1 == 0);snez|snez rd, rs|pseudo||sltu rd, zero, rs|set if not equal to zero|rd = (rs1 != 0);ld|ld rd, imm(rs)|I|-2048..2047||load doubleword|rd = mem64[rs1 + sext(imm)];lw|lw rd, imm(rs)|I|-2048..2047||load word|rd = sext(mem32[rs1 + sext(imm)]);lwu|lwu rd, imm(rs)|I|-2048..2047||load word unsigned|rd = zext(mem32[rs1 + sext(imm)]);lh|lh rd, imm(rs)|I|-2048..2047||load halfword|rd = sext(mem16[rs1 + sext(imm)]);lhu|lhu rd, imm(rs)|I|-2048..2047||load halfword unsigned|rd = zext(mem16[rs1 + sext(imm)]);lb|lb rd, imm(rs)|I|-2048..2047||load byte|rd = sext(mem8[rs1 + sext(imm)]);lbu|lbu rd, imm(rs)|I|-2048..2047||load byte unsigned|rd = zext(mem8[rs1 + sext(imm)]);sd|sd rs, imm(rd)|S|-2048..2047||store doubleword|mem64[rs1 + sext(imm)] = rs2;sw|sw rs, imm(rd)|S|-2048..2047||store word|mem32[rs1 + sext(imm)] = rs2[31:0];sh|sh rs, imm(rd)|S|-2048..2047||store halfword|mem16[rs1 + sext(imm)] = rs2[15:0];sb|sb rs, imm(rd)|S|-2048..2047||store byte|mem8[rs1 + sext(imm)] = rs2[7:0];jalr|jalr rd, imm(rs)|I|-2048..2047||jump and link register (short: jalr rs -> jalr ra,0(rs))|rd = pc+4, pc = (rs1 + sext(imm)) & ~1;j|j label|pseudo||jal x0, label|unconditional jump|pc = pc + sext(imm)  (jal x0);jr|jr rs|pseudo||jalr zero, 0(rs)|jump register|pc = rs1  (jalr x0, 0(rs1));call|call label|pseudo||auipc+jalr|PC-relative call|ra = pc+8, pc = target  (auipc + jalr);ret|ret|pseudo||jalr zero, ra, 0|return from call|pc = ra  (jalr x0, 0(ra));beq|beq rs1, rs2, label|B|+/-4KiB||branch if equal|if (rs1 == rs2) pc += sext(imm);bne|bne rs1, rs2, label|B|+/-4KiB||branch if not equal|if (rs1 != rs2) pc += sext(imm);blt|blt rs1, rs2, label|B|+/-4KiB||branch if signed less|if (rs1 <s rs2) pc += sext(imm);bge|bge rs1, rs2, label|B|+/-4KiB||branch if signed greater/equal|if (rs1 >=s rs2) pc += sext(imm);bltu|bltu rs1, rs2, label|B|+/-4KiB||branch if unsigned less|if (rs1 <u rs2) pc += sext(imm);bgeu|bgeu rs1, rs2, label|B|+/-4KiB||branch if unsigned greater/equal|if (rs1 >=u rs2) pc += sext(imm);beqz|beqz rs, label|pseudo||beq rs, zero, label|branch if zero|if (rs1 == 0) pc += sext(imm);bnez|bnez rs, label|pseudo||bne rs, zero, label|branch if non-zero|if (rs1 != 0) pc += sext(imm);nop|nop|pseudo||addi zero, zero, 0|no operation|no operation  (addi x0, x0, 0);wfi|wfi|I|||wait for interrupt|wait for interrupt (hint), stall until an IRQ is pending;mret|mret|I|||return from M-mode trap|pc = mepc, priv = mstatus.MPP, mstatus.MIE = MPIE;sret|sret|I|||return from S-mode trap|pc = sepc, priv = sstatus.SPP, sstatus.SIE = SPIE;ecall|ecall|I|||environment call|raise environment-call exception (trap to M/S handler);ebreak|ebreak|I|||breakpoint|raise breakpoint exception (trap to debugger);fencei|fence.i rd, rs, imm|I|||instruction fence|synchronize I-fetch with prior data writes (fence.i);fence.i|fence.i rd, rs, imm|I|||instruction fence (dotted alias)|synchronize I-fetch with prior data writes;csrr|csrr rd, csr|I|||CSR read|rd = csr;csrw|csrw csr, rs|I|||CSR write|csr = rs1;csrs|csrs csr, rs|I|||CSR set bits|csr = csr OR rs1  (set bits);csrc|csrc csr, rs|I|||CSR clear bits|csr = csr & ~rs1  (clear bits);csrrw|csrrw rd, csr, rs|I|||atomic CSR exchange|rd = csr, csr = rs1;csrrs|csrrs rd, csr, rs|I|||atomic CSR read-set|rd = csr, csr = csr OR rs1;csrrc|csrrc rd, csr, rs|I|||atomic CSR read-clear|rd = csr, csr = csr & ~rs1;csrrwi|csrrwi rd, csr, imm|I|0..31||CSR exchange immediate|rd = csr, csr = zimm5;csrrsi|csrrsi rd, csr, imm|I|0..31||CSR read-set immediate|rd = csr, csr = csr OR zimm5;csrrci|csrrci rd, csr, imm|I|0..31||CSR read-clear immediate|rd = csr, csr = csr & ~zimm5;csrwi|csrwi csr, imm|I|0..31||CSR write immediate|csr = zimm5;csrsi|csrsi csr, imm|I|0..31||CSR set immediate|csr = csr OR zimm5;csrci|csrci csr, imm|I|0..31||CSR clear immediate|csr = csr & ~zimm5;rdtime|rdtime rd|pseudo||csrr rd, time|read time CSR|rd = time CSR (wall-clock tick);fence|fence pred, succ|I|||memory-ordering fence (bare fence = iorw,iorw full barrier)|order pred-set mem ops before succ-set; masks use letters i/o/r/w;sfence.vma|sfence.vma rs1, rs2|R|||supervisor fence for address translation (bare = flush all)|flush TLB for vaddr rs1 / asid rs2 (x0,x0 = flush everything);lifp|lifp rd, imm|I|||HolyC label-in-function-pointer (host asm)|rd = address of label (HolyC label-in-function-pointer, host asm);lr.d|lr.d rd, (rs)|A|||load-reserved doubleword|rd = mem64[rs1], set reservation on the block;lr.w|lr.w rd, (rs)|A|||load-reserved word|rd = sext(mem32[rs1]), set reservation;lrd|lrd rd, (rs)|A|||lr.d alias (no dot)|rd = mem64[rs1], set reservation (lr.d alias);lrw|lrw rd, (rs)|A|||lr.w alias|rd = sext(mem32[rs1]), set reservation (lr.w alias);sc.d|sc.d rd, rs, (rt)|A|||store-conditional doubleword|if reserved: mem64[rs1]=rs2, rd=0, else rd=1;sc.w|sc.w rd, rs, (rt)|A|||store-conditional word|if reserved: mem32[rs1]=rs2, rd=0, else rd=1;scd|scd rd, rs, (rt)|A|||sc.d alias|sc.d alias;scw|scw rd, rs, (rt)|A|||sc.w alias|sc.w alias;amoswap.d|amoswap.d rd, rs, (rt)|A|||atomic swap doubleword|t = mem64[rs1], mem64[rs1] = rs2, rd = t (atomic);amoadd.d|amoadd.d rd, rs, (rt)|A|||atomic add doubleword|t = mem64[rs1], mem64[rs1] = t + rs2, rd = t;amoxor.d|amoxor.d rd, rs, (rt)|A|||atomic XOR doubleword|t = mem64[rs1], mem64[rs1] = t ^ rs2, rd = t;amoand.d|amoand.d rd, rs, (rt)|A|||atomic AND doubleword|t = mem64[rs1], mem64[rs1] = t & rs2, rd = t;amoor.d|amoor.d rd, rs, (rt)|A|||atomic OR doubleword|t = mem64[rs1], mem64[rs1] = t OR rs2, rd = t;amomin.d|amomin.d rd, rs, (rt)|A|||atomic signed min doubleword|t = mem64[rs1], mem64[rs1] = min_s(t, rs2), rd = t;amomax.d|amomax.d rd, rs, (rt)|A|||atomic signed max doubleword|t = mem64[rs1], mem64[rs1] = max_s(t, rs2), rd = t;amominu.d|amominu.d rd, rs, (rt)|A|||atomic unsigned min doubleword|t = mem64[rs1], mem64[rs1] = min_u(t, rs2), rd = t;amomaxu.d|amomaxu.d rd, rs, (rt)|A|||atomic unsigned max doubleword|t = mem64[rs1], mem64[rs1] = max_u(t, rs2), rd = t;amoswap.w|amoswap.w rd, rs, (rt)|A|||atomic swap word|t = mem32[rs1], mem32[rs1] = rs2, rd = sext(t);amoadd.w|amoadd.w rd, rs, (rt)|A|||atomic add word|t = mem32[rs1], mem32[rs1] = t + rs2, rd = sext(t);amoxor.w|amoxor.w rd, rs, (rt)|A|||atomic XOR word|t = mem32[rs1], mem32[rs1] = t ^ rs2, rd = sext(t);amoand.w|amoand.w rd, rs, (rt)|A|||atomic AND word|t = mem32[rs1], mem32[rs1] = t & rs2, rd = sext(t);amoor.w|amoor.w rd, rs, (rt)|A|||atomic OR word|t = mem32[rs1], mem32[rs1] = t OR rs2, rd = sext(t);amomin.w|amomin.w rd, rs, (rt)|A|||atomic signed min word|t = mem32[rs1], mem32[rs1] = min_s(t, rs2), rd = sext(t);amomax.w|amomax.w rd, rs, (rt)|A|||atomic signed max word|t = mem32[rs1], mem32[rs1] = max_s(t, rs2), rd = sext(t);amominu.w|amominu.w rd, rs, (rt)|A|||atomic unsigned min word|t = mem32[rs1], mem32[rs1] = min_u(t, rs2), rd = sext(t);amomaxu.w|amomaxu.w rd, rs, (rt)|A|||atomic unsigned max word|t = mem32[rs1], mem32[rs1] = max_u(t, rs2), rd = sext(t);amoswapd|amoswapd rd, rs, (rt)|A|||amoswap.d alias|amoswap.d alias;amoaddd|amoaddd rd, rs, (rt)|A|||amoadd.d alias|amoadd.d alias;amoxord|amoxord rd, rs, (rt)|A|||amoxor.d alias|amoxor.d alias;amoandd|amoandd rd, rs, (rt)|A|||amoand.d alias|amoand.d alias;amoord|amoord rd, rs, (rt)|A|||amoor.d alias|amoor.d alias;amomind|amomind rd, rs, (rt)|A|||amomin.d alias|amomin.d alias;amomaxd|amomaxd rd, rs, (rt)|A|||amomax.d alias|amomax.d alias;amominud|amominud rd, rs, (rt)|A|||amominu.d alias|amominu.d alias;amomaxud|amomaxud rd, rs, (rt)|A|||amomaxu.d alias|amomaxu.d alias;amoswapw|amoswapw rd, rs, (rt)|A|||amoswap.w alias|amoswap.w alias;amoaddw|amoaddw rd, rs, (rt)|A|||amoadd.w alias|amoadd.w alias;amoxorw|amoxorw rd, rs, (rt)|A|||amoxor.w alias|amoxor.w alias;amoandw|amoandw rd, rs, (rt)|A|||amoand.w alias|amoand.w alias;amoorw|amoorw rd, rs, (rt)|A|||amoor.w alias|amoor.w alias;amominw|amominw rd, rs, (rt)|A|||amomin.w alias|amomin.w alias;amomaxw|amomaxw rd, rs, (rt)|A|||amomax.w alias|amomax.w alias;amominuw|amominuw rd, rs, (rt)|A|||amominu.w alias|amominu.w alias;amomaxuw|amomaxuw rd, rs, (rt)|A|||amomaxu.w alias|amomaxu.w alias;fsqrtd|fsqrt.d fd, fs|R|||D-extension square root|fd = sqrt(fs1)  (double);faddd|fadd.d fd, fs1, fs2|R|||double add|fd = fs1 + fs2  (double);fsubd|fsub.d fd, fs1, fs2|R|||double subtract|fd = fs1 - fs2  (double);fmuld|fmul.d fd, fs1, fs2|R|||double multiply|fd = fs1 * fs2  (double);fdivd|fdiv.d fd, fs1, fs2|R|||double divide|fd = fs1 / fs2  (double);fled|fle.d rd, fs1, fs2|R|||double less-or-equal|rd = (fs1 <= fs2)  (double compare);fltd|flt.d rd, fs1, fs2|R|||double less-than|rd = (fs1 < fs2)  (double compare);feqd|feq.d rd, fs1, fs2|R|||double equal|rd = (fs1 == fs2)  (double compare);fmvdx|fmv.d.x fd, rs|R|||move GPR to FPR|fd = raw_bits(rs1)  (GPR to FPR, no convert);fmvxd|fmv.x.d rd, fs|R|||move FPR to GPR|rd = raw_bits(fs1)  (FPR to GPR, no convert);fcvtdl|fcvt.d.l fd, rs|R|||convert long to double|fd = (double)(i64)rs1;fcvtld_rtz|fcvt.l.d rd, fs|R|||convert double to long (RTZ)|rd = (i64)fs1  (round toward zero);fcvtld_rdn|fcvt.l.d rd, fs|R|||convert double to long (RDN)|rd = (i64)fs1  (round down);fcvtld_rmm|fcvt.l.d rd, fs|R|||convert double to long (RMM)|rd = (i64)fs1  (round to nearest, ties away);fsgnj.d|fsgnj.d fd, fs1, fs2|R|||sign-inject: magnitude of fs1, sign of fs2|fd = abs(fs1) with sign bit of fs2;fsgnjn.d|fsgnjn.d fd, fs1, fs2|R|||sign-inject negated: sign of ~fs2|fd = abs(fs1) with sign bit of (NOT fs2);fsgnjx.d|fsgnjx.d fd, fs1, fs2|R|||sign-inject xor (fabs/fneg building block)|fd = fs1 with sign bit = sign(fs1) XOR sign(fs2);fmin.d|fmin.d fd, fs1, fs2|R|||minimum (double, IEEE min)|fd = min(fs1, fs2), NaN-quieting;fmax.d|fmax.d fd, fs1, fs2|R|||maximum (double, IEEE max)|fd = max(fs1, fs2), NaN-quieting;fclass.d|fclass.d rd, fs|R|||classify double into a 10-bit mask|rd bit: 0=-inf 1=-normal 2=-subnormal 3=-0 4=+0 5=+subnormal 6=+normal 7=+inf 8=sNaN 9=qNaN;fcvt.w.d|fcvt.w.d rd, fs|R|||convert double to 32-bit signed int (dyn rm)|rd = sext32((i32)fs1);fcvt.wu.d|fcvt.wu.d rd, fs|R|||convert double to 32-bit unsigned int (dyn rm)|rd = sext32((u32)fs1);fcvt.l.d|fcvt.l.d rd, fs|R|||convert double to 64-bit signed int (dyn rm)|rd = (i64)fs1;fcvt.lu.d|fcvt.lu.d rd, fs|R|||convert double to 64-bit unsigned int (dyn rm)|rd = (u64)fs1;fcvt.d.w|fcvt.d.w fd, rs|R|||convert 32-bit signed int to double (exact)|fd = (f64)(i32)rs1;fcvt.d.wu|fcvt.d.wu fd, rs|R|||convert 32-bit unsigned int to double (exact)|fd = (f64)(u32)rs1;fcvt.d.l|fcvt.d.l fd, rs|R|||convert 64-bit signed int to double (dyn rm)|fd = (f64)(i64)rs1;fcvt.d.lu|fcvt.d.lu fd, rs|R|||convert 64-bit unsigned int to double (dyn rm)|fd = (f64)(u64)rs1;fcvt.s.d|fcvt.s.d fd, fs|R|||narrow double to single float (dyn rm)|fd = (f32)fs1  (single-precision result);fcvt.d.s|fcvt.d.s fd, fs|R|||widen single float to double (exact)|fd = (f64)fs1;fmadd.d|fmadd.d fd, fs1, fs2, fs3|R4|||fused multiply-add double (one rounding)|fd = fs1*fs2 + fs3;fmsub.d|fmsub.d fd, fs1, fs2, fs3|R4|||fused multiply-subtract double|fd = fs1*fs2 - fs3;fnmsub.d|fnmsub.d fd, fs1, fs2, fs3|R4|||fused negate multiply-sub double|fd = -(fs1*fs2) + fs3;fnmadd.d|fnmadd.d fd, fs1, fs2, fs3|R4|||fused negate multiply-add double|fd = -(fs1*fs2) - fs3;fmadd.s|fmadd.s fd, fs1, fs2, fs3|R4|||fused multiply-add single|fd = fs1*fs2 + fs3 (float);fmsub.s|fmsub.s fd, fs1, fs2, fs3|R4|||fused multiply-subtract single|fd = fs1*fs2 - fs3 (float);fnmsub.s|fnmsub.s fd, fs1, fs2, fs3|R4|||fused negate multiply-sub single|fd = -(fs1*fs2) + fs3 (float);fnmadd.s|fnmadd.s fd, fs1, fs2, fs3|R4|||fused negate multiply-add single|fd = -(fs1*fs2) - fs3 (float);flw|flw fd, imm(rs)|I|-2048..2047||load single float word|fd = mem32[rs1 + sext(imm)] (single);fsw|fsw fs, imm(rs)|S|-2048..2047||store single float word|mem32[rs1 + sext(imm)] = fs2 (single);fld|fld fd, imm(rs)|I|-2048..2047||load double float|fd = mem64[rs1 + sext(imm)];fsd|fsd fs, imm(rs)|S|-2048..2047||store double float|mem64[rs1 + sext(imm)] = fs2;fadd.s|fadd.s fd, fs1, fs2|R|||single add|fd = fs1 + fs2 (float);fsub.s|fsub.s fd, fs1, fs2|R|||single subtract|fd = fs1 - fs2 (float);fmul.s|fmul.s fd, fs1, fs2|R|||single multiply|fd = fs1 * fs2 (float);fdiv.s|fdiv.s fd, fs1, fs2|R|||single divide|fd = fs1 / fs2 (float);fsqrt.s|fsqrt.s fd, fs|R|||single square root|fd = sqrt(fs1) (float);fsgnj.s|fsgnj.s fd, fs1, fs2|R|||single sign-inject: magnitude fs1, sign fs2|fd = abs(fs1) with sign bit of fs2 (float);fsgnjn.s|fsgnjn.s fd, fs1, fs2|R|||single sign-inject negated|fd = abs(fs1) with sign bit of (NOT fs2);fsgnjx.s|fsgnjx.s fd, fs1, fs2|R|||single sign-inject xor|fd = fs1 with sign = sign(fs1) XOR sign(fs2);fmin.s|fmin.s fd, fs1, fs2|R|||single minimum (IEEE)|fd = min(fs1, fs2) (float);fmax.s|fmax.s fd, fs1, fs2|R|||single maximum (IEEE)|fd = max(fs1, fs2) (float);fle.s|fle.s rd, fs1, fs2|R|||single less-or-equal|rd = (fs1 <= fs2) (float compare);flt.s|flt.s rd, fs1, fs2|R|||single less-than|rd = (fs1 < fs2) (float compare);feq.s|feq.s rd, fs1, fs2|R|||single equal|rd = (fs1 == fs2) (float compare);fclass.s|fclass.s rd, fs|R|||classify single into a 10-bit mask|rd bit: 0=-inf 1=-normal 2=-subnormal 3=-0 4=+0 5=+subnormal 6=+normal 7=+inf 8=sNaN 9=qNaN;fmv.x.w|fmv.x.w rd, fs|R|||move single FPR bits to GPR|rd = sext32(raw_bits(fs1)) (no convert);fmv.w.x|fmv.w.x fd, rs|R|||move GPR low32 bits to single FPR|fd = raw_bits(rs1[31:0]) (no convert);fcvt.w.s|fcvt.w.s rd, fs|R|||convert single to 32-bit signed int (dyn rm)|rd = sext32((i32)fs1);fcvt.wu.s|fcvt.wu.s rd, fs|R|||convert single to 32-bit unsigned int (dyn rm)|rd = sext32((u32)fs1);fcvt.l.s|fcvt.l.s rd, fs|R|||convert single to 64-bit signed int (dyn rm)|rd = (i64)fs1;fcvt.lu.s|fcvt.lu.s rd, fs|R|||convert single to 64-bit unsigned int (dyn rm)|rd = (u64)fs1;fcvt.s.w|fcvt.s.w fd, rs|R|||convert 32-bit signed int to single (dyn rm)|fd = (f32)(i32)rs1;fcvt.s.wu|fcvt.s.wu fd, rs|R|||convert 32-bit unsigned int to single (dyn rm)|fd = (f32)(u32)rs1;fcvt.s.l|fcvt.s.l fd, rs|R|||convert 64-bit signed int to single (dyn rm)|fd = (f32)(i64)rs1;fcvt.s.lu|fcvt.s.lu fd, rs|R|||convert 64-bit unsigned int to single (dyn rm)|fd = (f32)(u64)rs1;c.nop|c.nop|C|||compressed no-op (16-bit)|no operation (= c.addi x0,0, 2 bytes);c.ebreak|c.ebreak|C|||compressed breakpoint (16-bit)|raise breakpoint exception (2 bytes);c.mv|c.mv rd, rs|C|||compressed move, rd/rs != x0 (16-bit CR)|rd = rs2;c.add|c.add rd, rs|C|||compressed add, rd/rs != x0 (16-bit CR)|rd = rd + rs2;c.li|c.li rd, imm|C|-32..31||compressed load-immediate, rd != x0 (16-bit CI)|rd = sext(imm6);c.addi|c.addi rd, imm|C|-32..31||compressed add-immediate, rd != x0 (16-bit CI)|rd = rd + sext(imm6);c.slli|c.slli rd, shamt|C|0..63||compressed shift-left-immediate, rd != x0 (16-bit CI, RV64 shamt6)|rd = rd << shamt;c.jr|c.jr rs|C|||compressed jump-register, rs != x0 (16-bit CR)|pc = rs1;c.jalr|c.jalr rs|C|||compressed jump-and-link-register, rs != x0 (16-bit CR)|ra = pc+2, pc = rs1;c.sub|c.sub rd, rs|C|||compressed subtract, regs x8-x15 (16-bit CA)|rd = rd - rs2;c.and|c.and rd, rs|C|||compressed AND, regs x8-x15 (16-bit CA)|rd = rd & rs2;c.or|c.or rd, rs|C|||compressed OR, regs x8-x15 (16-bit CA)|rd = rd OR rs2;c.xor|c.xor rd, rs|C|||compressed XOR, regs x8-x15 (16-bit CA)|rd = rd ^ rs2;c.j|c.j target|C|-2048..2046||compressed jump, even PC-rel offset or label (16-bit CJ)|pc = pc + off;c.beqz|c.beqz rs, target|C|-256..254||compressed branch-if-zero, rs in x8-x15 (16-bit CB)|if (rs1 == 0) pc += off;c.bnez|c.bnez rs, target|C|-256..254||compressed branch-if-nonzero, rs in x8-x15 (16-bit CB)|if (rs1 != 0) pc += off;c.ld|c.ld rd, off(rs)|C|0..248||compressed load doubleword, rd/rs in x8-x15, off mult of 8 (16-bit CL)|rd = mem64[rs1 + off];c.sd|c.sd rs2, off(rs)|C|0..248||compressed store doubleword, rs2/rs in x8-x15, off mult of 8 (16-bit CS)|mem64[rs1 + off] = rs2;c.lw|c.lw rd, off(rs)|C|0..124||compressed load word, rd/rs in x8-x15, off mult of 4 (16-bit CL)|rd = sext(mem32[rs1 + off]);c.sw|c.sw rs2, off(rs)|C|0..124||compressed store word, rs2/rs in x8-x15, off mult of 4 (16-bit CS)|mem32[rs1 + off] = rs2[31:0];c.addiw|c.addiw rd, imm|C|-32..31||compressed RV64 add-word immediate, rd != x0 (16-bit CI)|rd = sext32(rd + imm);c.andi|c.andi rd, imm|C|-32..31||compressed AND immediate, rd in x8-x15 (16-bit CB)|rd = rd & sext(imm6);c.srli|c.srli rd, shamt|C|0..63||compressed shift-right-logical immediate, rd in x8-x15 (16-bit CB)|rd = rd >> shamt logical;c.srai|c.srai rd, shamt|C|0..63||compressed shift-right-arithmetic immediate, rd in x8-x15 (16-bit CB)|rd = rd >> shamt arithmetic;c.lui|c.lui rd, imm|C|-32..31 nz||compressed load-upper-immediate, rd not x0/x2, imm a nonzero 6-bit field (16-bit CI)|rd = sext(imm6) << 12;c.addi16sp|c.addi16sp sp, imm|C|-512..496 x16||compressed sp frame adjust, imm nonzero mult of 16 (16-bit CI)|sp = sp + imm;c.addi4spn|c.addi4spn rd, sp, uimm|C|4..1020 x4||compressed sp+imm to rd', rd' in x8-x15, uimm nonzero mult of 4 (16-bit CIW)|rd = sp + uimm;c.lwsp|c.lwsp rd, off(sp)|C|0..252||compressed sp-relative load word, rd != x0, off mult of 4 (16-bit CI)|rd = sext(mem32[sp + off]);c.ldsp|c.ldsp rd, off(sp)|C|0..504||compressed sp-relative load doubleword, rd != x0, off mult of 8 (16-bit CI)|rd = mem64[sp + off];c.swsp|c.swsp rs2, off(sp)|C|0..252||compressed sp-relative store word, off mult of 4 (16-bit CSS)|mem32[sp + off] = rs2[31:0];c.sdsp|c.sdsp rs2, off(sp)|C|0..504||compressed sp-relative store doubleword, off mult of 8 (16-bit CSS)|mem64[sp + off] = rs2;c.fld|c.fld frd, off(rs)|C|0..248||compressed load double-float, frd in f8-f15, base rs in x8-x15, off mult of 8 (16-bit CL)|frd = mem64[rs1 + off];c.fsd|c.fsd frs2, off(rs)|C|0..248||compressed store double-float, frs2 in f8-f15, base rs in x8-x15, off mult of 8 (16-bit CS)|mem64[rs1 + off] = frs2;c.fldsp|c.fldsp frd, off(sp)|C|0..504||compressed sp-relative load double-float, off mult of 8 (16-bit CI)|frd = mem64[sp + off];c.fsdsp|c.fsdsp frs2, off(sp)|C|0..504||compressed sp-relative store double-float, off mult of 8 (16-bit CSS)|mem64[sp + off] = frs2;";
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

#define ASM_DOC_WHY 512
U8 g_rv_asm_doc_note2[ASM_DOC_WHY];

// Prose, broken at a space near the column limit. The motivation lines are sentences, not
// fields, and a man page that runs them off the side of an 80-column terminal is not one.
U0 RVAsmDocWrap(U8 *indent, U8 *text, I64 width)
{
  U8 line[128];
  I64 n = 0, brk;
  U8 *p;
  p = text;
  while (*p) {
    n = 0;
    while (p[n] && n < width)
      n++;
    if (p[n]) {
      brk = n;
      while (brk > 0 && p[brk] != ' ')
        brk--;
      if (brk > 0)
        n = brk;
    }
    MemCpy(line, p, n);
    line[n] = 0;
    Print("%s%s\n", indent, line);
    p += n;
    while (*p == ' ')
      p++;
  }
}

U0 RVAsmDocPrintField(U8 *label, U8 *val)
{
  if (!val || !*val)
    return;
  Print("%s%s\n", label, val);
}

// TRUE if `mn` is a branch/jump the guest asm{} assembler accepts with a NUMERIC
// PC-relative offset (not a label). Keeps AsmDoc's hint in sync with Asm_RV.HC.
// Examples and motivation, kept apart from the 244-entry catalog above: that one says what an
// instruction IS, this one says why you would reach for it and what it looks like in use. A
// mnemonic with no entry here still gets its template, encoding and semantics — the man page
// simply has fewer sections. Fields: mn | example | example | example | motivation.
U8 *rv_asm_ex_raw;
U0 RVAsmExRawInit()
{
  rv_asm_ex_raw = "addi|addi a0, a0, 1           # a0 = a0 + 1|addi sp, sp, -32         # open a stack frame|addi a0, zero, 7         # what li a0,7 becomes|The workhorse of RISC-V. There is no separate increment, move or load-small-constant instruction: all three are addi with one operand tied to zero. A frame prologue is addi on sp, a move is addi rd,rs,0, and a small constant is addi rd,zero,imm.;add|add a2, a0, a1           # a2 = a0 + a1|add t0, t0, t1           # accumulate||Register-register add. Use addi when one side is a constant that fits in 12 bits - it saves materialising the constant first.;sub|sub a0, a0, a1           # a0 = a0 - a1|sub t0, zero, t0         # negate, which is what neg is||There is no subi: subtract a constant with addi and a negative immediate. That is why the immediate range is asymmetric in your favour at -2048.;li|li a0, 7                 # one addi|li a0, 0x12345678        # lui + addiw pair|li t0, -1                # all ones, one instruction|A pseudo-instruction, not hardware. It becomes addi for anything in -2048..2047 and lui+addiw beyond that, so the same line can cost one instruction or two. Check with u if the size matters.;mv|mv a1, a0                # a1 = a0|||addi rd,rs,0 wearing a friendlier name. Moving a register costs an add because the ISA has no move unit - that is the RISC bargain.;lui|lui a0, 0x10E00          # a0 = 0x10E00 << 12|||Loads a 20-bit immediate into the TOP of a register, leaving the low 12 bits zero for a following addi. Every large constant on RISC-V is this pair. Note the operand is the already-shifted field, not the final value.;auipc|auipc t0, 0              # t0 = address of this instruction|auipc t0, 0x1            # t0 = pc + 0x1000||The only way to learn where you are. RISC-V has no pc-relative addressing mode and cannot read pc directly, so position-independent code, call and every la of a nearby symbol start with auipc. It is also how a JIT finds its own tables.;andi|andi a0, a0, 0xFF        # keep the low byte|andi a0, a0, -16         # align down to 16||Masking. A negative immediate sign-extends to a run of ones, which is how you round an address DOWN to a power of two in one instruction.;slli|slli a0, a0, 3           # a0 = a0 * 8|slli t6, t6, 3           # build 0x87000000 from lui 0x10E00||Multiply by a power of two, and half of every index calculation: an I64 array element is slli 3 then add. It is also how a two-instruction constant is built when lui alone cannot reach.;srli|srli a0, a0, 12          # page number from an address|||Logical shift right - zeros come in at the top. For signed division by a power of two you want srai instead, or negative numbers round the wrong way.;srai|srai a0, a0, 2           # a0 / 4, rounding toward -inf|||Arithmetic shift right: the sign bit is replicated. Note this is NOT what C division does for negatives - C rounds toward zero, this rounds down - which is why the compiler emits extra instructions for signed division by a constant.;sltu|sltu t0, a0, a1          # t0 = a0 <u a1|sltu t0, zero, a0        # t0 = (a0 != 0), which is snez||Unsigned compare into a register. It is also how you get a carry flag on a machine that has no flags: after add a2,a0,a1, sltu t0,a2,a0 is 1 exactly when the add wrapped.;ld|ld a0, 0(t6)             # load a doubleword|ld a0, 16(sp)            # a local||The 12-bit signed offset is the whole addressing mode: no index register, no scaling. An index becomes slli+add first, which is why array loops on RISC-V keep a running pointer instead.;sd|sd a0, 0(t6)             # store a doubleword|sd ra, 8(sp)             # save the return address||Same addressing as ld. Note the operand order reads backwards from the load: the register being STORED comes first, the address second.;lbu|lbu a0, 0(a1)            # a byte, zero-extended|||Use lbu for bytes that are data (characters, flags) and lb for bytes that are small signed numbers - the difference is whether bit 7 spreads into the top 56 bits.;beq|beq a0, a1, same         # jump if equal|beq a0, zero, done       # which is beqz||RISC-V compares and branches in ONE instruction - there is no flags register to set first. The comparison is part of the branch, which is why there are six of them.;bltu|bltu a0, a1, less        # unsigned less-than|bgeu a0, t0, oob         # bounds check in one instruction||The unsigned compare is the bounds check: bgeu index,limit,fail catches both too-big and negative in one go, because a negative index is a huge unsigned number.;jal|jal ra, target           # call, saving the return address|jal zero, target         # plain jump, which is j||One instruction for both call and jump: the difference is only which register the return address lands in, and zero discards it. That is the whole of RISC-V control flow - there is no separate call or jmp.;jalr|jalr zero, 0(ra)         # return, which is ret|jalr ra, 0(t0)           # indirect call||The indirect half of jal. Returning is jumping to ra and discarding the new return address, which is why ret is a pseudo-instruction for exactly this.;ret|ret                      # jalr zero, 0(ra)|||Not a real instruction. Knowing it is jalr on ra explains why a leaf function need not touch the stack at all, and why clobbering ra loses your way home.;call|call Foo                 # auipc + jalr|||A PC-relative call assembled as a pair, so it reaches +/-2 GiB without a fixed address anywhere in the encoding. That is what makes RISC-V code position-independent by default.;csrr|csrr a0, mcause          # why did I trap|csrr a0, 0x003           # fcsr, by number||The CSR number is an IMMEDIATE in the encoding, not an operand, so there is no such thing as reading a CSR whose number is in a register. Any by-number reader is a switch or self-modifying code - see docs/MACHINE_STATE_SURVEY.md.;csrw|csrw mtvec, t0           # install a trap vector|||Writing a CSR is how you configure the machine: the trap vector, the interrupt enables, the timer comparand. Note csrw discards the old value - use csrrw if you want it back.;csrrs|csrrs a0, mstatus, t0    # set bits, keep the rest|||Read-modify-write in one atomic instruction. csrs/csrc with a register are how you flip individual mstatus bits without a read-modify-write race against a trap that fires in between.;ecall|ecall                    # trap to the handler|||A deliberate trap - the system call. In this port it lands in the same handler a fault does, which is why the debugger sees both through one freeze.;ebreak|ebreak                   # breakpoint|||What a debugger writes over an instruction to stop there. Bp/BpClr in this REPL do exactly that, and the trap handler then tells you where you are.;mul|mul a0, a0, a1           # low 64 bits|||M extension. mul gives the low half and mulh the high half, so a full 128-bit product is two instructions - the pair is how the rv32 lifter builds 64-bit arithmetic.;div|div a0, a0, a1           # signed|||Division does not trap on RISC-V: divide by zero gives all-ones and overflow gives the dividend. Check the divisor yourself if you care - the hardware will not.;fence|fence rw, rw             # order loads and stores|fence                    # the full barrier||Memory ordering. RISC-V is weakly ordered: without a fence another hart can observe your stores in a different order. Device drivers need one between filling a descriptor and ringing a doorbell.;lr.d|lr.d t0, (a0)            # load-reserved|||Half of the atomic pair. lr.d takes a reservation and sc.d only succeeds if nothing touched the line in between - that is a compare-and-swap loop without a lock prefix.;amoadd.d|amoadd.d t0, t1, (a0)    # atomic add, old value in t0|||One instruction where the lr/sc pair would be a loop. Use the AMOs for counters and flags and keep lr/sc for the cases that actually need a read-modify-write of your own shape.;fmv.d.x|fmv.d.x fa0, t0          # bits into a float register|||Moves RAW BITS, no conversion: 4 in t0 becomes the double whose encoding is 4, a subnormal near zero - not 4.0. Use fcvt.d.l to convert a number. This is the instruction for building a float from a hex pattern, which is how you make an infinity or a NaN by hand.;fcvt.d.l|fcvt.d.l fa0, a0         # (double)(I64)a0|||The conversion fmv.d.x is not. Rounding is by the current rounding mode unless you name one - fcvt.d.l fa0,a0,rtz.;fadd.d|fadd.d fa0, fa1, fa2     # double add|||Sets the sticky flags in fcsr rather than trapping, so an overflow is something you find out about by reading fcsr afterwards - Csr('fcsr') in this REPL.;nop|nop                      # addi zero, zero, 0|||An addi that writes x0, which discards it. Padding, alignment, and something to patch over later.;wfi|wfi                      # stop until an interrupt|||An idle loop that does not burn the machine. It is a hint - a hart is allowed to treat it as a nop - so never rely on it for timing.;";
}

// The record for `mn` in the examples table, or 0.
U8 *RVAsmExFindRec(U8 *mn)
{
  U8 *p;
  if (!mn || !*mn)
    return 0;
  if (!rv_asm_ex_raw)
    RVAsmExRawInit;
  p = rv_asm_ex_raw;
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

I64 RVAsmIsGuestBranch(U8 *mn)
{
  if (!mn)
    return FALSE;
  if (!StrICmp(mn, "beq") || !StrICmp(mn, "bne") || !StrICmp(mn, "blt") ||
      !StrICmp(mn, "bge") || !StrICmp(mn, "bltu") || !StrICmp(mn, "bgeu") ||
      !StrICmp(mn, "beqz") || !StrICmp(mn, "bnez") || !StrICmp(mn, "jal") ||
      !StrICmp(mn, "jr"))
    return TRUE;
  return FALSE;
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
    // jal is assemblable but not in the doc catalog (jalr is) - still help.
    if (!StrICmp(mn, "jal")) {
      Print("AsmDoc jal\n");
      Print("  template  jal rd, off  |  jal off (rd=ra)\n");
      Print("  encoding  J-type opcode 0x6F\n");
      Print("  asm{}      target is a NUMERIC even byte offset OR a label, e.g.\n");
      Print("             asm{ jal x0,8 } / asm{ over: ... jal x0,over } (label, either dir)\n");
      Print("  semantics rd = pc+4; pc += off (off even, +/-1 MiB)\n");
      return;
    }
    Print("AsmDoc: unknown '%s' - AsmList(); Tab-complete inside asm{};\n", mn);
    return;
  }
  // A man page, not a row of fields: NAME/SYNOPSIS/DESCRIPTION/EXAMPLES/MOTIVATION/SEE ALSO,
  // with a section omitted when there is nothing to put in it. The examples and the motivation
  // come from a second table (rv_asm_ex_raw) — the catalog says what an instruction IS, and that
  // one says why you would reach for it.
  U8 *ex;
  s = RVAsmDocField(rec, 0, g_rv_asm_doc_buf, ASM_DOC_MN);
  Print("$FG,%d$NAME$FG$\n", YELLOW);
  Print("     %s", s);
  s = RVAsmDocField(rec, 5, g_rv_asm_doc_tpl, ASM_DOC_NOTE);
  if (s && *s)
    Print(" - %s", s);
  Print("\n\n");
  Print("$FG,%d$SYNOPSIS$FG$\n", YELLOW);
  RVAsmDocPrintField("     ", RVAsmDocField(rec, 1, g_rv_asm_doc_buf, ASM_DOC_TPL));
  s = RVAsmDocField(rec, 2, g_rv_asm_doc_buf, ASM_DOC_ENC);
  if (s && *s) {
    Print("     %s-type", s);
    s = RVAsmDocField(rec, 3, g_rv_asm_doc_tpl, ASM_DOC_IMM);
    if (s && *s)
      Print(", immediate %s", s);
    Print("\n");
  }
  Print("\n$FG,%d$DESCRIPTION$FG$\n", YELLOW);
  RVAsmDocPrintField("     ", RVAsmDocField(rec, 6, g_rv_asm_doc_buf, ASM_DOC_NOTE));
  RVAsmDocPrintField("     assembles as ", RVAsmDocField(rec, 4, g_rv_asm_doc_tpl, ASM_DOC_GNU));
  ex = RVAsmExFindRec(mn);
  if (ex) {
    U8 *e1, *e2, *e3;
    e1 = RVAsmDocField(ex, 1, g_rv_asm_doc_buf, ASM_DOC_TPL);
    if (e1 && *e1) {
      Print("\n$FG,%d$EXAMPLES$FG$\n", YELLOW);
      Print("     %s\n", e1);
      e2 = RVAsmDocField(ex, 2, g_rv_asm_doc_buf, ASM_DOC_TPL);
      if (e2 && *e2)
        Print("     %s\n", e2);
      e3 = RVAsmDocField(ex, 3, g_rv_asm_doc_buf, ASM_DOC_TPL);
      if (e3 && *e3)
        Print("     %s\n", e3);
    }
    e1 = RVAsmDocField(ex, 4, g_rv_asm_doc_note2, ASM_DOC_WHY);
    if (e1 && *e1) {
      Print("\n$FG,%d$MOTIVATION$FG$\n", YELLOW);
      RVAsmDocWrap("     ", e1, 66);
    }
  }
  // Use mn (stable arg), NOT s: s points into g_rv_asm_doc_buf, which the field
  // prints above overwrote - by here it holds the last field, not the mnemonic.
  Print("\n$FG,%d$SEE ALSO$FG$\n", YELLOW);
  Print("     AsmList (the whole catalog)   AsmRepl (type one and watch the registers)\n");
  if (RVAsmIsGuestBranch(mn)) {
    if (!StrICmp(mn, "jr")) {
      Print("  asm{}      asm{ jr a0 } = jalr x0,0(a0)\n");
    } else if (!StrICmp(mn, "beqz") || !StrICmp(mn, "bnez")) {
      Print("  asm{}      target is a NUMERIC even byte offset OR a label:\n");
      Print("             asm{ %s a0,8 } or asm{ L: ... %s a0,L } (either direction)\n", mn, mn);
    } else {
      Print("  asm{}      target is a NUMERIC even byte offset OR a label:\n");
      Print("             asm{ %s a0,a1,8 } or asm{ L: ... %s a0,a1,L }\n", mn, mn);
    }
  }
}

// AsmComplete -- AsmComplete(word, out, max)
// NAME
//   AsmComplete - complete a mnemonic from the documented catalog
// SYNOPSIS
//   AsmComplete("fcv", buf, 64);
// DESCRIPTION
//   The same 244 entries AsmList prints and AsmDoc explains, used as the asm REPL's Tab
//   vocabulary — so what completes is exactly what is documented, and a mnemonic cannot be
//   offered by one and unknown to the other. Returns 1 when it filled `out`, 2 when it listed
//   the candidates, 0 when nothing matched.
// SEE ALSO
//   AsmList  AsmDoc  AsmRepl
public I64 AsmComplete(U8 *word, U8 *out, I64 max)
{
  U8 *p, *s;
  I64 n, hits = 0, k, listed = 0;
  if (!word || !out || max < 2)
    return 0;
  // An EMPTY word is allowed and means "all of them" — that is Tab straight after a bare `?`,
  // and listing is what a shell does when there is nothing to narrow by.
  if (!rv_asm_doc_raw)
    RVAsmDocRawInit;
  n = StrLen(word);
  out[0] = 0;
  p = rv_asm_doc_raw;
  while (*p) {
    s = RVAsmDocField(p, 0, g_rv_asm_doc_buf, ASM_DOC_MN);
    if (s && *s && StrLen(s) >= n && !MemCmp(s, word, n)) {
      hits++;
      if (hits == 1) {
        StrCpy(out, s);
        if (StrLen(out) >= max)
          out[max - 1] = 0;
      } else {
        // keep only what every match agrees on
        k = 0;
        while (out[k] && s[k] && out[k] == s[k])
          k++;
        out[k] = 0;
      }
    }
    while (*p && *p != ';')
      p++;
    if (*p == ';')
      p++;
  }
  if (!hits)
    return 0;
  if (StrLen(out) > n)
    return 1;
  // nothing more to add — show the choices rather than beeping
  Print("\n");
  p = rv_asm_doc_raw;
  while (*p && listed < 24) {
    s = RVAsmDocField(p, 0, g_rv_asm_doc_buf, ASM_DOC_MN);
    if (s && *s && StrLen(s) >= n && !MemCmp(s, word, n)) {
      Print("  %s", s);
      listed++;
      if (listed % 6 == 0)
        Print("\n");
    }
    while (*p && *p != ';')
      p++;
    if (*p == ';')
      p++;
  }
  if (listed % 6)
    Print("\n");
  return 2;
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
  Print("Note: the asm{} assembler covers all non-compressed rv64imafdc (I+M+A+F+D+FMA+\n");
  Print("  Zicsr+priv), plus the COMPLETE RVC set (16-bit): reg/imm, c.j/c.beqz/c.bnez,\n");
  Print("  c.ld/c.sd/c.lw/c.sw, c.andi/c.srli/c.srai, c.addiw, c.lui, sp-relative\n");
  Print("  c.lwsp/c.ldsp/c.swsp/c.sdsp + c.addi16sp/c.addi4spn, and float c.fld/c.fsd/\n");
  Print("  c.fldsp/c.fsdsp. `call` assembles too (auipc+jalr pcrel pair) to a\n");
  Print("  block-local label or numeric offset; external-symbol call stays host-only.\n");
  Print("  Branches/jumps take a NUMERIC even byte\n");
  Print("  offset (beq a0,a1,8) OR a label, either direction (loop: ... bnez t0,loop).\n");
  Print("  Float ops that round take an optional trailing rm: rne/rtz/rdn/rup/rmm/dyn\n");
  Print("  (e.g. fcvt.w.d a0,fa1,rtz); omitted = dyn. New float names are dotted (fadd.d,\n");
  Print("  fcvt.w.s); the 14 legacy dot-free names (faddd, fcvtdl) still work. See RISCV_INVENTORY.md\n");
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

// The CSR decoders live in bootstrap/seed/csr_decode.hc now — one copy, shared with the seed
// image, included at the top of this file. The fork that used to sit here knew fewer mstatus
// fields than the seed's copy and decoded no satp at all, which is what two copies do.
U8 *McauseCauseName(I64 v)
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
  CsrDecodeMstatus(v);
}

public U0 Mcause()
{
  //Read and decode the current mcause CSR (last trap cause).
  I64 v = RVWinCsrrMcause();
  I64 intr = (v >> 63) & 1, code = v & 0x7FFFFFFFFFFFFFFF;
  U8 *kind = "Exception";
  if (intr)
    kind = "Interrupt";
  Print("mcause=0x%X  %s code=%d (%s)\n", v, kind, code, McauseCauseName(v));
}

public U0 Csr(U8 *name)
{
  //Read a CSR by name and print it, decoding the interesting ones (mstatus/mie/mip/
  // mtvec/misa/mcause). Covers the M- and S-mode CSRs the port can read.
  I64 v;
  if (!name || !*name) {
    Print("Csr: name — e.g. Csr(\"mtvec\");\n");
    Print("  m: mstatus mie mip mtvec mepc mcause mtval mscratch misa mhartid medeleg mideleg\n");
    Print("     mcounteren mcycle minstret\n");
    Print("  s: sstatus sie sip stvec sepc scause stval satp\n");
    Print("  f: fcsr\n");
    return;
  }
  if (!StrICmp(name, "mstatus"))      { v = RVWinCsrrMstatus();    Print("mstatus=0x%X\n", v);    CsrDecodeMstatus(v); }
  else if (!StrICmp(name, "mie"))     { v = RVWinCsrrMie();        Print("mie=0x%X\n", v);        CsrDecodeMie(v); }
  else if (!StrICmp(name, "mip"))     { v = RVWinCsrrMip();        Print("mip=0x%X\n", v);        CsrDecodeMip(v); }
  else if (!StrICmp(name, "mtvec"))   { v = RVWinCsrrMtvec();      Print("mtvec=0x%X\n", v);      CsrDecodeMtvec(v); }
  else if (!StrICmp(name, "mepc"))    { v = RVWinCsrrMepc();       Print("mepc=0x%X\n", v); }
  else if (!StrICmp(name, "mcause"))  { Mcause; }
  else if (!StrICmp(name, "mtval"))   { v = RVWinCsrrMtval();      Print("mtval=0x%X\n", v); }
  else if (!StrICmp(name, "mscratch")){ v = RVWinCsrrMscratch();   Print("mscratch=0x%X\n", v); }
  else if (!StrICmp(name, "misa"))    { v = RVWinCsrrMisa();       Print("misa=0x%X\n", v);       CsrDecodeMisa(v); }
  else if (!StrICmp(name, "mhartid")) { v = RVWinCsrrMhartid();    Print("mhartid=0x%X\n", v); }
  else if (!StrICmp(name, "medeleg")) { v = RVWinCsrrMedeleg();    Print("medeleg=0x%X\n", v);    CsrDecodeDeleg(v, FALSE); }
  else if (!StrICmp(name, "mideleg")) { v = RVWinCsrrMideleg();    Print("mideleg=0x%X\n", v);    CsrDecodeDeleg(v, TRUE); }
  else if (!StrICmp(name, "mcounteren")){ v = RVWinCsrrMcounteren(); Print("mcounteren=0x%X\n", v); CsrDecodeCounteren(v); }
  else if (!StrICmp(name, "mcycle"))  { v = RVWinCsrrMcycle();     Print("mcycle=%d\n", v); }
  else if (!StrICmp(name, "minstret")){ v = RVWinCsrrMinstret();   Print("minstret=%d\n", v); }
  else if (!StrICmp(name, "fcsr"))    { v = RVWinCsrrFcsr();       Print("fcsr=0x%X\n", v);       CsrDecodeFcsr(v); }
  else if (!StrICmp(name, "sstatus")) { v = RVWinCsrrSstatus();    Print("sstatus=0x%X\n", v);    CsrDecodeMstatus(v); }
  else if (!StrICmp(name, "sie"))     { v = RVWinCsrrSie();        Print("sie=0x%X\n", v);        CsrDecodeMie(v); }
  else if (!StrICmp(name, "sip"))     { v = RVWinCsrrSip();        Print("sip=0x%X\n", v);        CsrDecodeMip(v); }
  else if (!StrICmp(name, "stvec"))   { v = RVWinCsrrStvec();      Print("stvec=0x%X\n", v);      CsrDecodeMtvec(v); }
  else if (!StrICmp(name, "sepc"))    { v = RVWinCsrrSepc();       Print("sepc=0x%X\n", v); }
  else if (!StrICmp(name, "scause"))  { v = RVWinCsrrScause();     Print("scause=0x%X\n", v); }
  else if (!StrICmp(name, "stval"))   { v = RVWinCsrrStval();      Print("stval=0x%X\n", v); }
  else if (!StrICmp(name, "satp"))    { v = RVWinCsrrSatp();       Print("satp=0x%X\n", v);       CsrDecodeSatp(v); }
  else
    Print("Csr: unknown '%s' — Csr(); lists names\n", name);
}

// Plic -- Plic()
// NAME
//   Plic - the interrupt controller's state: what is enabled, what is pending, at what priority
// SYNOPSIS
//   Plic;
// DESCRIPTION
//   The PLIC is architectural state as much as any CSR, and nothing here could read it: MemMap
//   printed its base address and the IRQ path claimed from it, and that was all.
//
//   It does NOT read the claim register. A read of claim ACKNOWLEDGES the highest-pending
//   interrupt and hands it to the reader — a debugger that printed it would silently eat the
//   interrupt the system was about to service. Everything below is a read with no side effect.
// SEE ALSO
//   MemMap  Csr  Machine
public U0 Plic(I64 max_irq = 32)
{
  I64 i, pri, pend, en, thresh;
  if (max_irq < 1 || max_irq > 1023)
    max_irq = 32;
  thresh = *(U32 *)(CONFIG_PLIC_BASE + CONFIG_PLIC_THRESHOLD_OFF);
  Print("PLIC @ 0x%X  threshold=%d (an interrupt is delivered only above this)\n",
        CONFIG_PLIC_BASE, thresh);
  pend = *(U32 *)(CONFIG_PLIC_BASE + 0x1000);
  en = *(U32 *)(CONFIG_PLIC_BASE + CONFIG_PLIC_ENABLE_OFF);
  Print("  pending=0x%08X  enabled=0x%08X  (sources 1..31)\n", pend, en);
  i = 1;
  while (i < max_irq && i < 32) {
    pri = *(U32 *)(CONFIG_PLIC_BASE + i * 4);
    if (pri || (pend >> i) & 1 || (en >> i) & 1) {
      Print("  irq %-3d priority=%-3d %s%s\n", i, pri,
            (en >> i) & 1 ? "enabled " : "        ",
            (pend >> i) & 1 ? "PENDING" : "");
    }
    i++;
  }
  Print("  (claim/complete not read: a read of claim acknowledges the interrupt)\n");
}

#ifdef CONFIG_HAS_PMP
// One pmpaddr. The CSR number is an immediate, so there is no indexing a CSR — sixteen stubs and
// a chain is what "read pmpaddr[i]" costs on this machine. See docs/MACHINE_STATE_SURVEY.md §2.
I64 RVPmpAddr(I64 i)
{
  if (i == 0)
    return RVWinCsrrPmpaddr0();
  if (i == 1)
    return RVWinCsrrPmpaddr1();
  if (i == 2)
    return RVWinCsrrPmpaddr2();
  if (i == 3)
    return RVWinCsrrPmpaddr3();
  if (i == 4)
    return RVWinCsrrPmpaddr4();
  if (i == 5)
    return RVWinCsrrPmpaddr5();
  if (i == 6)
    return RVWinCsrrPmpaddr6();
  if (i == 7)
    return RVWinCsrrPmpaddr7();
  if (i == 8)
    return RVWinCsrrPmpaddr8();
  if (i == 9)
    return RVWinCsrrPmpaddr9();
  if (i == 10)
    return RVWinCsrrPmpaddr10();
  if (i == 11)
    return RVWinCsrrPmpaddr11();
  if (i == 12)
    return RVWinCsrrPmpaddr12();
  if (i == 13)
    return RVWinCsrrPmpaddr13();
  if (i == 14)
    return RVWinCsrrPmpaddr14();
  if (i == 15)
    return RVWinCsrrPmpaddr15();
  return 0;
}

// The A field: how the entry's address is interpreted.
U8 *RVPmpModeName(I64 a)
{
  if (!a)
    return "OFF";
  if (a == 1)
    return "TOR";
  if (a == 2)
    return "NA4";
  return "NAPOT";
}

// Pmp -- Pmp()
// NAME
//   Pmp - the physical memory protection entries, decoded
// SYNOPSIS
//   Pmp;
// DESCRIPTION
//   Sixteen entries on QEMU virt, each a permission set (R/W/X), an addressing mode and a range.
//   NAPOT packs the size into the address: the trailing ones say how big the region is, so
//   0x...0111 is a 64-byte region and an entry of all ones is the whole address space. TOR takes
//   its lower bound from the PREVIOUS entry's address, which is why they are printed in order.
//   A locked entry (L) cannot be changed until reset, and applies to M-mode as well.
// SEE ALSO
//   Csr  Machine  Plic
public U0 Pmp()
{
  I64 i, cfg, byte, a, addr, prev = 0, k, base, size, shown = 0;
  Print("PMP: %d entries\n", CONFIG_PMP_ENTRIES);
  i = 0;
  while (i < CONFIG_PMP_ENTRIES && i < 16) {
    cfg = RVWinCsrrPmpcfg0();
    if (i >= 8)
      cfg = RVWinCsrrPmpcfg2();
    byte = (cfg >> ((i & 7) * 8)) & 0xFF;
    addr = RVPmpAddr(i);
    a = (byte >> 3) & 3;
    if (a) {
      // No %-Nd here: HolyC's Print right-justifies it, so "pmp%-2d" reads "pmp 0" and the
      // column does not line up with anything anyway.
      Print("  pmp%d %s%s%s %s", i, byte & 1 ? "r" : "-", byte & 2 ? "w" : "-",
            byte & 4 ? "x" : "-", RVPmpModeName(a));
      if (a == 1) {
        // TOR: [previous entry's address, this one)
        Print(" 0x%08X..0x%08X\n", prev << 2, addr << 2);
      } else if (a == 2) {
        Print(" 0x%08X..0x%08X\n", addr << 2, (addr << 2) + 4);
      } else {
        // NAPOT: the trailing ones of the address are the size
        k = 0;
        while (k < 60 && (addr >> k) & 1)
          k++;
        base = (addr & ~((1 << k) - 1)) << 2;
        size = 1 << (k + 3);
        Print(" 0x%08X..0x%08X (%d bytes)\n", base, base + size, size);
      }
      if (byte & 0x80)
        Print("        locked until reset, and it binds M-mode too\n");
      shown++;
    }
    prev = addr;
    i++;
  }
  if (!shown)
    Print("  every entry is OFF: nothing is protected, and M-mode has all of memory\n");
}
#else
// Pmp -- Pmp()
// NAME
//   Pmp - say that PMP was configured out rather than fault trying to read it
// DESCRIPTION
//   CONFIG_HAS_PMP=n. pmpcfg/pmpaddr are optional CSRs and reading one on a hart without them
//   raises an illegal instruction, which in a debugger means faulting inside the thing you were
//   trying to look at. Turn it on in menuconfig for a hart that has them.
public U0 Pmp()
{
  Print("Pmp: built without PMP (CONFIG_HAS_PMP=n in templeos-riscv/Kconfig)\n");
}
#endif

// ---- page tables ----------------------------------------------------------------------------
//
// satp says where the root table is and how many levels to walk; the rest is reading 8-byte
// PTEs out of physical memory, which M-mode can do directly because nothing is translating its
// own accesses. That is the whole reason a debugger can show this at all.
//
// Sv39: the virtual address splits into three 9-bit indices and a 12-bit offset, and a PTE is a
// pointer to the next table unless R or X is set, which makes it a leaf. A leaf above level 0
// is a superpage — 2 MiB at level 1, 1 GiB at level 2.
U0 PtePerms(I64 pte)
{
  Print("%s%s%s%s%s%s%s%s", pte & 1 ? "v" : "-", pte & 2 ? "r" : "-", pte & 4 ? "w" : "-",
        pte & 8 ? "x" : "-", pte & 16 ? "u" : "-", pte & 32 ? "g" : "-", pte & 64 ? "a" : "-",
        pte & 128 ? "d" : "-");
}

I64 PtePpn(I64 pte)
{
  return (pte >> 10) & 0xFFFFFFFFFFF;
}

// PgAt -- PgAt(root, levels, va)
// NAME
//   PgAt - walk a page table that is not necessarily the live one
// SYNOPSIS
//   PgAt(root_physical, 0x80000024);      // Sv39 unless told otherwise
// DESCRIPTION
//   Takes the root table's PHYSICAL address rather than reading satp, so it can walk a table
//   that is being built, one belonging to another hart, or one from a dump — and so it can be
//   tested on a machine that has paging switched off, which this port does.
// SEE ALSO
//   Pg  Pt  Csr("satp")
// The defaulted argument goes LAST. HolyC, like C++, wants its defaults trailing: with
// `levels` in the middle the caller's remaining arguments arrived as zero and the walk ran no
// levels at all.
public I64 PgAt(I64 root, I64 va, I64 levels = 3)
{
  I64 lvl, idx, pte, tbl, shift, pa;
  tbl = root;
  lvl = levels - 1;
  while (lvl >= 0) {
    shift = 12 + 9 * lvl;
    idx = (va >> shift) & 511;
    pte = *(I64 *)(tbl + idx * 8);
    // %d, not %-3d: HolyC's Print right-justifies a negative width, so the column would not
    // line up anyway and the text would read "index   1"
    Print("  level %d  index %d  pte=%016X  ", lvl, idx, pte);
    PtePerms(pte);
    Print("\n");
    if (!(pte & 1)) {
      Print("  not valid: this address is not mapped\n");
      return 0;
    }
    if (pte & 10) {
      // R or X: a leaf
      pa = (PtePpn(pte) << 12) | (va & ((1 << shift) - 1));
      if (lvl)
        Print("  leaf at level %d — a %s superpage\n", lvl, lvl == 1 ? "2 MiB" : "1 GiB");
      Print("  0x%X -> 0x%X\n", va, pa);
      return pa;
    }
    tbl = PtePpn(pte) << 12;
    lvl--;
  }
  Print("  ran out of levels without reaching a leaf: the table is malformed\n");
  return 0;
}

// Pg -- Pg(va)
// NAME
//   Pg - translate a virtual address the way the hardware would, and show the working
// SYNOPSIS
//   Pg(0x80000024);
// DESCRIPTION
//   Reads satp, walks from its root, and prints every PTE on the way — which is the answer to
//   "why did that address fault": the level it stopped at says whether the table, the page or
//   the permissions were the problem. With satp in Bare mode there is nothing to walk and it
//   says so, because on this port M-mode addresses are physical.
// SEE ALSO
//   PgAt  Pt  Machine
public I64 Pg(I64 va)
{
  I64 satp, mode;
  satp = RVWinCsrrSatp();
  mode = (satp >> 60) & 15;
  if (!mode) {
    Print("satp=0x%X: Bare — no translation, 0x%X is already physical\n", satp, va);
    return va;
  }
  Print("satp=0x%X  root=0x%X  ASID=0x%X\n", satp, PtePpn(satp) << 12, (satp >> 44) & 0xFFFF);
  if (mode == 8)
    return PgAt(PtePpn(satp) << 12, va, 3);
  if (mode == 9)
    return PgAt(PtePpn(satp) << 12, va, 4);
  if (mode == 10)
    return PgAt(PtePpn(satp) << 12, va, 5);
  Print("satp mode %d is not one this walker knows\n", mode);
  return 0;
}

// Pt -- Pt()
// NAME
//   Pt - what the root page table maps
// SYNOPSIS
//   Pt;
// DESCRIPTION
//   The valid entries of the root table, one line each, with the virtual range each one covers.
//   A 1 GiB entry with R or X set maps that gigabyte directly; otherwise it points at a table
//   for the level below.
// SEE ALSO
//   Pg  PgAt  Csr("satp")
public U0 Pt()
{
  I64 satp, mode, root, i = 0, pte, shown = 0;
  satp = RVWinCsrrSatp();
  mode = (satp >> 60) & 15;
  if (!mode) {
    Print("satp=0x%X: Bare — nothing is translated, so there is no table to show\n", satp);
    return;
  }
  root = PtePpn(satp) << 12;
  Print("root table @ 0x%X (satp=0x%X)\n", root, satp);
  while (i < 512) {
    pte = *(I64 *)(root + i * 8);
    if (pte & 1) {
      Print("  [%d] 0x%012X..0x%012X  pte=%016X  ", i, i << 30, (i + 1) << 30, pte);
      PtePerms(pte);
      if (pte & 10)
        Print("  1 GiB leaf");
      else
        Print("  -> table 0x%X", PtePpn(pte) << 12);
      Print("\n");
      shown++;
    }
    i++;
  }
  if (!shown)
    Print("  no valid entries: nothing is mapped\n");
}

// PtDemo -- PtDemo()
// NAME
//   PtDemo - build a small Sv39 table and return its root, for walking
// SYNOPSIS
//   PgAt(PtDemo, 0x40403024);        // -> 0x80003024
// DESCRIPTION
//   Three levels mapping one 4 KiB page: virtual 0x40403000 to physical 0x80003000, readable,
//   writable and executable. It exists because this port runs with paging OFF — satp is Bare,
//   so there is no live table to walk — and a walker that has never walked anything is a
//   guess. It is also the shortest honest answer to "what does a page table look like": three
//   entries, each one a physical page number shifted up by ten with its permission bits in the
//   bottom.
// SEE ALSO
//   PgAt  Pg  Pt
U8 pt_demo_mem[4 * 4096];
public I64 PtDemo()
{
  I64 root, l1, l0;
  root = pt_demo_mem;
  root = (root / 4096 + 1) * 4096;
  // the tables have to be page-aligned, or the PPN shift means nothing
  l1 = root + 4096;
  l0 = root + 8192;
  MemSet(root, 0, 3 * 4096);
  // VPN[2] = 1, VPN[1] = 2, VPN[0] = 3 for virtual 0x40403000
  *(I64 *)(root + 1 * 8) = ((l1 >> 12) << 10) | 1;
  *(I64 *)(l1 + 2 * 8) = ((l0 >> 12) << 10) | 1;
  *(I64 *)(l0 + 3 * 8) = ((0x80003000 >> 12) << 10) | 15;
  // valid + rwx
  return root;
}

// PtWalk -- PtWalk()
// NAME
//   PtWalk - build the demonstration table and walk it, in one call
// SYNOPSIS
//   PtWalk;
// DESCRIPTION
//   PgAt(PtDemo, 0x40403024, 3) without the arguments. It exists because a planted pub only
//   delivers its FIRST argument — the rest arrive as zero — so the three-argument form cannot
//   be called from the REPL even though it is right in C. This is the shape a user can actually
//   run, and what the smoke checks.
// SEE ALSO
//   PgAt  PtDemo  Pg
public I64 PtWalk()
{
  I64 root;
  root = PtDemo;
  Print("walking the demonstration table at 0x%X for virtual 0x40403024\n", root);
  return PgAt(root, 0x40403024, 3);
}

public U0 Uptime()
{
  //Hart free-running counters (Zicntr): cycle, time (mtime tick), instret.
  Print("cycle=%d  time=%d  instret=%d\n",
    RVWinCsrrCycle(), RVWinCsrrTime(), RVWinCsrrInstret());
}
