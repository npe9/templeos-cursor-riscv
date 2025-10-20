// Minimal TempleOS Runtime for QEMU RISC-V
// Provides basic system functions using UART

// UART hardware access
#define UART_BASE 0x10000000

// Low-level UART functions
U0 UartPutC(U8 ch) {
  U8 *uart_lsr;
  U8 *uart_thr;
  
  uart_lsr = UART_BASE + 5;
  uart_thr = UART_BASE;
  
  // Wait for TX ready
  while (!(*uart_lsr & 32)) {}
  
  // Send character
  *uart_thr = ch;
}

U8 UartGetC() {
  U8 *uart_lsr;
  U8 *uart_rbr;
  
  uart_lsr = UART_BASE + 5;
  uart_rbr = UART_BASE;
  
  // Wait for data ready
  while (!(*uart_lsr & 1)) {}
  
  return *uart_rbr;
}

// TempleOS-style output functions
U0 PutChars(U8 *str) {
  while (*str) {
    if (*str == 10) UartPutC(13);  // LF -> CR+LF
    UartPutC(*str);
    str = str + 1;
  }
}

U0 Print(U8 *str) {
  PutChars(str);
}

// String functions
I64 StrLen(U8 *str) {
  I64 len;
  len = 0;
  while (*str) {
    len = len + 1;
    str = str + 1;
  }
  return len;
}

U0 StrCpy(U8 *dst, U8 *src) {
  while (*src) {
    *dst = *src;
    dst = dst + 1;
    src = src + 1;
  }
  *dst = 0;
}

I64 StrCmp(U8 *a, U8 *b) {
  while (*a && *b) {
    if (*a < *b) return -1;
    if (*a > *b) return 1;
    a = a + 1;
    b = b + 1;
  }
  if (*a) return 1;
  if (*b) return -1;
  return 0;
}

// Math functions
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

// Test/Demo
I64 Main() {
  Print("TempleOS Runtime for RISC-V\n");
  Print("Hello from HolyC!\n");
  return 42;
}
