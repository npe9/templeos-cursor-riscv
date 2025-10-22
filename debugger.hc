// RISC-V Debugger - Ported from TempleOS KDbg.HC
// Debugging functions for the REPL

I64 DbgMode = 0;  // Debug mode flag

U0 DbgHelp() {
  "\n"
  "RISC-V Debugger Commands:\n\n"
  ">D(0x100000);\t\t\t//Dump memory\n"
  ">Dm(0x100000);\t\t\t//Dump memory with addresses\n"
  ">U(&FuncName+0x8);\t\t//Disassemble function\n"
  ">Uf(\"FuncName\");\t\t//Disassemble function by name\n"
  ">Dr();\t\t\t\t//Dump registers\n"
  ">DbgMode=1;\t\t\t//Enable debug mode\n"
  ">DbgMode=0;\t\t\t//Disable debug mode\n\n";
}

U0 D(U8 *addr, I64 cnt = 0x80, Bool show_offset = TRUE) {
  // Dump memory in hex format
  I64 i, j;
  U8 *ptr = addr;
  while (cnt > 0) {
    if (show_offset)
      "%08X ", ptr - addr;
    else
      "%016X ", ptr;
    if (cnt > 16)
      j = 16;
    else
      j = cnt;
    for (i = 0; i < j; i++)
      "%02X ", ptr[i];
    for (; i < 16; i++)
      "   ";
    for (i = 0; i < j; i++) {
      I64 ch = ptr[i];
      if (ch < 32 || ch == 127)
        ch = '.';
      '' ch;
    }
    '\n';
    cnt -= j;
    ptr += j;
  }
}

U0 Dm(U8 *addr, I64 cnt = 0x80) {
  // Dump memory with addresses
  D(addr, cnt, FALSE);
}

U0 Da(U8 **addr, I64 cnt = 0x10) {
  // Dump memory, showing symbolic addresses
  while (cnt-- > 0) {
    "%08X:%08X,%P\n", addr, *addr, *addr;
    addr++;
  }
}

U0 Dr() {
  // Dump registers (simplified for RISC-V)
  "Registers:\n";
  "  a0: 0x%016X\n", 0; // Would need to get from context
  "  a1: 0x%016X\n", 0;
  "  sp: 0x%016X\n", 0;
  "  ra: 0x%016X\n", 0;
}

U0 RawPrint(I64 mS = 100, U8 *fmt, ...) {
  // Print using raw screen output
  U8 *buf = StrPrintJoin(NULL, fmt, argc, argv);
  "%s", buf;
  Free(buf);
}

U0 RawD(I64 mS = 100, U8 *addr, I64 cnt = 0x80) {
  // Dump memory using raw output
  D(addr, cnt);
}

U0 RawDm(I64 mS = 100, U8 *addr, I64 cnt = 0x80) {
  // Dump memory with addresses using raw output
  Dm(addr, cnt);
}

// Simple disassembler for RISC-V
U0 U(U8 *rip, I64 cnt = 20) {
  // Disassemble RISC-V instructions
  I64 i;
  U8 buf[1024];
  for (i = 0; i < cnt; i++) {
    // Simple disassembly - would need full RISC-V decoder
    "%016X: %08X\n", rip, *(U32*)rip;
    rip += 4;
  }
}

U0 Uf(U8 *st) {
  // Disassemble function by name
  CHashFun *tmpf = HashFind(st, Fs->hash_table, HTT_FUN);
  if (tmpf) {
    "Function: %s\n", st;
    "Address: %016X\n", tmpf->exe_addr;
    "Size: %d bytes\n", tmpf->size;
    U(tmpf->exe_addr, 20);
  } else {
    "Function not found: %s\n", st;
  }
}

U0 Dbg(U8 *msg = NULL, I64 msg_num = 0) {
  // Enter debugger
  "Debugger entered\n";
  if (msg)
    "Message: %s\n", msg;
  "MsgNum: %d\n", msg_num;
  DbgHelp();
}

U0 Panic(U8 *msg = NULL, I64 msg_num = 0, Bool panic = TRUE) {
  // Panic handler
  "PANIC: %s\n", msg ? msg : "Unknown error";
  "MsgNum: %d\n", msg_num;
  Dbg();
}

// Debug function calls
U0 DebugFunctionCall(U8 *func_name, U8 *code_addr, I64 code_size) {
  "=== Function Call Debug: %s ===\n", func_name;
  "Code Address: %016X\n", code_addr;
  "Code Size: %d bytes\n", code_size;
  "Disassembly:\n";
  U(code_addr, code_size / 4);
  "Memory Dump:\n";
  Dm(code_addr, code_size);
  "=== End Debug ===\n";
}

// Debug parameter passing
U0 DebugParameters(I64 arg_count, U8 *stack_addr) {
  "=== Parameter Debug ===\n";
  "Argument Count: %d\n", arg_count;
  "Stack Address: %016X\n", stack_addr;
  "Stack Contents:\n";
  Dm(stack_addr, arg_count * 8);
  "=== End Parameter Debug ===\n";
}
