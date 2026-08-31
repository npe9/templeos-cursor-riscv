U8 *malloc(I64 size) {
  return 0;
}

U8 *MyAlloc(I64 count) {
  I64 total = count * 8;
  U8 *ptr = malloc(total);
  return ptr;
}

