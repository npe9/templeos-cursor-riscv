# Making your own TempleOS Home account

`Demo/AcctExample/` is Terry Davis's own account, shipped inside TempleOS as a worked example. It
is the best documentation there is for how a TempleOS user actually customises the system — and it
does not compile out of the box, because it names a handful of values that lived in *his* `~/` and
were never part of the distribution.

This page is about that gap: which values were personal, what each one did, and how to write your
own. The placeholder set lives in **`tos/HomeAcctExample.HH`** — every value in it is obviously
fake (`lorem.example.invalid`, `ipsum`) so that a value nobody set is recognisable on sight.

## What a Home account is

TempleOS boots, mounts the distribution, and then runs your account out of `/Home`. The account is
ordinary HolyC source; there is no configuration format. `MakeHome.HC` is its makefile:

```
Cd(__DIR__);;
#include "~/HomeLocalize"          // your machine: keyboard, time zone, mouse scaling
#include "/Adam/Opt/Boot/MakeBoot" // the distribution's own pieces
#include "/Adam/Opt/Utils/MakeUtils"
#include "~/HomeWrappers"          // your shorthand commands
MapFileLoad("::/Kernel/Kernel");
MapFileLoad("::/Compiler/Compiler");
#include "~/HomeKeyPlugIns"        // your keys
#include "~/HomeSys"               // what a new task looks like
Cd("..");;
```

`~` is your Home directory. The comment at the top of the shipped `MakeHome.HC` states the rule
that makes this safe to experiment with:

> If these are not present in /Home, it uses the version in the root dir. You can make your own,
> modified, version of these files in your /Home directory.

So you copy only the files you want to change. The distribution ships a plain template of each one
at its root — in this repo they are `tos/HomeLocalize.HC`, `tos/HomeSys.HC`, `tos/HomeWrappers.HC`
and `tos/HomeKeyPlugIns.HC`.

On the host compiler, `~/X` resolves through `HOLYC_HOME_ROOT` (default `/Home`) and then falls
back to the distribution root, mirroring that rule — `host/lexer.c`, `LoadIncludeFile`. Before that,
`#include "~/HomeLocalize"` simply failed, so `MakeHome.HC` could not be read at all.

### The four files, and what each is for

| file | what it decides |
|---|---|
| `HomeLocalize.HC` | Your machine. `KbdTypeMatic(0)` for a fast keyboard, `local_time_offset` for your time zone (TempleOS has no daylight-saving rule — you change it by hand twice a year), `ms_hard.scale` for mouse speed. |
| `HomeSys.HC` | `UserStartUp()` and `SrvStartUp()`, run every time a task is spawned. This is where you decide what a fresh terminal looks like. |
| `HomeWrappers.HC` | Your own short commands. A wrapper is just a HolyC function; typing its name at the prompt runs it. |
| `HomeKeyPlugIns.HC` | Your keys, installed with `KeyDevAdd()`. This file's trailing `KeyDevAdd(...)` is not a demo run — it is the file doing its job, which is why `tools/guard_demo_autoruns.py` leaves it alone. |

## The values that were personal

Five of them, all in `tos/HomeAcctExample.HH`.

| define | what it was | placeholder |
|---|---|---|
| `PERSONAL_WEB` | Where your source is published, so `TOS/TOSToHtml.HC` can turn a `$LK$` doc link into an `<a href>`. | `https://lorem.example.invalid/ipsum` |
| `BLOG_WEB_BASE` | The URL your blog tree becomes once uploaded (`TOS/TOSBlog.HC`). | `https://lorem.example.invalid/ipsum/Blog` |
| `BLOG_LOCAL_BASE` | The local directory that tree is built in. | `B:/Home/Blog` |
| `TOS_HDS` | The drive letters this machine's hard disks answer to, as one string — `"C"` for one disk, `"CD"` for two. `TOS/TOSCfg.HC` normally `DefinePrint()`s it *while the file is compiling*, from the drives actually mounted. | `"C"` |
| `NIST_TIME_OFFSET` | The whole-second correction between a TempleOS `CDATE` and a NIST timestamp — leap seconds plus whatever your time source is out by. | `0` |

`INS_REG_MACHINE_NUM` is there too. It distinguished the machines on one registration;
`Demo/AcctExample/Registry.HC` also defines it as `0`, and the placeholder is for the files that
read it without including that one.

### Why `TOS_HDS` is the interesting one

`DefinePrint("TOS_HDS","\"CD\"")` at the top level of `TOSCfg.HC` runs **during the compile of that
file** and creates a `#define` that the rest of the file then uses. That is normal TempleOS: the
compiler is present at run time, so a program can extend the language while it is being read.

An ahead-of-time compiler never runs it. `tos/HomeAcctExample.HH` names the value instead — which
is also the honest thing for a port, because the host compiler has no idea what disks the target
machine has.

The same shape shows up twice more in the survey and only one of them can be handled this way:

- `RegDft(path,"F64 best_score=9999;\n"); RegExe(path);` — the default text is a literal, so
  `host/parser.c` parses it as declarations at compile time. Eleven stock games depend on it.
- `DefinePrint("UNITS_NUM","%d",4096/SqrI64(rad)&~1)` in `Demo/Games/TreeCheckers.HC`, where `rad`
  comes from a pop-up the user answers. That one is not reachable ahead of time at all.

## What is NOT personal

These also come up undefined in `Demo/AcctExample/`, and giving them placeholder values would
teach the wrong lesson. They are parts of the kernel and of Adam that this port has not brought
over yet:

| symbol | where it belongs |
|---|---|
| `SYS_KERNEL_END`, `SYS_IDLE_PT`, `SYS_RAM_REBOOT_END` | kernel link-time symbols |
| `BDVD_START`, `BMHD2_BLK_ARRAY` | `Adam/Opt/Boot` disk layout |
| `GR_PEN_BRUSHES_NUM`, `GR_SCRN_ZOOM_MAX` | `Adam/Gr` |
| `ins_reg` (`CInsReg`), `InsRereg` | `Adam/Opt/Utils/TOS.HC` install registration |
| `god` (`CGodGlbls`) | `Adam/God/GodExt.HC` — in the tree, not in `Kernel_RV.PRJ` |
| `meter_tops`, `meter_bottoms` | `tos/Apps/Psalmody`, a sibling file of the one being compiled |
| `LK_FILE_LINE`, `LK_PLAIN_LINE` | `Adam/DolDoc/DocLink.HC` — in the tree, not in the PRJ |
| `Touch`, `DocFind`, `DCScrnCapture`, `CRandExtDec5Form` | `Adam/` files, or a sibling of the file being compiled |

`docs/DEMO_SURVEY.md` keeps the current count of each, split by whether the symbol exists in the
tree at all.

`tos/PersonalMenu.DD` and `tos/PersonalNotes.DD` are already generic templates — the first says so
in its own first line ("Copy this file to your `/Home` directory and modify it. This version is the
default."), the second is one sentence. They need no placeholder version.

## Checking your own account

Measured: **not one file in the whole 204-program survey still names any of the six placeholder
values.** Five of the account's nineteen files compile and run — `HomeLocalize.HC`,
`HomeWrappers.HC`, `LightTable.HC`, `TOS/TOSExt.HC`, `TOS/TOSTheme.HC`. The other fourteen each
still need something from the list above, or from a sibling file:

| file | what is left |
|---|---|
| `HomeKeyPlugIns.HC` | `fg_on` — defined in `TOS/TOSMisc.HC`, a sibling |
| `HomeSys.HC` | `CPURep`, `WinTileVert` |
| `Once.HC` | `OnceExe` |
| `Registry.HC` | `ins_reg`, `registry_version`, `sys_msg_flags` |
| `TOS/TOSCfg.HC` | `SYS_KERNEL_END`, and `TOS_DBG_DISTRO` which it computes from it |
| `TOS/TOSMisc.HC` | `JukeSongsPuppet` (Psalmody) |
| `TOS/TOSNIST.HC` | `CRandExtDec5Form` — a class in `TOS/TOSExt.HC`, a sibling |
| `TOS/TOSBlog.HC` | `DCScrnCapture` |
| `TOS/TOSToHtml.HC` | `LK_FILE_LINE` (`Adam/DolDoc/DocLink.HC`), `Touch` |
| `TOS/TOSIns.HC` | `CWebBibleForm` (sibling), `DocFind`, `god` |
| `TOS/TOSHolySpirit.HC` | `CGodVideoForm`, `GBP_LONG` (siblings), `CRandExtDec5Form`, `god` |
| `TOS/TOSDistro.HC` | the `TOS_*` strings `TOSCfg.HC` defines, `DskChkAll`, `AOnceFlush`, `DocMax` |
| `TOS/MakeTOS.HC` | the union of the above |
| `MakeHome.HC` | the `Adam/Opt/Boot` and `Adam/Gr` constants, `InsRereg`, Psalmody's meters |

Notice how many of those are "a sibling file of the same account". A Home account is built as one
unit — `MakeHome.HC` includes `TOSExt`, then `TOSCfg`, then `TOSMisc`, then `TOSDistro`, in that
order — so compiling one file of it on its own is the wrong unit of measurement. The per-file rows
in `docs/DEMO_SURVEY.md` are honest about compiling that file alone and nothing more.

To see it for yourself:

```sh
printf '#include "/Kernel/Kernel_RV.PRJ"\n#include "/tos/HomeAcctExample.HH"\n#define RV_NO_DEMO_AUTORUN\n#include "/Demo/AcctExample/TOS/TOSNIST.HC"\nI64 main(){return 0;}\n' > /tmp/acct.hc
HOLYC_ALL_ERRORS=1 HOLYC_NO_TIER2=1 HOLYC_INCLUDE_ROOT=$PWD ./holyc-riscv /tmp/acct.hc -o /dev/null
```

`TOSNIST.HC` goes from `NIST_TIME_OFFSET` and `CRandExtDec5Form` down to `CRandExtDec5Form` alone —
and that one is a class defined in `TOS/TOSExt.HC`, a sibling file, not anything you have to write.

`tools/survey_demo_one.sh` includes the placeholder header for `Demo/AcctExample/**` and nothing
else, so an L0 change in that directory is partly this header rather than port progress.

To start your own account, copy the four templates and this header into your `/Home`, `#include`
the header from your `~/HomeLocalize`, and change the values. Nothing in the placeholder set is
Terry's.
