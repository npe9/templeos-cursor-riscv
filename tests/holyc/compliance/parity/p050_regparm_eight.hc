// Parity: exactly 8 arguments (register boundary before 9th stack arg)
I64 Sum8(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h) {
  return a + b + c + d + e + f + g + h;
}

I64 main() {
  return Sum8(1, 2, 3, 4, 5, 6, 7, 8);
}
