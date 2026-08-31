// An interactive shell on RISC-V on a REAL persistent virtio-blk disk, driven by the kernel's OWN code: it reads command lines
// over the UART (RVUartGetLine), runs as a real CTask that Adam's Spawn() created and the kernel
// schedules, and stores/reads files and directories through the kernel's own RedSea filesystem on a
// RAM disk (DirMk / FilesFind / Cd / FileWrite / FileRead — Kernel/BlkDev/*.HC, no device driver).
// Commands: dir | mkdir <d> | cd <d> | write <f> <text> | cat <f> | run <f> | exit. `run` loads a
// program blob off the disk and executes it (FileRead + RVRunBlob) — a precompiled program
// (prog_hello.hc) is staged at A:/HELLO.PRG at startup. This ties the whole authentic stack together
// — boot, scheduler, filesystem, and running a program from disk — into a TempleOS-like prompt, and
// it depends on every compiler fix this port needed (array-deref store, implicit-print varargs, and
// the U0 zero-size-marker layout). Distinct from kernel_shell_demo.hc, the Phase-1 parallel-runtime
// shell over virtio-blk + a hand-rolled FS.
#include "/Kernel/Kernel_RV.PRJ"
#include "/build/exec/prog_arr.hc"   // generated at test time: prog_blob[], prog_blob_size (prog_hello.hc)
#define MEM_UART 0x10000000
U0 Sh(U8 *s)
{
  U8 *u = MEM_UART;
  while (*s)
    *u = *s++;
}
// Return the index of the first space in s, or -1.
I64 SpaceAt(U8 *s)
{
  I64 i = 0;
  while (s[i]) {
    if (s[i] == ' ')
      return i;
    i++;
  }
  return -1;
}

U0 ShellTask()
{
  U8 line[160];
  Sh("TempleOS/RISC-V shell on a REAL virtio disk. Commands: dir mkdir cd write cat run exit\n");
  while (TRUE) {
    Sh(Fs->cur_dir);
    Sh("> ");
    RVUartGetLine(line, 160);
    if (!*line)
      continue;
    if (!StrCmp(line, "exit")) {
      Sh("bye\n");
      break;
    } else if (!StrCmp(line, "dir")) {
      CDirEntry *de = FilesFind("*"), *e = de;
      I64 n = 0;
      while (e) {
        Sh("  ");
        Sh(e->name);
        Sh("\n");
        n++;
        e = e->next;
      }
      U8 nb[32];
      StrPrint(nb, "  (%d entries)\n", n);
      Sh(nb);
    } else if (!StrNCmp(line, "mkdir ", 6)) {
      if (DirMk(line + 6))
        Sh("made dir\n");
      else
        Sh("mkdir failed\n");
    } else if (!StrNCmp(line, "cd ", 3)) {
      if (Cd(line + 3)) {
        Sh("now in ");
        Sh(Fs->cur_dir);
        Sh("\n");
      } else
        Sh("cd failed\n");
    } else if (!StrNCmp(line, "cat ", 4)) {
      I64 sz = 0;
      U8 *b = FileRead(line + 4, &sz, NULL);
      if (b) {
        Sh(b);
        if (sz && b[sz - 1] != '\n')
          Sh("\n");
      } else
        Sh("no such file\n");
    } else if (!StrNCmp(line, "write ", 6)) {
      U8 *rest = line + 6;
      I64 sp = SpaceAt(rest);
      if (sp < 0)
        Sh("usage: write <file> <text>\n");
      else {
        rest[sp] = 0;
        U8 *fn = rest, *txt = rest + sp + 1;
        FileWrite(fn, txt, StrLen(txt));
        Sh("wrote ");
        Sh(fn);
        Sh("\n");
      }
    } else if (!StrNCmp(line, "run ", 4)) {
      // load a program blob off the FS and execute it
      I64 sz = 0;
      U8 *code = FileRead(line + 4, &sz, NULL);
      if (!code)
        Sh("no such program\n");
      else {
        I64 r = RVRunBlob(code, sz);
        U8 rb[40];
        StrPrint(rb, "[exit %d]\n", r);
        Sh(rb);
      }
    } else {
      Sh("? unknown command\n");
    }
  }
  Bts(&Fs->task_flags, TASKf_KILL_TASK);
  Yield();
}

I64 main()
{
  // Boot scaffolding + mount, then HomeSet so a spawned task inherits a valid current drive.
  CTask *adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
  CBlkPool *bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  CHeapCtrl *ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0);
  CCPU *gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  RVKernelInit();
  RVMountVirtioDisk('A');
  HomeSet("A:/");
  // Pre-stage a runnable program on the disk so the shell's `run` command has something to load: a
  // precompiled position-independent blob (prog_hello.hc), written as a file the shell can execute.
  FileWrite("A:/HELLO.PRG", prog_blob, prog_blob_size);
  // Run the shell as a real CTask that the kernel's own Spawn() created and Yield() schedules.
  CTask *t = RVKSpawn(&ShellTask, "Shell", adam);
  while (!(t->task_flags & (1 << TASKf_KILL_TASK)))
    Yield();
  Sh("shell task exited; adam done\n");
  return 0;
}
