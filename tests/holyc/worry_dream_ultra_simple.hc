// Worry Dream Machine - Ultra Simple Device Write
// ONE write to RAM, return address

I64 Main() {
  U8 *device;
  
  device = 0x80FF0000;
  *device = 0xAB;
  
  return 0x80FF0000;
}
