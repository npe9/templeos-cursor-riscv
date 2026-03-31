// Same TosApi magic check as kmain.hc; optional copy for experiments.
I64 main() {
  I64 base;
  U32 *magic_word;
  base = 0x803;
  base = base * 0x100000;
  magic_word = (U32 *)base;
  if (*magic_word != 0x41534f54)
    return 2;
  return 42;
}
