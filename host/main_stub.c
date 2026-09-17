#ifdef HOLYC_STANDALONE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "holyc_compiler.h"
#include "holyc_fmt.h"

static int fmt_file(const char *path, int inplace) {
  FILE *f;
  long sz;
  char *src, *out;
  long long n, cap;

  f = fopen(path, "rb");
  if (!f) {
    fprintf(stderr, "Cannot open %s\n", path);
    return 1;
  }
  if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return 1; }
  sz = ftell(f);
  if (sz < 0) { fclose(f); return 1; }
  if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return 1; }
  src = malloc((size_t)sz + 1);
  if (!src) { fclose(f); return 1; }
  if (fread(src, 1, (size_t)sz, f) != (size_t)sz) { free(src); fclose(f); return 1; }
  src[sz] = 0;
  fclose(f);

  cap = sz * 2 + 4096;
  out = malloc((size_t)cap);
  if (!out) { free(src); return 1; }
  n = HolyFmtSrc(src, out, cap);
  free(src);
  if (n < 0) {
    fprintf(stderr, "Fmt failed for %s (buffer)\n", path);
    free(out);
    return 1;
  }

  if (!inplace) {
    fwrite(out, 1, (size_t)n, stdout);
    free(out);
    return 0;
  }

  f = fopen(path, "wb");
  if (!f) {
    fprintf(stderr, "Cannot write %s\n", path);
    free(out);
    return 1;
  }
  fwrite(out, 1, (size_t)n, f);
  fclose(f);
  free(out);
  printf("Formatted %s (%lld bytes)\n", path, n);
  return 0;
}

static int asm_dump_file(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) {
    fprintf(stderr, "Cannot open %s\n", path);
    return 2;
  }
  if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return 2; }
  long sz = ftell(f);
  if (sz < 0) { fclose(f); return 2; }
  if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return 2; }
  char *src = malloc((size_t)sz + 1);
  if (!src) { fclose(f); return 2; }
  if (fread(src, 1, (size_t)sz, f) != (size_t)sz) { free(src); fclose(f); return 2; }
  src[sz] = '\0';
  fclose(f);

  Compiler *cc = CompileBuf(src, (size_t)sz, path, true);
  free(src);
  if (cc->error) {
    const char *file = cc->error_file ? cc->error_file : path;
    fprintf(stderr, "%s:%d:%d: error: %s\n", file, cc->error_line,
            cc->error_col > 0 ? cc->error_col : 1, cc->error);
    CompilerFree(cc);
    return 2;
  }

  I64 n = 0;
  for (CIntermediateCode *ic = cc->ic_head; ic; ic = ic->next) {
    if (ic->ic_code != IC_RAW_RV) continue;
    printf("%08x\n", (unsigned)(U32)ic->ic_data);
    n++;
  }
  CompilerFree(cc);
  if (n == 0) {
    fprintf(stderr, "asm-dump: no IC_RAW_RV words (asm skipped or empty)\n");
    return 1;
  }
  return 0;
}

static char *stem_map_path(const char *bin) {
  size_t n = strlen(bin);
  char *m = malloc(n + 5);
  if (!m) return NULL;
  memcpy(m, bin, n + 1);
  char *dot = strrchr(m, '.');
  if (dot && strchr(dot, '/') == NULL) strcpy(dot, ".map");
  else strcat(m, ".map");
  return m;
}

static void usage(const char *argv0) {
  fprintf(stderr,
          "Usage: %s <file.hc> [-o out.bin] [--target rv64|rv32] [--deps out.d] [--map out.map]\n"
          "       %s --link -o out.bin [--base 0x80800000] a.bin b.bin...\n"
          "       %s --fmt [--stdout] <file.hc>...\n"
          "       %s --asm-dump <file.hc>\n"
          "   --target selects the codegen ISA (rv64 default, rv32; also via HOLYC_ARCH).\n",
          argv0, argv0, argv0, argv0);
}

int main(int argc, char **argv) {
  if (argc >= 2 && strcmp(argv[1], "--fmt") == 0) {
    int inplace = 1;
    int i = 2;
    if (argc < 3) { usage(argv[0]); return 1; }
    if (strcmp(argv[2], "--stdout") == 0) { inplace = 0; i = 3; }
    if (i >= argc) { usage(argv[0]); return 1; }
    for (; i < argc; i++) {
      int rc = fmt_file(argv[i], inplace);
      if (rc) return rc;
    }
    return 0;
  }

  if (argc >= 2 && strcmp(argv[1], "--asm-dump") == 0) {
    if (argc < 3) { usage(argv[0]); return 1; }
    return asm_dump_file(argv[2]);
  }

  if (argc >= 2 && strcmp(argv[1], "--link") == 0)
    return HolyAOTLink(argc - 1, argv + 1);

  const char *input = NULL;
  const char *output = "a.bin";
  const char *deps = NULL;
  const char *map_arg = NULL;
  const char *target_arg = NULL;
  int quiet = 0;
  int map_owned = 0;

  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-o") && i + 1 < argc) {
      output = argv[++i];
      quiet = 1;
    } else if (!strcmp(argv[i], "--deps") && i + 1 < argc) {
      deps = argv[++i];
    } else if (!strcmp(argv[i], "--target") && i + 1 < argc) {
      target_arg = argv[++i];
    } else if (!strcmp(argv[i], "--map") && i + 1 < argc) {
      map_arg = argv[++i];
    } else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
      usage(argv[0]);
      return 0;
    } else if (argv[i][0] == '-') {
      fprintf(stderr, "Unknown option: %s\n", argv[i]);
      usage(argv[0]);
      return 1;
    } else if (!input) {
      input = argv[i];
    } else {
      /* Legacy: holyc-riscv in.hc out.bin */
      output = argv[i];
      quiet = 1;
    }
  }

  if (!input) { usage(argv[0]); return 1; }

  /* Codegen target: --target arg > HOLYC_ARCH env > rv64 default. rv32 emits the P0
   * subset (32-bit values; wide I64 lands later); others are not wired yet. */
  {
    const char *t = target_arg ? target_arg : getenv("HOLYC_ARCH");
    if (t && strcmp(t, "rv64") != 0 && strcmp(t, "rv32") != 0) {
      fprintf(stderr, "holyc-riscv: unknown --target '%s' (supported: rv64, rv32)\n", t);
      return 1;
    }
    if (target_arg) setenv("HOLYC_ARCH", target_arg, 1); /* so CompilerNewBuf agrees */
  }

  char *map_path = NULL;
  if (map_arg) {
    map_path = (char *)map_arg;
  } else {
    map_path = stem_map_path(output);
    map_owned = 1;
  }

  FILE *f = fopen(input, "rb");
  if (!f) {
    fprintf(stderr, "Cannot open %s\n", input);
    if (map_owned) free(map_path);
    return 1;
  }

  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);
  char *src = malloc((size_t)sz + 1);
  if (!src) { fclose(f); if (map_owned) free(map_path); return 1; }
  if (sz > 0 && fread(src, 1, (size_t)sz, f) != (size_t)sz) {
    free(src); fclose(f); if (map_owned) free(map_path); return 1;
  }
  src[sz] = '\0';
  fclose(f);

  if (!quiet) {
    printf("═══════════════════════════════════════════════════════════\n");
    printf("HolyC to RISC-V Compiler (AOT/JIT)\n");
    printf("═══════════════════════════════════════════════════════════\n\n");
    printf("Compiling %s...\n", input);
  }

  Compiler *cc = CompileBuf(src, (size_t)sz, input, true);
  free(src);

  if (cc->error) {
    const char *file = cc->error_file ? cc->error_file : input;
    fprintf(stderr, "%s:%d:%d: error: %s\n", file, cc->error_line,
            cc->error_col > 0 ? cc->error_col : 1, cc->error);
    if (cc->error_count > 1 || getenv("HOLYC_ALL_ERRORS")) {
      I64 n = cc->error_count < 256 ? cc->error_count : 256;
      for (I64 ei = 0; ei < n; ei++)
        fprintf(stderr, "%s:%lld:%lld: error: %s\n",
                cc->errors[ei].file ? cc->errors[ei].file : input,
                (long long)cc->errors[ei].line,
                (long long)(cc->errors[ei].col > 0 ? cc->errors[ei].col : 1),
                cc->errors[ei].msg);
      if (cc->error_count > 256)
        fprintf(stderr, "  ... %lld more\n", (long long)(cc->error_count - 256));
    }
    fprintf(stderr, "(%lld error(s))\n", (long long)cc->error_count);
    CompilerFree(cc);
    if (map_owned) free(map_path);
    return 1;
  }

  if (!cc->code_buffer) {
    fprintf(stderr, "AOT emit failed\n");
    CompilerFree(cc);
    if (map_owned) free(map_path);
    return 1;
  }

  f = fopen(output, "wb");
  if (!f) {
    fprintf(stderr, "Cannot write %s\n", output);
    CompilerFree(cc);
    if (map_owned) free(map_path);
    return 1;
  }
  fwrite(cc->code_buffer, 1, (size_t)cc->code_size, f);
  fclose(f);

  if (map_path) AOTWriteMap(cc, map_path);
  if (deps) AOTWriteDeps(cc, deps, output);

  // `-o` implies quiet (above), which silences the "Code size:" line that
  // tests/scripts/run_holyc_compliance.sh parses to check a construct actually
  // emitted code. Opt-in so no existing script's captured stdout changes shape.
  if (quiet && getenv("HOLYC_PRINT_SIZE"))
    printf("Code size: %lld bytes\n", cc->code_size);

  if (!quiet) {
    printf("✓ Compiled successfully (AOT mode)\n");
    if (cc->asm_blocks_skipped)
      printf("  (%lld x86 asm block(s) skipped)\n", (long long)cc->asm_blocks_skipped);
    printf("Code size: %lld bytes\n", cc->code_size);
    printf("✓ Wrote %s\n", output);
    if (map_path) printf("✓ Wrote %s\n", map_path);
  }

  CompilerFree(cc);
  if (map_owned) free(map_path);
  return 0;
}
#endif
