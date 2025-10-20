// Demo application using TempleOS runtime

// Runtime functions (will be provided)
U0 Print(U8 *str);
I64 StrLen(U8 *str);
I64 Abs(I64 x);
I64 Max(I64 a, I64 b);

U0 Demo() {
  Print("Demo function called!\n");
  Print("Testing runtime functions...\n");
}

I64 Main() {
  Print("TempleOS Runtime on RISC-V\n");
  Print("==========================\n");
  
  Demo();
  
  Print("\nTesting math: Max(Abs(-42), 10)\n");
  
  return Max(Abs(-42), 10);  // Should return 42
}
