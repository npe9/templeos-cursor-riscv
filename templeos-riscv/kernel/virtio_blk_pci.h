#ifndef TEMPLEOS_VIRTIO_BLK_PCI_H
#define TEMPLEOS_VIRTIO_BLK_PCI_H

#include <stddef.h>
#include <stdint.h>

/* Last virtio_pci_blk_read_lba failure site (0 = success / unused). */
extern int g_virtio_pci_fail_stage;

/* Single 512-byte sector read at virtio-blk LBA (512-byte units). */
int virtio_pci_blk_read_lba(void *buf, size_t buf_len, uint64_t lba);
int virtio_pci_blk_read_sector0(void *buf, size_t buf_len);

#endif
