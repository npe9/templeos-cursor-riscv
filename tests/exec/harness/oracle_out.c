#include <stdint.h>
#include <stddef.h>
#ifndef UART_BASE
#define UART_BASE 0x10000000UL
#endif
volatile unsigned char *const uart = (volatile unsigned char *)UART_BASE;
static void putc_uart(int c) {
  *uart = (unsigned char)c;
}
/* Bump heap for the runtime's MAlloc (the blob's own data lives in .user_blob). */
/* Bump heap for imported MAlloc — Kernel boot + Compiler_RV CInit need far more than 1MB
 * (AsmHashLoad HashTableNew + defines). Prefer guest Kernel MAlloc once self-resolved. */
/* Bump arena only for leftovers; Kernel MAlloc/CAlloc/Free are guest-owned (not imported). */
static unsigned char rt_heap[256 * 1024];
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
/* Fatal-fault report, called from crt0's trap_entry. The blob-relative offset is
 * the point of this: it feeds straight into HOLYC_MAP=file (offset -> function name),
 * which is the only way to name a faulting PC — the blob is objcopy -I binary'd in
 * and so carries no ELF symbols. */
static const char *const trap_cause_name[16] = {
  "insn-misaligned", "insn-fault",  "illegal-insn",   "breakpoint",
  "load-misaligned", "load-fault",  "store-misaligned", "store-fault",
  "ecall-u",         "ecall-s",     "?",              "ecall-m",
  "insn-page-fault", "load-page-fault", "?",          "store-page-fault"
};
static void puts_uart(const char *s) {
  while (*s)
    putc_uart(*s++);
}
void trap_report(unsigned long cause, unsigned long epc, unsigned long tval) {
  puts_uart("\nTRAP mcause=0x");
  put_hex_u64(cause);
  if ((int64_t)cause >= 0 && cause < 16) {
    puts_uart(" (");
    puts_uart(trap_cause_name[cause]);
    putc_uart(')');
  } else if ((int64_t)cause < 0) {
    puts_uart(" (interrupt)");
  }
  puts_uart(" mepc=0x");
  put_hex_u64(epc);
  puts_uart(" mtval=0x");
  put_hex_u64(tval);
  if (epc >= (unsigned long)_binary_blob_bin_start &&
      epc < (unsigned long)_binary_blob_bin_end) {
    puts_uart(" blob+0x");
    put_hex_u64(epc - (unsigned long)_binary_blob_bin_start);
  }
  puts_uart("\nTRAP halted\n");
}

void oracle_report(unsigned long result) {
  uint64_t bits = (uint64_t)result;
  const char *p = "ORACLE ";
  while (*p)
    putc_uart(*p++);
  put_hex_u64(bits);
  putc_uart('\n');
}
