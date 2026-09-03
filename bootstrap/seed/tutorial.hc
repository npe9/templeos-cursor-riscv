// tutorial.hc -- Software Foundations-style curriculum entry (Tutorial / SF).
// Lessons live in /Tutorials as A## / B## / C## .hc — Run("B02_DataRep.hc"); still works
// (unique-basename fallback). Cd("Tutorials"); Dir; to browse.
// Books: CSAPP 3e (Bryant & O'Hallaron); Beck System Software 3e.
// Loaded at boot via Run("tutorial.hc") from boot.hc (not in boot blob concat).
// Tutorial -- Tutorial()
// NAME
//   Tutorial - print SF-style curriculum map (Part A/B/C)
// SYNOPSIS
//   U0 Tutorial();
// DESCRIPTION
//   Lists executable HolyC labs aligned to RISC-V ISA drills, CSAPP 3e chapters,
//   and Beck 3e chapters. Each lesson is a .hc file: Run it, read demos, fill
//   TODO/Fill_in exercises (Ex1..ExN), Run again until PASS. Alias: SF;
// EXAMPLES
//   Tutorial;
//   SF;
//   Run("A01_RV64I.hc");
//   Run("B02_DataRep.hc");
// SEE ALSO
//   Help  Man  Dir  Run
// BUGS
//   Lesson files are memfs seeds (seed/tutorials/); rebuild: make repl-blob.
U0 Tutorial()
{
  UartStr("Tutorials (Software Foundations style - code is the lesson)\n");
  UartStr("  Run(\"NAME.hc\");  or  Cd(\"Tutorials\"); Dir;  then Run the lesson.\n");
  UartStr("  Demos print PASS; unfinished exercises print FAIL until filled.\n");
  UartStr("Part A - RISC-V ISA (prereq)  ~7-8 Ex each\n");
  UartStr("  A01_RV64I  A02_RegsABI  A03_LoadStore  A04_Branches\n");
  UartStr("  A05_CSRTraps  A06_AsmHolyC  A07_MemMapMan  A08_REPLDrills\n");
  UartStr("Part B - CSAPP 3e (+ B13 thread lib, B14 multicore / Herlihy&Shavit)\n");
  UartStr("  B01_Tour .. B12_Concurrent;  B13_ThreadLib;  B14_ArtOfMulticore\n");
  UartStr("Part C - Beck 3e System Software  8 Ex each\n");
  UartStr("  C01_Background .. C08_SoftwareEngineering\n");
  UartStr("Start: Cd(\"Tutorials\"); Run(\"A01_RV64I.hc\");   Index: docs/tutorials/README.md\n");
}

U0 SF()
{
  Tutorial();
}
