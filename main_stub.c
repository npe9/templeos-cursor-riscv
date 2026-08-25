#ifdef HOLYC_STANDALONE
#include <stdio.h>
#include <stdlib.h>
#include "holyc_compiler.h"

int main(int argc, char **argv) {
  printf("═══════════════════════════════════════════════════════════\n");
  printf("HolyC to RISC-V Compiler (AOT/JIT)\n");
  printf("═══════════════════════════════════════════════════════════\n\n");
  
  if (argc < 2) {
    printf("Usage: %s <file.hc> [-o output.bin]\n", argv[0]);
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
    fprintf(stderr, "Error: %s (%lld error(s))\n", cc->error, (long long)cc->error_count);
    if (getenv("HOLYC_ALL_ERRORS")) {
      I64 n = cc->error_count < 256 ? cc->error_count : 256;
      for (I64 i = 0; i < n; i++)
        fprintf(stderr, "  %s:%lld: %s\n", cc->errors[i].file ? cc->errors[i].file : input, (long long)cc->errors[i].line, cc->errors[i].msg);
      if (cc->error_count > 256) fprintf(stderr, "  ... %lld more\n", (long long)(cc->error_count - 256));
    }
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


