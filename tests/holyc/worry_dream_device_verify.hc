// Worry Dream Machine - Memory-Mapped Device Access
// Write to PLIC interrupt controller registers

I64 Main() {
  U8 *plic_priority_1;
  U8 *plic_priority_2;
  U8 *plic_enable;
  U8 *result_buffer;
  
  // PLIC device registers (interrupt controller)
  plic_priority_1 = 0x0C000004;  // Interrupt 1 priority
  plic_priority_2 = 0x0C000008;  // Interrupt 2 priority
  plic_enable = 0x0C002000;      // Interrupt enable bitmap
  
  // Write signature to PLIC registers
  *plic_priority_1 = 0x42;  // Write 0x42 to priority register 1
  *plic_priority_2 = 0x99;  // Write 0x99 to priority register 2
  *plic_enable = 0x03;      // Write 0x03 to enable register
  
  // Store proof in RAM for C to verify
  result_buffer = 0x80FF0000;
  *result_buffer = 0x42;  // Copy what we wrote
  result_buffer = result_buffer + 1;
  *result_buffer = 0x99;
  result_buffer = result_buffer + 1;
  *result_buffer = 0x03;
  
  // Return PLIC base address
  return 0x0C000000;
}
