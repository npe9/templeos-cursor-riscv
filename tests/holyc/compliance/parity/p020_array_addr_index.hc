// Parity: local array, address-of element, indexing
I64 main() {
  I64 buf[4];
  buf[0] = 2;
  buf[1] = 3;
  I64 *p = &buf[1];
  *p = *p + 10;
  return buf[0] + buf[1];
}
