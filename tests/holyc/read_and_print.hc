// Cicl - Read PLIC and print to UART
I64 Main() {
  U32 *plic_addr;
  U32 plic_val;
  U8 *uart;
  
  // Read from PLIC
  plic_addr = 0x0C000004;
  plic_val = *plic_addr;
  
  // Print to UART
  uart = 0x10000000;
  
  *uart = 'P';
  *uart = 'L';
  *uart = 'I';
  *uart = 'C';
  *uart = '=';
  *uart = '0';
  *uart = 'x';
  
  // Print hex value
  U8 nibble;
  nibble = (plic_val >> 4) & 0xF;
  if (nibble < 10) {
    *uart = '0' + nibble;
  } else {
    *uart = 'A' + (nibble - 10);
  }
  
  nibble = plic_val & 0xF;
  if (nibble < 10) {
    *uart = '0' + nibble;
  } else {
    *uart = 'A' + (nibble - 10);
  }
  
  *uart = '\n';
  
  return plic_val;
}
