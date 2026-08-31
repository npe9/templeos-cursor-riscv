#include "virtio_mmio.h"
#include "generated/autoconf.h"

/* Addresses from Kconfig autoconf.h — no separate C virtio “driver” module. */
#ifndef CONFIG_VIRTIO_MMIO_BASE
#define CONFIG_VIRTIO_MMIO_BASE 0x10001000ULL
#endif
#ifndef CONFIG_VIRTIO_MMIO_COUNT
#define CONFIG_VIRTIO_MMIO_COUNT 8u
#endif
#ifndef CONFIG_VIRTIO_MMIO_STRIDE
#define CONFIG_VIRTIO_MMIO_STRIDE 0x1000ULL
#endif

int virtio_mmio_find_blk(uintptr_t *out_base) {
#ifdef CONFIG_HAS_VIRTIO_MMIO
  for (unsigned n = 0; n < (unsigned)CONFIG_VIRTIO_MMIO_COUNT; n++) {
    volatile uint32_t *r = (volatile uint32_t *)(uintptr_t)(
        CONFIG_VIRTIO_MMIO_BASE + (uintptr_t)n * (uintptr_t)CONFIG_VIRTIO_MMIO_STRIDE);
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
#else
  (void)out_base;
#endif
  return -1;
}
