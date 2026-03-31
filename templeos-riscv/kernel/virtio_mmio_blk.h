/* VirtIO 1.x virtio-blk over virtio-mmio (QEMU `virt` DTB slots @ 0x10001000 + n*0x1000). */
#ifndef TEMPLEOS_VIRTIO_MMIO_BLK_H
#define TEMPLEOS_VIRTIO_MMIO_BLK_H

#include <stddef.h>
#include <stdint.h>

extern int g_virtio_mmio_fail_stage;

/* reg_base: first register page (Magic @ 0); polled single-sector read. */
int virtio_mmio_blk_read_lba(uintptr_t reg_base, void *buf, size_t buf_len, uint64_t lba);
int virtio_mmio_blk_read_sector0(uintptr_t reg_base, void *buf, size_t buf_len);

#endif
