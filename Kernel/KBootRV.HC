// RISC-V kernel boot initialisation: the portable part of what the x86 KMain()/SysGlblsInit() do,
// with the hardware/x86 pieces (CPUId, IDE, interrupt tables, MP) left to phase 2. Populates the
// runtime tables the kernel's own code needs and wires a UART console so a program that #includes
// the kernel gets a working environment on the QEMU `virt` machine. Included last in Kernel_RV.PRJ
// so every global and function it touches is already defined.

// The QEMU virt 16550 UART is at 0x10000000; the kernel's PutS/Print reach it through this sink.
Bool RVUartPutS(U8 *st)
{
  U8 *uart=0x10000000;
  while (*st)
    *uart=*st++;
  return TRUE;
}

U0 RVKernelInit()
{//Bring up the portable kernel environment on RISC-V (QEMU virt). Call once before using the kernel.
  I64 i,j;

  // Base-10 power table: %f float formatting (StrPrint) and Str2F64 index it.
  pow10_I64=CAlloc(sizeof(F64)*(308+308+1));
  for (i=-308;i<=308;i++)
    pow10_I64[i+309]=Pow10(ToF64(i));

  // Bit-reversal and pop-count tables (verbatim from SysGlblsInit).
  rev_bits_table=CAlloc(256);
  set_bits_table=CAlloc(256);
  for (i=0;i<256;i++)
    for (j=0;j<8;j++) {
      if (Bt(&i,7-j))	LBts(rev_bits_table+i,j);
      if (Bt(&i,j))	set_bits_table[i]++;
    }

  // Native console: register a UART sink in the StdOut (keyboard-device) chain so the kernel's own
  // PutS()/Print() dispatch to the UART. (KeyDevInit's x86 input filters are phase 2.)
  MemSet(&keydev.put_key_head,0,sizeof(CKeyDevEntry));
  QueInit(&keydev.put_key_head);
  KeyDevAdd(NULL,&RVUartPutS,0x10000000,FALSE);
  Fs->display_flags=0;
  kbd.scan_code=0;
}

// --- UART input (QEMU virt 16550) --------------------------------------------------------------
// The kernel's own GetKey() blocks via the scheduler (phase 2). Until that exists, these polling
// helpers give a program interactive input over the same UART the console writes to.
#define RV_UART_BASE  0x10000000
#define RV_UART_LSR   0x10000005   // line status register; bit0 = data ready

Bool RVUartDataReady()
{
  U8 *lsr=RV_UART_LSR;
  return (*lsr & 1) != 0;
}

I64 RVUartGetC()
{//Block (poll) until a byte arrives on the UART, then return it.
  U8 *rbr=RV_UART_BASE;
  while (!RVUartDataReady())
    ;
  return *rbr;
}

I64 RVUartGetLine(U8 *buf,I64 max)
{//Read a line into buf (up to max-1 chars), echoing as we go. Returns the length. Stops on \n or \r.
  I64 n=0,ch;
  while (n<max-1) {
    ch=RVUartGetC;
    if (ch=='\r' || ch=='\n') {
      RVUartPutS("\n");
      break;
    }
    if (ch==8 || ch==127) {          // backspace / delete
      if (n>0) { n--; RVUartPutS("\b \b"); }
      continue;
    }
    buf[n++]=ch;
    U8 e[2]; e[0]=ch; e[1]=0; RVUartPutS(e);   // echo
  }
  buf[n]=0;
  return n;
}
