// disasm.hc -- a RISC-V disassembler in HolyC. Disasm(addr) prints a 28-instruction window from
// a function entry; Src() falls back to it for a function with no source. Decodes base RV64IM,
// the D-extension floats the compiler emits, and RVC (compressed). Edit it: Src("DisasmOne").
// HolyC won't accept a bare no-arg "str"; as an if-body, so Pm(s) prints a mnemonic and the
// mnemonic otherwise goes into a variable printed once with args.
U8 *RN[32]  = {"zero","ra","sp","gp","tp","t0","t1","t2","s0","s1","a0","a1","a2","a3","a4","a5",
               "a6","a7","s2","s3","s4","s5","s6","s7","s8","s9","s10","s11","t3","t4","t5","t6"};
U8 *FRN[32] = {"ft0","ft1","ft2","ft3","ft4","ft5","ft6","ft7","fs0","fs1","fa0","fa1","fa2","fa3","fa4","fa5",
               "fa6","fa7","fs2","fs3","fs4","fs5","fs6","fs7","fs8","fs9","fs10","fs11","ft8","ft9","ft10","ft11"};

U0 Pm(U8 *s) { "%s", s; }
U0 DiImm(I64 v) { if (v < 0) { PutCh('-'); v = -v; } "0x%X", v; }

U0 DisasmOne(I64 addr, I64 w) {
  I64 op, rd, f3, rs1, rs2, f7, immI, immS, csr;
  U8 *mn;
  op = w & 0x7F; rd = (w >> 7) & 0x1F; f3 = (w >> 12) & 7;
  rs1 = (w >> 15) & 0x1F; rs2 = (w >> 20) & 0x1F; f7 = (w >> 25) & 0x7F; csr = (w >> 20) & 0xFFF;
  immI = (w >> 20) & 0xFFF; if (immI & 0x800) immI |= ~0xFFF;
  immS = (((w >> 25) & 0x7F) << 5) | ((w >> 7) & 0x1F); if (immS & 0x800) immS |= ~0xFFF;
  if (w == 0x00000013)      Pm("nop");
  else if (w == 0x30200073) Pm("mret");
  else if (w == 0x10500073) Pm("wfi");
  else if (w == 0x0000100F) Pm("fence.i");
  else if (w == 0x00008067) Pm("ret");
  else if (op == 0x37) { "lui %s, ", RN[rd]; DiImm(w & 0xFFFFF000); }
  else if (op == 0x17) { "auipc %s, ", RN[rd]; DiImm(w & 0xFFFFF000); }
  else if (op == 0x6F) { "jal %s", RN[rd]; }
  else if (op == 0x67) { "jalr %s, ", RN[rd]; DiImm(immI); "(%s)", RN[rs1]; }
  else if (op == 0x13) {
    if (f3 == 0 && rs1 == 0) { "li %s, ", RN[rd]; DiImm(immI); }
    else {
      if (f3==0) mn = "addi"; else if (f3==1) mn = "slli"; else if (f3==2) mn = "slti";
      else if (f3==4) mn = "xori"; else if (f3==5) { if (f7 & 0x20) mn = "srai"; else mn = "srli"; }
      else if (f3==6) mn = "ori"; else mn = "andi";
      "%s %s, %s, ", mn, RN[rd], RN[rs1]; if (f3==1 || f3==5) DiImm(rs2); else DiImm(immI);
    }
  }
  else if (op == 0x1B) { if (f3==0) mn="addiw"; else if (f3==1) mn="slliw"; else mn="srliw"; "%s %s, %s, ", mn, RN[rd], RN[rs1]; if (f3==0) DiImm(immI); else DiImm(rs2); }
  else if (op == 0x33) {
    if (f7==0x20) { if (f3==0) mn="sub"; else mn="sra"; }
    else if (f7==1) { if (f3==0) mn="mul"; else if (f3==4) mn="div"; else if (f3==5) mn="divu"; else if (f3==6) mn="rem"; else mn="remu"; }
    else { if (f3==0) mn="add"; else if (f3==1) mn="sll"; else if (f3==2) mn="slt"; else if (f3==3) mn="sltu"; else if (f3==4) mn="xor"; else if (f3==5) mn="srl"; else if (f3==6) mn="or"; else mn="and"; }
    "%s %s, %s, %s", mn, RN[rd], RN[rs1], RN[rs2];
  }
  else if (op == 0x03) {
    if (f3==0) mn="lb"; else if (f3==1) mn="lh"; else if (f3==2) mn="lw"; else if (f3==3) mn="ld";
    else if (f3==4) mn="lbu"; else if (f3==5) mn="lhu"; else mn="lwu";
    "%s %s, ", mn, RN[rd]; DiImm(immI); "(%s)", RN[rs1];
  }
  else if (op == 0x23) { if (f3==0) mn="sb"; else if (f3==1) mn="sh"; else if (f3==2) mn="sw"; else mn="sd"; "%s %s, ", mn, RN[rs2]; DiImm(immS); "(%s)", RN[rs1]; }
  else if (op == 0x63) { if (f3==0) mn="beq"; else if (f3==1) mn="bne"; else if (f3==4) mn="blt"; else if (f3==5) mn="bge"; else if (f3==6) mn="bltu"; else mn="bgeu"; "%s %s, %s", mn, RN[rs1], RN[rs2]; }
  else if (op == 0x73) {
    if (f3==1) mn="csrrw"; else if (f3==2) mn="csrrs"; else if (f3==3) mn="csrrc"; else mn="";
    if (mn[0]) { "%s %s, ", mn, RN[rd]; DiImm(csr); ", %s", RN[rs1]; }
    else { if (w==0x73) Pm("ecall"); else Pm("system"); }
  }
  else if (op == 0x07 && f3==3) { "fld %s, ", FRN[rd]; DiImm(immI); "(%s)", RN[rs1]; }
  else if (op == 0x27 && f3==3) { "fsd %s, ", FRN[rs2]; DiImm(immS); "(%s)", RN[rs1]; }
  else if (op == 0x53) {
    if (f7==0x01) { "fadd.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]; }
    else if (f7==0x05) { "fsub.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]; }
    else if (f7==0x09) { "fmul.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]; }
    else if (f7==0x0D) { "fdiv.d %s, %s, %s", FRN[rd], FRN[rs1], FRN[rs2]; }
    else if (f7==0x2D) { "fsqrt.d %s, %s", FRN[rd], FRN[rs1]; }
    else if (f7==0x51) { if (f3==0) mn="fle.d"; else if (f3==1) mn="flt.d"; else mn="feq.d"; "%s %s, %s, %s", mn, RN[rd], FRN[rs1], FRN[rs2]; }
    else if (f7==0x79) { "fmv.d.x %s, %s", FRN[rd], RN[rs1]; }
    else if (f7==0x71) { if (f3==0) mn="fmv.x.d"; else mn="fclass.d"; "%s %s, %s", mn, RN[rd], FRN[rs1]; }
    else if (f7==0x61) { if (rs2==2) mn="fcvt.l.d"; else if (rs2==3) mn="fcvt.lu.d"; else if (rs2==0) mn="fcvt.w.d"; else mn="fcvt.wu.d"; "%s %s, %s", mn, RN[rd], FRN[rs1]; }
    else if (f7==0x69) { if (rs2==2) mn="fcvt.d.l"; else if (rs2==3) mn="fcvt.d.lu"; else if (rs2==0) mn="fcvt.d.w"; else mn="fcvt.d.wu"; "%s %s, %s", mn, FRN[rd], RN[rs1]; }
    else { Pm("fp f7="); DiImm(f7); }
  }
  else Pm(".word");
  "\n";
}
U0 DisasmC(I64 addr, I64 w) {
  I64 op, f3, rd, rs2, rdp, rs1p, imm, u, sh, f2, ff, b12;
  U8 *mn;
  op = w & 3; f3 = (w >> 13) & 7; rd = (w >> 7) & 0x1F; rs2 = (w >> 2) & 0x1F;
  rdp = ((w >> 2) & 7) + 8; rs1p = ((w >> 7) & 7) + 8;
  if (w == 0x0000)      Pm("illegal");
  else if (w == 0x0001) Pm("c.nop");
  else if (w == 0x9002) Pm("c.ebreak");
  else if (op == 0) {
    if (f3==0) { u = ((w>>7)&0x30)|((w>>1)&0x3C0)|((w>>4)&4)|((w>>2)&8); "c.addi4spn %s, sp, ", RN[rdp]; DiImm(u); }
    else if (f3==2) { u = ((w>>7)&0x38)|((w<<1)&0x40)|((w>>4)&4); "c.lw %s, ", RN[rdp]; DiImm(u); "(%s)", RN[rs1p]; }
    else if (f3==3) { u = ((w>>7)&0x38)|((w<<1)&0xC0); "c.ld %s, ", RN[rdp]; DiImm(u); "(%s)", RN[rs1p]; }
    else if (f3==6) { u = ((w>>7)&0x38)|((w<<1)&0x40)|((w>>4)&4); "c.sw %s, ", RN[rdp]; DiImm(u); "(%s)", RN[rs1p]; }
    else if (f3==7) { u = ((w>>7)&0x38)|((w<<1)&0xC0); "c.sd %s, ", RN[rdp]; DiImm(u); "(%s)", RN[rs1p]; }
    else Pm(".chalf");
  }
  else if (op == 1) {
    imm = ((w>>2)&0x1F)|((w>>7)&0x20); if (imm & 0x20) imm |= ~0x3F;
    if (f3==0) { if (rd==0) Pm("c.nop"); else { "c.addi %s, ", RN[rd]; DiImm(imm); } }
    else if (f3==1) { "c.addiw %s, ", RN[rd]; DiImm(imm); }
    else if (f3==2) { "c.li %s, ", RN[rd]; DiImm(imm); }
    else if (f3==3) {
      if (rd==2) { imm = ((w>>3)&0x200)|((w<<4)&0x180)|((w<<1)&0x40)|((w<<3)&0x20)|((w>>2)&0x10); if (imm & 0x200) imm |= ~0x3FF; Pm("c.addi16sp sp, "); DiImm(imm); }
      else { imm = (((w>>2)&0x1F)<<12)|(((w>>12)&1)<<17); if (imm & 0x20000) imm |= ~0x3FFFF; "c.lui %s, ", RN[rd]; DiImm(imm); }
    }
    else if (f3==4) {
      f2 = (w>>10)&3; sh = ((w>>2)&0x1F)|((w>>7)&0x20);
      if (f2==0) { "c.srli %s, ", RN[rs1p]; DiImm(sh); }
      else if (f2==1) { "c.srai %s, ", RN[rs1p]; DiImm(sh); }
      else if (f2==2) { imm = sh; if (imm & 0x20) imm |= ~0x3F; "c.andi %s, ", RN[rs1p]; DiImm(imm); }
      else { ff = (w>>5)&3; if ((w>>12)&1) { if (ff==0) mn="c.subw"; else mn="c.addw"; } else { if (ff==0) mn="c.sub"; else if (ff==1) mn="c.xor"; else if (ff==2) mn="c.or"; else mn="c.and"; } "%s %s, %s", mn, RN[rs1p], RN[rdp]; }
    }
    else if (f3==5) Pm("c.j");
    else if (f3==6) { "c.beqz %s", RN[rs1p]; }
    else { "c.bnez %s", RN[rs1p]; }
  }
  else if (op == 2) {
    if (f3==0) { sh = ((w>>2)&0x1F)|((w>>7)&0x20); "c.slli %s, ", RN[rd]; DiImm(sh); }
    else if (f3==2) { u = ((w>>7)&0x20)|((w>>2)&0x1C)|((w<<4)&0xC0); "c.lwsp %s, ", RN[rd]; DiImm(u); "(sp)"; }
    else if (f3==3) { u = ((w>>7)&0x20)|((w>>2)&0x18)|((w<<4)&0x1C0); "c.ldsp %s, ", RN[rd]; DiImm(u); "(sp)"; }
    else if (f3==4) {
      b12 = (w>>12)&1;
      if (!b12) { if (rs2==0) { "c.jr %s", RN[rd]; } else { "c.mv %s, %s", RN[rd], RN[rs2]; } }
      else { if (rd==0 && rs2==0) Pm("c.ebreak"); else if (rs2==0) { "c.jalr %s", RN[rd]; } else { "c.add %s, %s", RN[rd], RN[rs2]; } }
    }
    else if (f3==6) { u = ((w>>7)&0x3C)|((w>>1)&0xC0); "c.swsp %s, ", RN[rs2]; DiImm(u); "(sp)"; }
    else if (f3==7) { u = ((w>>7)&0x38)|((w>>1)&0x1C0); "c.sdsp %s, ", RN[rs2]; DiImm(u); "(sp)"; }
    else Pm(".chalf");
  }
  else Pm(".chalf");
  "\n";
}
// DisasmAt(addr) -- disassemble a 28-instruction window from a raw address.
U0 DisasmAt(I64 addr) {
  I64 i, lo, w;
  "; disassembly window @ 0x%08X\n", addr;
  i = 0;
  while (i < 28) {
    lo = *(U16 *)addr;
    "0x%08X:  ", addr;
    if ((lo & 3) != 3) { DisasmC(addr, lo); addr += 2; }
    else { w = *(U32 *)addr; DisasmOne(addr, w); if (w == 0x00008067) return; addr += 4; }
    i++;
  }
}
// Disasm("Name") -- disassemble a function by name (resolves via FnAddr).
U0 Disasm(U8 *name) {
  I64 a;
  a = FnAddr(name);
  if (!a) { "Disasm: no such function: %s\n", name; return; }
  "; %s:\n", name;
  DisasmAt(a);
}
