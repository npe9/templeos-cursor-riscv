/*
 * Minimal modern virtio-blk over PCI (QEMU virt + -drive if=virtio).
 * ECAM at 0x30000000; polled virtqueue 0; single sector read.
 */
#include "virtio_blk_pci.h"
#include "pci_ecam.h"
#include <stddef.h>
#include <stdint.h>

#define VIRTIO_PCI_CAP_VENDOR 9
#define VIRTIO_PCI_CAP_COMMON_CFG 1
#define VIRTIO_PCI_CAP_NOTIFY_CFG 2

#define VIRTQ_DESC_F_NEXT 1u
#define VIRTQ_DESC_F_WRITE 2u

#define VIRTIO_BLK_T_IN 0u

#define PCI_VENDOR_VIRTIO 0x1af4
#define PCI_DEV_VIRTIO_BLK_TRANS 0x1001
#define PCI_DEV_VIRTIO_BLK_MODERN 0x1042

#define VPCI_COMMON_MSIX_CONFIG 16
#define VPCI_COMMON_DEVICE_STATUS 20
#define VPCI_COMMON_QUEUE_SELECT 22
#define VPCI_COMMON_QUEUE_SIZE 24
#define VPCI_COMMON_QUEUE_MSIX_VECTOR 26
#define VPCI_COMMON_QUEUE_ENABLE 28
#define VPCI_COMMON_QUEUE_NOTIFY_OFF 30
#define VPCI_COMMON_QUEUE_DESC 32
#define VPCI_COMMON_QUEUE_AVAIL 40
#define VPCI_COMMON_QUEUE_USED 48

#define VIRTIO_CONFIG_S_ACKNOWLEDGE 1
#define VIRTIO_CONFIG_S_DRIVER 2
#define VIRTIO_CONFIG_S_DRIVER_OK 4
#define VIRTIO_CONFIG_S_FEATURES_OK 8
#define VIRTIO_CONFIG_S_FAILED 128

#define VIRTIO_BLK_S_OK 0

typedef struct {
  uint64_t addr;
  uint32_t len;
  uint16_t flags;
  uint16_t next;
} __attribute__((packed)) vring_desc;

struct virtio_blk_req_hdr {
  uint32_t type;
  uint32_t reserved;
  uint64_t sector;
} __attribute__((packed));

static void fence_rw(void) {
  __asm__ volatile("fence rw, rw" ::: "memory");
}

/* Device may DMA to guest RAM; be conservative vs CPU stores. */
static void fence_dev(void) {
  __asm__ volatile("fence iorw, iorw" ::: "memory");
}

static void mmio_w8(volatile void *base, unsigned off, uint8_t v) {
  *(volatile uint8_t *)((uintptr_t)base + off) = v;
}

static uint8_t mmio_r8(volatile void *base, unsigned off) {
  return *(volatile uint8_t *)((uintptr_t)base + off);
}

static void mmio_w16(volatile void *base, unsigned off, uint16_t v) {
  *(volatile uint16_t *)((uintptr_t)base + off) = v;
}

static uint16_t mmio_r16(volatile void *base, unsigned off) {
  return *(volatile uint16_t *)((uintptr_t)base + off);
}

static void mmio_w32(volatile void *base, unsigned off, uint32_t v) {
  *(volatile uint32_t *)((uintptr_t)base + off) = v;
}

static void mmio_w64(volatile void *base, unsigned off, uint64_t v) {
  mmio_w32(base, off, (uint32_t)v);
  mmio_w32(base, off + 4, (uint32_t)(v >> 32));
}

/*
 * QEMU `-bios none` often leaves virtio-pci BAR4 (64-bit MMIO) unassigned (reads ~0x0c).
 * Map device registers into the PCIe MMIO window (see virt machine DTB ranges).
 */
#define VIRTIO_PCI_ASSIGNED_MMIO_BASE 0x48000000ULL

static void pci_assign_virtio_bar4(unsigned b, unsigned d, unsigned f) {
  uint32_t lo = pci_read32(b, d, f, 0x20u);
  uint32_t hi = pci_read32(b, d, f, 0x24u);
  uint8_t lo_type = (uint8_t)(lo & 0xfu);
  if (lo_type != 0x4u && lo_type != 0xcu)
    return;
  uint64_t cur = ((uint64_t)hi << 32) | (uint64_t)lo;
  if ((cur & ~0xfULL) != 0ULL)
    return;

  uint16_t cmd = pci_read16(b, d, f, 0x04u);
  pci_write16(b, d, f, 0x04u, (uint16_t)(cmd & ~6u));
  uint64_t base = VIRTIO_PCI_ASSIGNED_MMIO_BASE;
  pci_write32(b, d, f, 0x20u, (uint32_t)(base | (uint32_t)lo_type));
  pci_write32(b, d, f, 0x24u, (uint32_t)(base >> 32));
  pci_write16(b, d, f, 0x04u, (uint16_t)(cmd | 6u));
}

static int pci_fill_bars(unsigned b, unsigned d, unsigned f, uint64_t *bar6) {
  for (int i = 0; i < 6; i++) {
    uint32_t lo = pci_read32(b, d, f, (unsigned)(0x10 + 4 * i));
    if ((lo & 1u) != 0u) {
      bar6[i] = 0;
      continue;
    }
    if ((lo & 0x6u) == 0x4u) {
      uint32_t hi = pci_read32(b, d, f, (unsigned)(0x10 + 4 * (i + 1)));
      bar6[i] = ((uint64_t)hi << 32) | (lo & ~0xfULL);
      i++;
      if (i < 6)
        bar6[i] = 0;
    } else {
      bar6[i] = lo & ~0xfULL;
    }
  }
  return 0;
}

/*
 * noinline: if this is inlined into virtio_pci_blk_read_lba, RV64 gcc has been
 * observed to reuse a1 (buf_len) for PCI id temporaries and break the caller.
 */
__attribute__((noinline)) static int find_virtio_blk(unsigned *ob, unsigned *od, unsigned *of) {
  for (unsigned bus = 0u; bus < 8u; bus++) {
    for (unsigned dev = 0u; dev < 32u; dev++) {
      for (unsigned fn = 0u; fn < 8u; fn++) {
        uint32_t idl = pci_read32(bus, dev, fn, 0);
        uint16_t vid = (uint16_t)(idl & 0xffffu);
        if (vid == 0xffffu || vid == 0u)
          continue;
        uint16_t did = (uint16_t)(idl >> 16);
        if (vid != PCI_VENDOR_VIRTIO)
          continue;
        if (did != PCI_DEV_VIRTIO_BLK_TRANS && did != PCI_DEV_VIRTIO_BLK_MODERN)
          continue;
        *ob = bus;
        *od = dev;
        *of = fn;
        return 0;
      }
    }
  }
  return -1;
}

static int parse_virtio_caps(unsigned b, unsigned d, unsigned f, const uint64_t *bars,
                             volatile void **out_common, volatile void **out_notify,
                             uint32_t *out_mult) {
  volatile void *common = NULL, *notify = NULL;
  uint32_t mult = 0;

  uint8_t ptr = pci_read8(b, d, f, 0x34);
  while (ptr != 0) {
    uint8_t id = pci_read8(b, d, f, ptr);
    uint8_t next = pci_read8(b, d, f, ptr + 1u);
    uint8_t len = pci_read8(b, d, f, ptr + 2u);

    if (id == VIRTIO_PCI_CAP_VENDOR && len >= 16u) {
      uint8_t cfg_type = pci_read8(b, d, f, ptr + 3u);
      uint8_t bar_idx = pci_read8(b, d, f, ptr + 4u);
      uint32_t off = pci_read32(b, d, f, ptr + 8u);
      if (bar_idx < 6u && bars[bar_idx] != 0u) {
        uintptr_t base = (uintptr_t)bars[bar_idx] + off;
        if (cfg_type == VIRTIO_PCI_CAP_COMMON_CFG)
          common = (volatile void *)base;
        else if (cfg_type == VIRTIO_PCI_CAP_NOTIFY_CFG) {
          notify = (volatile void *)base;
          mult = (len >= 20u) ? pci_read32(b, d, f, ptr + 16u) : 1u;
          if (mult == 0u)
            mult = 1u;
        }
      }
    }
    ptr = next;
  }

  if (!common || !notify)
    return -1;
  *out_common = common;
  *out_notify = notify;
  *out_mult = mult;
  return 0;
}

static void mem_zero(void *p, size_t n) {
  unsigned char *q = (unsigned char *)p;
  while (n--)
    *q++ = 0;
}

/* 16 KiB: descriptors + avail + used for qsz<=256 */
static uint8_t vq_blob[16 * 1024] __attribute__((aligned(4096)));
static struct virtio_blk_req_hdr g_blk_hdr __attribute__((aligned(16)));
static uint8_t g_blk_status;

int g_virtio_pci_fail_stage;

#define VIRTIO_FAIL(n)                                                                 \
  do {                                                                                 \
    g_virtio_pci_fail_stage = (int)(n);                                                \
    return -1;                                                                         \
  } while (0)

int virtio_pci_blk_read_lba(void *buf, size_t buf_len, uint64_t lba) {
  g_virtio_pci_fail_stage = 0;
  if (buf_len < 512u)
    VIRTIO_FAIL(1);

  unsigned b, d, fn;
  if (find_virtio_blk(&b, &d, &fn) != 0)
    VIRTIO_FAIL(2);

  uint16_t cmd = pci_read16(b, d, fn, 0x04);
  pci_write16(b, d, fn, 0x04, (uint16_t)(cmd | 6u)); /* memory + bus master */

  pci_assign_virtio_bar4(b, d, fn);

  uint64_t bars[6];
  pci_fill_bars(b, d, fn, bars);

  volatile void *common, *notify;
  uint32_t notify_mult;
  if (parse_virtio_caps(b, d, fn, bars, &common, &notify, &notify_mult) != 0)
    VIRTIO_FAIL(3);

  /* Device init: negotiate VIRTIO_F_VERSION_1 (bit 32). */
  mmio_w8(common, VPCI_COMMON_DEVICE_STATUS, 0);
  fence_rw();
  mmio_w8(common, VPCI_COMMON_DEVICE_STATUS, VIRTIO_CONFIG_S_ACKNOWLEDGE);
  mmio_w8(common, VPCI_COMMON_DEVICE_STATUS,
          (uint8_t)(VIRTIO_CONFIG_S_ACKNOWLEDGE | VIRTIO_CONFIG_S_DRIVER));

  mmio_w32(common, 8, 0);
  mmio_w32(common, 12, 0);
  mmio_w32(common, 8, 1);
  mmio_w32(common, 12, 1u);

  mmio_w16(common, VPCI_COMMON_MSIX_CONFIG, 0xffffu);

  uint8_t st = (uint8_t)(VIRTIO_CONFIG_S_ACKNOWLEDGE | VIRTIO_CONFIG_S_DRIVER | VIRTIO_CONFIG_S_FEATURES_OK);
  mmio_w8(common, VPCI_COMMON_DEVICE_STATUS, st);
  fence_dev();
  st = mmio_r8(common, VPCI_COMMON_DEVICE_STATUS);
  if ((st & VIRTIO_CONFIG_S_FEATURES_OK) == 0 || (st & VIRTIO_CONFIG_S_FAILED) != 0)
    VIRTIO_FAIL(4);

  mmio_w16(common, VPCI_COMMON_QUEUE_SELECT, 0);
  fence_rw();
  uint16_t qsz = mmio_r16(common, VPCI_COMMON_QUEUE_SIZE);
  if (qsz < 3u)
    VIRTIO_FAIL(5);
  if (qsz > 256u)
    qsz = 256u;
  /* VirtIO 1.x PCI: driver must write queue_size (<= max read above) before queue_enable. */
  mmio_w16(common, VPCI_COMMON_QUEUE_SIZE, qsz);
  fence_rw();

  size_t nd = (size_t)qsz * sizeof(vring_desc);
  size_t navail = 6u + 2u * (size_t)qsz;
  size_t nused = 6u + 8u * (size_t)qsz;
  size_t avail_off = (nd + 1u) & ~(size_t)1u;
  size_t used_off = (avail_off + navail + 3u) & ~(size_t)3u;
  if (used_off + nused > sizeof(vq_blob))
    VIRTIO_FAIL(6);

  mem_zero(vq_blob, sizeof(vq_blob));
  mem_zero(buf, 512u);
  g_blk_status = 0xff;

  g_blk_hdr.type = VIRTIO_BLK_T_IN;
  g_blk_hdr.reserved = 0;
  g_blk_hdr.sector = lba;

  uintptr_t pa_vq = (uintptr_t)vq_blob;
  uintptr_t pa_hdr = (uintptr_t)&g_blk_hdr;
  uintptr_t pa_buf = (uintptr_t)buf;
  uintptr_t pa_st = (uintptr_t)&g_blk_status;

  vring_desc *desc = (vring_desc *)vq_blob;
  desc[0].addr = pa_hdr;
  desc[0].len = sizeof(struct virtio_blk_req_hdr);
  desc[0].flags = VIRTQ_DESC_F_NEXT;
  desc[0].next = 1;
  desc[1].addr = pa_buf;
  desc[1].len = 512u;
  desc[1].flags = (uint16_t)(VIRTQ_DESC_F_WRITE | VIRTQ_DESC_F_NEXT);
  desc[1].next = 2;
  desc[2].addr = pa_st;
  desc[2].len = 1u;
  desc[2].flags = VIRTQ_DESC_F_WRITE;
  desc[2].next = 0;

  volatile uint16_t *avail = (volatile uint16_t *)(vq_blob + avail_off);
  volatile uint16_t *used = (volatile uint16_t *)(vq_blob + used_off);
  avail[0] = 0;
  avail[1] = 0;
  avail[2] = 0;
  fence_dev();

  mmio_w64(common, VPCI_COMMON_QUEUE_DESC, pa_vq);
  mmio_w64(common, VPCI_COMMON_QUEUE_AVAIL, pa_vq + avail_off);
  mmio_w64(common, VPCI_COMMON_QUEUE_USED, pa_vq + used_off);

  mmio_w16(common, VPCI_COMMON_QUEUE_MSIX_VECTOR, 0xffffu);
  mmio_w16(common, VPCI_COMMON_QUEUE_ENABLE, 1);
  fence_dev();

  st = (uint8_t)(st | VIRTIO_CONFIG_S_DRIVER_OK);
  mmio_w8(common, VPCI_COMMON_DEVICE_STATUS, st);
  fence_dev();
  if (mmio_r8(common, VPCI_COMMON_DEVICE_STATUS) & VIRTIO_CONFIG_S_FAILED)
    VIRTIO_FAIL(7);

  uint16_t old_idx = used[1];

  /* Publish one buffer only after queue addresses are live and queue is enabled. */
  avail[1] = 1;
  fence_dev();

  uint16_t q_notify_off = mmio_r16(common, VPCI_COMMON_QUEUE_NOTIFY_OFF);
  volatile uint16_t *notify_reg =
      (volatile uint16_t *)((uintptr_t)notify + (uintptr_t)q_notify_off * notify_mult);
  *notify_reg = 0;
  fence_dev();

  for (unsigned spin = 0; spin < 10000000u; spin++) {
    fence_dev();
    if (used[1] != old_idx)
      break;
  }
  if (used[1] == old_idx)
    VIRTIO_FAIL(8);

  if (g_blk_status != VIRTIO_BLK_S_OK)
    VIRTIO_FAIL(9);

  return 0;
}

int virtio_pci_blk_read_sector0(void *buf, size_t buf_len) {
  return virtio_pci_blk_read_lba(buf, buf_len, 0);
}
