// Parity: goto backward (label after use)
I64 main() {
  I64 x = 0;
  goto tail;
again:
  x = x + 1;
  if (x < 3)
    goto again;
tail:
  if (x == 0)
    goto again;
  return x;
}
