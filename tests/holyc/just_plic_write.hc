I64 Main() {
  U32 *ptr;
  ptr = 0x0C000004;
  *ptr = 99;
  return 99;
}
