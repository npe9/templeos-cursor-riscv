// Worry Dream Machine - PLIC Register Access
// Write to Platform-Level Interrupt Controller

I64 Main() {
  U8 *uart;
  U8 *plic_priority;
  U8 *plic_enable;
  
  uart = 0x10000000;
  
  // PLIC registers (Platform-Level Interrupt Controller)
  plic_priority = 0x0C000004;   // Interrupt 1 priority
  plic_enable = 0x0C002000;     // Interrupt enable for context 0
  
  // Write to PLIC priority register
  *plic_priority = 7;  // Set priority to 7
  
  // Write to PLIC enable register  
  *plic_enable = 1;    // Enable interrupt 1
  
  // Report via UART
  *uart = 80;  // 'P'
  *uart = 76;  // 'L'
  *uart = 73;  // 'I'
  *uart = 67;  // 'C'
  *uart = 32;  // ' '
  *uart = 87;  // 'W'
  *uart = 82;  // 'R'
  *uart = 73;  // 'I'
  *uart = 84;  // 'T'
  *uart = 69;  // 'E'
  *uart = 58;  // ':'
  *uart = 32;  // ' '
  *uart = 79;  // 'O'
  *uart = 75;  // 'K'
  *uart = 10;  // '\n'
  
  return 42;
}
