// Parity: && / || short-circuit style control flow
I64 main() {
  I64 x = 0;
  if (0 && (x = 10))
    return 99;
  if (1 || (x = 20))
    x = x + 1;
  return x;
}
