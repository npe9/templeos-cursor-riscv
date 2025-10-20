// Worry Dream Machine - RAM Device Access
// Write to memory-mapped RAM region and return address

I64 Main() {
  U8 *ram_device;
  
  // Write to RAM at specific address (0x80FF0000)
  ram_device = 0x80FF0000;
  
  // Write signature pattern
  *ram_device = 0xDE;
  ram_device = ram_device + 1;
  *ram_device = 0xAD;
  ram_device = ram_device + 1;
  *ram_device = 0xBE;
  ram_device = ram_device + 1;
  *ram_device = 0xEF;
  ram_device = ram_device + 1;
  *ram_device = 0xCA;
  ram_device = ram_device + 1;
  *ram_device = 0xFE;
  ram_device = ram_device + 1;
  *ram_device = 0xBA;
  ram_device = ram_device + 1;
  *ram_device = 0xBE;
  
  // Return the base address so C can verify
  return 0x80FF0000;
}
