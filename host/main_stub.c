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

/* Walk IC after Compile(); print each IC_RAW_RV word as 8 lowercase hex digits.
 * Bypasses RVU32 peephole (which drops nop / mv rd,rd) so this is assembler semantics. */
static int asm_dump_file(const char *path) {
  FILE *f = fopen(path, "r");
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

  Compiler *cc = Compile(src, path, true);
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

int main(int argc, char **argv) {
  if (argc >= 2 && strcmp(argv[1], "--fmt") == 0) {
    int inplace = 1;
    int i = 2;
    if (argc < 3) {
      fprintf(stderr, "Usage: %s --fmt [--stdout] <file.hc>...\n", argv[0]);
      return 1;
    }
    if (strcmp(argv[2], "--stdout") == 0) {
      inplace = 0;
      i = 3;
    }
    if (i >= argc) {
      fprintf(stderr, "Usage: %s --fmt [--stdout] <file.hc>...\n", argv[0]);
      return 1;
    }
    for (; i < argc; i++) {
      int rc = fmt_file(argv[i], inplace);
      if (rc) return rc;
    }
    return 0;
  }

  if (argc >= 2 && strcmp(argv[1], "--asm-dump") == 0) {
    if (argc < 3) {
      fprintf(stderr, "Usage: %s --asm-dump <file.hc>\n", argv[0]);
      return 1;
    }
    return asm_dump_file(argv[2]);
  }

  printf("═══════════════════════════════════════════════════════════\n");
  printf("HolyC to RISC-V Compiler (AOT/JIT)\n");
  printf("═══════════════════════════════════════════════════════════\n\n");

  if (argc < 2) {
    printf("Usage: %s <file.hc> [-o output.bin]\n", argv[0]);
    printf("       %s --fmt [--stdout] <file.hc>...\n", argv[0]);
    printf("       %s --asm-dump <file.hc>\n", argv[0]);
    return 1;
  }

  const char *input = argv[1];
  const char *output = argc > 3 ? argv[3] : "a.bin";

  FILE *f = fopen(input, "r");
  if (!f) {
    fprintf(stderr, "Cannot open %s\n", input);
    return 1;
  }

  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);
  char *src = malloc(sz + 1);
  fread(src, 1, sz, f);
  src[sz] = '\0';
  fclose(f);

  printf("Compiling %s...\n", input);
  Compiler *cc = Compile(src, input, true);
  free(src);

  if (cc->error) {
    const char *file = cc->error_file ? cc->error_file : input;
    fprintf(stderr, "%s:%d:%d: error: %s\n", file, cc->error_line, cc->error_col > 0 ? cc->error_col : 1, cc->error);
    if (cc->error_count > 1 || getenv("HOLYC_ALL_ERRORS")) {
      I64 n = cc->error_count < 256 ? cc->error_count : 256;
      for (I64 i = 0; i < n; i++)
        fprintf(stderr, "%s:%lld:%lld: error: %s\n",
                cc->errors[i].file ? cc->errors[i].file : input,
                (long long)cc->errors[i].line,
                (long long)(cc->errors[i].col > 0 ? cc->errors[i].col : 1),
                cc->errors[i].msg);
      if (cc->error_count > 256) fprintf(stderr, "  ... %lld more\n", (long long)(cc->error_count - 256));
    }
    fprintf(stderr, "(%lld error(s))\n", (long long)cc->error_count);
    return 1;
  }

  printf("✓ Compiled successfully (AOT mode)\n");
  if (cc->asm_blocks_skipped) printf("  (%lld x86 asm block(s) skipped)\n", (long long)cc->asm_blocks_skipped);
  printf("Code size: %lld bytes\n", cc->code_size);

  f = fopen(output, "wb");
  fwrite(cc->code_buffer, 1, cc->code_size, f);
  fclose(f);

  printf("✓ Wrote %s\n\n", output);
  printf("To disassemble:\n");
  printf("  riscv64-unknown-elf-objdump -D -b binary -m riscv:rv64 %s\n\n", output);
  printf("To run in QEMU:\n");
  printf("  qemu-riscv64 %s\n", output);

  CompilerFree(cc);
  return 0;
}
#endif
