/* virtio-mmio transport (VirtIO 1.x) — register layout only; used for discovery on QEMU virt. */
#ifndef TEMPLEOS_VIRTIO_MMIO_H
#define TEMPLEOS_VIRTIO_MMIO_H

#include <stdint.h>

#define VIRTIO_MMIO_MAGIC_VALUE 0x74726976u /* "virt" little-endian */
/* QEMU virtio-mmio defaults to legacy (version 1); we only drive modern MMIO (version 2). */
#define VIRTIO_MMIO_VERSION_MODERN 2u
#define VIRTIO_ID_BLOCK         2u

/* Scan QEMU `virt` virtio-mmio slots; returns 0 if a modern (v2) block device is present. */
int virtio_mmio_find_blk(uintptr_t *out_base);

#endif
