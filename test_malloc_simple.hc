U8 *_heap_ptr = 0x80400000;

U8 *malloc(I64 size) {
  U8 *ptr = _heap_ptr;
  _heap_ptr += size;
  return ptr;
}

