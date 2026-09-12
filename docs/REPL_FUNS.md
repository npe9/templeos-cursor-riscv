# Adam / DocTerm command-line → UART REPL catalog

Lean map of **user-facing** TempleOS Adam / DocTerm command-line funs to this port’s
HolyC UART REPL (`make hc-repl` → `build/repl-holyc.elf`). Not every Kernel
internal — only what users type at `>` / DocTerm.

**Do not invent APIs.** Status is cited from stock `tos/` / in-tree Adam·Kernel·Compiler
and from `bootstrap/seed/` / Soft tip Soft Call paths. Soft tips are **not** claimed done.

| Status | Meaning |
|--------|---------|
| **present** | On thin `repl-holyc` seeds today |
| **Soft tip** | Soft Call / Soft tip toward stock Adam (phase3 / Win / Doc) — not product REPL |
| **missing** | Not on UART REPL; stock path exists in-tree |
| **escape** | Sensible ANSI/VT map via `term.hc` (or raw `\e[…`) |
| **N/A UART** | Needs WinMgr / FB DocTerm / graphics |

Related: [REPL.md](REPL.md), [CONSOLE.md](CONSOLE.md), [UART.md](UART.md),
[DEBUGGER.md](DEBUGGER.md), [GAPS.md](GAPS.md), [PATHS.md](PATHS.md),
[BOARD_FB.md](../templeos-riscv/BOARD_FB.md).

---

## Architecture (thin REPL vs Adam)

`repl-holyc` / `bootstrap/hc_repl` is a **thin** UART HolyC guest: memfs seeds
(`bootstrap/seed/*.hc`), seed symbol table / `CompTab`, ExePutS→JIT — **not** a
full Adam hash after `MakeAdam` / `DocTermNew`.

Stock Adam command-line surface (`U` from guest Cmp `UAsm`, `F` from
`~/HomeWrappers`, `Who`/`Man`/`Ed`/`DocPrint`/`PopUp*`) lives on the **Adam hash**
built by `Adam/MakeAdam` (RV entry: `Adam/MakeAdam_RV.PRJ` → `#include MakeAdam`)
and StartOS / DocTerm (`Adam/DolDoc/DocTerm.HC`, Soft tip
`Adam/StartOS_RV.HC` / `Kernel/RVDoc.HC`). That path is Soft tip Soft Call /
`win_*.elf` / RedSea Load — **not** auto-loaded into thin UART REPL.

| Layer | What you get | Where |
|-------|--------------|--------|
| Thin UART REPL | Seed `Help`/`Man`/`Dir`/`Find`/`F`/`R`/`Print`/`U`/`Uf`/ANSI+SGR `term.hc` | `bootstrap/seed/`, `make hc-repl` |
| Soft tip Adam lite | Soft Cmp+Call slices (DocInit, DocPrint flags, DocTermNew, Menu, PopUp) | `Kernel/RVPhase3.HC`, `tests/exec/seeds/phase3_*`, [GAPS.md](GAPS.md) G8 |
| Full Adam / DocTerm | Stock hash + DolDoc widgets + WinMgr | `MakeAdam_RV` + FB Win ([BOARD_FB.md](../templeos-riscv/BOARD_FB.md)) |

**U / F specifically:** thin `repl-holyc` now ships live `U` / `Uf` / `UA` / `Disasm`
(`bootstrap/seed/disasm.hc` is `#include`d in `bootstrap/hc_repl/repl.hc`, embedded full in
`gen_embed.py` `SEED_BOOT_ORDER`, and `JitAdd`'d) plus the stock home wrappers
`F` / `R` / `FD` / `RD` (`bootstrap/seed/home_wrappers.hc` over memfs). Two honest caveats:

- **`Uf` bounds are heuristic.** Thin `man_sym.hc` `FnSize` returns a synthetic 64 (no
  ELF / hash size table), so `Uf` uses the next registered JIT symbol as an upper bound and
  `DisasmAt`'s ret-stop to find the real end — it prints `<=N bytes to next symbol`, not
  stock's exact `dbg_info` size. Stock `FunRep` is still **missing**.
- **No default args through the JIT.** The REPL call path passes only the args you type, so
  `U(addr)` falls back to 28 insns via a clamp in `repl.hc` (`ReplUCnt`), and `R`/`RD`
  require both needle and replacement. `F`/`R` are plain substring — stock `fu_flags`
  (`+l` / `-i`), regex, and the interactive FUF window are **missing**.

---

## DolDoc → UART / ANSI escape codes

Stock DolDoc cmds come from `DefineLstLoad("ST_DOC_CMDS",…)` in
`Adam/DolDoc/DocInit.HC` (RV twin `Adam/DolDoc/DocInit_RV.HC`). Colors:
`ST_COLORS` in `Kernel/KDefine.HC` (`BLACK`…`WHITE`, 0–15).

UART side: `bootstrap/seed/term.hc` — `TermGoto` → `\e[{row};{col}H`,
`TermClear` → `\e[2J` + home, `TermClearEol` → `\e[2K`, cursor hide/show
`\e[?25l`/`h`. The attribute rows below are now backed by a real SGR API in the same
seed (all `JitAdd`'d, so they are callable at `>`):

```holyc
TermColor(1);                 // TF_COLOR gate — OFF by default (piped smokes stay plain)
TermFg(n); TermBg(n);         // n = ST_COLORS 0..15, remapped to SGR 30-37 / 90-97 (+10 for BG)
TermFgDft; TermBgDft;         // $$FD$$ / $$BD$$  → \e[39m / \e[49m
TermInverse(1); TermUnderline(1); TermBlink(1); TermBold(1);
TermAttrOff;                  // \e[0m — always emit before returning to the prompt
TermColorDemo;                // 16-color chart; TermSgrColor(n) is the raw map
```

`TermSgrColor` remaps rather than adding `30+n`: TempleOS `ST_COLORS`
(`BLACK BLUE GREEN CYAN RED PURPLE BROWN LTGRAY` then the eight light variants,
`Kernel/KDefine.HC`) orders its first eight differently from ANSI and puts 8–15 on the
bright plane. Every helper is gated on `TF_ANSI | TF_COLOR`, and `TF_COLOR` is off at boot —
nothing changes for existing output unless you call `TermColor(1)`.

Still **not** wired: nothing parses a `$$…$$` stream on the UART side. Win Doc-lite parses
`$$FG`/`$$BG`/`$$TX` into entries (`Kernel/RVDoc.HC` `RVDocColorName`) but does not emit SGR;
a DolDoc→SGR *renderer* (feed `DocPrint` output through `Term*`) is Soft tip work.
See [CONSOLE.md](CONSOLE.md) #2.

| DolDoc form | Meaning | UART/ANSI escape (or “no map”) | Port status |
|-------------|---------|--------------------------------|-------------|
| `$$FG$$` / `$$FG,n$$` / `$$RED$$`… | Foreground (dft or 0–15 / name) | `\e[3Xm` / `\e[9Xm` (map 0–15→SGR) | **present** as API — `TermFg(n)` / `TermSgrColor` (`term.hc`). `$$RED$$` *name* → index is Soft tip (`RVDocColorName`); no UART `$$…$$` parser |
| `$$BG$$` / `$$BG,n$$` / `$$BLUE$$`… | Background | `\e[4Xm` / `\e[10Xm` | **present** as API — `TermBg(n)`; same caveats as FG |
| `$$FD$$` / `$$BD$$` | Default FG / BG restore | `\e[39m` / `\e[49m` | **present** as API — `TermFgDft` / `TermBgDft` |
| `$$TX,"…"$$` | Text tag | plain text | **present** as `Print`/`UartStr`; Soft tip DocPrint TX+CX (`Kernel/RVDoc.HC`) |
| `$$CR$$` / `$$SR$$` | Hard / soft newline | `\n` | **present** (plain) |
| `$$TB$$` | Tab | `\t` | **present** |
| `$$PB$$` | Page break | form-feed `\f` or clear — weak | **no map** clean; Soft tip cheap PB on Doc |
| `$$CU$$` | Cursor entry | no map (Doc stream marker) | Soft tip / DocTerm |
| `$$CL$$` / `$$CL+H$$` | Clear document | `\e[2J\e[H` via `TermClear` | **escape** for screen; Doc `DocClear` Soft tip (`RVDoc`) ≠ UART |
| `$$CM,…$$` | Cursor move | `\e[{row};{col}H` (`TermGoto`) | **escape**; Doc CM Soft tip marker only |
| `$$PT$$` | Prompt | no map (Doc) | Soft tip / DocTerm |
| `$$PL$$`/`$$LM$$`/`$$RM$$`/`$$HD$$`/`$$FO$$`/`$$ID$$` | Page len / margins / header / footer / indent | no map | Soft tip layout; **N/A UART** as widgets |
| `$$WW$$` | Word wrap | host PTY wrap only | **no map** |
| `$$HL,1$$`/`$$HL,0$$` | Highlight on/off | no clean SGR (syntax) | `TermBold(1)` (`\e[1m`) as the honest stand-in; stock `U`/`Un` wrap HL (`Compiler/UAsm.HC`) — UART `U` output stays plain |
| `$$BK,1$$`/`0$$` | Blink | `\e[5m` / `\e[25m` | **present** as API — `TermBlink(on)`; most hosts ignore or bold it |
| `$$IV,1$$`/`0$$` | Invert | `\e[7m` / `\e[27m` | **present** as API — `TermInverse(on)` |
| `$$UL,1$$`/`0$$` | Underline | `\e[4m` / `\e[24m` | **present** as API — `TermUnderline(on)` |
| `$$SX$$`/`$$SY$$` | Shifted X/Y | no map | **N/A UART** |
| `$$AN,"…"$$` | Anchor | plain text / no link | Soft tip Win |
| `$$LK,"tag",A="…"$$` | Link (FI/MN/…) | plain `tag` text; optional OSC 8 **not** in tree | Soft tip Doc / Win OpenLink; UART **no map** interactive |
| `$$BT$$`/`$$DA$$`/`$$CB$$`/`$$LS$$`/`$$MA$$`/`$$MU$$` | Button / data / checkbox / list / macro / menu | no map | Soft tip DocEd/DocMenu; **N/A UART** |
| `$$HX$$` | Hex editor widget | no map | **N/A UART** |
| `$$TR$$` + `$$ID$$` | Tree collapse | no map | Soft tip Win trees |
| `$$SP$$`/`$$IB$$`/`$$IS$$` | Sprite / insert bin | no map | **N/A UART** (Gr/Sprite) |
| `$$SO$$` | Song | no map (audio) | Soft tip `GodSong` / Psalmody; UART **missing** |
| `$$HC$$` | HolyC widget | no map | Soft tip |
| `$$ER$$` | Error entry | plain text | Soft tip |
| `$$MK$$` | Marker | no map | Soft tip |
| `"%$$"` / `%$$Q` | Print escaped `$` / quoted DolDoc | N/A as escape — fmt in `DocPrint`/`StrPrint` | Soft tip DocPrint; UART use `Print` / `$$` literal caution |
| `DocPrint` / `DocPrintAtomic` | Emit DolDoc into `DocPut` | UART: use `Print` / `UartStr`; Atomic = batch + Recalc | Soft tip `Kernel/RVDoc.HC`; stock `Adam/DolDoc/DocPutS.HC` |

**Coverage count (this table):** ~35 DolDoc forms — **~12** have a direct ANSI/plain map
(**escape** / plain text), **~23** are **no map** / Soft tip DocTerm / **N/A UART**.
Of the mappable dozen, the **7 attribute forms** (`$$FG`, `$$BG`, `$$FD`, `$$BD`, `$$IV`,
`$$UL`, `$$BK`) plus `$$CL`/`$$CM` are now backed by callable `term.hc` code; the rest are
plain text (`$$TX`/`$$CR`/`$$SR`/`$$TB`). Backed **API** still is not a **parser** — no UART
code consumes a `$$…$$` stream.

---

## Catalog: classic helpers

| Stock name | Stock role + source | REPL translation | Notes |
|------------|---------------------|------------------|-------|
| **U** | Unassemble *n* instructions at addr — `Compiler/UAsm.HC` (`U(rip,cnt=20)`; x86 `Ui`) | **present** — seed `disasm.hc` `U(addr,n)` (RV64IM + D + RVC, jal/branch targets, `<Sym+off>`) | Bare `U(addr)` clamps to 28 (`ReplUCnt` — the JIT fills no default args). `UA`/`UAsm` emit paste-into-`asm{}` source |
| **Un** | Unassemble *bytes* — `Compiler/UAsm.HC` | **missing** (no stock `Un` name on seed) | Seed `U` is insn-count; byte windows via `DisasmAt(addr,max,end)` |
| **Uf** / **UF** | Unassemble named fun (+ FunRep) — `Adam/ADbg.HC` | **present** — `Uf("Name")` / alias `Disasm` | Bound is heuristic: thin `FnSize` is a synthetic 64, so `repl.hc` `ReplUf` uses the next JIT symbol + ret-stop and prints `<=N bytes`. `FunRep` still **missing** |
| **F** | Find text in all text files — `tos/HomeWrappers.HC` → `Find(…,"/*")` | **present** — `home_wrappers.hc` (whole memfs tree, `file:line`, returns hits) | Plain substring; no `fu_flags` / regex / FUF window. Stock `Find`: `Adam/Opt/Utils/Find.HC` |
| **R** / **FD** / **RD** | Replace / find-in-dir wrappers — `tos/HomeWrappers.HC` | **present** — `home_wrappers.hc` | `FD`/`RD` are cwd-scoped (stock `"*"`); `R`/`RD` rewrite in place via `FileWrite` so edits land in `FsChanges`/`FsLog`. Both args required, no confirm prompt |
| **Find** | Grep/replace across files — `Adam/Opt/Utils/Find.HC` | **present** (memfs) — `files.hc` | Not full FUF recurse/replace UI |
| **Grep** | (no stock public `Grep`; users say Find/F) | **N/A** name — use `Find` | — |
| **Man** | Owner’s manual / edit src for symbol — `Kernel/FunSeg.HC` (MN: → `Ed`) | **present** — `man.hc` + `man_topics.hc` (UART print, not DocEd) | Soft tip `RVWinSoftMan`; stock Raw→EdLite |
| **Help** | DbgHelp or HelpIndex.DD — `Kernel/StrB.HC` | **present** — `boot.hc` UART banner | Stock PopUp Type HelpIndex — **N/A UART** PopUp |
| **Ed** | Doc editor via link — `Adam/DolDoc/DocEd.HC` | **present** as `Ed`/`EdHoly`/`Vi`/`EditHoly` — `ed.hc`/`vim.hc`/`edit.hc` | Not DolDoc `DocEd`; memfs text. Soft tip `RVDocEdSoft` |
| **Type** | Print file as DolDoc — `Adam/DolDoc/DocFile.HC` `Type`→`DocType` | **maps** → `Cat` — `files.hc` | Plain dump; no DolDoc recalc |
| **Plain** | Edit with `$` not special — `DocEd.HC` | **missing** / editors treat `$` as text | — |
| **Dir** | List directory — `Kernel/BlkDev/DskDirB.HC` | **present** — `dir.hc` | Memfs; see [PATHS.md](PATHS.md) |
| **Cd** / **Pwd** / **DirMk** | Change dir / print / mkdir — `DskDirB.HC` / StrA | **present** — `fs.hc` (`MkDir` alias) | `::/` / `A:` grammar Soft tip `soft_let.hc` |
| **Drv** | Switch drive letter — `Kernel/BlkDev/DskDrv.HC` | **missing** / Soft tip Let2Drv | UART memfs single tree; Soft tip `soft_let.hc` |
| **Mount** / **Unmount** | Interactive blkdev mount — `Adam/ABlkDev/Mount.HC` | **missing** ATA UI | **present** twin: `Mount9p` — `ninep.hc` / [NINEP.md](NINEP.md) |
| **Copy** / **Move** / **Del** | File ops — `Adam/ABlkDev/ADskA.HC`, `DskCopy.HC` | **present** — `files.hc` / `fs.hc` | Memfs only on thin REPL |
| **GodSong** / **GodSongStr** | Holy Spirit song insert — `Adam/God/GodSong.HC` | **missing** on UART | Soft tip `Adam/ASnd_RV.HC` GodSongStr; needs PopUp/Doc/Snd |
| **God\*** (Bible/Doodle/…) | `Adam/God/*` | **missing** / Soft tip | DocTerm + PopUp |
| **PopUpOk** / **PopUpGetStr** / **PopUpEd** | Modal UI — `Adam/DolDoc/DocPopUp.HC` | **N/A UART** | Soft tip `Adam/PopUp_RV.HC` / WinMgr; UART print soft stub in `WinDemo_RV` |
| **AutoComplete** | AC task on/off — `Adam/AutoComplete/ACTask.HC` | **maps** → `CompTab` Tab — `complete.hc` / readline | Not stock AC dictionary task |
| **Who** | Hash table listing — `Adam/AHash.HC` | **maps** → `FunsList` / `Funs` — `sym.hc`/`funs.hc` | Soft tip full Who needs Adam hash + DocPrint |
| **HashAdd** / **HashFind** | Symbol table — `Kernel/KHashA.HC` / `KHashRV.HC` | Soft tip / Kernel; REPL uses seed Comp/FnAddr | User-facing dig: `FnAddr`/`SymName`; not stock Hash* at `>` |
| **FunRep** | Fun arg/local dump — `Adam/ADbg.HC` | **missing** | Soft tip with Uf |
| **DocTermNew** | Term + border docs — `Adam/DolDoc/DocTerm.HC` | **N/A UART** / Soft tip | Soft tip `RVDocTermNewSoft`; Win StartOS |
| **Src** / **Run** / **Fmt** | (port helpers; Src≈open source) | **present** — `run.hc` / editors / `fmt.hc` | Not stock Adam names; REPL everyday |

---

## Catalog: print / Doc

| Stock name | Stock role + source | REPL translation | Notes |
|------------|---------------------|------------------|-------|
| **Print** | Formatted stdout — Kernel PutS path | **present** — `print.hc` | UART bytes |
| **DocPrint** | DolDoc printf into doc — `Adam/DolDoc/DocPutS.HC` | Soft tip — `Kernel/RVDoc.HC` | Needs DocPut/DocTerm; UART use `Print` |
| **DocPrintAtomic** | Multi-cmd atomic print + Recalc — `DocPutS.HC` | Soft tip | Trees/widgets |
| **DocPrintPartial** | Half-cmd / keystroke path — `DocPutS.HC` | Soft tip | — |
| **DocPutS** | Raw DolDoc string insert | Soft tip | Prefer DocPrint |
| `"%$$"` / `%$$Q` | Escape `$` in fmt | Soft tip Doc | Careful with `$` in UART strings |
| Sprite / entry types users see (`$$SP$$`, `$$BT$$`, …) | DolDoc widgets | **N/A UART** | Soft tip Doc + Win Gr |

---

## Catalog: window / FB

| Stock name | Stock role | REPL translation | Notes |
|------------|------------|------------------|-------|
| **WinMgr** / **Refresh** / **WinFocus** | Window manager | **N/A UART** | Soft tip `Kernel/RVWinMgr.HC`; [BOARD_FB.md](../templeos-riscv/BOARD_FB.md) |
| **DocTerm** body / Adam window | Focus HolyC + DolDoc | **N/A UART** | Soft tip StartOS_RV / WinSerial ExePutS is separate UART twin on FB image |
| **Gr\*** / sprites | Graphics | **N/A UART** | Soft tip Gr Soft |

---

## Quick dig-down (UART REPL)

```holyc
Help; Man("Print"); Man("CLINT");
Dir; Cd("Tutorials"); Find("TermGoto");
TermClear; TermGoto(1,1); TermHelp;
FunsList; Sections;
Uf("Print"); U(FnAddr("Print"), 8); UA(FnAddr("Print"), 8);
U(pc - 16);                       // after a Fault: pc holds the trapped mepc
F("TermGoto"); Cd("Lib"); FD("PutCh"); Cd("/");
TermColor(1); TermColorDemo; TermAttrOff;
```

Stock-shaped `F("needle");` works as-is now. `R("old","new");` rewrites memfs files in
place — check `FsChanges` / `DumpChanges` after, or `FsCheckpoint` before.

---

## See also

- [REPL.md](REPL.md) — everyday commands, memfs layout
- [CONSOLE.md](CONSOLE.md) — ANSI/TTY wishlist honesty
- [DEBUGGER.md](DEBUGGER.md) — `U`/`Uf`/`Regs`/`Bp` matrix
- [GAPS.md](GAPS.md) — Soft tip Doc/Menu/Adam DoD
- `tos/Doc/Welcome.DD` — stock pitch for `F`/`Find`
- `tos/HomeWrappers.HC` — stock `F`/`R`/`FD`/`RD`
