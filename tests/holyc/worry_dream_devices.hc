// Worry Dream Machine - Multiple Device Access
// Prove HolyC can access different memory-mapped devices

I64 Main() {
  U8 *uart_tx;
  U8 *uart_lsr;
  I64 status;
  
  // UART registers (different addresses)
  uart_tx = 0x10000000;   // Transmit holding register
  uart_lsr = 0x10000005;  // Line status register
  
  // READ from UART line status register
  status = *uart_lsr;
  
  // WRITE to UART TX register
  *uart_tx = 68;  // 'D'
  *uart_tx = 69;  // 'E'
  *uart_tx = 86;  // 'V'
  *uart_tx = 73;  // 'I'
  *uart_tx = 67;  // 'C'
  *uart_tx = 69;  // 'E'
  *uart_tx = 32;  // ' '
  *uart_tx = 82;  // 'R'
  *uart_tx = 69;  // 'E'
  *uart_tx = 65;  // 'A'
  *uart_tx = 68;  // 'D'
  *uart_tx = 58;  // ':'
  *uart_tx = 32;  // ' '
  
  // Print status value (should be non-zero)
  *uart_tx = 48 + ((status / 16) % 10);
  *uart_tx = 48 + (status % 10);
  
  *uart_tx = 10;  // '\n'
  
  // Return status to prove read worked
  return status;
}
