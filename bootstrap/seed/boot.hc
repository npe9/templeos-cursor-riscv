// boot.hc -- user-editable tail of boot (primitives already loaded by C BootHolyCRuntime).
// Preferred editor for Src/DirEd/FunEd/Activate is set by RVEditorSelected.hc (Kconfig:
//   make menuconfig → Editors, or CONFIG_EDITOR_VI / _EDIT / _ED). Override live with
//   editor=&Vi;  editor=&EditHoly;  or editor=&EdHoly;
// Help -- Help()
// NAME
//   Help - reprint the UART REPL capability overview
// SYNOPSIS
//   U0 Help();
// DESCRIPTION
//   One-screen map of the REPL: how to eval, open editors, look up Man pages, dig
//   into MemMap/Regs, arm the timer, list files, and soft-reset. Same banner runs
//   at boot — call Help anytime you forget the entry points.
// EXAMPLES
//   Help;
//   Man("Print");
//   Sections;
// SEE ALSO
//   Man  Sections  MemMap  Regs  Dir
// BUGS
//   Banner is hand-maintained; Up/Down history seed lives in C (worry_dream_repl).
U0 Help()
{
  UartStr("TempleOS RISC-V — HolyC REPL\n");
  UartStr("  Eval     >  statements run now; ans= hex (or Print / \"fmt\", args;)\n");
  UartStr("  Editors  Src(\"x.hc\");  Vi: gd/^]=src K=man (:q pops)  editor=&EditHoly;\n");
  UartStr("  Help     Man(\"Clint\"); Man(\"Print\"); Help; Sections;\n");
  UartStr("  Labs     Tutorial;  SF;  Cd(\"Tutorials\"); Run(\"A01_RV64I.hc\");\n");
  UartStr("  Funs     Funs;  type to filter  Enter=Src  Esc=quit  (FunsList; dump)\n");
  UartStr("  Dig-down MemMap; Regs; Reg(\"mstatus\"); CsrExplain(\"mcause\"); Man(\"ABI\");\n");
  UartStr("  Sys      Sys; Uptime; MemRep; IrqRep; DevRep; Cnts;  // /proc-ish\n");
  UartStr("  Tty      Tty; TtyCanon; TtyRaw; TtyEcho(1);  // line discipline\n");
  UartStr("  Term     TermSize(80,24); TermRep; TermQuery; TermHelp;\n");
  UartStr("  VT       Vt(1); VtAttach(1); VtList; VtPutStr(\"note\");  // soft mux\n");
  UartStr("  Debug    Bp(&F); Bt; Watch(&x); Step; HwTrigProbe; DbgHelp; HwHelp;\n");
  UartStr("  Crash    Fault → crash> md/mw/regs/bt/go; CrashHelp; Man(\"CrashMon\");\n");
  UartStr("  Log      LogInfo(\"boot\",\"msg\"); DMesg; LogClear;  // ring ≠ Print\n");
  UartStr("  Asm      asm { li a7,4 addi a7,a7,-1 }; AsmDoc(\"addi\"); AsmList();\n");
  UartStr("  Timer    Man(\"Clint\");  // SetTrap → TrapInit → TimerArm → wfi\n");
  UartStr("  Files    Dir; ZmodemSend(\"boot.hc\"); FsChanges; DumpChanges;\n");
  UartStr("  Keys     Up/Down=history  Tab  ^U=kill  ^W=werase  BS/DEL  Ctrl-C\n");
  UartStr("  Soft     SafeMode; Recover; Reset; Halt;  Man(\"SafeMode\");\n");
  UartStr("  QEMU     Quit; Exit; Fail; HardReset;  // SiFive test @ MEM_TEST\n");
}
LogInfo("boot", "HolyC primitives loaded");
UartStr("[boot] HolyC primitives loaded. Dir; to list, Run/Edit to change them live.\n");
Help();
Sys;
Tty;
Run("tutorial.hc");
FsEpochSeal(FS_EPOCH_BOOT);
