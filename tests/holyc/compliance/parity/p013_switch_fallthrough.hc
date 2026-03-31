// Parity: switch fall-through (same as TempleOS C switch)
I64 F(I64 x) {
  I64 r = 0;
  switch (x) {
    case 1:
      r = r + 1;
    case 2:
      r = r + 10;
      break;
    default:
      r = 100;
  }
  return r;
}

I64 main() {
  return F(1) + F(2) + F(9);
}
