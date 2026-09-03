// A03_LoadStore.hc -- Part A3: Loads, stores, endianness, MEM_*
//
// HOW TO WORK THIS LAB
//   Run("A03_LoadStore.hc");  edit Fill_in;  Run again.
//
// LEARNING GOALS
//   RV64I is little-endian: the least-significant byte of a multi-byte
//   value sits at the lowest address. For I64 word 0x0102030405060708,
//   byte[0]==0x08, byte[1]==0x07, ...
//
//   Widths: lb/lbu/lh/lhu/lw/lwu/ld and sb/sh/sw/sd. Sign-extending loads
//   (lb/lh/lw) vs zero-extending (lbu/lhu/lwu) matter when the high bits
//   of the destination register must be defined.
//
//   On this port, board devices and soft arenas are named MEM_* (see
//   csr.hc / MemMap). UART is typically MEM_UART, timer MEM_CLINT /
//   MEM_MTIME, memfs MEM_FS, heap MEM_HEAP. Never hardcode magic addresses
//   in new code -- use the symbols or MemMapFind("uart").
//
//   Alignment: natural alignment is required for many MMIO regs; DRAM
//   accesses should stay aligned for performance and for strict platforms.
//
// NEXT
//   A04_Branches -- control flow; HolyC if/while vs beq/jal.
U0 A03_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}
I64 A03_cell;
U0 A03_Demo()
{
  I64 w;
  U8 *p;
  w = 0x0102030405060708;
  p = &w;
  Print("A03 endian peek low bytes: %02X %02X %02X %02X (expect 08 07 06 05)\n", p[0], p[1], p[2], p[3]);
  Print("MEM_UART=%X  MEM_CLINT=%X  MEM_FS=%X\n", MEM_UART, MEM_CLINT, MEM_FS);
  Print("MemMapFind(\"uart\")=%X\n", MemMapFind("uart"));
  A03_Expect("A03_LE_b0", p[0], 0x08);
  A03_Expect("A03_UART_sym", MEM_UART == MemMapFind("uart"), 1);
}
// Ex1 Warmup: store then load a cell in HolyC.
I64 A03_Ex1_StoreLoad()
{
  I64 cell;
  // TODO Fill_in: cell = 0xDEAD; return cell;
  cell = 0;
  return cell;
}
// Ex2: return the least-significant byte of x (LE low address).
I64 A03_Ex2_LowByte(I64 x)
{
  // TODO Fill_in: return x & 0xFF;
  return -1;
}
// Ex3: second byte (bits 15:8).
I64 A03_Ex3_Byte1(I64 x)
{
  // TODO Fill_in: return (x >> 8) & 0xFF;
  return 0;
}
// Ex4: sign-extend a byte in 0..255 as I64 (-128..127).
I64 A03_Ex4_SignExtU8(I64 b)
{
  // TODO Fill_in:
  //   b = b & 0xFF;
  //   if (b & 0x80) return b - 256;
  //   return b;
  return -1;
}
// Ex5: zero-extend U8 (always 0..255).
I64 A03_Ex5_ZeroExtU8(I64 b)
{
  // TODO Fill_in: return b & 0xFF;
  return -1;
}
// Ex6: which MEM_* owns the console UART? Return MemMapFind("uart").
I64 A03_Ex6_UartBase()
{
  // TODO Fill_in: return MemMapFind("uart");
  return 0;
}
// Ex7: alignment -- return 1 if addr is 8-byte aligned.
I64 A03_Ex7_Align8(I64 addr)
{
  // TODO Fill_in: return (addr & 7) == 0;
  return -1;
}
// Ex8 Challenge: poke A03_cell via pointer (models sd to a symbol).
I64 A03_Ex8_PokeGlobal()
{
  I64 *p;
  // TODO Fill_in:
  //   p = &A03_cell;
  //   *p = 0xBEEF;
  //   return A03_cell;
  A03_cell = 0;
  return A03_cell;
}

U0 A03_Check()
{
  Print("-- A03 exercises --\n");
  A03_Expect("Ex1_StoreLoad", A03_Ex1_StoreLoad(), 0xDEAD);
  A03_Expect("Ex2_LowByte", A03_Ex2_LowByte(0x01020304), 0x04);
  A03_Expect("Ex3_Byte1", A03_Ex3_Byte1(0x01020304), 0x03);
  A03_Expect("Ex4_SignExt_FF", A03_Ex4_SignExtU8(0xFF), -1);
  A03_Expect("Ex4_SignExt_7F", A03_Ex4_SignExtU8(0x7F), 0x7F);
  A03_Expect("Ex5_ZeroExt", A03_Ex5_ZeroExtU8(0x1FF), 0xFF);
  A03_Expect("Ex6_UartBase", A03_Ex6_UartBase(), MEM_UART);
  A03_Expect("Ex7_Align8_ok", A03_Ex7_Align8(0x80000000), 1);
  A03_Expect("Ex7_Align8_bad", A03_Ex7_Align8(0x80000001), 0);
  A03_Expect("Ex8_PokeGlobal", A03_Ex8_PokeGlobal(), 0xBEEF);
}

U0 A03()
{
  Print("=== A03 Load / store ===\n");
  Print("Also try: MemMap;  Man(\"UART\");\n");
  A03_Demo();
  A03_Check();
  Print("Next: Run(\"A04_Branches.hc\");\n");
}
A03;
