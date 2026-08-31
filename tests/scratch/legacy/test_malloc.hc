
// Memory Management

U8 *malloc(I64 size) {
  // Align to 8 bytes
  size = (size + 7) & ~7;
  
  if (_heap_ptr + size >= _heap_end) {
    uart_puts("ERROR: Out of memory!\n");
    return NULL;
  }
  
  U8 *ptr = _heap_ptr;
  _heap_ptr += size;
  
  return ptr;
}

U0 free(U8 *ptr) {
  // Simple bump allocator - no-op for free
  // Could implement a free list later
}

U8 *calloc(I64 count, I64 size) {
  I64 total = count * size;
  U8 *ptr = malloc(total);
  
  if (ptr) {
    // Zero memory
    for (I64 i = 0; i < total; i++) {
      ptr[i] = 0;
    }
  }
  
  return ptr;
}
