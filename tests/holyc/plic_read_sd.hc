I64 Main() {
  U32 *addr;
  U32 val;
  
  addr = 0x0C000004;
  val = *addr;
  
  return val;
}
