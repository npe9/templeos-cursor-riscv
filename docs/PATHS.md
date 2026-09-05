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

`DirCur` prints `A:/path`. Guest `StreamDir` / `#define __DIR__` follow the include
file’s drive-letter abs path.

## UART memfs bridge (partial unification)

Internal names stay hierarchical slash paths (`Home/…`, `Tutorials/…`) — no letter
device. Bridge in `FsResolve`:

| Input | Resolves as |
|-------|-------------|
| `::/Tutorials`, `:/Tutorials` | absolute `Tutorials/` |
| `A:/Home`, `Z:/…` | absolute (letter ignored; one memfs) |
| `~`, `~/Work` | `Home/`, `Home/Work/` |
| `/Tutorials`, `Tutorials` | unchanged (absolute / cwd-relative) |

`Pwd` prints TempleOS boot-root form: `::/Home/Work/`.  
`Cd` still logs `cwd: /Home/Work/` (smoke-stable memfs form).

## Host AOT adapter

`HOLYC_INCLUDE_ROOT` = repo root. Includes:

| Written | Tries |
|---------|-------|
| `/Kernel/…`, `::/Kernel/…`, `A:/Kernel/…` | `$ROOT/Kernel/…` |
| `::/Apps/…`, `A:/Apps/…` | `$ROOT/Apps/…` then **`$ROOT/tos/Apps/…`** |
| `/tos/Apps/…` | `$ROOT/tos/Apps/…` (host layout escape hatch) |
| relative | directory of current file |

`__DIR__` / `__FILE__` (host builtins; guest uses `#exe{StreamDir;}`):

- Emit **`/…`** under the include root (not raw `/Users/…`).
- **Keep** a leading repo `tos/` in `__DIR__` (`/tos/Apps/Span`) — stripping to
  `/Apps/Span` makes pre-mount AOT `Cd(__DIR__)` hang in RedSeaCd; `/tos/…` fails fast.
- Relative compile paths (`Demo/Foo.HC`) count as already under the include root.
- Guest `StreamDir` still emits drive-letter paths (`A:/…` / `::/…`).
- `#include "::/Apps/…"` still resolves via `$ROOT/tos/Apps/…` (include adapter only).

Smokes may still `#include "/tos/…"` or `/Kernel/…`; prefer `::/…` in new guest-facing
code. Do not grow new host-only `/Users/…` absolutes.

## 9P / export

Virtfs share paths are **not** a BlkDev letter yet. `Virtio9pNormSharePath` /
`NinepNormSharePath` strip `A:` / `::` for the host share name. Mount-as-`P:` (or
import into `A:/Host/…`) is future work — see [NINEP.md](NINEP.md).

## What “done” looks like

| Milestone | Status |
|-----------|--------|
| Document dual namespaces | **This page** |
| Host `__DIR__` / `__FILE__` TempleOS-shaped | **Partial** (`/` under include root; keeps `tos/` for Cd-before-mount) |
| Host `#include` `A:` / `::` + `tos/` fallback | **Partial** |
| UART `Cd`/`FsResolve` accepts `::` / `A:` / `~` | **Partial** |
| UART `Pwd` prints `::/` | **Partial** |
| One Cd/Pwd story on all product shells (memfs = BlkDev) | Open |
| 9P under a drive letter | Open |

## See also

- [LAYOUT.md](LAYOUT.md) — `tos/` vs guest `::/`
- [REPL.md](REPL.md) — memfs tree
- [NINEP.md](NINEP.md) — virtfs paths
- [FILE_EXPORT.md](FILE_EXPORT.md) — export path stripping
- [GAPS.md](GAPS.md) — path unification residual
