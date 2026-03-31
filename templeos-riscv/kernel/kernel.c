/*
 * TempleOS/RISC-V kernel — UART, traps, compiler slot, TosApi (Phase C), yield hook (Phase D stub).
 */
#include <stdint.h>
#include "tos_api.h"
#include "virtio_mmio.h"
#include "virtio_mmio_blk.h"
#include "virtio_blk_pci.h"
#include "redsea_min.h"

typedef int (*phase_e_blk_read_t)(void *ctx, void *buf, size_t len, uint64_t lba);

static int phase_e_read_pci(void *ctx, void *buf, size_t len, uint64_t lba) {
  (void)ctx;
  return virtio_pci_blk_read_lba(buf, len, lba);
}

static int phase_e_read_mmio(void *ctx, void *buf, size_t len, uint64_t lba) {
  return virtio_mmio_blk_read_lba((uintptr_t)ctx, buf, len, lba);
}

volatile unsigned char *const uart_reg = (volatile unsigned char *)0x10000000UL;
#define UART_LSR  (*(volatile unsigned char *)0x10000005UL)

#define GUEST_VMA       0x80100000UL
#define COMPILER_VMA    0x80200000UL
#define COMPILER_MAGIC  0x504d4f43UL

/* Placed at 0x80300000 — see link/kernel.ld */
__attribute__((section(".tos_api"), aligned(8))) struct TosApi g_tos_api;

volatile uint64_t g_yield_count;

static void uart_putc(int c) {
  *uart_reg = (unsigned char)c;
}

static void uart_puts(const char *s) {
  while (*s)
    uart_putc(*s++);
}

static void put_hex_u64(uint64_t x) {
  for (int i = 15; i >= 0; i--) {
    unsigned n = (unsigned)((x >> (i * 4)) & 0xfu);
    uart_putc((char)(n < 10 ? ('0' + n) : ('a' + (n - 10))));
  }
}

static void oracle_report(unsigned long result) {
  const char *p = "ORACLE ";
  while (*p)
    uart_putc(*p++);
  put_hex_u64((uint64_t)result);
  uart_putc('\n');
}

void tos_api_putchar(int c) {
  uart_putc(c);
}

int tos_api_getchar(void) {
  while ((UART_LSR & 1u) == 0)
    __asm__ volatile("" ::: "memory");
  return (int)*uart_reg;
}

/* Phase D stub: cooperative yield (no task switch yet). */
void tos_api_yield(void) {
  g_yield_count++;
}

void rv_s_trap_fatal(uint64_t scause, uint64_t sepc, uint64_t stval) {
  uart_puts("\r\n*** TRAP (S-mode) ***\r\n");
  uart_puts("  scause=");
  put_hex_u64(scause);
  uart_puts(" sepc=");
  put_hex_u64(sepc);
  uart_puts(" stval=");
  put_hex_u64(stval);
  uart_puts("\r\n");
  for (;;)
    __asm__ volatile("wfi" ::: "memory");
}

typedef void (*compiler_stub_fn_t)(void);

long templeos_invoke_guest(uintptr_t guest_vma);

static uint8_t g_boot_sector[512] __attribute__((aligned(512)));
static uint8_t g_root_sector[512] __attribute__((aligned(512)));
#define REDSEA_PHASE_E_FILE_CAP 2048u
static uint8_t g_redsea_file_buf[REDSEA_PHASE_E_FILE_CAP] __attribute__((aligned(512)));

typedef struct {
  phase_e_blk_read_t rb;
  void *disk_ctx;
} phase_e_redsea_wr_t;

static int phase_e_redsea_adapter(void *ctx, void *buf, size_t len, uint64_t lba) {
  phase_e_redsea_wr_t *w = (phase_e_redsea_wr_t *)ctx;
  return w->rb(w->disk_ctx, buf, len, lba);
}

static void uart_print_redsea_snip(const uint8_t *p, uint64_t total, size_t head_n, size_t tail_n) {
  size_t h = (size_t)(total < (uint64_t)head_n ? total : (uint64_t)head_n);
  for (size_t i = 0; i < h; i++) {
    unsigned char c = p[i];
    if (c >= 32u && c < 127u)
      uart_putc((int)c);
    else
      uart_putc('.');
  }
  if (total <= (uint64_t)h)
    return;
  if (total > (uint64_t)h + (uint64_t)tail_n)
    uart_puts("...");
  size_t start = (size_t)(total > (uint64_t)h + (uint64_t)tail_n ? total - (uint64_t)tail_n : (uint64_t)h);
  for (size_t i = start; i < (size_t)total; i++) {
    unsigned char c = p[i];
    if (c >= 32u && c < 127u)
      uart_putc((int)c);
    else
      uart_putc('.');
  }
}

static void uart_print_redsea_name(const char *s) {
  for (; *s; s++) {
    char c = *s;
    if (c >= 32 && c < 127)
      uart_putc(c);
    else
      uart_putc('?');
  }
}

static void phase_e_virtio_disk_report(const char *tag, phase_e_blk_read_t rb, void *ctx) {
  if (rb(ctx, g_boot_sector, sizeof g_boot_sector, 0) != 0) {
    uart_puts("kernel: Phase E — virtio-blk ");
    uart_puts(tag);
    uart_puts(" LBA0 read failed\r\n");
    if (rb == phase_e_read_mmio) {
      uart_puts("kernel: Phase E — virtio_mmio_fail_stage = 0x");
      put_hex_u64((uint64_t)(unsigned)g_virtio_mmio_fail_stage);
      uart_puts("\r\n");
    } else {
      uart_puts("kernel: Phase E — virtio_pci_fail_stage = 0x");
      put_hex_u64((uint64_t)(unsigned)g_virtio_pci_fail_stage);
      uart_puts("\r\n");
    }
    return;
  }

  uint32_t w = (uint32_t)g_boot_sector[0] | ((uint32_t)g_boot_sector[1] << 8) |
               ((uint32_t)g_boot_sector[2] << 16) | ((uint32_t)g_boot_sector[3] << 24);
  uart_puts("kernel: Phase E — virtio-blk (");
  uart_puts(tag);
  uart_puts(") LBA0 first_u32 = 0x");
  put_hex_u64((uint64_t)w);
  uart_puts("\r\n");

  redsea_boot_fields_t rs;
  if (redsea_parse_boot(g_boot_sector, &rs) != 0)
    return;

  uart_puts("kernel: Phase E — RedSea boot: sects=");
  put_hex_u64(rs.sects);
  uart_puts(" root_clus=");
  put_hex_u64(rs.root_clus);
  uart_puts(" bitmap_sects=");
  put_hex_u64(rs.bitmap_sects);
  uart_puts("\r\n");

  if (rb(ctx, g_root_sector, sizeof g_root_sector, rs.root_clus) != 0) {
    uart_puts("kernel: Phase E — RedSea root cluster read failed\r\n");
    return;
  }

  for (unsigned slot = 0; slot < 512u / CDIR_SIZE; slot++) {
    redsea_dirent_t de;
    const uint8_t *rec = g_root_sector + slot * CDIR_SIZE;
    if (redsea_dirent_decode(rec, &de) != 0)
      continue;
    uart_puts("kernel: Phase E — RedSea root[");
    uart_putc((char)('0' + slot));
    uart_puts("] name=\"");
    uart_print_redsea_name(de.name);
    uart_puts("\" attr=0x");
    put_hex_u64((uint64_t)de.attr);
    uart_puts(" clus=0x");
    put_hex_u64(de.clus);
    uart_puts(" size=0x");
    put_hex_u64(de.size);
    uart_puts("\r\n");
  }

  phase_e_redsea_wr_t wrap;
  wrap.rb = rb;
  wrap.disk_ctx = ctx;

  for (unsigned slot = 0; slot < 512u / CDIR_SIZE; slot++) {
    redsea_dirent_t de;
    if (redsea_dirent_decode(g_root_sector + slot * CDIR_SIZE, &de) != 0)
      continue;
    if ((de.attr & RS_ATTR_DIR) != 0)
      continue;
    if (de.name[0] == '\0')
      continue;
    if (de.size == 0 || de.size > (uint64_t)REDSEA_PHASE_E_FILE_CAP) {
      uart_puts("kernel: Phase E — RedSea file skip (size) name=\"");
      uart_print_redsea_name(de.name);
      uart_puts("\"\r\n");
      continue;
    }
    if (redsea_read_contiguous(phase_e_redsea_adapter, &wrap, de.clus, g_redsea_file_buf, de.size,
                               REDSEA_PHASE_E_FILE_CAP) != 0) {
      uart_puts("kernel: Phase E — RedSea file read failed name=\"");
      uart_print_redsea_name(de.name);
      uart_puts("\"\r\n");
      continue;
    }
    uart_puts("kernel: Phase E — RedSea file \"");
    uart_print_redsea_name(de.name);
    uart_puts("\" ");
    put_hex_u64(de.size);
    uart_puts(" bytes snip=\"");
    uart_print_redsea_snip(g_redsea_file_buf, de.size, 24u, 16u);
    uart_puts("\"\r\n");
  }
}

static void phase_e_storage_report(void) {
  uintptr_t mmio_base = 0;
  if (virtio_mmio_find_blk(&mmio_base) == 0) {
    uart_puts("kernel: Phase E — virtio-blk MMIO @ 0x");
    put_hex_u64((uint64_t)mmio_base);
    uart_puts("\r\n");
    phase_e_virtio_disk_report("MMIO", phase_e_read_mmio, (void *)mmio_base);
    return;
  }

  phase_e_virtio_disk_report("PCI", phase_e_read_pci, NULL);
}

static void try_compiler_slot(void) {
  volatile uint32_t *magic = (volatile uint32_t *)COMPILER_VMA;
  uart_puts("kernel: compiler slot @ 0x80200000\r\n");
  if (*magic != (uint32_t)COMPILER_MAGIC) {
    uart_puts("kernel: compiler slot — no COMP magic (stub not linked)\r\n");
    return;
  }
  uart_puts("kernel: compiler slot — invoking stub @ +4\r\n");
  compiler_stub_fn_t stub = (compiler_stub_fn_t)(COMPILER_VMA + 4);
  stub();
  uart_puts("kernel: compiler stub returned\r\n");
}

static void tos_api_init(void) {
  g_tos_api.magic = TOS_API_MAGIC;
  g_tos_api.version = 1;
  g_tos_api.putchar = tos_api_putchar;
  g_tos_api.getchar = tos_api_getchar;
  g_tos_api.yield = tos_api_yield;
}

void kernel_main(void) {
  uart_puts("\r\n*** TempleOS/RISC-V ***\r\n");
  uart_puts("kernel: Phase A/B traps+compiler, Phase C TosApi @ 0x80300000, Phase D yield stub\r\n");

  tos_api_init();
  /* Prove TosApi vtable from C before running the HolyC guest. */
  g_tos_api.putchar('T');
  g_tos_api.putchar('O');
  g_tos_api.putchar('S');
  g_tos_api.putchar(':');
  uart_puts("\r\nkernel: HolyC guest @ 0x80100000\r\n");

  long r = templeos_invoke_guest((uintptr_t)GUEST_VMA);
  oracle_report((unsigned long)r);

  uart_puts("kernel: guest yield count = ");
  put_hex_u64(g_yield_count);
  uart_puts("\r\n");

  phase_e_storage_report();
  try_compiler_slot();
}
