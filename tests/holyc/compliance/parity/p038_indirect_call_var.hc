// Parity: indirect call through variable pointer (not direct name)
I64 Doub(I64 x) {
  return x + x;
}

I64 main() {
  I64 (*fp)(I64) = Doub;
  return fp(21);
}
