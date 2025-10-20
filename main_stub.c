#ifdef HOLYC_STANDALONE
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
    fprintf(stderr, "Error: %s\n", cc->error);
    return 1;
  }
  
  printf("✓ Compiled successfully (AOT mode)\n");
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


