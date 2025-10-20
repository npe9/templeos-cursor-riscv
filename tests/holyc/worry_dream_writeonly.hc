// Worry Dream Machine - Write-Only Device Test
// NO READS - only writes to prove device access

I64 Main() {
  U8 *dev1;
  U8 *dev2;
  U8 *dev3;
  
  // Three different device registers
  dev1 = 0x10000000;  // UART TX
  dev2 = 0x10000001;  // UART IER
  dev3 = 0x10000002;  // UART FCR
  
  // Write to all three devices
  *dev1 = 77;  // 'M' to TX
  *dev2 = 0;   // 0 to IER
  *dev1 = 85;  // 'U' to TX
  *dev3 = 1;   // 1 to FCR
  *dev1 = 76;  // 'L' to TX
  *dev1 = 84;  // 'T' to TX
  *dev1 = 73;  // 'I' to TX
  *dev2 = 7;   // 7 to IER
  *dev1 = 45;  // '-' to TX
  *dev1 = 68;  // 'D' to TX
  *dev1 = 69;  // 'E' to TX
  *dev1 = 86;  // 'V' to TX
  *dev3 = 3;   // 3 to FCR
  *dev1 = 73;  // 'I' to TX
  *dev1 = 67;  // 'C' to TX
  *dev1 = 69;  // 'E' to TX
  *dev1 = 10;  // '\n' to TX
  
  return 42;
}
