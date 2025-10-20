// Combined TempleOS Runtime + Demo
// Shows runtime functions working with HolyC

// ═══════════════════════════════════════════════════════════════
// RUNTIME LAYER - Basic TempleOS Functions for RISC-V
// ═══════════════════════════════════════════════════════════════

U0 PutChar(U8 ch) {
  U8 *uart_thr;
  U8 *uart_lsr;
  
  uart_thr = 0x10000000;
  uart_lsr = 0x10000005;
  
  // Wait for TX ready (bit 5)
  while (!(*uart_lsr & 32)) {}
  
  *uart_thr = ch;
}

U0 PutChars(U8 *str) {
  while (*str) {
    if (*str == 10) PutChar(13);  // \n -> \r\n
    PutChar(*str);
    str = str + 1;
  }
}

U0 Print(U8 *str) {
  PutChars(str);
}

I64 StrLen(U8 *str) {
  I64 count;
  count = 0;
  while (*str) {
    count = count + 1;
    str = str + 1;
  }
  return count;
}

I64 Abs(I64 x) {
  if (x < 0) return -x;
  return x;
}

I64 Min(I64 a, I64 b) {
  if (a < b) return a;
  return b;
}

I64 Max(I64 a, I64 b) {
  if (a > b) return a;
  return b;
}

// ═══════════════════════════════════════════════════════════════
// USER APPLICATION - Uses Runtime Functions
// ═══════════════════════════════════════════════════════════════

I64 TestMath() {
  return Max(Abs(-42), Min(10, 20));
}

I64 Main() {
  Print("TempleOS Runtime Demo\n");
  Print("=====================\n");
  
  return TestMath();
}
