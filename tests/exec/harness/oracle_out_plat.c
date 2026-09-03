/* Slim oracle for tiny-RAM plat smokes (sifive_e DTIM 16 KiB).
 * Avoids bootstrap/holy_rt.h BSS (256 KiB heap + virtq). Plat demo needs Yield. */
#include <stdint.h>
#include <stddef.h>

#ifndef UART_BASE
#define UART_BASE 0x10013000UL
#endif

#define HOLY_IMPORT_MAGIC 0x31504D4959464F48ULL /* "HOFYIMP1" */

/* SiFive UART: TXDATA @ +0 (bit31 FULL). */
static void putc_uart(int c) {
  volatile uint32_t *tx = (volatile uint32_t *)UART_BASE;
  while (*tx & 0x80000000u)
    ;
  *tx = (uint32_t)(unsigned char)c;
}

static void puts_uart(const char *s) {
  while (*s)
    putc_uart(*s++);
}

static int64_t rt_yield(void) { return 0; }

/* Host AOT may emit Call(fn) for indirect calls; plat demo does not need it. */
static int64_t rt_call(int64_t fn) {
  if (!fn)
    return 0;
  return ((int64_t(*)(void))(uintptr_t)fn)();
}

static int64_t unresolved_import(void) {
  puts_uart("[unresolved import]\n");
  return 0;
}

static int name_eq(const char *a, const char *b) {
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return *a == 0 && *b == 0;
}

extern unsigned char _binary_blob_bin_start[], _binary_blob_bin_end[];

void resolve_imports(void) {
  unsigned char *blob_start = _binary_blob_bin_start;
  unsigned char *blob_end = _binary_blob_bin_end;
  if (blob_end - blob_start < 16)
    return;
  uint64_t magic = 0, count = 0;
  for (int i = 0; i < 8; i++) {
    ((unsigned char *)&magic)[i] = blob_end[-8 + i];
    ((unsigned char *)&count)[i] = blob_end[-16 + i];
  }
  if (magic != HOLY_IMPORT_MAGIC)
    return;
  unsigned char *ent = blob_end - 16 - (ptrdiff_t)count * 32;
  for (uint64_t k = 0; k < count; k++, ent += 32) {
    uint64_t slot = 0;
    for (int i = 0; i < 8; i++)
      ((unsigned char *)&slot)[i] = ent[i];
    const char *name = (const char *)(ent + 8);
    uint64_t fn = (uint64_t)(uintptr_t)unresolved_import;
    if (name_eq(name, "Yield"))
      fn = (uint64_t)(uintptr_t)rt_yield;
    else if (name_eq(name, "Call"))
      fn = (uint64_t)(uintptr_t)rt_call;
    else {
      puts_uart("[import unresolved: ");
      puts_uart(name);
      puts_uart("]\n");
    }
    for (int i = 0; i < 8; i++)
      blob_start[slot + (uint64_t)i] = (unsigned char)((fn >> (8 * i)) & 0xff);
  }
}

static void put_hex_u64(uint64_t x) {
  for (int i = 15; i >= 0; i--) {
    unsigned n = (unsigned)((x >> (i * 4)) & 0xfu);
    putc_uart(n < 10 ? (char)('0' + n) : (char)('a' + (n - 10)));
  }
}

void oracle_report(unsigned long result) {
  puts_uart("ORACLE ");
  put_hex_u64((uint64_t)result);
  putc_uart('\n');
}
