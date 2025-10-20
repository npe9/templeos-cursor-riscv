// Worry Dream Machine - Final Device Proof
// Write to UART TX register multiple times

I64 Main() {
  U8 *uart_tx;
  U8 *uart_lsr;
  
  uart_tx = 0x10000000;
  uart_lsr = 0x10000005;
  
  // Write message
  *uart_tx = 68;   // 'D'
  *uart_tx = 69;   // 'E'
  *uart_tx = 86;   // 'V'
  *uart_tx = 73;   // 'I'
  *uart_tx = 67;   // 'C'
  *uart_tx = 69;   // 'E'
  *uart_tx = 32;   // ' '
  *uart_tx = 87;   // 'W'
  *uart_tx = 82;   // 'R'
  *uart_tx = 73;   // 'I'
  *uart_tx = 84;   // 'T'
  *uart_tx = 69;   // 'E'
  *uart_tx = 10;   // '\n'
  
  return 42;
}
