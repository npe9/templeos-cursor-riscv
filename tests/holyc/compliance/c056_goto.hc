I64 main() {
  I64 x = 0;
  goto mid;
  x = 100;
mid:
  x = x + 5;
  return x;
}
