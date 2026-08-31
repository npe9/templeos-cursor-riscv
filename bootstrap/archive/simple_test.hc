// Super simple test - just write to UART directly

U0 Main() {
  // Write "OK" to UART
  *(U8*)0x10000000 = 'O';
  *(U8*)0x10000000 = 'K';
  *(U8*)0x10000000 = '\n';
  
  // Halt
  while (TRUE);
}


