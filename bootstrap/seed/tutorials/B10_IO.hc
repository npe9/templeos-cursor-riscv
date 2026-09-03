// B10_IO.hc -- CSAPP 3e Ch.10: System-Level I/O
// Remap: UART + memfs FileRead/FileWrite/Dir/Cat -- not POSIX read/write.
//
// HOW TO WORK THIS LAB
//   Run("B10_IO.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Unix I/O, RIO, metadata, sharing. Here the console is NS16550A @ MEM_UART
//   (PutS/Print/UartStr) and files are the in-RAM memfs (fs.hc). Drivers are
//   HolyC -- Man("UART"); Src("UartPut");.
//
// NEXT
//   B11_Network -- VirtioNet hook + honest socket gap.
U0 B10_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 B10_Demo()
{
  Print("B10: UART console + memfs files\n");
  Print("UartStr/Print -> THR @ MEM_UART; Dir/Cat/FileWrite -> fs.hc\n");
  UartStr("[B10] hello via UartStr\n");
  PutS("[B10] hello via PutS\n");
  B10_Expect("B10_uart", MemMapFind("uart"), MEM_UART);
  B10_Expect("B10_fs", MemMapFind("fs"), MEM_FS);
}
// Ex1 Warmup: UART base.
I64 B10_Ex1_Uart()
{
  // TODO Fill_in: return MemMapFind("uart");
  return 0;
}
// Ex2: FS base.
I64 B10_Ex2_Fs()
{
  // TODO Fill_in: return MemMapFind("fs");
  return 0;
}
// Ex3: StrLen of an I/O greeting.
I64 B10_Ex3_Len()
{
  // TODO Fill_in: return StrLen("hello");
  return 0;
}
// Ex4: LSR THRE bit value used by driver (UART_LSR_THRE).
I64 B10_Ex4_Thre()
{
  // TODO Fill_in: return UART_LSR_THRE;
  return -1;
}
// Ex5: LSR offset from UART base.
I64 B10_Ex5_LsrOff()
{
  // TODO Fill_in: return UART_LSR_OFF;
  return -1;
}
// Ex6: PutS linked.
I64 B10_Ex6_PutS()
{
  // TODO Fill_in: if (FnAddr("PutS")) return 1; return 0;
  return 0;
}
// Ex7 Challenge: FileWrite/FileRead roundtrip via memfs.
// Write "B10\n" to a scratch name, read length back. Returns bytes written
// style: we check FileWrite return / StrLen path.
I64 B10_Ex7_FileRoundtrip()
{
  U8 *s;
  I64 n;
  // TODO Fill_in:
  //   n = FileWrite("B10_note.txt", "B10\n", 4);
  //   s = FileRead("B10_note.txt");
  //   if (s && StrLen(s) >= 3) return 1;
  //   return 0;
  return 0;
}
// Ex8 Challenge: Dir linked.
I64 B10_Ex8_Dir()
{
  // TODO Fill_in: if (FnAddr("Dir")) return 1; return 0;
  return 0;
}

U0 B10_Check()
{
  Print("-- B10 exercises --\n");
  B10_Expect("Ex1_Uart", B10_Ex1_Uart(), MEM_UART);
  B10_Expect("Ex2_Fs", B10_Ex2_Fs(), MEM_FS);
  B10_Expect("Ex3_Len", B10_Ex3_Len(), 5);
  B10_Expect("Ex4_Thre", B10_Ex4_Thre(), UART_LSR_THRE);
  B10_Expect("Ex5_LsrOff", B10_Ex5_LsrOff(), UART_LSR_OFF);
  B10_Expect("Ex6_PutS", B10_Ex6_PutS(), 1);
  B10_Expect("Ex7_FileRoundtrip", B10_Ex7_FileRoundtrip(), 1);
  B10_Expect("Ex8_Dir", B10_Ex8_Dir(), 1);
}

U0 B10()
{
  Print("=== B10 CSAPP Ch.10 System-level I/O ===\n");
  B10_Demo();
  B10_Check();
  Print("Try: FileWrite/Cat/Del interactively if Ex7 pending.\n");
  Print("Next: Run(\"B11_Network.hc\");\n");
}
B10;
