// Parity: >8 arguments (stack spill / shuffle vs x86 register+stack ABI)
I64 Sum9(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h, I64 i) {
  return a + b + c + d + e + f + g + h + i;
}

I64 main() {
  return Sum9(1, 2, 3, 4, 5, 6, 7, 8, 9);
}
