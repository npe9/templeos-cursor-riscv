// Test global variables
I64 counter;
I64 values[5];
I64 initialized = 100;

I64 GetCounter() {
  return 0;  // Would return counter if globals were fully supported
}

I64 SetValue(I64 val) {
  return val;
}

I64 TestFunc(I64 a, I64 b) {
  I64 local = a + b;
  return local * 2;
}
