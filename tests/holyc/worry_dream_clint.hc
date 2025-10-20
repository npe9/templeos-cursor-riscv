// Worry Dream Machine - CLINT Timer Register Access
// Read and write device registers (NOT UART)

I64 Main() {
  U8 *uart;
  U8 *clint_mtime;
  U8 *clint_mtimecmp;
  I64 time1;
  I64 time2;
  
  uart = 0x10000000;
  
  // CLINT registers (Core Local Interruptor - Timer)
  clint_mtime = 0x200BFF8;      // MTIME register (current time)
  clint_mtimecmp = 0x2004000;   // MTIMECMP register (compare value)
  
  // Read MTIME register (64-bit read)
  time1 = *clint_mtime;
  
  // Write to MTIMECMP register
  *clint_mtimecmp = 999999;
  
  // Read MTIME again
  time2 = *clint_mtime;
  
  // Write results to UART for visibility
  *uart = 82;  // 'R'
  *uart = 69;  // 'E'
  *uart = 65;  // 'A'
  *uart = 68;  // 'D'
  *uart = 58;  // ':'
  *uart = 32;  // ' '
  
  // Print first digit of time1 (will be small)
  *uart = 48 + ((time1 / 10) % 10);
  *uart = 48 + (time1 % 10);
  
  *uart = 10;  // '\n'
  
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
  
  // Return time difference as proof
  return time2 - time1;
}
