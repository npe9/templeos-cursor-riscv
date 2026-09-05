# IDE behaviors (TempleOS RISC-V / HolyC)

Product spec and best-practices checklist for the UART HolyC IDE on this port:
**Vi**, **EditHoly**, **EdHoly**, **`Src`**, **`Man`**, and the **REPL**. Emulators are the CI
harness — not the UX. Shape expectations like TempleOS (Src / Man / Adam later), not a
VS Code clone.

How to run and smoke: [REPL.md](REPL.md). Honesty gate: [../tests/REGRESSION.md](../tests/REGRESSION.md).
Editors are selected by Kconfig (**Editors** → `RVEditorSelected.hc`); override live with
`editor=&Vi;` / `editor=&EditHoly;` / `editor=&EdHoly;`.

---

## 1. Navigation (`gd` / `^]` / Enter-on-symbol)

| Situation | Expected behavior |
|-----------|-------------------|
| Symbol defined **in the current buffer** | Seek to the definition **in place** (no session push). Vertically **center** the target line. One quit (`:q` / `^X`) leaves the editor. |
| Symbol defined in **another file** | Push a nested editor session (memfs spill; depth limit ~4), open that file, seek to def, **center**. `:q` / `^X` **pops** to the parent buffer. |
| Quit at session depth 0 | Leave the editor back to the REPL. |
| After any successful jump | Cursor on the target; viewport centered on that line. |

**Resolve order** (same idea as `SrcFile`): srcmap file → srcmap text spill → memfs / `Name.hc` → `DocFileFor` (Man topics). No full TempleOS hash `SrcLink` yet.

**Editors**

| Editor | Jump keys | Pop |
|--------|-----------|-----|
| Vi | `gd`, `^]`, Enter on symbol (**NORMAL / navigate only**) | `:q` |
| EditHoly | `^]` / `^G` | `^X` |
| EdHoly | (line-oriented; prefer Vi/Edit for dig-down) | `q` |

Vi **INSERT**: Enter splits the line (newline). Enter must not jump.

**Checklist**

- [ ] Same-file jump never nests a redundant session.
- [ ] Cross-file jump always nests and is poppable.
- [ ] Every jump centers the target (not just “line somewhere on screen”).
- [ ] Depth overflow fails safely (no crash / corrupt parent).

---

## 2. `Src("Name")`

TempleOS-shaped goto-definition from the REPL:

1. Resolve defining source (`SrcFile` / srcmap / memfs / Doc).
2. Open the **preferred editor** on that file.
3. Land on the **definition line**, **centered** (`JumpIdent` → editor seek).
4. On quit, **`Run`** the file when it is executable HolyC (topic-only Doc files: edit only, no `Run`).

Nil / empty name → message (`Src: no source`), no crash.

**Checklist**

- [ ] `Src("Print")` / `Src("Dir")` open Vi (or selected editor) at the def, not file top.
- [ ] Stub paths that only `FileWrite` `Name.hc` and return are regressions — gate via `make repl-regression`.

---

## 3. Man (`K` / `gM` / `Man("…")`)

| Action | Expected |
|--------|----------|
| Vi `K` or `gM` | `Man(ident under cursor)`; pause for a key; redraw editor. |
| EditHoly `^K` | Same. |
| `Man("Print")` | Function page from `// Name --` doc block + addr/size when in REPL. |
| `Man("CLINT")` / `Man("Clint")` | Topic page from `man_topics.hc` (case-insensitive where practical). |
| `Man(0)` / `Man("")` | Print `Man: nil` and return — **never** trap / hang. |
| Unknown name | `Man: no such symbol: …` — safe. |
| Doc-only / `FnAddr=0` | Clear “NOT IN REPL” / topic wording; do not claim callable. |

Man is UART text (NAME / SYNOPSIS / DESCRIPTION / …), not DolDoc `MN:` hyperlinks yet.

**Checklist**

- [ ] Topics and functions both work; CI covers `Clint`/`CLINT` and nil args.
- [ ] Editor Man paths tolerate nil cursor / empty ident.

---

## 4. Editing

| Behavior | Expected |
|----------|----------|
| **Tab** mid-token | Case-insensitive complete (funs / paths via `CompTab`); one match → fill; several → common prefix or list. Inside `asm{}`: opcodes / GPRs / CSR names (`asm_complete.hc`). |
| **Tab** at indent / no partial | Insert **2-space** indent (not a completion popup). |
| **Undo** | Vi: single-level buffer undo (`u`). Ideal: multi-level + EditHoly/Ed parity. |
| **Split / join** | Vi **INSERT**: Enter splits line (suffix via `VSuf`). Vi **NORMAL**: Enter activates / jumps (not split). Join is the inverse for line surgery. |
| **Format-on-save** | Vi `:w` / Edit `^O` / Ed `w` go through `FmtSave` / host `HolyFmtSrc` (same as `holyc-riscv --fmt`). Explicit: `Fmt("file.hc");`. |
| **Dirty / quit** | Warn or require write before discarding when dirty (product ideal); never lose parent session on nested quit. |

Style is gofmt-like — do not hand-fight formatting; see `.cursor/rules/holyc-fmt.mdc`.

---

## 5. Errors

| Behavior | Expected |
|----------|----------|
| Compile / eval failure | Print **`file:line:col: error: …`** (jumpable triple). |
| `ErrGo;` | Open preferred editor on the **last** error site. Ideal: seek to **line:col** and **center**. |
| No last error | `ErrGo: no error` — safe. |

Host `holyc-riscv` and the UART REPL should agree on the `file:line:col` shape so humans and scripts can parse it the same way.

---

## 6. REPL integration

| Surface | Expected |
|---------|----------|
| **Help;** | Short capability overview (same as boot welcome). |
| **History** | Up/Down; boot **preloads** demos (oldest→newest) so first Up is `Help;`. |
| **Tab at `>`** | Complete like editors (CI funs / paths). |
| **Ctrl-C at prompt** | Clear draft; print interrupted; stay at `>`. |
| **Ctrl-C during eval** | Abort busy eval → `Interrupted` (or `throw('Break')` into `try`/`catch`). Needs RX IRQ / `TrapInit` armed. |
| **Editors + Ctrl-C** | Not break-armed — `^C` is a keystroke inside Vi/Edit. |
| **`Reset;`** | Soft re-enter Boot / REPL. |
| **`HardReset;`** | Board/sim reset via `MEM_TEST` finisher when present — not a soft Boot loop. |
| Leave session | Guest `Reset;` / platform halt — **not** host-emulator quit keys as product UI. |

Dig-down companions: `MemMap;` `Regs;` `Man("Clint");` — teach hardware from HolyC, not from QEMU monitors.

---

## 7. What not to do

| Anti-pattern | Why |
|--------------|-----|
| QEMU-centric UX (`Ctrl-A X`, monitor, machine flags as “features”) | Product is board HolyC; emulators are harness-only ([PLATFORM.md](../templeos-riscv/PLATFORM.md)). |
| Exploding / trapping on `Man(0)` / empty / missing topics | Nil-safe Man is a hard contract. |
| Always nesting on same-file `gd` | Burns session depth; breaks “one `:q` exits” muscle memory. |
| Claiming `Src` works when it only writes `Name.hc` | Caught once as a false-green smoke — regression must open an editor. |
| Growing `bootstrap/hc_repl/jit.hc` for IDE features | Transitional Mac-AOT bridge; destination is guest `Compiler_RV`. |
| Treating host slots / EdC as the long-term IDE | Repair hatches; HolyC Vi/EditHoly/EdHoly are the editable surface. |
| Full DolDoc / mouse / WinMgr as REPL blockers | Separate kernel FB/Win track ([BOARD_FB.md](../templeos-riscv/BOARD_FB.md)). |
| Fighting in-flight Src/gd/Man work with drive-by editor rewrites | Coordinate; prefer docs + tests over contested seed churn. |

---

## 8. Gap list (current vs ideal)

Honest snapshot against the checklist above. Priority is backlog order, **not** a request to implement here.

| Area | Today (approx.) | Ideal | Priority |
|------|-----------------|-------|----------|
| Same-file vs nested `gd` | Vi/EditHoly: in-place seek vs session push; regression needles | Keep; cover EdHoly dig-down if promoted | **done / hold** |
| Center after jump | `VCenter` / `EvCenter` on seek | Same for `ErrGo` and any Activate/link entry | **P1** (ErrGo) |
| `Src("Name")` at def | `SrcJumpSet` + seek; regression checks status line Ln | Keep gated | **done / hold** |
| Man nil / topics / `K` | Safe nil; topics + funs; Vi `K`/`gM` | DolDoc-style links later (Adam) | **P3** links |
| Tab complete CI | Editors + REPL readline | Shared HolyC path; less C-only readline drift | **P2** |
| Undo | Vi single-level | Multi-level; EditHoly/Ed | **P2** |
| Split/join | Vi Enter split | Documented join; Edit parity | **P2** |
| Format-on-save | `FmtSave` / host `HolyFmtSrc` | Guest-owned fmt when Cmp owns loop | **P2** bridge |
| Errors `file:line:col` | Printed; stored for `ErrGo` | — | **done** |
| `ErrGo` seek+center | Opens **file only** (HolyC `ErrGo` + err slots); line/col printed but not applied | Seek to line:col + center like `Src` | **P0** |
| Help / history / Ctrl-C / Reset | Documented in REPL.md; regression covers Ctrl-C / Man / Src | Keep; don’t invent emulator keys | **done / hold** |
| Session depth UX | Depth 4; silent no-op at max | Clear message when push refused | **P2** |
| TempleOS `SrcLink` / hash | Resolve via srcmap + memfs | Richer guest hash when Compiler_RV owns symbols | **P2** |
| Adam / DolDoc IDE | Not this UART REPL | Later StartOS / Adam path | **P3** |

**Suggested backlog (no implementation in this doc):**

1. **P0** — `ErrGo`: open at stored `line:col`, center (parity with `Src`/`gd`).
2. **P1** — Regression needles for ErrGo cursor position; any remaining jump paths that skip center.
3. **P2** — Undo depth / EditHoly parity; session-full message; complete/fmt ownership toward guest Cmp.
4. **P3** — DolDoc Man links, Adam editor story, full WinMgr — out of UART REPL scope.

---

## Related

- [REPL.md](REPL.md) — run, Help, Ctrl-C, everyday commands
- [../tests/REGRESSION.md](../tests/REGRESSION.md) — honesty gate for Src / Man / editors
- [ARCHITECTURE.md](ARCHITECTURE.md) — host vs guest vs REPL
- [README.md](README.md) — docs index
