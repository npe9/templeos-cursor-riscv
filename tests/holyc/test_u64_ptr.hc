I64 Main() {
  U64 *addr;
  U64 val;
  
  addr = 0x0C000004;
  val = *addr;
  
  return val;
}
