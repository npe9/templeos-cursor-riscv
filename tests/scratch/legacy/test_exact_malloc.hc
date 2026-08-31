U8 *_heap_ptr = 0x80400000;
U8 *_heap_end = 0x88000000;

U0 uart_puts(U8 *str) {
  // Stub
}

U8 *malloc(I64 size) {
  size = (size + 7) & ~7;
  
  if (_heap_ptr + size >= _heap_end) {
    uart_puts("ERROR: Out of memory!\n");
    return 0;
  }
  
  U8 *ptr = _heap_ptr;
  _heap_ptr += size;
  
  return ptr;
}

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

