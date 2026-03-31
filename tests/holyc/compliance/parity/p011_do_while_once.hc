// Parity: do-while runs body once when condition false at end
I64 main() {
  I64 n = 0;
  do {
    n = n + 1;
  } while (0);
  return n;
}
