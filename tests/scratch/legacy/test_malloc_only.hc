U8 *_heap_ptr = 0x80400000;
U8 *_heap_end = 0x88000000;

U8 *malloc(I64 size) {
  size = (size + 7) & ~7;
  
  if (_heap_ptr + size >= _heap_end) {
    return NULL;
  }
  
  U8 *ptr = _heap_ptr;
  _heap_ptr += size;
  
  return ptr;
}

