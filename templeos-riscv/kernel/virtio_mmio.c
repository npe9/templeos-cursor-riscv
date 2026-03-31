#include "virtio_mmio.h"

/* QEMU `-M virt`: DTB maps virtio-mmio at 0x10001000 + n * 0x1000 (see qemu/hw/riscv/virt.c). */
#define QEMU_VIRTIO_MMIO_BASE   0x10001000ULL
#define QEMU_VIRTIO_MMIO_SLOTS  8u
#define QEMU_VIRTIO_MMIO_STRIDE 0x1000ULL

int virtio_mmio_find_blk(uintptr_t *out_base) {
  for (unsigned n = 0; n < QEMU_VIRTIO_MMIO_SLOTS; n++) {
    volatile uint32_t *r =
        (volatile uint32_t *)(QEMU_VIRTIO_MMIO_BASE + (uintptr_t)n * QEMU_VIRTIO_MMIO_STRIDE);
    if (r[0] != VIRTIO_MMIO_MAGIC_VALUE)
      continue;
    if (r[1] != VIRTIO_MMIO_VERSION_MODERN)
      continue;
    if (r[2] != VIRTIO_ID_BLOCK)
      continue;
    if (out_base)
      *out_base = (uintptr_t)r;
    return 0;
  }
  return -1;
}
