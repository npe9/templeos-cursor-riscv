// Parity: switch containing loop
I64 main() {
  I64 x = 1;
  I64 t = 0;
  switch (x) {
    case 1: {
      I64 i = 0;
      while (i < 3) {
        t = t + i;
        i = i + 1;
      }
      break;
    }
    default:
      t = 99;
  }
  return t;
}
