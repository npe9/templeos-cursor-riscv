
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

U8 *realloc(U8 *ptr, I64 new_size) {
  // Simplified realloc - just allocate new memory
  U8 *new_ptr = malloc(new_size);
  
  if (new_ptr && ptr) {
    // Copy old data (we don't track original size, so this is unsafe)
    // For bootstrapping, try to avoid realloc
    for (I64 i = 0; i < new_size; i++) {
      new_ptr[i] = ptr[i];
    }
  }
  
  return new_ptr;
}

// String Functions

I64 strlen(U8 *str) {
  I64 len = 0;
  while (*str++) len++;
  return len;
}

U8 *strcpy(U8 *dst, U8 *src) {
  U8 *ret = dst;
  while ((*dst++ = *src++));
  return ret;
}

I64 strcmp(U8 *s1, U8 *s2) {
  while (*s1 && *s1 == *s2) {
    s1++;
    s2++;
  }
  return *s1 - *s2;
}

U8 *strdup(U8 *str) {
  I64 len = strlen(str);
  U8 *new_str = malloc(len + 1);
  if (new_str) {
    strcpy(new_str, str);
  }
  return new_str;
