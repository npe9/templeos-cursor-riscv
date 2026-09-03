# Vendored Linux `scripts/kconfig` (mconf + conf)

Interactive `make menuconfig` uses Linux **mconf** + **lxdialog** (ncurses) — the
same front-end as the kernel. Not Kconfiglib. Not a Python TUI.

## Provenance

| Item | Value |
|------|--------|
| Upstream | Linux **v6.11** `scripts/kconfig/*` + `scripts/include/{list,list_types,hashtable,array_size}.h` |
| License | GPL-2.0 (SPDX in each file) |
| Note | See `ORIGIN.md` |

Kept: `mconf`, `conf`, shared confdata/lexer/parser/symbol/menu/…, `lxdialog/`.
Omitted: `nconf`, `qconf`, `gconf`, `tests/`, Qt/GTK helpers.

**Pregenerated** `lexer.lex.c` / `parser.tab.{c,h}` are checked in so **flex/bison
are not required** to build. Optional regenerate:

```bash
cd templeos-riscv/scripts/kconfig
bison -t -l -o parser.tab.c --defines=parser.tab.h parser.y
flex -L -o lexer.lex.c lexer.l
```

## Host dependencies

| Package | Purpose |
|---------|---------|
| C compiler (`cc` / gcc / clang) | Build `mconf` / `conf` |
| **ncurses** (dev headers + libs) | lxdialog / mconf |
| `pkg-config` (recommended) | Find ncurses; `mconf-cfg.sh` also tries Homebrew + system paths |

```bash
# Debian / Ubuntu
sudo apt install libncurses-dev pkg-config

# Fedora
sudo dnf install ncurses-devel pkgconf-pkg-config

# macOS
brew install ncurses pkg-config
```

## Build / use

```bash
make -C templeos-riscv/scripts/kconfig    # → conf, mconf
make menuconfig                            # from repo root (or templeos-riscv/)
make -C templeos-riscv menuconfig-test     # conf --olddefconfig + mconf link check
make -C templeos-riscv syncconfig          # kconfig.py sync after hand-edits
```

Flow: build `mconf` → `./mconf Kconfig` → write `.config` → `kconfig.py sync`
(emits `autoconf.h`, `RVAutoConf.HH`, `kconfig.mk`, driver selects, MemMap seed).

Build products (`mconf`, `conf`, `*.o`, `mconf-cflags`, `mconf-libs`) are local;
`*.o` is already gitignored at repo root.
