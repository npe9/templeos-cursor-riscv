/* pack_tosb.c — wrap host holyc-riscv AOT blob (+ optional HOFYIMP1 trailer)
 * into a TempleOS CBinFile (TOSB) with IET_IMM_I64 import patch entries.
 *
 * Host emit (compiler.c) appends:
 *   { u64 slot_off; char name[24]; } × N
 *   u64 count; u64 magic = "HOFYIMP1" LE
 *
 * Guest Load() (KLoad.HC) expects CBinFile + code + IET_* stream ending in IET_END.
 *
 * Usage:
 *   pack_tosb [-v] [-main] [-e NAME:OFF]... in.blob out.BIN
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>

#define BIN_SIGNATURE_VAL  0x42534F54u /* 'TOSB' LE */
#define IET_END            0
#define IET_IMM_I64        11
#define IET_REL64_EXPORT   18
#define IET_MAIN           25
#define HOFYIMP1_MAGIC     0x31504D4959464F48ULL /* "HOFYIMP1" LE */

#pragma pack(push, 1)
typedef struct {
  uint16_t jmp;
  uint8_t  module_align_bits;
  uint8_t  reserved;
  uint32_t bin_signature;
  int64_t  org;
  int64_t  patch_table_offset;
  int64_t  file_size;
} CBinFile;
#pragma pack(pop)

typedef struct {
  uint64_t slot_off;
  char name[24];
} HofyImp;

typedef struct {
  char name[64];
  uint32_t off;
} Export;

static void die(const char *msg) {
  fprintf(stderr, "pack_tosb: %s\n", msg);
  exit(1);
}

static uint8_t *read_file(const char *path, size_t *n_out) {
  FILE *f = fopen(path, "rb");
  if (!f) die("cannot open input");
  if (fseek(f, 0, SEEK_END)) die("seek");
  long n = ftell(f);
  if (n < 0) die("ftell");
  rewind(f);
  uint8_t *buf = malloc((size_t)n);
  if (!buf) die("oom");
  if (fread(buf, 1, (size_t)n, f) != (size_t)n) die("read");
  fclose(f);
  *n_out = (size_t)n;
  return buf;
}

static bool parse_hofy(uint8_t *buf, size_t n, HofyImp **imps, size_t *n_imps,
                       size_t *code_len) {
  *imps = NULL;
  *n_imps = 0;
  *code_len = n;
  if (n < 16) return false;
  uint64_t magic, count;
  memcpy(&magic, buf + n - 8, 8);
  memcpy(&count, buf + n - 16, 8);
  if (magic != HOFYIMP1_MAGIC) return false;
  size_t dir = (size_t)count * 32 + 16;
  if (dir > n) die("HOFYIMP1 trailer larger than file");
  *code_len = n - dir;
  *n_imps = (size_t)count;
  *imps = calloc(count ? (size_t)count : 1, sizeof(HofyImp));
  if (!*imps) die("oom");
  memcpy(*imps, buf + *code_len, (size_t)count * 32);
  return true;
}

int main(int argc, char **argv) {
  bool verbose = false;
  Export exps[32];
  int n_exps = 0;
  bool emit_main = false;
  int argi = 1;
  while (argi < argc && argv[argi][0] == '-') {
    if (!strcmp(argv[argi], "-v")) { verbose = true; argi++; }
    else if (!strcmp(argv[argi], "-main")) { emit_main = true; argi++; }
    else if (!strcmp(argv[argi], "-e") && argi + 1 < argc) {
      char *spec = argv[++argi];
      char *colon = strrchr(spec, ':');
      if (!colon) die("-e NAME:OFF");
      *colon = 0;
      if (n_exps >= 32) die("too many -e");
      strncpy(exps[n_exps].name, spec, sizeof(exps[0].name) - 1);
      exps[n_exps].off = (uint32_t)strtoul(colon + 1, NULL, 0);
      n_exps++;
      argi++;
    } else {
      die("usage: pack_tosb [-v] [-main] [-e NAME:OFF]... in.blob out.BIN");
    }
  }
  if (argi + 2 != argc)
    die("usage: pack_tosb [-v] [-main] [-e NAME:OFF]... in.blob out.BIN");

  size_t n = 0;
  uint8_t *in = read_file(argv[argi], &n);
  HofyImp *imps = NULL;
  size_t n_imps = 0, code_len = n;
  bool has_hofy = parse_hofy(in, n, &imps, &n_imps, &code_len);

  size_t patch = 0;
  for (size_t i = 0; i < n_imps; i++) {
    size_t nl = strnlen(imps[i].name, 24);
    patch += 1 + 4 + nl + 1;
  }
  for (int i = 0; i < n_exps; i++)
    patch += 1 + 4 + strlen(exps[i].name) + 1;
  if (emit_main)
    patch += 1 + 4 + 1;
  patch += 1; /* END */

  size_t hdr = sizeof(CBinFile);
  size_t file_size = (hdr + code_len + patch + 15) & ~(size_t)15;
  uint8_t *out = calloc(1, file_size);
  if (!out) die("oom");

  CBinFile *bfh = (CBinFile *)out;
  /* TempleOS: EB xx  short jump over header (xx = hdr-2). */
  bfh->jmp = (uint16_t)(0x00EB | ((uint16_t)(hdr - 2) << 8));
  bfh->module_align_bits = 0;
  bfh->reserved = 0;
  bfh->bin_signature = BIN_SIGNATURE_VAL;
  bfh->org = (int64_t)INT64_MAX; /* TempleOS INVALID_PTR = I64_MAX */
  bfh->patch_table_offset = (int64_t)(hdr + code_len);
  bfh->file_size = (int64_t)file_size;
  memcpy(out + hdr, in, code_len);

  uint8_t *p = out + hdr + code_len;
  for (size_t i = 0; i < n_imps; i++) {
    size_t nl = strnlen(imps[i].name, 24);
    if (imps[i].slot_off + 8 > code_len)
      die("import slot past code");
    *p++ = IET_IMM_I64;
    uint32_t off = (uint32_t)imps[i].slot_off;
    memcpy(p, &off, 4); p += 4;
    memcpy(p, imps[i].name, nl); p += nl;
    *p++ = 0;
  }
  for (int i = 0; i < n_exps; i++) {
    *p++ = IET_REL64_EXPORT;
    memcpy(p, &exps[i].off, 4); p += 4;
    size_t nl = strlen(exps[i].name);
    memcpy(p, exps[i].name, nl); p += nl;
    *p++ = 0;
  }
  if (emit_main) {
    *p++ = IET_MAIN;
    uint32_t z = 0;
    memcpy(p, &z, 4); p += 4;
    *p++ = 0;
  }
  *p++ = IET_END;

  FILE *of = fopen(argv[argi + 1], "wb");
  if (!of) die("cannot open output");
  if (fwrite(out, 1, file_size, of) != file_size) die("write");
  fclose(of);

  if (verbose) {
    printf("pack_tosb: code=%zu imports=%zu exports=%d patch=%zu file=%zu hofy=%s\n",
           code_len, n_imps, n_exps, patch, file_size, has_hofy ? "yes" : "no");
    for (size_t i = 0; i < n_imps && i < 8; i++)
      printf("  imm_i64 @ 0x%llx %.*s\n",
             (unsigned long long)imps[i].slot_off, 24, imps[i].name);
    if (n_imps > 8) printf("  ... %zu more\n", n_imps - 8);
  }

  free(imps);
  free(in);
  free(out);
  return 0;
}
