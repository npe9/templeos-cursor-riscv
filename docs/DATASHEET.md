# Datasheet bitfield format (UART REPL)

OS-owned register field tables the REPL can query live — not a static PDF.
Engine: [`bootstrap/seed/ds.hc`](../bootstrap/seed/ds.hc). Sheets:
[`bootstrap/seed/datasheet/`](../bootstrap/seed/datasheet/) (memfs `Doc/Datasheet/ds_uart.hc`,
…; `Run("ds_uart.hc")` still works by basename).

## REPL commands

| Call | Effect |
|------|--------|
| `DsFind("uart");` / `DsFind("");` | List matching / all register ids |
| `DsShow("mstatus");` | Field legend (bit ranges + enums), no value |
| `DsDecode("mstatus");` | Live peek (`CSRGet` / MMIO) + decode |
| `DsDecode("uart.lsr", 0x21);` | Decode a given value |
| `Bits("mie");` | Alias of `DsDecode` |
| `DsFieldGet("uart.lsr","THRE",0x21);` | Extract one field (returns `I64`) |
| `DsHelp;` / `Man("Datasheet");` | Cheat sheet / topic page |

## Sheet authoring (HolyC)

Each register is registered at load time:

```holyc
DsBegin("uart.lsr", "uart", DS_KIND_MMIO, MEM_UART + UART_LSR_OFF, 1);
DsField("DR", 0, 0, "0=empty,1=data", "Receiver data ready");
DsField("THRE", 5, 5, "0=full,1=empty", "TX holding empty");
DsEnd;
```

| Piece | Meaning |
|-------|---------|
| `id` | Lookup key (`"mstatus"`, `"uart.lsr"`, `"plic.claim"`) |
| `device` | Group for `DsFind` (`"csr"`, `"uart"`, `"clint"`, `"plic"`) |
| `kind` | `DS_KIND_CSR` → `CSRGet(addr)`; `DS_KIND_MMIO` → peek `width` bytes at `addr` |
| `addr` | CSR number (`CSR_MSTATUS`) or absolute MMIO (`MEM_UART+5`) |
| `width` | MMIO access size: `1` / `4` / `8` |
| `DsField(name, lo, hi, enums=0, note=0)` | Inclusive bit range; `enums` is `"val=sym,…"` |

`DsBegin` **replaces** an existing id, so `Run("ds_uart.hc");` after an edit is safe.

Keep each sheet file under ~256 lines; split by device.

## Decode output shape

```
DsDecode uart.lsr  = 0x21  (33)
  MMIO 0x10000005
  [0] DR = 1  data
  [5] THRE = 1  empty
  …
```

Whole value as hex and decimal; each known field shows bit range, raw bits, and
symbolic enum text when defined.

## Boot / rebuild

Sheets load after `csr.hc` (see `gen_boot_blob.py` `BOOT_ORDER`). After edits:

```bash
make hc-repl                              # rebuild the guest image with the new sheets
# seed blob headers only: make repl-blob   (= make -C bootstrap -f Makefile.repl)
```

## Related

- [REPL.md](REPL.md) — interactive overview
- `Man("Datasheet")` / `Man("UART")` / `Man("CLINT")` / `Man("CSR")`
- `Reg("mstatus")` — single-value dig-down; `Bits` adds field symbolism
