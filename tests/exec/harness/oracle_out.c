#include <stdint.h>
#include <stddef.h>
volatile unsigned char *const uart = (volatile unsigned char *)0x10000000UL;
static void putc_uart(int c) {
  *uart = (unsigned char)c;
}
/* Bump heap for the runtime's MAlloc (the blob's own data lives in .user_blob). */
static unsigned char rt_heap[1024 * 1024];
static size_t rt_heap_pos;
static void *rt_malloc(size_t sz) {
  sz = (sz + 15) & ~(size_t)15;
  if (rt_heap_pos + sz > sizeof rt_heap) return 0;
  void *p = rt_heap + rt_heap_pos;
  rt_heap_pos += sz;
  return p;
}
#define HOLY_RT_PUTC(c) putc_uart(c)
#define HOLY_RT_MALLOC(sz) rt_malloc(sz)
#include "../../../bootstrap/holy_rt.h"

extern unsigned char _binary_blob_bin_start[], _binary_blob_bin_end[];
/* Called from crt0 before jumping to the blob: fill its runtime import slots by name. */
void resolve_imports(void) {
  holy_resolve_imports(_binary_blob_bin_start, _binary_blob_bin_end);
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
