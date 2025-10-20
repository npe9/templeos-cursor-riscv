I64 Main() {
  U32 *ptr;
  U32 val;
  
  ptr = 0x80500000;  // RAM address
  *ptr = 99;         // Write
  val = *ptr;        // Read back
  
  return val;
}
