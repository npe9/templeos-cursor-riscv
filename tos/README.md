# TempleOS ISO / home tree (`tos/`)

Upstream TempleOS **system root** content that used to sit at the git repo root
(menus, Home files, Apps, Doc, Misc, …). Kept here so the **port repo root**
stays contributor-shaped (`host/`, `Kernel/`, `Compiler/`, …).

## Layout (mirrors TempleOS `/`)

```
tos/
├── StartOS.HC MakeHome.HC Once.HC Home*.HC
├── PersonalMenu.DD PersonalNotes.DD ReadMe.TXT
├── Apps/ Doc/ Misc/ Linux/ Downloads/ 0000Boot/
└── README.md   # this file
```

At **runtime** on a TempleOS-shaped image, these paths are still `::/StartOS.HC`,
`::/Apps/…`, `::/Doc/…` (ISO root). On **disk in this git repo**, the same
relative cluster lives under `tos/` so it is not mixed with port tooling.

Actively ported trees stay at the **repo root** (not under `tos/`):

- `Kernel/` `Compiler/` `Adam/` `Demo/`

RV StartOS work is `Adam/StartOS_RV.HC` / `Adam/MakeAdam_RV_Core.HC`, not
`tos/StartOS.HC` (x86 reference).

## Note

Do not mass-rename internals inside `tos/` — preserve TempleOS relative
structure (`Apps` beside `Doc` beside `Misc`). HolyC `$LK` / `::/` links are
guest paths; host scripts should use `tos/…`.
