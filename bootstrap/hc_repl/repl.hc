// repl.hc -- Mac-hosted holyc-riscv AOT entry for the HolyC REPL guest.
// Build: make hc-repl → build/hc_repl.elf
// Entry: HolyC asm `_start` in start.hc (no crt0.S).
#include "/bootstrap/hc_repl/start.hc"
#include "/bootstrap/hc_repl/uart.hc"
#include "/bootstrap/seed/mem.hc"
#include "/bootstrap/seed/str.hc"
#include "/bootstrap/seed/print.hc"
#include "/bootstrap/hc_repl/fs.hc"
#include "/bootstrap/hc_repl/dir.hc"
#include "/bootstrap/hc_repl/jit.hc"
#include "/bootstrap/hc_repl/eval.hc"
#include "/bootstrap/hc_repl/seed_embed.hc"
U8 repl_buf[512];
U0 ReplReadLine()
{
  I64 n = 0, ch;
  while (n < 511) {
    ch = UartGet();
    if (ch == '\r')
      continue;
    if (ch == '\n')
      break;
    if (ch == 8 || ch == 127) {
      if (n > 0) {
        n--;
        UartStr("\b \b");
      }
      continue;
    }
    if (ch >= 32 && ch < 127) {
      repl_buf[n] = ch;
      n++;
      PutCh(ch);
    }
  }
  repl_buf[n] = 0;
  PutCh('\n');
}

U0 ReplLoop()
{
  while (1) {
    UartStr("> ");
    ReplReadLine();
    ReplEvalLine(repl_buf);
  }
}

I64 main()
{
  FsInit();
  MemfsSeed();
  JitInit();
  UartStr("\n");
  Help();
  UartStr("Try: Dir;  I64 F(){return 1;} F();\n\n");
  ReplLoop();
  return 0;
}
