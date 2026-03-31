/*
 * Minimal virtio-blk over virtio-mmio (VirtIO 1.x), polled virtqueue 0, 512-byte LBA read.
 * Register map: Linux uapi/linux/virtio_mmio.h
 */
#include "virtio_mmio_blk.h"
#include <stddef.h>
#include <stdint.h>

#define VIRTQ_DESC_F_NEXT 1u
#define VIRTQ_DESC_F_WRITE 2u
#define VIRTIO_BLK_T_IN 0u
#define VIRTIO_BLK_S_OK 0

#define VIRTIO_MMIO_MAGIC_VALUE 0x74726976u
#define VIRTIO_MMIO_VERSION 0x004
#define VIRTIO_MMIO_STATUS 0x070
#define VIRTIO_MMIO_DEVICE_FEATURES 0x010
#define VIRTIO_MMIO_DEVICE_FEATURES_SEL 0x014
#define VIRTIO_MMIO_DRIVER_FEATURES 0x020
#define VIRTIO_MMIO_DRIVER_FEATURES_SEL 0x024
#define VIRTIO_MMIO_QUEUE_SEL 0x030
#define VIRTIO_MMIO_QUEUE_NUM_MAX 0x034
#define VIRTIO_MMIO_QUEUE_NUM 0x038
#define VIRTIO_MMIO_QUEUE_READY 0x044
#define VIRTIO_MMIO_QUEUE_NOTIFY 0x050
#define VIRTIO_MMIO_QUEUE_DESC_LOW 0x080
#define VIRTIO_MMIO_QUEUE_DESC_HIGH 0x084
#define VIRTIO_MMIO_QUEUE_AVAIL_LOW 0x090
#define VIRTIO_MMIO_QUEUE_AVAIL_HIGH 0x094
#define VIRTIO_MMIO_QUEUE_USED_LOW 0x0a0
#define VIRTIO_MMIO_QUEUE_USED_HIGH 0x0a4

#define VIRTIO_CONFIG_S_ACKNOWLEDGE 1
#define VIRTIO_CONFIG_S_DRIVER 2
#define VIRTIO_CONFIG_S_DRIVER_OK 4
#define VIRTIO_CONFIG_S_FEATURES_OK 8
#define VIRTIO_CONFIG_S_FAILED 128

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

static void fence_dev(void) {
  __asm__ volatile("fence iorw, iorw" ::: "memory");
}

static uint32_t vr32(uintptr_t b, unsigned o) {
  return *(volatile uint32_t *)(b + (uintptr_t)o);
}

static void vw32(uintptr_t b, unsigned o, uint32_t v) {
  *(volatile uint32_t *)(b + (uintptr_t)o) = v;
}

static void vwa64(uintptr_t b, unsigned off_low, uint64_t pa) {
  vw32(b, off_low, (uint32_t)pa);
  vw32(b, off_low + 4u, (uint32_t)(pa >> 32));
}

static void mem_zero(void *p, size_t n) {
  unsigned char *q = (unsigned char *)p;
  while (n--)
    *q++ = 0;
}

int g_virtio_mmio_fail_stage;

#define MM_FAIL(n)                                                                           \
  do {                                                                                       \
    g_virtio_mmio_fail_stage = (int)(n);                                                     \
    return -1;                                                                               \
  } while (0)

static uint8_t mm_vq_blob[16 * 1024] __attribute__((aligned(4096)));
static struct virtio_blk_req_hdr mm_blk_hdr __attribute__((aligned(16)));
static uint8_t mm_blk_status;

int virtio_mmio_blk_read_lba(uintptr_t b, void *buf, size_t buf_len, uint64_t lba) {
  g_virtio_mmio_fail_stage = 0;
  if (buf_len < 512u)
    MM_FAIL(1);
  if (vr32(b, 0) != VIRTIO_MMIO_MAGIC_VALUE)
    MM_FAIL(2);
  if (vr32(b, VIRTIO_MMIO_VERSION) != 2u)
    MM_FAIL(11);

  vw32(b, VIRTIO_MMIO_STATUS, 0);
  fence_rw();
  vw32(b, VIRTIO_MMIO_STATUS, VIRTIO_CONFIG_S_ACKNOWLEDGE);
  vw32(b, VIRTIO_MMIO_STATUS, (uint32_t)(VIRTIO_CONFIG_S_ACKNOWLEDGE | VIRTIO_CONFIG_S_DRIVER));

  vw32(b, VIRTIO_MMIO_DRIVER_FEATURES_SEL, 0);
  vw32(b, VIRTIO_MMIO_DRIVER_FEATURES, 0);
  vw32(b, VIRTIO_MMIO_DRIVER_FEATURES_SEL, 1);
  vw32(b, VIRTIO_MMIO_DRIVER_FEATURES, 1u);

  vw32(b, VIRTIO_MMIO_STATUS,
       (uint32_t)(VIRTIO_CONFIG_S_ACKNOWLEDGE | VIRTIO_CONFIG_S_DRIVER | VIRTIO_CONFIG_S_FEATURES_OK));
  fence_dev();
  {
    uint32_t sr = vr32(b, VIRTIO_MMIO_STATUS);
    if ((sr & VIRTIO_CONFIG_S_FEATURES_OK) == 0 || (sr & VIRTIO_CONFIG_S_FAILED) != 0)
      MM_FAIL(3);
  }

  vw32(b, VIRTIO_MMIO_QUEUE_SEL, 0);
  fence_rw();
  uint32_t qmax = vr32(b, VIRTIO_MMIO_QUEUE_NUM_MAX);
  if (qmax < 3u)
    MM_FAIL(4);
  /* vq_blob sized for qsz<=256; devices may advertise e.g. 1024. */
  uint16_t qsz = (qmax > 256u) ? 256u : (uint16_t)qmax;
  vw32(b, VIRTIO_MMIO_QUEUE_NUM, (uint32_t)qsz);
  fence_rw();
  size_t nd = (size_t)qsz * sizeof(vring_desc);
  size_t navail = 6u + 2u * (size_t)qsz;
  size_t nused = 6u + 8u * (size_t)qsz;
  size_t avail_off = (nd + 1u) & ~(size_t)1u;
  size_t used_off = (avail_off + navail + 3u) & ~(size_t)3u;
  if (used_off + nused > sizeof mm_vq_blob)
    MM_FAIL(5);

  mem_zero(mm_vq_blob, sizeof mm_vq_blob);
  mem_zero(buf, 512u);
  mm_blk_status = 0xff;

  mm_blk_hdr.type = VIRTIO_BLK_T_IN;
  mm_blk_hdr.reserved = 0;
  mm_blk_hdr.sector = lba;

  uintptr_t pa_vq = (uintptr_t)mm_vq_blob;
  uintptr_t pa_hdr = (uintptr_t)&mm_blk_hdr;
  uintptr_t pa_buf = (uintptr_t)buf;
  uintptr_t pa_st = (uintptr_t)&mm_blk_status;

  vring_desc *desc = (vring_desc *)mm_vq_blob;
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

  volatile uint16_t *avail = (volatile uint16_t *)(mm_vq_blob + avail_off);
  volatile uint16_t *used = (volatile uint16_t *)(mm_vq_blob + used_off);
  avail[0] = 0;
  avail[1] = 0;
  avail[2] = 0;
  fence_dev();

  vwa64(b, VIRTIO_MMIO_QUEUE_DESC_LOW, pa_vq);
  vwa64(b, VIRTIO_MMIO_QUEUE_AVAIL_LOW, pa_vq + avail_off);
  vwa64(b, VIRTIO_MMIO_QUEUE_USED_LOW, pa_vq + used_off);

  vw32(b, VIRTIO_MMIO_QUEUE_READY, 1);
  fence_dev();

  vw32(b, VIRTIO_MMIO_STATUS,
       (uint32_t)(VIRTIO_CONFIG_S_ACKNOWLEDGE | VIRTIO_CONFIG_S_DRIVER | VIRTIO_CONFIG_S_FEATURES_OK |
                  VIRTIO_CONFIG_S_DRIVER_OK));
  fence_dev();
  if (vr32(b, VIRTIO_MMIO_STATUS) & VIRTIO_CONFIG_S_FAILED)
    MM_FAIL(6);

  uint16_t old_idx = used[1];
  avail[1] = 1;
  fence_dev();

  vw32(b, VIRTIO_MMIO_QUEUE_NOTIFY, 0);
  fence_dev();

  for (unsigned spin = 0; spin < 10000000u; spin++) {
    fence_dev();
    if (used[1] != old_idx)
      break;
  }
  if (used[1] == old_idx)
    MM_FAIL(7);

  if (mm_blk_status != VIRTIO_BLK_S_OK)
    MM_FAIL(8);

  return 0;
}

int virtio_mmio_blk_read_sector0(uintptr_t reg_base, void *buf, size_t buf_len) {
  return virtio_mmio_blk_read_lba(reg_base, buf, buf_len, 0);
}
