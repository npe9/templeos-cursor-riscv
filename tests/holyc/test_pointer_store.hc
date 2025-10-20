I64 Main() {
  I64 x;
  I64 *ptr;
  
  x = 0;
  ptr = &x;
  *ptr = 42;
  
  return x;  // Should be 42
}
