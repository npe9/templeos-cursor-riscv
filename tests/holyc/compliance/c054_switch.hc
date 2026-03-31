I64 Pick(I64 x) {
  switch (x) {
    case 1:
      return 10;
    case 2:
    case 3:
      return 20;
    default:
      return 0;
  }
}

I64 main() {
  return Pick(1) + Pick(3) + Pick(99);
}
