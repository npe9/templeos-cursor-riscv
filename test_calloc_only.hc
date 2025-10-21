U8 *malloc(I64 size);

U8 *calloc(I64 count, I64 size) {
  I64 total = count * size;
  U8 *ptr = malloc(total);
  
  if (ptr) {
    for (I64 i = 0; i < total; i++) {
      ptr[i] = 0;
    }
  }
  
  return ptr;
}

