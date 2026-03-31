I64 main() {
  I64 i = 0;
  I64 s = 0;
  while (i < 10) {
    i = i + 1;
    if (i == 3)
      continue;
    if (i == 8)
      break;
    s = s + i;
  }
  return s;
}
