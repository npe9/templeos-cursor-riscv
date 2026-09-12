# Interactive DolDoc REPL over a VT100 — `make kernel-vt-repl`

`kernel_vt_demo.hc` paints a frame and holds; it takes no input, which is a fair
complaint about calling it a demo. This is the interactive one. It renders the WinMgr
menu bar, a Term window with chrome, echoes what you type into the window's DolDoc
body, and renders command output inside that window — all as ANSI diffs on a plain
serial line.

## Three things had to line up

**1. The right input entry point.** There are two, and only one works here:

| | behaviour |
|---|---|
| `RVWinSerialPoll()` | reads the UART and echoes + prints straight **back to the UART** |
| `RVWinTermPutChar()` | echoes into the focused window's DolDoc body; on Enter raises `rv_win_term_mirror` so `RVWinSerialDispatch`'s output is captured into that body |

The first is correct when the UART is a side-channel next to a framebuffer. Here the
UART *is* the screen, so two writers shred the frame. Driving `RVWinTermPutChar` makes
`RVVtPresent` the only writer.

**2. Only the text half of the compose.** Nothing rendered at first — blank grid,
~3 KB emitted. `RVWinMgrRefresh` returns immediately when `!RVGrU8ComposeActive &&
!rv_fb.pixels`. But only its first two steps touch the text grid:

```
RVWinMgrWallPaper;      // <- text_base
RVWinMgrComposeWins;    // <- text_base
RVWinMgrBlitTextBase;   // pixels from here down
RVWinMgrDrawDocSprites; RVWinMgrUpdateODEs; RVWinMgrDrawIts;
RVWinMgrDrawCursorAt;   RVWinMgrPresent;
```

Calling the first two and letting `RVVtPresent` be the scanout is the headless
equivalent of a refresh. Worth remembering: **`RVWinMgrRefresh` is not the text
pipeline, it is the pixel pipeline that begins with two text steps.**

**3. `RVConsolePutS` writes twice, on purpose.** Output still bled through and
overlapped the frame. `Kernel/KBootRV.HC`:

```c
Bool RVConsolePutS(U8 *st)
{
  if (RVConsoleMirrorPutS && st)
    (*RVConsoleMirrorPutS)(st);
  return RVUartPutS(st);          // <- unconditional
}
```

with the comment "set while evaluating a Term line so Print lands in **both** UART and
the graphical Term body." That is right for a framebuffer and wrong for one wire.

Fixed with `rv_console_mirror_only`, **default 0 — existing behaviour byte-identical**.
When set, a mirror that accepted the string suppresses the raw write. Only the VT REPL
case sets it. Same treatment for `RVConsolePutKey`.

## Verified

`kernel-vt-smoke`, `kernel-boot`, `kernel-print`, `kernel-heap`, `kernel-fs`,
`kernel-shell`, `exec-oracle` (84/0), `kernel-plat-matrix` (11/0) all pass after the
`KBootRV.HC` change. `kernel-win-serial-smoke` still fails on `PopUpPickFile ok` — log
**byte-identical** to the pre-change baseline, so it is the same pre-existing failure.

## Honest scope

The REPL is `RVWinSerialDispatch`'s **built-in command set** — help, regs, bt, md, mw,
max, tileh, tilev, user, fault, crash, q — not full HolyC. The guest says so itself:

```
Wire RVWinSerialEval=&ExePutS (win interactive) for HolyC REPL.
```

`RVWinSerialEval` is a function pointer that `kernel-win-interactive` points at
`ExePutS`. In this bare AOT harness the compiler symbols (`Lex`, `CmpCtrlNew`,
`ExePutS`, `LexStmt2Bin`) arrive as **unresolved imports**, so arbitrary HolyC is not
available in this image. Wiring `ExePutS` — probably by building this case against the
same AOT unit set as `kernel-win-interactive` — is the obvious next step and is **not
done**.

Also untested by anything here: an actual human pressing keys. Everything above is
reconstructed from the emitted ANSI byte stream, which is correct as bytes; whether a
real terminal renders it as intended is what a person still has to check.
