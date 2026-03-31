#include <stdint.h>

volatile unsigned char *const uart = (volatile unsigned char *)0x10000000UL;

static void putc_uart(int c) {
  *uart = (unsigned char)c;
}

static void put_hex_u64(uint64_t x) {
  for (int i = 15; i >= 0; i--) {
    unsigned n = (unsigned)((x >> (i * 4)) & 0xfu);
    putc_uart(n < 10 ? (char)('0' + n) : (char)('a' + (n - 10)));
  }
}

void oracle_report(unsigned long result) {
  uint64_t bits = (uint64_t)result;
  const char *p = "ORACLE ";
  while (*p)
    putc_uart(*p++);
  put_hex_u64(bits);
  putc_uart('\n');
}
