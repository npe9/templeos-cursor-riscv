// Test arrays of different types
I64 TestArrayI8() {
  I8 bytes[10];
  bytes[0] = 65;
  return bytes[0];
}

I64 TestArrayI64() {
  I64 numbers[5];
  numbers[0] = 100;
  numbers[1] = 200;
  return numbers[0] + numbers[1];
}
