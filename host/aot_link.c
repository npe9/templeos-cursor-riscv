/* Host AOT multi-unit linker: stitch HolyC blobs + patch HOFYIMP1 cross-imports.
 *
 * Each input is a holyc-riscv AOT blob (code+data [+ HOFYIMP1 trailer]) with a
 * sibling `.map` ("offset name" per HOLYC_MAP). Modules are placed in order at
 * --base (default 0x80800000). Cross-unit imports are patched to absolute VMAs;
 * remaining imports (host holy_rt) become one combined trailer for resolve_imports.
 */
#ifndef BARE_METAL
#include "holyc_compiler.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>

#define HOFYIMP1_MAGIC 0x31504D4959464F48ULL
#define DEFAULT_BLOB_BASE 0x80800000ULL

typedef struct {
  uint64_t slot_off;
  char name[24];
} HofyImp;

typedef struct {
  char *name;
  uint64_t off; /* within module raw */
} Exp;

typedef struct {
  char *path;
  uint8_t *file;
  size_t file_n;
  uint8_t *raw;
  size_t raw_n;
  HofyImp *imps;
  size_t n_imps;
  Exp *exps;
  size_t n_exps;
  size_t place; /* offset in combined image */
} Mod;

static void die(const char *fmt, ...) {
  va_list ap;
  fputs("holyc-link: ", stderr);
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fputc('\n', stderr);
  exit(1);
}

static uint8_t *read_all(const char *path, size_t *n_out) {
  FILE *f = fopen(path, "rb");
  if (!f) die("cannot open %s", path);
  if (fseek(f, 0, SEEK_END)) die("seek %s", path);
  long n = ftell(f);
  if (n < 0) die("ftell %s", path);
  rewind(f);
  uint8_t *buf = malloc((size_t)n + 1);
  if (!buf) die("oom");
  if (n && fread(buf, 1, (size_t)n, f) != (size_t)n) die("read %s", path);
  fclose(f);
  *n_out = (size_t)n;
  return buf;
}

static bool strip_hofy(uint8_t *buf, size_t n, HofyImp **imps, size_t *n_imps, size_t *raw_n) {
  *imps = NULL;
  *n_imps = 0;
  *raw_n = n;
  if (n < 16) return false;
  uint64_t magic, count;
  memcpy(&magic, buf + n - 8, 8);
  memcpy(&count, buf + n - 16, 8);
  if (magic != HOFYIMP1_MAGIC) return false;
  size_t dir = (size_t)count * 32 + 16;
  if (dir > n) die("HOFYIMP1 larger than file");
  *raw_n = n - dir;
  *n_imps = (size_t)count;
  if (count) {
    *imps = calloc(count, sizeof(HofyImp));
    if (!*imps) die("oom");
    memcpy(*imps, buf + *raw_n, (size_t)count * 32);
  }
  return true;
}

static char *map_path_for(const char *bin) {
  size_t n = strlen(bin);
  char *m = malloc(n + 5);
  if (!m) die("oom");
  memcpy(m, bin, n + 1);
  char *dot = strrchr(m, '.');
  if (dot && strchr(dot, '/') == NULL) strcpy(dot, ".map");
  else strcat(m, ".map");
  return m;
}

static void load_map(Mod *mod, const char *map_path) {
  FILE *f = fopen(map_path, "r");
  if (!f) die("missing map %s (compile with -o and map sidecar)", map_path);
  char line[512];
  size_t cap = 64, n = 0;
  Exp *exps = calloc(cap, sizeof(Exp));
  if (!exps) die("oom");
  while (fgets(line, sizeof line, f)) {
    unsigned long long off = 0;
    char name[256];
    if (sscanf(line, "%llx %255s", &off, name) != 2) continue;
    if (n == cap) {
      cap *= 2;
      exps = realloc(exps, cap * sizeof(Exp));
      if (!exps) die("oom");
    }
    exps[n].name = strdup(name);
    exps[n].off = off;
    n++;
  }
  fclose(f);
  mod->exps = exps;
  mod->n_exps = n;
}

static uint64_t find_export(Mod *mods, size_t nmods, const char *name, bool *ok) {
  for (size_t i = 0; i < nmods; i++) {
    for (size_t j = 0; j < mods[i].n_exps; j++) {
      if (!strcmp(mods[i].exps[j].name, name)) {
        *ok = true;
        return (uint64_t)mods[i].place + mods[i].exps[j].off;
      }
    }
  }
  *ok = false;
  return 0;
}

static void write_u64_le(uint8_t *p, uint64_t v) {
  for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i));
}

int HolyAOTLink(int argc, char **argv) {
  /* argv[0] is --link; remaining: [-o out] [--base hex] a.bin b.bin ... */
  const char *out = "a.bin";
  uint64_t base = DEFAULT_BLOB_BASE;
  int i = 1;
  while (i < argc && argv[i][0] == '-') {
    if (!strcmp(argv[i], "-o") && i + 1 < argc) {
      out = argv[++i];
      i++;
    } else if (!strcmp(argv[i], "--base") && i + 1 < argc) {
      base = strtoull(argv[++i], NULL, 0);
      i++;
    } else {
      die("unknown link option %s", argv[i]);
    }
  }
  if (i >= argc) {
    fprintf(stderr, "Usage: holyc-riscv --link -o out.bin [--base 0x80800000] a.bin b.bin...\n");
    return 1;
  }

  size_t nmods = (size_t)(argc - i);
  Mod *mods = calloc(nmods, sizeof(Mod));
  if (!mods) die("oom");

  HolyProgress("link %zu unit(s) → %s", nmods, HolyProgressRel(out));

  size_t place = 0;
  for (size_t m = 0; m < nmods; m++) {
    mods[m].path = argv[i + (int)m];
    HolyProgress("  unit %s", HolyProgressRel(mods[m].path));
    mods[m].file = read_all(mods[m].path, &mods[m].file_n);
    if (!strip_hofy(mods[m].file, mods[m].file_n, &mods[m].imps, &mods[m].n_imps, &mods[m].raw_n)) {
      mods[m].raw_n = mods[m].file_n;
      mods[m].imps = NULL;
      mods[m].n_imps = 0;
    }
    mods[m].raw = mods[m].file; /* trailer ignored via raw_n */
    char *mp = map_path_for(mods[m].path);
    load_map(&mods[m], mp);
    free(mp);
    place = (place + 7) & ~(size_t)7;
    mods[m].place = place;
    place += mods[m].raw_n;
  }

  /* Combined raw + worst-case trailer for unresolved imports */
  size_t total_imps = 0;
  for (size_t m = 0; m < nmods; m++) total_imps += mods[m].n_imps;
  size_t out_cap = place + total_imps * 32 + 16 + 64;
  uint8_t *outbuf = calloc(1, out_cap);
  if (!outbuf) die("oom");

  for (size_t m = 0; m < nmods; m++)
    memcpy(outbuf + mods[m].place, mods[m].raw, mods[m].raw_n);

  HofyImp *remain = calloc(total_imps ? total_imps : 1, sizeof(HofyImp));
  size_t n_remain = 0;
  size_t n_patched = 0;

  for (size_t m = 0; m < nmods; m++) {
    for (size_t k = 0; k < mods[m].n_imps; k++) {
      HofyImp *imp = &mods[m].imps[k];
      char name[25];
      memcpy(name, imp->name, 24);
      name[24] = 0;
      bool ok = false;
      uint64_t rel = find_export(mods, nmods, name, &ok);
      size_t slot = mods[m].place + (size_t)imp->slot_off;
      if (slot + 8 > place) die("import slot out of range in %s (%s)", mods[m].path, name);
      if (ok) {
        write_u64_le(outbuf + slot, base + rel);
        n_patched++;
      } else {
        remain[n_remain] = *imp;
        remain[n_remain].slot_off = (uint64_t)slot; /* combined-relative */
        n_remain++;
      }
    }
  }

  size_t out_n = place;
  if (n_remain) {
    uint8_t *dp = outbuf + out_n;
    for (size_t k = 0; k < n_remain; k++) {
      write_u64_le(dp, remain[k].slot_off);
      memcpy(dp + 8, remain[k].name, 24);
      dp += 32;
    }
    write_u64_le(dp, (uint64_t)n_remain);
    write_u64_le(dp + 8, HOFYIMP1_MAGIC);
    out_n += n_remain * 32 + 16;
  }

  FILE *of = fopen(out, "wb");
  if (!of) die("cannot write %s", out);
  if (fwrite(outbuf, 1, out_n, of) != out_n) die("write %s", out);
  fclose(of);

  HolyProgress("link ok (%zu bytes, %zu patched, %zu host-imports)", out_n, n_patched, n_remain);

  free(remain);
  free(outbuf);
  for (size_t m = 0; m < nmods; m++) {
    free(mods[m].file);
    free(mods[m].imps);
    for (size_t j = 0; j < mods[m].n_exps; j++) free(mods[m].exps[j].name);
    free(mods[m].exps);
  }
  free(mods);
  return 0;
}
#endif
