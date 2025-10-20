I64 TestSwitch(I64 x) {
  switch (x) {
    case 0:
      return 100;
    case 1:
      return 200;
    case 2:
      return 300;
    default:
      return -1;
  }
}

I64 TestSwitch2(I64 val) {
  I64 result = 0;
  switch (val) {
    case 10:
      result = 1;
      break;
    case 20:
      result = 2;
      break;
    case 30:
      result = 3;
      break;
    default:
      result = -1;
  }
  return result;
}
