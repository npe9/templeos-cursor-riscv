// Parity: U0 procedures + I64/Bool helpers (TempleOS idiom)
U0 Nop() {
}

I64 Add3(I64 a, I64 b, I64 c) {
  return a + b + c;
}

I64 main() {
  Nop();
  return Add3(1, 2, 3);
}
