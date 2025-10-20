// Worry Dream Machine - Proof of Concept
// Write directly to UART device register

I64 Main() {
  U8 *uart;
  
  // UART base address
  uart = 0x10000000;
  
  // Write "WORRY DREAM MACHINE" to UART
  *uart = 87;   // 'W'
  *uart = 79;   // 'O'
  *uart = 82;   // 'R'
  *uart = 82;   // 'R'
  *uart = 89;   // 'Y'
  *uart = 32;   // ' '
  *uart = 68;   // 'D'
  *uart = 82;   // 'R'
  *uart = 69;   // 'E'
  *uart = 65;   // 'A'
  *uart = 77;   // 'M'
  *uart = 32;   // ' '
  *uart = 77;   // 'M'
  *uart = 65;   // 'A'
  *uart = 67;   // 'C'
  *uart = 72;   // 'H'
  *uart = 73;   // 'I'
  *uart = 78;   // 'N'
  *uart = 69;   // 'E'
  *uart = 10;   // '\n'
  
  return 42;
}
