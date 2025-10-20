// Write to PLIC interrupt controller device
I64 Main() {
  U8 *plic_priority;
  U8 *plic_enable;
  
  // PLIC device registers
  plic_priority = 0x0C000004;  // Interrupt 1 priority register
  plic_enable = 0x0C002080;    // Hart 0 M-mode enable register
  
  // Write to PLIC device
  *plic_priority = 7;  // Set priority
  *plic_enable = 3;    // Enable interrupts 0 and 1
  
  return 0x0C000000;  // Return PLIC base
}
