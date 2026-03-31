I64 Classify(I64 x) {
  if (x < 0)
    return 0;
  else if (x == 0)
    return 1;
  else if (x < 10)
    return 2;
  else
    return 3;
}

I64 main() {
  return Classify(5) + Classify(-1) + Classify(0) + Classify(100);
}
