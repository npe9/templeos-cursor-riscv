// C06_OperatingSystems.hc -- Beck 3e Ch.6: Operating Systems
// Remap: TempleOS Kernel_*RV + drivers; REPL is a thin OS-ish environment.
//
// HOW TO WORK THIS LAB
//   Run("C06_OperatingSystems.hc");  MemMap;  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Processes, memory, I/O, filesystems, protection. Here: KStartRV, Drv
//   (UART, CLINT, PLIC, Virtio*), memfs, traps. Not a full StartOS desktop
//   in the UART REPL -- still an OS-shaped stack.
//
// NEXT
//   C07_OtherSystemSoftware.
U0 C06_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 C06_Demo()
{
  U8 *drv;
  Print("C06: Kernel/ KStartRV + Drv (UART, CLINT, PLIC, Virtio*).\n");
  Print("REPL: memfs, traps, editors -- not full StartOS desktop.\n");
  MemMap;
  drv = MemMapDrvFind("uart");
  Print("uart driver column: %s\n", drv);
  C06_Expect("C06_uart", MemMapFind("uart"), MEM_UART);
  C06_Expect("C06_clint", MemMapFind("clint"), MEM_CLINT);
}
// Ex1 Warmup: uart.
I64 C06_Ex1_Uart()
{
  // TODO Fill_in: return MemMapFind("uart");
  return 0;
}
// Ex2: plic.
I64 C06_Ex2_Plic()
{
  // TODO Fill_in: return MemMapFind("plic");
  return 0;
}
// Ex3: clint.
I64 C06_Ex3_Clint()
{
  // TODO Fill_in: return MemMapFind("clint");
  return 0;
}
// Ex4: fs.
I64 C06_Ex4_Fs()
{
  // TODO Fill_in: return MemMapFind("fs");
  return 0;
}
// Ex5: uart driver non-NULL.
I64 C06_Ex5_Drv()
{
  U8 *d;
  // TODO Fill_in: d = MemMapDrvFind("uart"); if (d) return 1; return 0;
  return 0;
}
// Ex6: Reset linked (soft reboot path).
I64 C06_Ex6_Reset()
{
  // TODO Fill_in: if (FnAddr("Reset")) return 1; return 0;
  return 0;
}
// Ex7 Challenge: services count we named -- uart/timer/irq/fs = 4.
I64 C06_Ex7_Services()
{
  // TODO Fill_in: return 4;
  return 0;
}
// Ex8 Challenge: affirm REPL != full desktop StartOS.
I64 C06_Ex8_NotDesktop()
{
  // TODO Fill_in: return 1;
  return -1;
}

U0 C06_Check()
{
  Print("-- C06 exercises --\n");
  C06_Expect("Ex1_Uart", C06_Ex1_Uart(), MEM_UART);
  C06_Expect("Ex2_Plic", C06_Ex2_Plic(), MEM_PLIC);
  C06_Expect("Ex3_Clint", C06_Ex3_Clint(), MEM_CLINT);
  C06_Expect("Ex4_Fs", C06_Ex4_Fs(), MEM_FS);
  C06_Expect("Ex5_Drv", C06_Ex5_Drv(), 1);
  C06_Expect("Ex6_Reset", C06_Ex6_Reset(), 1);
  C06_Expect("Ex7_Services", C06_Ex7_Services(), 4);
  C06_Expect("Ex8_NotDesktop", C06_Ex8_NotDesktop(), 1);
}

U0 C06()
{
  Print("=== C06 Beck Ch.6 Operating systems ===\n");
  C06_Demo();
  C06_Check();
  Print("Next: Run(\"C07_OtherSystemSoftware.hc\");\n");
}
C06;
