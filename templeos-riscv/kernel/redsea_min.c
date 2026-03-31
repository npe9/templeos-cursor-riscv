#include "redsea_min.h"

static uint64_t rs_le64(const uint8_t *p) {
  uint64_t v = 0;
  for (int i = 0; i < 8; i++)
    v |= (uint64_t)p[i] << (8 * i);
  return v;
}

static int64_t rs_le64_signed(const uint8_t *p) {
  uint64_t u = rs_le64(p);
  return (int64_t)u;
}

static uint16_t rs_le16(const uint8_t *p) {
  return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

int redsea_parse_boot(const uint8_t *s, redsea_boot_fields_t *out) {
  if (s[3] != MBR_PT_REDSEA)
    return -1;
  if (rs_le16(s + 510) != REDSEA_BOOT_SIG2)
    return -1;
  if (!out)
    return 0;
  out->drv_offset = rs_le64_signed(s + 8);
  out->sects = rs_le64(s + 16);
  out->root_clus = rs_le64(s + 24);
  out->bitmap_sects = rs_le64(s + 32);
  out->unique_id = rs_le64(s + 40);
  return 0;
}

int redsea_dirent_name_equals(const redsea_dirent_t *d, const char *ascii) {
  if (!d || !ascii)
    return 0;
  for (size_t i = 0; i < sizeof d->name; i++) {
    char a = d->name[i], b = ascii[i];
    if (b == '\0')
      return a == '\0';
    if (a != b)
      return 0;
  }
  return 0;
}

int redsea_read_contiguous(redsea_blk_read_fn read_lba, void *ctx, uint64_t start_clus, uint8_t *out,
                           uint64_t file_size, size_t out_cap) {
  if (!read_lba || !out || file_size > (uint64_t)out_cap)
    return -1;
  size_t off = 0;
  uint64_t lba = start_clus;
  uint8_t sec[512];
  while (off < (size_t)file_size) {
    if (read_lba(ctx, sec, sizeof sec, lba) != 0)
      return -1;
    size_t need = (size_t)file_size - off;
    size_t take = need > sizeof sec ? sizeof sec : need;
    for (size_t i = 0; i < take; i++)
      out[off++] = sec[i];
    lba++;
  }
  return 0;
}

int redsea_sector_find_file(const uint8_t *sec512, const char *name, redsea_dirent_t *out_de) {
  if (!sec512 || !name)
    return -1;
  for (unsigned slot = 0; slot < 512u / CDIR_SIZE; slot++) {
    redsea_dirent_t de;
    if (redsea_dirent_decode(sec512 + slot * CDIR_SIZE, &de) != 0)
      continue;
    if ((de.attr & RS_ATTR_DIR) != 0)
      continue;
    if (!redsea_dirent_name_equals(&de, name))
      continue;
    if (out_de)
      *out_de = de;
    return (int)slot;
  }
  return -1;
}

int redsea_dirent_decode(const uint8_t *rec64, redsea_dirent_t *out) {
  if (!rec64 || !out)
    return -1;
  uint16_t attr = (uint16_t)rec64[0] | ((uint16_t)rec64[1] << 8);
  if (rec64[2] == 0 && attr == 0)
    return -1;
  out->attr = attr;
  size_t j = 0;
  for (size_t i = 0; i < CDIR_NAME_MAX && j + 1 < sizeof out->name; i++) {
    uint8_t c = rec64[2u + i];
    if (c == 0)
      break;
    if (c >= 32u && c < 127u)
      out->name[j++] = (char)c;
    else
      out->name[j++] = '?';
  }
  out->name[j] = '\0';
  out->clus = rs_le64(rec64 + 40);
  out->size = rs_le64(rec64 + 48);
  out->datetime = rs_le64(rec64 + 56);
  return 0;
}

void redsea_first_dirent_name(const uint8_t *dir, char *out, size_t out_sz) {
  if (out_sz == 0)
    return;
  out[0] = '\0';
  if (!dir)
    return;
  redsea_dirent_t d;
  if (redsea_dirent_decode(dir, &d) != 0)
    return;
  for (size_t i = 0; i < sizeof d.name && i + 1 < out_sz; i++) {
    out[i] = d.name[i];
    if (d.name[i] == '\0')
      return;
  }
  out[out_sz - 1] = '\0';
}
