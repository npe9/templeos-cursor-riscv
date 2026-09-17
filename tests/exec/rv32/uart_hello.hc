// RV32 P0: import-free UART hello — only MMIO stores, no runtime calls.
U0 UartPutS(U8 *s)
{
  U8 *uart = 0x10000000;
  while (*s)
    *uart = *s++;
}

I64 main()
{
  UartPutS("TempleOS/RISC-V rv32 hello\n");
  return 0;
}
