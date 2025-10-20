// Cicl - PLIC Read & Write Test
I64 Main() {
  U32 *plic;
  U32 val;
  U8 *uart;
  
  plic = 0x0C000004;
  uart = 0x10000000;
  
  // Write to PLIC
  *plic = 42;
  
  // Read back
  val = *plic;
  
  // Print result
  *uart = 'P';
  *uart = 'L';
  *uart = 'I';
  *uart = 'C';
  *uart = '=';
  *uart = '0';
  *uart = 'x';
  
  // Print hex
  U8 h;
  h = (val >> 4) & 0xF;
  if (h < 10) {
    *uart = '0' + h;
  } else {
    *uart = 'A' + (h - 10);
  }
  
  U8 l;
  l = val & 0xF;
  if (l < 10) {
    *uart = '0' + l;
  } else {
    *uart = 'A' + (l - 10);
  }
  
  *uart = '\n';
  
  return val;
}
