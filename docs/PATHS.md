# Path namespaces (TempleOS `::` / BlkDev vs UART / host)

Honest dual-namespace map. Product goal: **one TempleOS-shaped grammar**
(`A:` / `::` / `~`) everywhere Cd / FilesFind / `#include` / `__DIR__` matter;
Unix-looking `/…` remains an adapter, not a second SoT.

## Three surfaces

| Surface | Grammar | Storage | Typical APIs |
|---------|---------|---------|--------------|
| **Kernel BlkDev** (Win / ExePutS / phase3) | TempleOS: `A:/…`, `::/…`, `~/…` | RedSea (RAM / virtio-blk) | `Cd`, `DirCur`, `FileNameAbs`, `FilesFind`, `FileRead` |
| **UART memfs** (`repl-holyc`) | Slash tree **or** TempleOS prefixes | Fixed arena `MEM_FS` | `Cd` / `Pwd` / `Dir` / `Cat` in `bootstrap/seed/fs.hc` |
| **Host AOT** (`holyc-riscv`) | `#include` + `__DIR__`/`__FILE__` | Repo files via `HOLYC_INCLUDE_ROOT` | `host/lexer.c` (`StripTempleOSPathPrefix`, `TempleosPathFromHost`) |

Same *words* (`Cd`, `Pwd`, `Dir`) can mean different FSes — that is why shells feel wrong
if docs only show `/Home` or only `A:`.

## TempleOS rules (BlkDev SoT)

Stock behavior (see `Kernel/BlkDev/DskStrA.HC`, `DskDirB.HC`, `DskDrv.HC`):

| Form | Meaning |
|------|---------|
| `A:`…`Z:` | Drive letter (`Let2Drv` / `Drv`) |
| `::` | Boot drive root (`blkdev.boot_drv_let`) |
| `~` | Home (`blkdev.home_dir`, often `::/Home`) |
| `/…` | Absolute on **current** drive |
| relative | Under `Fs->cur_dir` |

`DirCur` prints `A:/path` when mounted. Guest `StreamDir` / `#define __DIR__`
follow the include file’s drive-letter abs path (often `::/…` or `A:/…`).

### Soft Cd (AOT pre-mount)

Stock `Load.HC` does `Cd(__DIR__);` as a **top-level** stmt. Host AOT runs that
chunk **before** `main` mounts a BlkDev, so `Fs->cur_dv` is still null.

`Cd` in `DskDirB.HC`: when `!Fs->cur_dv`, strip `A:` / `::`, record `Fs->cur_dir`,
return — **do not** call `RedSeaCd` / `FAT32Cd`. Mount later resets `cur_dir` to `/`.
That is what keeps Span / Psalmody `Cd(__DIR__)` from hanging on empty RAM disks.

`DirCur` / SoftCall `Pwd` in the soft window print **`::` + `cur_dir`** (boot-root
form, same as host `__DIR__` / UART `Pwd`) — never bare Unix `/…`. Soft `Cd("A:/Home")`
still stores `/Home` internally; `DirCur` reports `::/Home`. Soft `DirNameAbs("A:/Home")`
likewise yields `::/Home` (no `Drv2Let` throw). `RVSoftLetPlant('A')` plants a signed
`BDT_RAM` + `CDrv` so `Let2Drv('A')` / `Let2Drv(':')` work **without** virtio or
`RedSeaFmt`, and **without** setting `Fs->cur_dv` (soft Cd path stays). Gated by
`make kernel-home-smoke` (`SoftCd DirCur ok` / `Soft Let2Drv` / `Soft DirNameAbs`).

## UART memfs bridge (partial unification)

Internal names stay hierarchical slash paths (`Home/…`, `Tutorials/…`) — no letter
**device**. Bridge in `FsResolve` (letters are aliases of the one memfs):

| Input | Resolves as |
|-------|-------------|
| `::/Tutorials`, `:/Tutorials` | absolute `Tutorials/` |
| `A:/Home`, `Z:/…` | absolute (letter ignored; one memfs) |
| `~`, `~/Work` | `Home/`, `Home/Work/` |
| `/Tutorials`, `Tutorials` | unchanged (absolute / cwd-relative) |

`Pwd` prints TempleOS boot-root form: `::/Home/Work/`.  
`Cd` logs the same form: `cwd: ::/Home/Work/`.

**Safe now:** TempleOS *grammar* on memfs (`::` / `A:` / `~` accepted; `Pwd`/`Cd` log → `::/`).  
**Kernel soft letter:** `RVSoftLetPlant` → real `Let2Drv` without virtio (`kernel-home-smoke`).  
**UART soft letter:** seed `soft_let.hc` plants the same tables in `repl-holyc` (`SoftLetRep` / `hc-repl-smoke`).  
**9P letter:** `RVSoftLet9pPlant('P')` / `Virtio9pConnect` → `Let2Drv('P')`; soft `Cd("P:/…")` (`kernel-home-smoke`, `kernel-virtio-9p-smoke`).

## Host AOT adapter

`HOLYC_INCLUDE_ROOT` = repo root. Includes:

| Written | Tries |
|---------|-------|
| `/Kernel/…`, `::/Kernel/…`, `A:/Kernel/…` | `$ROOT/Kernel/…` |
| `::/Apps/…`, `A:/Apps/…` | `$ROOT/Apps/…` then **`$ROOT/tos/Apps/…`** |
| `/tos/Apps/…` | `$ROOT/tos/Apps/…` (host layout escape hatch) |
| `~/HomeLocalize` | `$HOLYC_HOME_ROOT/HomeLocalize` (default `/Home/…`) then `/HomeLocalize` |
| relative | directory of current file |

`~` is the logged-in account's Home directory. There is no logged-in account on the host, so
`HOLYC_HOME_ROOT` names one. The fallback to the distribution root is the rule stated in
`MakeHome.HC`: "If these are not present in /Home, it uses the version in the root dir." In this
repo the shipped templates are `tos/HomeLocalize.HC` and friends, reached as `/HomeLocalize` →
`$ROOT/tos/HomeLocalize.HC` through the `::/` adapter above. See `docs/ACCT_EXAMPLE.md`.

Guest Soft Cmp (`Compiler/Lex.HC` `#include`): relative names (no `A:`/`::`/`/`)
also join the **including file's directory** from `lex_include_stk->full_name`
before `FileNameAbs` — same host AOT shape. Stock JIT relies on `Cd(__DIR__)`
running before Lex hits the include; Soft AOT does not. Soft tip `+makedocrel`
proves nest MakeDoc_RV relative `#include "DocInit_RV"` Soft Cmp+Call.
Stock Soft `Cd(__DIR__)` / Soft `#exe{Cd}` still blocked (Soft AOT KernelA
`__DIR__` `#exe{StreamDir}` → Invalid lval; SoftExeDir HTT_FUN plant hung
DocEd Soft Call). Soft nest seed keeps Soft `#define __DIR__` string + Soft
`import Cd` workaround.

`__DIR__` / `__FILE__` (host builtins; guest uses `#exe{StreamDir;}`):

- Emit **`::/…`** under the include root (StreamDir / boot-root shape).
- Map host **`tos/X` → `::/X`** (ISO layout; `#include "::/Apps/…"` already falls
  back to `$ROOT/tos/Apps/…`).
- Soft Cd (above) makes pre-mount `Cd(__DIR__)` safe — no need to keep `/tos/…`
  in the string for hang avoidance.
- Relative compile paths (`Demo/Foo.HC`) count as already under the include root.
- Guest `StreamDir` may still prefer a concrete drive letter (`A:/…`); host uses
  portable `::/…`.
- Smokes may still `#include "/tos/…"` or `/Kernel/…`; prefer `::/…` in new
  guest-facing code. Do not grow new host-only `/Users/…` absolutes.

## 9P / export

Virtfs share letter is **`P:`**. `RVSoftLet9pPlant('P')` / `Virtio9pConnect` plant a
signed soft BlkDev (`FSt_9P`) so `Let2Drv('P')` works; soft `Cd("P:/…")` / `DirNameAbs` stay on
the `::/…` path until a real `Drv()` (same honesty as soft `A:`). Stock `FileRead("P:/…")` goes
through `NinePTryFileRead` → `Virtio9pReadPath` (no explicit client import). `Virtio9pNormSharePath`
/ `NinepNormSharePath` strip `A:` / `P:` / `::` for the host share name. Stock `FilesFind("P:/*")` and nested `FilesFind("P:/dir/*")` list via
`Virtio9pFilesFindMask` (walk + Treaddir multi-dirent + `d_off`). After `Virtio9pConnect`,
`Drv('P')` selects the share so stock `Cd("P:/…")` / DirContext relative `FilesFind("*")` work
(`kernel-virtio-9p-smoke`); plant-only soft Cd stays `::/…` until Connect (`kernel-home-smoke`).

## What “done” looks like

| Milestone | Status |
|-----------|--------|
| Document dual namespaces | **This page** |
| Soft Cd when `!Fs->cur_dv` (Span Load) | **Done** |
| Soft `DirCur`/`Pwd` → `::/…` (pre-mount) | **Done** (`kernel-home-smoke`) |
| Soft `DirNameAbs` → `::/…`; soft `Let2Drv` via `RVSoftLetPlant` (no virtio) | **Done** (`kernel-home-smoke`) |
| Host `__DIR__` / `__FILE__` → `::/…` (tos→ISO) | **Done** |
| Host `#include` `A:` / `::` + `tos/` fallback | **Done** |
| UART `Cd`/`FsResolve` accepts `::` / `A:` / `~` | **Done** (letter = alias) |
| UART `Pwd` prints `::/` | **Done** |
| UART `Cd` log `cwd: ::/` | **Done** (`repl-holyc-smoke`) |
| Real memfs BlkDev letter / `Let2Drv` (Kernel soft) | **Done** (`RVSoftLetPlant`) |
| UART memfs → Kernel `Let2Drv` tables | **Done** (`bootstrap/seed/soft_let.hc`, `hc-repl-smoke`) |
| One Cd/Pwd log story (memfs `cwd:` vs `::/`) | **Done** |
| 9P under drive letter `P:` (`Let2Drv` / soft `Cd`) | **Done** (`RVSoftLet9pPlant`, `kernel-home-smoke`, `kernel-virtio-9p-smoke`, UART SoftLetRep) |
| 9P `FileRead("P:/…")` (no Virtio9pReadPath import) | **Done** (`NinePTryFileRead`, `kernel-virtio-9p-smoke`) |
| 9P `FilesFind("P:/*")` (share root) | **Done** (`Virtio9pFilesFindMask` Treaddir, `kernel-virtio-9p-smoke`) |
| Nested `FilesFind("P:/dir/*")` | **Done** (dir walk + Treaddir, `kernel-virtio-9p-smoke`) |
| DirContext Cd on `FSt_9P` | **Done** (`Virtio9pConnect`→`Drv('P')` + string `NinePCd`, `kernel-virtio-9p-smoke`) |

## See also

- [LAYOUT.md](LAYOUT.md) — `tos/` vs guest `::/`
- [REPL.md](REPL.md) — memfs tree
- [NINEP.md](NINEP.md) — virtfs paths
- [FILE_EXPORT.md](FILE_EXPORT.md) — export path stripping
- [GAPS.md](GAPS.md) — path unification residual
