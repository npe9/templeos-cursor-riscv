I64 Main() {
  U32 *plic_ptr;
  U32 value;
  
  plic_ptr = 0x0C000004;
  value = *plic_ptr;
  
  return value;
}
