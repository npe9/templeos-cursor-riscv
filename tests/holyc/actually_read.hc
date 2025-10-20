I64 Main() {
  U8 *plic;
  U8 val;
  
  plic = 0x0C000004;
  val = *plic;  
  
  return val;
}
