// Cicl - Read Device Registers
I64 Main() {
  U8 *plic_base;
  U32 *plic_priority;
  U32 *plic_enable;
  U32 val1;
  U32 val2;
  
  // PLIC addresses
  plic_base = 0x0C000000;
  plic_priority = 0x0C000004;  // Interrupt 1 priority
  plic_enable = 0x0C002080;    // Enable register
  
  // Read PLIC registers
  val1 = *plic_priority;
  val2 = *plic_enable;
  
  // Print to UART
  U8 *uart;
  uart = 0x10000000;
  
  *uart = 'P';
  *uart = 'L';
  *uart = 'I';
  *uart = 'C';
  *uart = ':';
  *uart = ' ';
  *uart = '0';
  *uart = 'x';
  
  // Print val1 (priority register)
  U8 digit;
  digit = (val1 >> 4) & 0xF;
  if (digit < 10) {
    *uart = '0' + digit;
  } else {
    *uart = 'A' + digit - 10;
  }
  digit = val1 & 0xF;
  if (digit < 10) {
    *uart = '0' + digit;
  } else {
    *uart = 'A' + digit - 10;
  }
  
  *uart = ' ';
  *uart = '0';
  *uart = 'x';
  
  // Print val2 (enable register)
  digit = (val2 >> 4) & 0xF;
  if (digit < 10) {
    *uart = '0' + digit;
  } else {
    *uart = 'A' + digit - 10;
  }
  digit = val2 & 0xF;
  if (digit < 10) {
    *uart = '0' + digit;
  } else {
    *uart = 'A' + digit - 10;
  }
  
  *uart = '\n';
  
  return val1;
}


