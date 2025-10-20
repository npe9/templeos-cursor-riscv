// Test 4: Loop (factorial)

I64 factorial(I64 n) {
  I64 result = 1;
  I64 i = 1;
  
  while (i <= n) {
    result = result * i;
    i = i + 1;
  }
  
  return result;
}

I64 main() {
  return factorial(5);  // Should return 120
}


