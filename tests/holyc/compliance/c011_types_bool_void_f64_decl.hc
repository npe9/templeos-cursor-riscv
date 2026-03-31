U0 Empty() {
}

Bool IsThree(I64 x) {
  return x == 3;
}

I64 main() {
  Empty();
  if (IsThree(3))
    return 1;
  return 0;
}
