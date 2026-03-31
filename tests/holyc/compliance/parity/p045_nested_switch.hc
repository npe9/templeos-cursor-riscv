// Parity: switch inside switch
I64 main() {
  I64 a = 1;
  I64 b = 2;
  I64 r = 0;
  switch (a) {
    case 1:
      switch (b) {
        case 2:
          r = 5;
          break;
        default:
          r = 9;
      }
      break;
    default:
      r = 99;
  }
  return r;
}
