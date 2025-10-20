// Simple device read test
I64 Main() {
  U32 *addr;
  U32 val;
  
  addr = 0x0C000004;  // PLIC priority register
  val = *addr;        // Read from device
  
  return val;
}


