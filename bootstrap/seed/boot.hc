// boot.hc -- user-editable tail of boot (primitives already loaded by C BootHolyCRuntime).
// Preferred editor for Src/DirEd/FunEd/Activate is set by RVEditorSelected.hc (Kconfig:
//   make menuconfig-rv → Editors, or CONFIG_EDITOR_VI / _EDIT / _ED). Override live with
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
  UartStr("  Labs     Tutorial;  SF;  Run(\"A01_RV64I.hc\");  (SF-style curriculum)\n");
  UartStr("  Funs     Funs;  type to filter  Enter=Src  Esc=quit  (FunsList; dump)\n");
  UartStr("  Dig-down MemMap; Regs; Reg(\"a7\"); Bits(\"mstatus\"); RegHelp;\n");
  UartStr("  Asm      asm { li a7,4 addi a7,a7,-1 }; AsmDoc(\"addi\"); AsmList();\n");
  UartStr("  Timer    Man(\"Clint\");  // SetTrap → TrapInit → TimerArm → wfi\n");
  UartStr("  Files    Dir; Cat(\"boot.hc\"); DumpFile(\"boot.hc\"); Fmt(\"file.hc\");\n");
  UartStr("  Keys     Up/Down=history  Tab=complete (CI)  Ctrl-C=interrupt\n");
  UartStr("  Soft     Reset;   HardReset; Halt; Fault;  Man(\"Reset\");\n");
}
UartStr("[boot] HolyC primitives loaded. Dir; to list, Run/Edit to change them live.\n");
Run("tutorial.hc");
Help();
