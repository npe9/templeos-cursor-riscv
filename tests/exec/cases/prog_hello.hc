// A standalone HolyC program compiled to a position-independent blob, stored on the RedSea disk, and
// loaded + run at runtime by kernel_load_demo.hc (FileRead + RVRunBlob). It may use only runtime
// intrinsics (Print etc.) — RVRunBlob resolves a loaded blob's imports against the runtime table,
// not the kernel's own functions. main() must be first (the blob's entry is byte 0).
I64 fib(I64 n)
{
  if (n < 2)
    return n;
  return fib(n - 1) + fib(n - 2);
}

I64 main()
{
  Print("Hello from a program loaded off the RedSea disk!\n");
  Print("  (relocated, imports resolved at load time; computing fib(10)...)\n");
  return fib(10);
  // 55 = 0x37
}
