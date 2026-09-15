# Stock TempleOS parity audit (2026-09-11)

Reference tree: `../TempleOS` (byte-identical to `../templeos`). "Ours" = this repo.
Anything the ISA (x86 → RISC-V) or the console (VGA/DolDoc → VT/curses) forces to
differ is out of scope; everything else is expected to match stock behaviour.

## File-level picture

| Tree     | identical | modified | added | deleted |
|----------|----------:|---------:|------:|--------:|
| Kernel   | 48        | 29       | 119   | 0       |
| Compiler | 14        | 20       | 13    | 0       |
| Adam     | 130       | 2        | 18    | 0       |

* No stock file is deleted. `KThin*Stubs.HC` bodies exist only under `RV_THIN_LOADER`
  (not the win build).
* 18 providerless `_extern` x86 primitives remain declared; only `SetMSR` is ever called
  (once, from stock init) and it is a no-op on RV.

## Guest compiler backend (`Compiler/*_RV.HC`) — what was stubbed and is now real

Verified line by line in the win_vt REPL (`make build/exec/win_vt.elf`).

| Area | Stock behaviour | Was | Now |
|------|-----------------|-----|-----|
| F64 operand convention | F64 values travel as raw bits in integer regs (RAX) | mixed FP/int register meaning; `Sqrt(16.0)` returned an address, `ToI64(f)` garbage | bits-in-int-regs everywhere (`ICFLoad`/`ICFStore` are the only FP-reg transitions), matches host AOT/runtime |
| F64 literals | exact (x87 80-bit) | `1.5` lexed as `0x3FF7FFFFFFFFFFFD` (`i*Pow10I64(-k)`, and the table came from runtime `Pow10()`) | exact: `i/Pow10I64(k)`, table built by exact `*10.0` / `1.0/10^k` |
| `+= -= *= /= %= <<= >>=` | `ICAddSubEctEqu` / `ICFOpEqu` | unimplemented | `ICArithEqu` (int + F64, int-lval-with-F64-rhs converts like stock) |
| `Bt/Bts/Btr/Btc/LBt*` | `bt r/m64(arg2=bit-string), reg(arg1=bit#)`; bit-strings past 64 bits | args reversed and the *pointer* was tested | stock semantics; `LBt*` are real `amoor/amoand/amoxor.d` |
| `if (x & (1<<n))`, `while(--i)` | `IC_BR_BT*`, `IC_BR_MM_ZERO` | unimplemented (fault) | implemented |
| `Sin Cos Tan ATan` | FPU | identity stubs | call Kernel wrappers `RVF64Sin…` (table set by `RVCmpSetF64Rt`) |
| `` a`b `` (`IC_POWER`) | `ICFPow` | unimplemented | `RVF64Pow` |
| `Sqr SqrI64 SqrU64` | | unimplemented | implemented |
| `Swap*` | swap two pointed-to values | byte-reverse of one value | stock |
| `Min/Max I64/U64`, `AbsI64`, `SignI64`, `Bsf`, `Bsr` | | wrong results (a `j +4` that skipped nothing; BSF jumped into an unrolled loop) | branch-free / looped; `Bsf(0)=-1` |
| `ToUpper`, `QueInit/QueIns/QueInsRev/QueRem`, `ModU64` | | unimplemented | implemented |
| `_intern` functions in the REPL hash | `KernelB.HH` `_intern` declarations | absent ("Undefined identifier" for `ToI64`, `Bt`, …) | `RVExePubInternsIn` plants them as `Ff_INTERNAL` `CHashFun`s |
| 64-bit immediate stored to a global | | `RVLi` scratched the address reg → `sd` to `0xFFFFFFFD` | value materialised before the address |
| Branch conditions with RIP-relative operands | | loads used the function-local `rip` | branch helpers take `rip2` |
| Hex literals `0xA`…`0xE` | | only `0xF` lexed | host bug (below) |

### Host compiler fixes this uncovered

`&ExternFn` (see "Still open" below, now closed) and the pointer-array member stride:

`host/parser.c`: a class member `T *arr[N]` took `sizeof(T)` as its element stride, so
`cmp.internal_types[raw_type]=tmpc` in `AsmHashLoad` wrote heap pointers hundreds of bytes
past `cmp`, over other compiler-unit globals (`char_bmp_hex_numeric` word 2 became a
pointer → bits for `A`–`E` gone). Regression case: `tests/exec/cases/e_member_ptr_array.hc`.

### Pointer-array members affected by the stride bug (audit)

Every `T *arr[N]` class member compiled by the host had the wrong stride before the fix.
Sites, all stock code with no compensating hacks: `CCmpGlbls.internal_types` (the one that
surfaced), `CBlkDevGlbls.let_to_drv` (drive-letter lookup — `Cd`/`Let2BlkDev`), `CTask.
except_callers` (stride 1 — smeared into `catch_except`), `CHashAC.fillin_matches` (REPL
autocomplete), `CAutoCompleteDictGlbls.fillins`, and in Adam `gr.pen_brushes` /
`scrn_zoom_tables` (not in the win image). The only "compensation" found is
`AsmHashLoad`'s re-assert of the `*`/`**` class slots, which is harmless and kept.
kernel-win-interactive and kernel-win-serial-smoke went green once these indexed correctly.

## Deliberately different (ISA / console)

* x86-only ICs stay unimplemented and are not planted in the REPL hash: `IC_IN_*`,
  `IC_OUT_*`, `IC_CARRY`, `IC_GET/SET_RFLAGS`, `IC_INVLPG`, `IC_RDTSC` maps to `rdcycle`.
* `asm {}` assembles native RISC-V (see `docs/fault_examples.md`); `OpCodes.DD` (x86
  tables) is not loaded — `AsmHashLoad` soft-loads the HolyC keywords.
* `sret` at the prompt drops to U-mode with no PMP, so nothing is fetchable; the recovery
  path now forces `MPP=M` so it returns to the prompt. The working trap-return form is
  `asm{auipc x5,0; addi x5,x5,28; csrw mepc,x5; lui x6,2; addi x6,x6,-2048; csrs mstatus,x6; mret}`.

## Still open

* ~~Cross-unit `&ExternFn` resolved to a dead import slot~~ — fixed in the host: the unary
  `&` path retracted the slot-load DEREF that `EmitFnAddress` emits (leaving the slot
  address), and an address-only use never bumped the slot's `use_cnt`, so the loader never
  filled it. Regression: `tests/exec/cases/e_addr_of_extern_fn.hc`. The F64 runtime table
  (`RVCmpSetF64Rt`) is kept as the simpler mechanism.
* ~~`Bp`/`Step`, disassembler and `PassTrace` absent from the seed REPL~~ — `Bp`/`BpClr`,
  `Disasm`/`U`/`UA`/`Uf`/`FnAddr` (`Kernel/RVDisasm.HC`) and `PassTrace` are now planted
  (`RVExePubsWireDbg`); a breakpoint recovers to the prompt. No single-step yet.
* ~~The DocTerm console froze after roughly a windowful of output~~ — the "not getting the
  full console" symptom. Root cause was the VT console **redraw**, not input, eval or the
  UART: `RVDocDrawWin` rendered doc entries at `y = doc_e->y - scroll_y`, and `DocRecalc`
  lays a console oldest-first from `y=0`, so a bare `scroll_y=0` painted only the FIRST
  `hh` lines and every later line fell past the client. Bisected by flipping
  `rv_console_mirror_only` to 0 (raw UART): all output appeared, proving the DolDoc redraw
  was the only broken stage. Fix: console docs (Term/Adam/User) now render the TAIL page
  by default (`sy = RVDocLineCount - hh + scroll_y`), and the `scroll_y` in `[-max,0]` that
  `RVWinClampScroll` keeps pages back through history — PgUp/PgDn scrollback verified.
  `RVWinBodyAppend` also no longer `DocRst`s the CDoc when the flat 1 KB `body[]` fills
  (that wiped scrollback and dropped new text); it front-trims whole lines and always
  appends to the CDoc incrementally. The first-char-on-scroll clip (`Ab375Ab`→`b375Ab`)
  was fixed earlier via `line_start_col` reset.
* RV_VT_COLS/ROWS: the presenter queries the terminal (`CSI 18 t`) at startup and parses
  the `CSI 8;r;c t` reply; compiled-in defaults otherwise.
* Boot-time harness probes `PopUp("FileMgr(1,0);")` / `Cd("A:")` report
  `Undefined identifier at "("` in win_vt (pre-existing; the kernel-win-* gates were red
  before this audit and are unchanged by it).

## Probe lines (all pass)

```
F64 f; f=1.5; Print("%d\n", ToI64(f*100));          // 150
f+=2.25; f*=2.0; f/=3.0; f-=0.5;                     // 375 750 250 200
I64 i; i=1; i+=2.75; i;                              // 3
ToI64(2.0`10.0); ToI64(Sqrt(16.0)*10); ToI64(Sqr(3.0)); ToI64(ATan(1.0)*4000);  // 1024 40 9 3141
I64 b; b=4; Bt(&b,2); Bts(&b,0); b; Btr(&b,2); LBts(&b,3); b;                 // 1 0 5 1 0 9
I64 arr[4]; Btc(arr,70); Bt(arr,70); arr[1];        // 0 1 64
I64 k; k=6; if (k&2) …; I64 n; n=3; while(--n) c++;  // taken; c=2
ModU64(&qq,7) (qq=100) → 2, qq=14; SwapI64(&s1,&s2); MaxI64(3,9)=9; MinI64=3; AbsI64(-4)=4; SignI64(-4)=-1; Bsf(8)=3; Bsr(8)=3; Bsf(0)=-1
QueInit(qa); QueIns(qb,qa); qa[0]==qb; qb[1]==qa; QueRem(qb); qa[0]==qa   // 1 1 1
0xA; 0xABC; 0x123456789ABC;                          // 10 2748 20015998343868
```

## Interactive console (`make tos`) — what works now (2026-09-14)

The clean boot is a usable TempleOS/RISC-V console, everything driven through the guest
`Compiler_RV` (`ExePutS`):

* **HolyC REPL** — arithmetic, statements, F64 math, `Cat`/`Dir`/`Cd`, `#include` to run a
  program from disk. All the runtime functions and struct types are planted (see REPL.md).
* **DolDoc desktop** — windows, PersonalMenu, `max`/`tileh`/`tilev`, Tab focus; the
  `RVWinMgr` presenter composes to VT100/ANSI over the UART.
* **Links selectable by the cursor** — Tab to a doc window, arrows select a link/tree
  (inverted highlight), Enter follows it; `FI:` links `FileRead` the real target from the
  mounted tree (stock `B:/Doc/*.DD`).
* **Search** — `Find("needle");` greps the doc tree into a browsable results window.
* **Editor** — `Ed("file");` (arrows, Ctrl-W save, Esc leave); the write-a-program /
  save / run loop closes entirely in the console.
* **Tasks** — `Tasks;` lists the desktop windows and their task bindings; `user` spawns a
  live task-backed Term.

`Find`/`Ed`/`Tasks` are planted HolyC functions (Compiler/RVExePubs.HC), not crash-shell
barewords; the `RVWinSerial` dispatch sidecar is only for `md`/`mw`/`regs`/`crash`/`fault`.
Deliberately omitted per scope: graphics demos and sound.
