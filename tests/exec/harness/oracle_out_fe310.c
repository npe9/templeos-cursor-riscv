/* FE310 / sifive_e fuller tiny-Kernel oracle — XIP-resident helpers.
 *
 * Kernel code + HolyC blob execute from QSPI/XIP. Bootloader lives in DTIM
 * (see crt0_sifive_e_boot.S). Import slots are host-prepatched
 * (patch_fe310_xip_imports.py) — do not write XIP at runtime.
 *
 * Exports fe310_rt_{yield,call,print} for the host patcher + fe310_boot_banner
 * (called from DTIM bootloader to prove RAM-resident boot). */
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

#ifndef UART_BASE
#define UART_BASE 0x10013000UL
#endif

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

static void put_hex_u64(uint64_t x) {
  for (int i = 15; i >= 0; i--) {
    unsigned n = (unsigned)((x >> (i * 4)) & 0xfu);
    putc_uart(n < 10 ? (char)('0' + n) : (char)('a' + (n - 10)));
  }
}

/* DTIM-resident UART (JAL cannot reach XIP from 0x80000000). */
__attribute__((section(".text.boot")))
static void boot_putc(int c) {
  volatile uint32_t *tx = (volatile uint32_t *)UART_BASE;
  while (*tx & 0x80000000u)
    ;
  *tx = (uint32_t)(unsigned char)c;
}

__attribute__((section(".text.boot")))
static void boot_puts(const char *s) {
  while (*s)
    boot_putc(*s++);
}

__attribute__((section(".text.boot")))
static void boot_put_hex_u64(uint64_t x) {
  for (int i = 15; i >= 0; i--) {
    unsigned n = (unsigned)((x >> (i * 4)) & 0xfu);
    boot_putc(n < 10 ? (char)('0' + n) : (char)('a' + (n - 10)));
  }
}

/* Called from DTIM-resident boot_main — must live in .text.boot (copied to RAM). */
__attribute__((section(".text.boot")))
void fe310_boot_banner(void) {
  uintptr_t pc;
  __asm__ volatile("auipc %0, 0" : "=r"(pc));
  boot_puts("fe310-boot: dtim pc=");
  boot_put_hex_u64((uint64_t)pc);
  boot_putc('\n');
  if (pc >= 0x80000000UL && pc < 0x80004000UL)
    boot_puts("fe310-boot: in_dtim\n");
  else
    boot_puts("fe310-boot: NOT_in_dtim\n");
}

int64_t fe310_rt_yield(void) { return 0; }

int64_t fe310_rt_call(int64_t fn) {
  if (!fn)
    return 0;
  return ((int64_t(*)(void))(uintptr_t)fn)();
}

/* Minimal Print for RVMemMap: %s %x %X %d %u %% (C varargs AOT). */
int64_t fe310_rt_print(char *fmt, ...) {
  va_list ap;
  if (!fmt)
    return 0;
  va_start(ap, fmt);
  for (const char *p = fmt; *p; p++) {
    if (*p != '%') {
      putc_uart(*p);
      continue;
    }
    p++;
    while (*p == '-' || *p == '0' || *p == ',')
      p++;
    while (*p >= '0' && *p <= '9')
      p++;
    if (*p == '.') {
      p++;
      while (*p >= '0' && *p <= '9')
        p++;
    }
    while (*p == 'h') {
      p++;
      if (*p == '?' || *p == '*')
        p++;
      else if (*p == '-') {
        p++;
        while (*p >= '0' && *p <= '9')
          p++;
      } else {
        while (*p >= '0' && *p <= '9')
          p++;
      }
    }
    switch (*p) {
    case 's': {
      char *sv = va_arg(ap, char *);
      puts_uart(sv ? sv : "(null)");
      break;
    }
    case 'x':
    case 'X': {
      uint64_t v = (uint64_t)va_arg(ap, int64_t);
      put_hex_u64(v);
      break;
    }
    case 'd':
    case 'u': {
      int64_t v = va_arg(ap, int64_t);
      char buf[24];
      int n = 0;
      uint64_t u = v < 0 && *p == 'd' ? (uint64_t)(-v) : (uint64_t)v;
      if (v < 0 && *p == 'd')
        putc_uart('-');
      if (!u)
        buf[n++] = '0';
      while (u && n < (int)sizeof(buf)) {
        buf[n++] = (char)('0' + (u % 10));
        u /= 10;
      }
      while (n--)
        putc_uart(buf[n]);
      break;
    }
    case '%':
      putc_uart('%');
      break;
    case 0:
      va_end(ap);
      return 0;
    default:
      putc_uart('%');
      putc_uart(*p);
      break;
    }
  }
  va_end(ap);
  return 0;
}

void oracle_report(unsigned long result) {
  puts_uart("ORACLE ");
  put_hex_u64((uint64_t)result);
  putc_uart('\n');
}

/* crt0 may still reference resolve_imports on other boards; FE310 boot skips it. */
void resolve_imports(void) {}
