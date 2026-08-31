/* Minimal RedSea (TempleOS) on-disk layout — see tos/Doc/RedSea.DD, Kernel/KernelA.HH CRedSeaBoot. */
#ifndef TEMPLEOS_REDSEA_MIN_H
#define TEMPLEOS_REDSEA_MIN_H

#include <stddef.h>
#include <stdint.h>

#define MBR_PT_REDSEA 0x88u
#define REDSEA_BOOT_SIG2 0xAA55u

typedef struct {
  int64_t drv_offset;
  uint64_t sects;
  uint64_t root_clus;
  uint64_t bitmap_sects;
  uint64_t unique_id;
} redsea_boot_fields_t;

/* LBA0 boot sector: signature byte @3, trailing 0xAA55 @510. */
int redsea_parse_boot(const uint8_t *sector512, redsea_boot_fields_t *out);

#define CDIR_SIZE 64u
#define CDIR_NAME_MAX 38u

#define RS_ATTR_DIR 0x10u
#define RS_ATTR_CONTIGUOUS 0x800u

typedef struct {
  uint16_t attr;
  char name[40];
  uint64_t clus;
  uint64_t size;
  uint64_t datetime;
} redsea_dirent_t;

/* Decode one 64-byte CDirEntry. Returns 0 on success, -1 if slot looks unused (empty name). */
int redsea_dirent_decode(const uint8_t *rec64, redsea_dirent_t *out);

int redsea_dirent_name_equals(const redsea_dirent_t *d, const char *ascii);

/* First non-directory entry matching basename in one 512-byte dir sector; slot index or -1. */
int redsea_sector_find_file(const uint8_t *sec512, const char *name, redsea_dirent_t *out_de);

/* One 512-byte sector at virtio-blk LBA `lba` (RedSea clus == LBA for 512-byte clusters). */
typedef int (*redsea_blk_read_fn)(void *ctx, void *buf, size_t len, uint64_t lba);

/* Contiguous file: reads ceil(file_size/512) sectors from start_clus. Returns 0 or -1. */
int redsea_read_contiguous(redsea_blk_read_fn read_lba, void *ctx, uint64_t start_clus,
                           uint8_t *out, uint64_t file_size, size_t out_cap);

/* First 64-byte directory record in a root cluster sector; copies name (NUL-term, max 38). */
void redsea_first_dirent_name(const uint8_t *dir_sector512, char *out, size_t out_sz);

#endif
