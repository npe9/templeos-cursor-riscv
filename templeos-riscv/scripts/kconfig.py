#!/usr/bin/env python3
"""Minimal Kconfig sync for TempleOS/RISC-V.

Parser/sync for .config → autoconf.h / RVAutoConf.HH / MemMap / kconfig.mk.
Interactive UI is Linux's real mconf + lxdialog (vendored under scripts/kconfig/),
built with a C compiler + ncurses — see `make menuconfig`.

Supports (Linux Kconfig subset used by this tree): mainmenu, source, menu/endmenu,
choice/endchoice, config (bool/hex/int/string), default (with optional `if`),
depends on, help.

Commands:
  defconfig [FILE]   apply configs/*_defconfig or named file (default: virt_defconfig)
  olddefconfig       fill missing symbols from defaults using current .config
  menuconfig         run vendored mconf (TTY); then sync (prefer: make menuconfig)
  menuconfig-test    build/run Linux conf --olddefconfig sanity check
  sync               rewrite autoconf headers from .config
  qemu-args [M]      print suggested qemu args from .config, or resolve M's defconfig
                     without writing global headers (multi-kernel / docs)
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent  # templeos-riscv/
REPO = ROOT.parent
CONFIG_PATH = ROOT / ".config"
AUTOCONF_H = ROOT / "include" / "generated" / "autoconf.h"
AUTOCONF_HC = REPO / "Kernel" / "RVAutoConf.HH"
KCONFIG_MK = ROOT / "include" / "generated" / "kconfig.mk"
DEFCONFIG_DIR = ROOT / "configs"


@dataclass
class Symbol:
    name: str
    type: str = "bool"  # bool | hex | int | string
    prompt: Optional[str] = None
    defaults: List[Tuple[str, Optional[str]]] = field(default_factory=list)  # (value, cond)
    depends: List[str] = field(default_factory=list)
    help: str = ""
    choice: Optional[str] = None  # choice group id
    value: Any = None


@dataclass
class Choice:
    id: str
    prompt: str
    members: List[str] = field(default_factory=list)
    default: Optional[str] = None
    default_conds: List[Tuple[str, Optional[str]]] = field(default_factory=list)


@dataclass
class Menu:
    prompt: str
    symbols: List[str] = field(default_factory=list)
    choices: List[str] = field(default_factory=list)
    children: List["Menu"] = field(default_factory=list)


class Kconfig:
    def __init__(self) -> None:
        self.symbols: Dict[str, Symbol] = {}
        self.choices: Dict[str, Choice] = {}
        self.menus: List[Menu] = []
        self.root_items: List[Tuple[str, Any]] = []
        self.mainmenu = "Configuration"
        self._choice_seq = 0
        self._order: List[str] = []

    def parse_file(self, path: Path, base: Path) -> None:
        text = path.read_text()
        lines = text.splitlines()
        i = 0
        menu_stack: List[Menu] = []
        cur_sym: Optional[Symbol] = None
        cur_choice: Optional[Choice] = None
        in_help = False
        help_lines: List[str] = []

        def flush_help() -> None:
            nonlocal in_help, help_lines, cur_sym
            if in_help and cur_sym is not None:
                cur_sym.help = "\n".join(help_lines).strip()
            in_help = False
            help_lines = []

        while i < len(lines):
            raw = lines[i]
            line = raw.split("#", 1)[0].rstrip()
            if in_help:
                if raw.startswith("\t") or raw.startswith(" ") or raw.strip() == "":
                    help_lines.append(raw.strip())
                    i += 1
                    continue
                flush_help()

            s = line.strip()
            if not s:
                i += 1
                continue

            if s.startswith("mainmenu "):
                self.mainmenu = s[len("mainmenu ") :].strip().strip('"')
                i += 1
                continue

            if s.startswith("source "):
                rel = s[len("source ") :].strip().strip('"')
                self.parse_file(base / rel, base)
                i += 1
                continue

            if s.startswith("menu "):
                flush_help()
                m = Menu(prompt=s[len("menu ") :].strip().strip('"'))
                if menu_stack:
                    menu_stack[-1].children.append(m)
                else:
                    self.root_items.append(("menu", m))
                menu_stack.append(m)
                self.menus.append(m)
                cur_sym = None
                i += 1
                continue

            if s == "endmenu":
                flush_help()
                if menu_stack:
                    menu_stack.pop()
                cur_sym = None
                i += 1
                continue

            if s.startswith("choice"):
                flush_help()
                self._choice_seq += 1
                cid = f"choice_{self._choice_seq}"
                cur_choice = Choice(id=cid, prompt="")
                self.choices[cid] = cur_choice
                if menu_stack:
                    menu_stack[-1].choices.append(cid)
                else:
                    self.root_items.append(("choice", cid))
                cur_sym = None
                i += 1
                continue

            if s == "endchoice":
                flush_help()
                cur_choice = None
                cur_sym = None
                i += 1
                continue

            if s.startswith("config "):
                flush_help()
                name = s.split(None, 1)[1].strip()
                cur_sym = Symbol(name=name)
                self.symbols[name] = cur_sym
                self._order.append(name)
                if cur_choice is not None:
                    cur_sym.choice = cur_choice.id
                    cur_sym.type = "bool"
                    cur_choice.members.append(name)
                if menu_stack:
                    menu_stack[-1].symbols.append(name)
                elif cur_choice is None:
                    self.root_items.append(("sym", name))
                i += 1
                continue

            if cur_sym is None and cur_choice is None:
                i += 1
                continue

            # Inside config / choice body
            if s.startswith("bool"):
                rest = s[4:].strip()
                if cur_sym:
                    cur_sym.type = "bool"
                    if rest.startswith('"'):
                        cur_sym.prompt = _parse_string(rest)
                i += 1
                continue
            if s.startswith("hex"):
                rest = s[3:].strip()
                if cur_sym:
                    cur_sym.type = "hex"
                    if rest.startswith('"'):
                        cur_sym.prompt = _parse_string(rest)
                i += 1
                continue
            if s.startswith("int"):
                rest = s[3:].strip()
                if cur_sym:
                    cur_sym.type = "int"
                    if rest.startswith('"'):
                        cur_sym.prompt = _parse_string(rest)
                i += 1
                continue
            if s.startswith("string"):
                rest = s[6:].strip()
                if cur_sym:
                    cur_sym.type = "string"
                    if rest.startswith('"'):
                        cur_sym.prompt = _parse_string(rest)
                i += 1
                continue
            if s.startswith("prompt "):
                p = _parse_string(s[len("prompt ") :].strip())
                if cur_choice is not None and cur_sym is None:
                    cur_choice.prompt = p
                elif cur_sym is not None:
                    cur_sym.prompt = p
                i += 1
                continue
            if s.startswith("default "):
                body = s[len("default ") :].strip()
                val, cond = _split_if(body)
                if cur_choice is not None and cur_sym is None:
                    # default SYMBOL [if COND]
                    sym_name = val.strip()
                    cur_choice.default_conds.append((sym_name, cond))
                    if cond is None and cur_choice.default is None:
                        cur_choice.default = sym_name
                elif cur_sym is not None:
                    cur_sym.defaults.append((val.strip().strip('"'), cond))
                i += 1
                continue
            if s.startswith("depends on "):
                expr = s[len("depends on ") :].strip()
                if cur_sym is not None:
                    cur_sym.depends.append(expr)
                i += 1
                continue
            if s == "help" or s.startswith("help"):
                in_help = True
                help_lines = []
                i += 1
                continue

            i += 1

        flush_help()


def _parse_string(s: str) -> str:
    s = s.strip()
    if s.startswith('"'):
        m = re.match(r'"((?:[^"\\]|\\.)*)"', s)
        if m:
            return m.group(1)
    return s


def _split_if(body: str) -> Tuple[str, Optional[str]]:
    # value if COND  — COND may contain || &&
    m = re.search(r"\s+if\s+", body)
    if not m:
        return body.strip(), None
    return body[: m.start()].strip(), body[m.end() :].strip()


def _tokenize_cond(expr: Optional[str], vals: Dict[str, Any]) -> bool:
    if expr is None:
        return True
    # Replace symbol names with True/False/value then eval carefully
    e = expr
    # Normalize
    e = e.replace("||", " or ").replace("&&", " and ").replace("!", " not ")

    def repl(m: re.Match) -> str:
        name = m.group(0)
        if name in ("or", "and", "not"):
            return name
        v = vals.get(name)
        if isinstance(v, bool):
            return "True" if v else "False"
        if v is None:
            return "False"
        # non-bool presence
        if isinstance(v, str):
            return "True" if v else "False"
        return "True" if v else "False"

    e2 = re.sub(r"[A-Za-z_][A-Za-z0-9_]*", repl, e)
    try:
        return bool(eval(e2, {"__builtins__": {}}, {}))
    except Exception:
        return False


def load_kconfig() -> Kconfig:
    k = Kconfig()
    k.parse_file(ROOT / "Kconfig", ROOT)
    return k


def read_config_file(path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            # "# CONFIG_FOO is not set"
            m = re.match(r"# CONFIG_(\w+) is not set", line)
            if m:
                out[m.group(1)] = "n"
            continue
        m = re.match(r"CONFIG_(\w+)=(.*)", line)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def write_config_file(path: Path, vals: Dict[str, Any], order: List[str], symbols: Dict[str, Symbol]) -> None:
    lines = [
        "#",
        "# TempleOS/RISC-V platform configuration (generated — do not edit by hand;",
        "# use: make menuconfig / make -C templeos-riscv defconfig)",
        "#",
        "",
    ]
    seen = set()
    for name in order:
        if name not in vals:
            continue
        seen.add(name)
        sym = symbols[name]
        v = vals[name]
        if sym.type == "bool":
            if v is True or v == "y":
                lines.append(f"CONFIG_{name}=y")
            else:
                lines.append(f"# CONFIG_{name} is not set")
        elif sym.type == "string":
            s = str(v).strip('"')
            lines.append(f'CONFIG_{name}="{s}"')
        elif sym.type == "hex":
            if isinstance(v, str) and v.startswith("0x"):
                lines.append(f"CONFIG_{name}={v}")
            else:
                lines.append(f"CONFIG_{name}={_fmt_hex(v)}")
        else:
            lines.append(f"CONFIG_{name}={v}")
    for name, v in vals.items():
        if name in seen or name not in symbols:
            continue
        sym = symbols[name]
        if sym.type == "bool":
            lines.append(f"CONFIG_{name}=y" if v in (True, "y") else f"# CONFIG_{name} is not set")
        else:
            lines.append(f"CONFIG_{name}={v}")
    path.write_text("\n".join(lines) + "\n")


def _fmt_hex(v: Any) -> str:
    if isinstance(v, str):
        v = v.strip().strip('"')
        if v.startswith("0x") or v.startswith("0X"):
            return "0x" + v[2:].upper()
        try:
            return f"0x{int(v, 0):X}"
        except ValueError:
            return v
    return f"0x{int(v):X}"


def _parse_val(sym: Symbol, raw: str) -> Any:
    raw = raw.strip().strip('"')
    if sym.type == "bool":
        return raw in ("y", "Y", "1", "true", "True")
    if sym.type == "hex":
        return _fmt_hex(raw)
    if sym.type == "int":
        return str(int(raw, 0))
    return raw


def resolve_defaults(k: Kconfig, preset: Dict[str, str]) -> Dict[str, Any]:
    vals: Dict[str, Any] = {}

    # Seed from preset (defconfig / .config)
    for name, raw in preset.items():
        if name in k.symbols:
            vals[name] = _parse_val(k.symbols[name], raw)

    # Resolve choices: ensure exactly one member is y
    for ch in k.choices.values():
        selected = None
        for m in ch.members:
            if vals.get(m) is True:
                selected = m
                break
        if selected is None:
            # pick default from conditions
            for sym_name, cond in ch.default_conds:
                # evaluate cond with current bools
                if _tokenize_eval_choice_default(cond, vals, k):
                    selected = sym_name
                    break
            if selected is None:
                selected = ch.default or (ch.members[0] if ch.members else None)
        for m in ch.members:
            vals[m] = m == selected

    # Multi-pass defaults for non-choice symbols
    for _ in range(8):
        changed = False
        for name in k._order:
            sym = k.symbols[name]
            if sym.choice:
                continue
            if name in vals and name in preset:
                continue  # keep preset
            # depends
            deps_ok = all(_tokenize_cond(d, vals) for d in sym.depends) if sym.depends else True
            if not deps_ok:
                if sym.type == "bool":
                    if vals.get(name) is not False:
                        vals[name] = False
                        changed = True
                continue
            if name in vals and preset.get(name) is not None:
                continue
            # find first matching default
            chosen = None
            for dval, cond in sym.defaults:
                if _tokenize_eval_choice_default(cond, vals, k):
                    chosen = dval
                    break
            if chosen is None:
                if sym.type == "bool":
                    chosen = "n"
                elif sym.type == "hex":
                    chosen = "0x0"
                elif sym.type == "int":
                    chosen = "0"
                else:
                    chosen = ""
            # Symbol-ref defaults (e.g. `default ENTRY_POINT` for hex)
            if (
                isinstance(chosen, str)
                and chosen in k.symbols
                and chosen != name
                and not chosen.startswith("0x")
                and not chosen.startswith("0X")
                and not (chosen[:1].isdigit() if chosen else False)
                and not chosen.startswith('"')
            ):
                if chosen not in vals:
                    continue  # wait for multi-pass until ref is resolved
                ref = vals[chosen]
                if sym.type == "hex":
                    newv = _fmt_hex(ref)
                elif sym.type == "string":
                    newv = str(ref).strip('"')
                elif sym.type == "int":
                    newv = str(int(str(ref).strip('"'), 0)) if not isinstance(ref, bool) else "0"
                else:
                    newv = _parse_val(sym, str(ref))
            else:
                newv = _parse_val(sym, chosen)
            if vals.get(name) != newv:
                vals[name] = newv
                changed = True
        if not changed:
            break

    # Re-assert choice exclusivity
    for ch in k.choices.values():
        selected = None
        for m in ch.members:
            if vals.get(m) is True:
                selected = m
                break
        if selected is None and ch.members:
            selected = ch.members[0]
        for m in ch.members:
            vals[m] = m == selected

    return vals


def _tokenize_eval_choice_default(cond: Optional[str], vals: Dict[str, Any], k: Kconfig) -> bool:
    if cond is None:
        return True
    return _tokenize_cond(cond, vals)


def write_autoconf(vals: Dict[str, Any], symbols: Dict[str, Symbol]) -> None:
    AUTOCONF_H.parent.mkdir(parents=True, exist_ok=True)
    h_lines = [
        "/* Generated by templeos-riscv/scripts/kconfig.py — do not edit. */",
        "#ifndef TOS_RV_AUTOCONF_H",
        "#define TOS_RV_AUTOCONF_H",
        "",
    ]
    hc_lines = [
        "// Generated by templeos-riscv/scripts/kconfig.py — do not edit.",
        "// Include early from Kernel_RV.PRJ (platform addresses + driver selects).",
        "#ifndef TOS_RV_AUTOCONF_HH",
        "#define TOS_RV_AUTOCONF_HH",
        "",
    ]

    def emit(name: str, sym: Symbol, v: Any) -> None:
        if sym.type == "bool":
            if v is True or v == "y":
                h_lines.append(f"#define CONFIG_{name} 1")
                hc_lines.append(f"#define CONFIG_{name} 1")
            return
        if sym.type == "string":
            s = str(v).strip('"')
            h_lines.append(f'#define CONFIG_{name} "{s}"')
            hc_lines.append(f'#define CONFIG_{name} "{s}"')
            return
        if sym.type == "hex":
            hx = _fmt_hex(v)
            h_lines.append(f"#define CONFIG_{name} {hx}")
            hc_lines.append(f"#define CONFIG_{name} {hx}")
            # Convenience without CONFIG_ prefix for common HolyC macros
            return
        h_lines.append(f"#define CONFIG_{name} {v}")
        hc_lines.append(f"#define CONFIG_{name} {v}")

    for name, sym in symbols.items():
        if name in vals:
            emit(name, sym, vals[name])

    # Friendly aliases used by drivers
    aliases = [
        ("CONFIG_UART_BASE", "RV_CFG_UART_BASE"),
        ("CONFIG_CLINT_BASE", "RV_CFG_CLINT_BASE"),
        ("CONFIG_PLIC_BASE", "RV_CFG_PLIC_BASE"),
        ("CONFIG_VIRTIO_MMIO_BASE", "RV_CFG_VIRTIO_MMIO_BASE"),
        ("CONFIG_VIRTIO_MMIO_IRQ_BASE", "RV_CFG_VIRTIO_MMIO_IRQ_BASE"),
        ("CONFIG_VIRTIO_DRV_RAM_BASE", "RV_CFG_VIRTIO_DRV_RAM_BASE"),
        ("CONFIG_FW_CFG_BASE", "RV_CFG_FW_CFG_BASE"),
        ("CONFIG_RTC_BASE", "RV_CFG_RTC_BASE"),
        ("CONFIG_ENTRY_POINT", "RV_CFG_ENTRY_POINT"),
        ("CONFIG_KERNEL_ENTRY", "RV_CFG_KERNEL_ENTRY"),
        ("CONFIG_KERNEL_LINK_ADDR", "RV_CFG_KERNEL_LINK_ADDR"),
        ("CONFIG_DRAM_BASE", "RV_CFG_DRAM_BASE"),
        ("CONFIG_RISCV_ISA", "RV_CFG_RISCV_ISA"),
        ("CONFIG_RISCV_ABI", "RV_CFG_RISCV_ABI"),
        ("CONFIG_SYS_FIXED_AREA", "RV_CFG_SYS_FIXED_AREA"),
        ("CONFIG_FB_SOFT_BASE", "RV_CFG_FB_SOFT_BASE"),
        ("CONFIG_HEAP_BASE", "RV_CFG_HEAP_BASE"),
        ("CONFIG_MEMFS_BASE", "RV_CFG_MEMFS_BASE"),
        ("CONFIG_HOST_SLOTS_BASE", "RV_CFG_HOST_SLOTS_BASE"),
        ("CONFIG_SMP_MAILBOX_BASE", "RV_CFG_SMP_MAILBOX_BASE"),
        ("CONFIG_STACK_BASE", "RV_CFG_STACK_BASE"),
    ]
    h_lines.append("")
    hc_lines.append("")
    for src, dst in aliases:
        # strip CONFIG_ from name key
        key = src[len("CONFIG_") :]
        if key in vals and symbols[key].type != "bool":
            h_lines.append(f"#define {dst} CONFIG_{key}")
            hc_lines.append(f"#define {dst} CONFIG_{key}")

    # Seed-style MEM_* aliases for Kernel demos that still speak MemMap language
    mem_aliases = [
        ("UART_BASE", "MEM_UART"),
        ("CLINT_BASE", "MEM_CLINT"),
        ("PLIC_BASE", "MEM_PLIC"),
        ("VIRTIO_MMIO_BASE", "MEM_VIRTIO"),
        ("FW_CFG_BASE", "MEM_FW_CFG"),
        ("RTC_BASE", "MEM_RTC"),
        ("DRAM_BASE", "MEM_RAM"),
        ("SYS_FIXED_AREA", "MEM_FIXED"),
        ("FB_SOFT_BASE", "MEM_FB"),
        ("HEAP_BASE", "MEM_HEAP"),
        ("MEMFS_BASE", "MEM_FS"),
        ("HOST_SLOTS_BASE", "MEM_HOST_SLOTS"),
        ("STACK_BASE", "MEM_STACK"),
        ("SIFIVE_TEST_BASE", "MEM_TEST"),
        ("SIFIVE_GPIO_BASE", "MEM_GPIO"),
        ("SIFIVE_UART1_BASE", "MEM_UART1"),
        ("SIFIVE_PRCI_BASE", "MEM_PRCI"),
        ("SIFIVE_ETH_BASE", "MEM_ETH"),
    ]
    for key, dst in mem_aliases:
        if key in vals and symbols.get(key) and symbols[key].type == "hex":
            h_lines.append(f"#define {dst} CONFIG_{key}")
            hc_lines.append(f"#define {dst} CONFIG_{key}")

    # RISCV_VIRT kept for existing #ifdef RISCV_VIRT sites (legacy; RTC uses CONFIG_HAS_GOLDFISH_RTC)
    if vals.get("PLATFORM_VIRT"):
        h_lines.append("#define RISCV_VIRT 1")
        hc_lines.append("#define RISCV_VIRT 1")
    else:
        h_lines.append("/* RISCV_VIRT unset — non-virt platform */")
        hc_lines.append("// RISCV_VIRT unset — non-virt platform")

    h_lines += ["", "#endif /* TOS_RV_AUTOCONF_H */", ""]
    hc_lines += ["", "#endif", ""]
    AUTOCONF_H.write_text("\n".join(h_lines))
    AUTOCONF_HC.write_text("\n".join(hc_lines))
    write_drv_selecteds(vals)
    write_editor_selected(vals)
    write_memmap_selected(vals)
    write_kconfig_mk(vals)


def write_kconfig_mk(vals: Dict[str, Any]) -> None:
    """Make + shell-friendly variables from .config (KEY=value, no spaces).

    Sourced by build_kernel_plat.sh; included by Makefiles.
    """
    KCONFIG_MK.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Generated by templeos-riscv/scripts/kconfig.py — do not edit.",
        "# Format: KEY=value (Make include + shell `source` both work).",
        "",
    ]
    if vals.get("OUTPUT_FORMAT_FIRMWARE"):
        lines.append("CONFIG_OUTPUT_FORMAT_FIRMWARE=y")
        lines.append("OUTPUT_FORMAT=firmware")
    else:
        lines.append("OUTPUT_FORMAT=elf")
    lines.append(f"FLASH_BASE={_fmt_hex(vals.get('FLASH_BASE', '0x20000000'))}")
    lines.append(f"PFLASH_SIZE={_fmt_hex(vals.get('PFLASH_SIZE', '0x02000000'))}")
    entry = (
        vals.get("ENTRY_POINT")
        or vals.get("KERNEL_ENTRY")
        or vals.get("KERNEL_LINK_ADDR")
        or vals.get("DRAM_BASE")
        or "0x80000000"
    )
    entry_h = _fmt_hex(entry)
    ram = vals.get("KERNEL_LINK_ADDR") or entry
    lines.append(f"ENTRY_POINT={entry_h}")
    lines.append(f"LOAD_BASE={entry_h}")
    lines.append(f"RAM_BASE={_fmt_hex(ram)}")
    if vals.get("BOOT_SPLIT"):
        lines.append("CONFIG_BOOT_SPLIT=y")
        lines.append("BOOT_SPLIT=y")
        bl_base = vals.get("BOOTLOADER_BASE") or "0x20000000"
        lines.append(f"BOOTLOADER_BASE={_fmt_hex(bl_base)}")
        if vals.get("BOOT_MODE_COPY"):
            lines.append("CONFIG_BOOT_MODE_COPY=y")
            lines.append("BOOT_MODE_COPY=y")
            lines.append("BOOT_MODE=copy")
        else:
            lines.append("CONFIG_BOOT_MODE_JUMP=y")
            lines.append("BOOT_MODE_JUMP=y")
            lines.append("BOOT_MODE=jump")
    else:
        lines.append(f"BOOTLOADER_BASE={_fmt_hex(vals.get('BOOTLOADER_BASE', '0x20000000'))}")
        lines.append("BOOT_MODE=jump")
    isa = str(vals.get("RISCV_ISA", "rv64imafdc")).strip().strip('"') or "rv64imafdc"
    abi = str(vals.get("RISCV_ABI", "lp64d")).strip().strip('"') or "lp64d"
    lines.append(f"RISCV_ISA={isa}")
    lines.append(f"RISCV_ABI={abi}")
    lines.append(f"MARCH={isa}")
    lines.append(f"MABI={abi}")
    if vals.get("ARCH_RISCV32"):
        lines.append("ARCH_BITS=32")
        lines.append("CONFIG_ARCH_RISCV32=y")
    else:
        lines.append("ARCH_BITS=64")
        lines.append("CONFIG_ARCH_RISCV64=y")
    lines.append("")
    KCONFIG_MK.write_text("\n".join(lines))


def _hex_int(vals: Dict[str, Any], key: str, default: int = 0) -> int:
    v = vals.get(key)
    if v is None or v == "":
        return default
    if isinstance(v, str):
        return int(v.strip().strip('"'), 0)
    return int(v)


def _mem_hex(n: int) -> str:
    """Board addresses as 0x######## (match RVAutoConf / historical csr.hc padding)."""
    hx = f"{n:X}"
    if len(hx) < 8:
        hx = hx.zfill(8)
    return "0x" + hx


def write_memmap_selected(vals: Dict[str, Any]) -> None:
    """REPL seed MEM_* / MemMapDrv strings from the active Kconfig board profile.

    Concrete hex #defines (not CONFIG_* aliases) so Tab completion / SymDefineHash
    and uart.hc / datasheet sheets see the same numbers as Kernel/RVAutoConf.HH.
    Rewritten by defconfig / menuconfig / syncconfig; rebuild repl.elf after flip.
    """
    seed = REPO / "bootstrap" / "seed" / "MemMapSelected.hc"
    plat = str(vals.get("PLATFORM_NAME", "unknown")).strip('"')

    uart = _hex_int(vals, "UART_BASE")
    clint = _hex_int(vals, "CLINT_BASE")
    mtime_off = _hex_int(vals, "CLINT_MTIME_OFF", 0xBFF8)
    mtimecmp_off = _hex_int(vals, "CLINT_MTIMECMP_OFF", 0x4000)
    if vals.get("HAS_XPS_TIMER"):
        clint = _hex_int(vals, "XPS_TIMER_BASE", 0x41C00000)
        mtime_off = 0
        mtimecmp_off = 0x10  # Timer1 TCSR (one-shot arm legend)
    plic = _hex_int(vals, "PLIC_BASE") if vals.get("HAS_PLIC") else 0
    plic_en = _hex_int(vals, "PLIC_ENABLE_OFF", 0x2000) if vals.get("HAS_PLIC") else 0
    plic_thr = _hex_int(vals, "PLIC_THRESHOLD_OFF", 0x200000) if vals.get("HAS_PLIC") else 0
    plic_claim = _hex_int(vals, "PLIC_CLAIM_OFF", 0x200004) if vals.get("HAS_PLIC") else 0
    if vals.get("HAS_XPS_INTC"):
        plic = _hex_int(vals, "XPS_INTC_BASE", 0x41200000)
        plic_en = 0x10  # SIE
        plic_thr = 0
        plic_claim = 0x18  # IVR / IAR adjacent legend
    virtio = _hex_int(vals, "VIRTIO_MMIO_BASE") if vals.get("HAS_VIRTIO_MMIO") else 0
    virtio_stride = _hex_int(vals, "VIRTIO_MMIO_STRIDE", 0x1000) if vals.get("HAS_VIRTIO_MMIO") else 0
    fw_cfg = _hex_int(vals, "FW_CFG_BASE") if vals.get("HAS_FW_CFG") else 0
    rtc = _hex_int(vals, "RTC_BASE") if vals.get("HAS_GOLDFISH_RTC") else 0
    ram = _hex_int(vals, "DRAM_BASE", 0x80000000)
    fixed = _hex_int(vals, "SYS_FIXED_AREA", 0x87000000)
    fb = _hex_int(vals, "FB_SOFT_BASE", 0x86100000)
    heap = _hex_int(vals, "HEAP_BASE", 0x86000000)
    memfs = _hex_int(vals, "MEMFS_BASE", 0x87800000)
    host_slots = _hex_int(vals, "HOST_SLOTS_BASE", 0x87001000)
    stack = _hex_int(vals, "STACK_BASE", 0x87F00000)
    test = _hex_int(vals, "SIFIVE_TEST_BASE")
    gpio = _hex_int(vals, "SIFIVE_GPIO_BASE")
    uart1 = _hex_int(vals, "SIFIVE_UART1_BASE")
    prci = _hex_int(vals, "SIFIVE_PRCI_BASE")
    eth = _hex_int(vals, "SIFIVE_ETH_BASE")

    if vals.get("UART_SIFIVE"):
        drv_uart = "RVSifivePlat / uart.hc"
        drv_clint = "RVSifivePlat / RVTimer"
        drv_plic = "RVSifivePlat / RVPlicHw" if vals.get("HAS_PLIC") else "RVPlicStub"
    elif vals.get("UART_HTIF"):
        drv_uart = "RVUartHtif / uart.hc"
        drv_clint = "RVTimer / CLINT"
        drv_plic = "RVPlicHw" if vals.get("HAS_PLIC") else "RVPlicStub"
    elif vals.get("UART_SHAKTI"):
        drv_uart = "RVUartShakti / uart.hc"
        drv_clint = "RVTimer / CLINT"
        drv_plic = "RVPlicHw" if vals.get("HAS_PLIC") else "RVPlicStub"
    elif vals.get("UART_UARTLITE"):
        drv_uart = "RVUartUartlite / uart.hc"
        if vals.get("HAS_XPS_TIMER"):
            drv_clint = "RVTimerXps"
        elif vals.get("HAS_IBEX_TIMER"):
            drv_clint = "RVTimerIbex"
        elif vals.get("HAS_CLINT", True):
            drv_clint = "RVTimer / CLINT"
        else:
            drv_clint = "RVTimerStub"
        if vals.get("HAS_XPS_INTC"):
            drv_plic = "RVPlicXps"
        elif vals.get("HAS_PLIC"):
            drv_plic = "RVPlicHw"
        else:
            drv_plic = "RVPlicStub"
    elif vals.get("UART_IBEX"):
        drv_uart = "RVUartIbex / uart.hc"
        if vals.get("HAS_IBEX_TIMER"):
            drv_clint = "RVTimerIbex"
        elif vals.get("HAS_CLINT", True):
            drv_clint = "RVTimer / CLINT"
        else:
            drv_clint = "RVTimerStub"
        if vals.get("HAS_PLIC"):
            drv_plic = "RVPlicHw"
        elif vals.get("HAS_APLIC"):
            drv_plic = "RVPlicAplic"
        else:
            drv_plic = "RVPlicStub"
    elif vals.get("UART_STUB"):
        drv_uart = "RVUartStub / uart.hc"
        if vals.get("HAS_IBEX_TIMER"):
            drv_clint = "RVTimerIbex"
        elif vals.get("HAS_CLINT", True):
            drv_clint = "RVTimer / CLINT"
        else:
            drv_clint = "RVTimerStub"
        if vals.get("HAS_PLIC"):
            drv_plic = "RVPlicHw"
        elif vals.get("HAS_APLIC"):
            drv_plic = "RVPlicAplic"
        else:
            drv_plic = "RVPlicStub"
    else:
        drv_uart = "RVUart16550 / uart.hc"
        if vals.get("HAS_IBEX_TIMER"):
            drv_clint = "RVTimerIbex"
        elif vals.get("HAS_CLINT", True):
            drv_clint = "RVTimer / CLINT"
        else:
            drv_clint = "RVTimerStub"
        if vals.get("HAS_PLIC"):
            drv_plic = "RVPlicHw"
        elif vals.get("HAS_APLIC"):
            drv_plic = "RVPlicAplic"
        else:
            drv_plic = "RVPlicStub"

    # SiFive / HTIF / Shakti branches still use HAS_PLIC for drv_plic; APLIC boards
    # (xiangshan) are UART_16550 and hit the else branch above.
    if vals.get("UART_SIFIVE"):
        if vals.get("HAS_APLIC") and not vals.get("HAS_PLIC"):
            drv_plic = "RVPlicAplic"
    elif vals.get("UART_HTIF") or vals.get("UART_SHAKTI"):
        if vals.get("HAS_APLIC") and not vals.get("HAS_PLIC"):
            drv_plic = "RVPlicAplic"

    if vals.get("HAS_VIRTIO_MMIO"):
        drv_virtio = "DskVirtioRV / VirtioNet / VirtioInput / Virtio9p"
        if vals.get("HAS_VIRTIO_PCI"):
            drv_virtio += " / VirtioPciBlk"
    elif vals.get("HAS_VIRTIO_PCI"):
        drv_virtio = "VirtioPci / VirtioPciBlk"
    else:
        drv_virtio = "RVVirtioMmioNo"

    if vals.get("FB_PRESENT_SIMPLEFB"):
        drv_fb = "RVFb / simplefb"
    elif vals.get("FB_PRESENT_NONE"):
        drv_fb = "RVFb / none"
    else:
        drv_fb = "RVFb / ramfb"

    drv_fw = "RVFwCfgYes" if vals.get("HAS_FW_CFG") else "RVFwCfgNo"
    drv_rtc = "RVRtcGoldfish" if vals.get("HAS_GOLDFISH_RTC") else "RVRtcNo"

    lines = [
        "// Generated by templeos-riscv/scripts/kconfig.py — do not edit.",
        "// REPL MemMap / MEM_* for the active board (same bases as Kernel/RVAutoConf.HH).",
        f"// Platform: {plat}",
        f"#define MEM_RAM        {_mem_hex(ram)}",
        f"#define MEM_TEST       {_mem_hex(test)}",
        f"#define MEM_CLINT      {_mem_hex(clint)}",
        f"#define MEM_CLINT_MTIME_OFF    {_mem_hex(mtime_off)}",
        f"#define MEM_CLINT_MTIMECMP_OFF {_mem_hex(mtimecmp_off)}",
        f"#define MEM_MTIME      {_mem_hex(clint + mtime_off)}",
        f"#define MEM_MTIMECMP   {_mem_hex(clint + mtimecmp_off)}",
        f"#define MEM_PLIC       {_mem_hex(plic)}",
        f"#define MEM_PLIC_ENABLE_OFF    {_mem_hex(plic_en)}",
        f"#define MEM_PLIC_THRESHOLD_OFF {_mem_hex(plic_thr)}",
        f"#define MEM_PLIC_CLAIM_OFF     {_mem_hex(plic_claim)}",
        f"#define MEM_UART       {_mem_hex(uart)}",
        f"#define MEM_UART1      {_mem_hex(uart1)}",
        f"#define MEM_GPIO       {_mem_hex(gpio)}",
        f"#define MEM_PRCI       {_mem_hex(prci)}",
        f"#define MEM_ETH        {_mem_hex(eth)}",
        f"#define MEM_VIRTIO     {_mem_hex(virtio)}",
        f"#define MEM_VIRTIO_STRIDE {_mem_hex(virtio_stride)}",
        f"#define MEM_FW_CFG     {_mem_hex(fw_cfg)}",
        f"#define MEM_RTC        {_mem_hex(rtc)}",
        f"#define MEM_FS         {_mem_hex(memfs)}",
        f"#define MEM_HEAP       {_mem_hex(heap)}",
        f"#define MEM_FB         {_mem_hex(fb)}",
        f"#define MEM_FIXED      {_mem_hex(fixed)}",
        f"#define MEM_TRAP_SNAP  {_mem_hex(fixed + 0x100)}",
        f"#define MEM_REGS_SNAP  {_mem_hex(fixed + 0x300)}",
        f"#define MEM_HOST_SLOTS {_mem_hex(host_slots)}",
        f"#define MEM_STACK      {_mem_hex(stack)}",
        "// Kernel phase3 Compiler.BIN embed — not present in the UART REPL image.",
        "#define MEM_COMPILER   0",
        f'#define MEMMAP_DRV_UART    "{drv_uart}"',
        f'#define MEMMAP_DRV_CLINT   "{drv_clint}"',
        f'#define MEMMAP_DRV_PLIC    "{drv_plic}"',
        f'#define MEMMAP_DRV_VIRTIO  "{drv_virtio}"',
        f'#define MEMMAP_DRV_FB      "{drv_fb}"',
        f'#define MEMMAP_DRV_FW_CFG  "{drv_fw}"',
        f'#define MEMMAP_DRV_RTC     "{drv_rtc}"',
        '#define MEMMAP_DRV_FS      "fs.hc"',
        '#define MEMMAP_DRV_HEAP    "mem.hc"',
        '#define MEMMAP_DRV_TRAP    "trap.hc"',
        '#define MEMMAP_DRV_REGS    "Regs / csr.hc"',
        '#define MEMMAP_DRV_TEST    "[plat SiFive test]"',
        '#define MEMMAP_DRV_RAM     "[plat DRAM]"',
        "",
    ]
    seed.write_text("\n".join(lines))


def write_editor_selected(vals: Dict[str, Any]) -> None:
    """REPL boot seed: set HolyC `editor` from Kconfig Editors choice."""
    seed = REPO / "bootstrap" / "seed" / "RVEditorSelected.hc"
    hdr = (
        "// Generated by templeos-riscv/scripts/kconfig.py — do not edit.\n"
        "// Default Src/DirEd/FunEd editor (Kconfig Editors menu).\n"
    )
    if vals.get("EDITOR_EDIT"):
        body = "editor=&EditHoly;\n"
        note = "// Selected: Edit (EditHoly)\n"
    elif vals.get("EDITOR_ED"):
        body = "editor=&EdHoly;\n"
        note = "// Selected: Ed (EdHoly)\n"
    else:
        body = "editor=&Vi;\n"
        note = "// Selected: Vi (default)\n"
    seed.write_text(hdr + note + body)


def write_drv_selecteds(vals: Dict[str, Any]) -> None:
    """HolyC AOT cannot emit code for functions wrapped in #ifdef — select whole .HC files."""
    drv = REPO / "Kernel" / "Drv"
    hdr = "// Generated by templeos-riscv/scripts/kconfig.py — do not edit.\n"

    if vals.get("UART_SIFIVE"):
        uart = '#include "RVUartSifive.HC"\n'
    elif vals.get("UART_HTIF"):
        uart = '#include "RVUartHtif.HC"\n'
    elif vals.get("UART_SHAKTI"):
        uart = '#include "RVUartShakti.HC"\n'
    elif vals.get("UART_UARTLITE"):
        uart = '#include "RVUartUartlite.HC"\n'
    elif vals.get("UART_IBEX"):
        uart = '#include "RVUartIbex.HC"\n'
    elif vals.get("UART_STUB"):
        uart = '#include "RVUartStub.HC"\n'
    else:
        uart = '#include "RVUart16550.HC"\n'
    (drv / "RVUartSelected.HH").write_text(hdr + uart)

    if vals.get("HAS_CLINT", True):
        (drv / "RVTimerSelected.HH").write_text(hdr + '#include "RVTimerClint.HC"\n')
    elif vals.get("HAS_IBEX_TIMER"):
        (drv / "RVTimerSelected.HH").write_text(hdr + '#include "RVTimerIbex.HC"\n')
    elif vals.get("HAS_XPS_TIMER"):
        (drv / "RVTimerSelected.HH").write_text(hdr + '#include "RVTimerXps.HC"\n')
    else:
        (drv / "RVTimerSelected.HH").write_text(hdr + '#include "RVTimerStub.HC"\n')

    if vals.get("HAS_PLIC"):
        (drv / "RVPlicSelected.HH").write_text(hdr + '#include "RVPlicHw.HC"\n')
    elif vals.get("HAS_APLIC"):
        (drv / "RVPlicSelected.HH").write_text(hdr + '#include "RVPlicAplic.HC"\n')
    elif vals.get("HAS_XPS_INTC"):
        (drv / "RVPlicSelected.HH").write_text(hdr + '#include "RVPlicXps.HC"\n')
    else:
        (drv / "RVPlicSelected.HH").write_text(hdr + '#include "RVPlicStub.HC"\n')

    # SiFive plat facade (UART0 + CLINT + PLIC named API); Yes when UART_SIFIVE.
    if vals.get("UART_SIFIVE") or vals.get("PLATFORM_SIFIVE_U") or vals.get("PLATFORM_SIFIVE_E"):
        (drv / "RVSifiveSelected.HH").write_text(hdr + '#include "RVSifiveYes.HC"\n')
    else:
        (drv / "RVSifiveSelected.HH").write_text(hdr + '#include "RVSifiveNo.HC"\n')

    vio = []
    vio.append('#include "RVVirtioMmioYes.HC"\n' if vals.get("HAS_VIRTIO_MMIO") else '#include "RVVirtioMmioNo.HC"\n')
    vio.append('#include "RVVirtioPciYes.HC"\n' if vals.get("HAS_VIRTIO_PCI") else '#include "RVVirtioPciNo.HC"\n')
    (drv / "RVVirtioSelected.HH").write_text(hdr + "".join(vio))

    fb = []
    if vals.get("FB_PRESENT_SIMPLEFB"):
        fb.append('#include "RVFbKindSimple.HC"\n')
    elif vals.get("FB_PRESENT_NONE"):
        fb.append('#include "RVFbKindNone.HC"\n')
    else:
        fb.append('#include "RVFbKindRamfb.HC"\n')
    (drv / "RVFbSelected.HH").write_text(hdr + "".join(fb))

    (drv / "RVFwCfgSelected.HH").write_text(
        hdr + ('#include "RVFwCfgYes.HC"\n' if vals.get("HAS_FW_CFG") else '#include "RVFwCfgNo.HC"\n')
    )
    (drv / "RVRtcSelected.HH").write_text(
        hdr + ('#include "RVRtcGoldfish.HC"\n' if vals.get("HAS_GOLDFISH_RTC") else '#include "RVRtcNo.HC"\n')
    )

    # SiFive Cadence GEM (FU540); Yes when SIFIVE_ETH_BASE is non-zero.
    eth_base = _hex_int(vals, "SIFIVE_ETH_BASE")
    (drv / "RVSifiveGemSelected.HH").write_text(
        hdr + ('#include "RVSifiveGemYes.HC"\n' if eth_base else '#include "RVSifiveGemNo.HC"\n')
    )


def cmd_defconfig(name: str) -> int:
    k = load_kconfig()
    if name.endswith("_defconfig") or Path(name).exists():
        path = Path(name)
        if not path.is_absolute():
            cand = DEFCONFIG_DIR / name
            path = cand if cand.exists() else Path(name)
    else:
        path = DEFCONFIG_DIR / f"{name}_defconfig"
    if not path.exists():
        print(f"error: defconfig not found: {path}", file=sys.stderr)
        return 1
    preset = read_config_file(path)
    vals = resolve_defaults(k, preset)
    write_config_file(CONFIG_PATH, vals, k._order, k.symbols)
    write_autoconf(vals, k.symbols)
    plat = vals.get("PLATFORM_NAME", name)
    print(f"wrote {CONFIG_PATH.relative_to(REPO)} (platform={plat})")
    print(f"wrote {AUTOCONF_H.relative_to(REPO)}")
    print(f"wrote {AUTOCONF_HC.relative_to(REPO)}")
    return 0


def cmd_sync() -> int:
    k = load_kconfig()
    preset = read_config_file(CONFIG_PATH)
    if not preset:
        return cmd_defconfig("virt")
    vals = resolve_defaults(k, preset)
    write_config_file(CONFIG_PATH, vals, k._order, k.symbols)
    write_autoconf(vals, k.symbols)
    print(f"synced autoconf from {CONFIG_PATH}")
    return 0


def cmd_qemu_args(machine: Optional[str] = None) -> int:
    """Print harness argv. With machine=, resolve that defconfig without mutating .config."""
    if machine:
        name = machine
        if name.endswith("_defconfig"):
            name = name[: -len("_defconfig")]
        path = DEFCONFIG_DIR / f"{name}_defconfig"
        if not path.is_file():
            print(f"error: no defconfig for {machine}", file=sys.stderr)
            return 1
        k = load_kconfig()
        preset = read_config_file(path)
        vals = resolve_defaults(k, preset)
        system = str(vals.get("QEMU_SYSTEM", "qemu-system-riscv64")).strip('"')
        qmachine = str(vals.get("QEMU_MACHINE", name)).strip('"')
        extra = str(vals.get("QEMU_EXTRA_ARGS", "")).strip('"')
        load = str(vals.get("QEMU_LOAD_MODE", "kernel")).strip('"')
        if load == "board" or qmachine in ("board-only",):
            entry = vals.get("ENTRY_POINT", "0x40200000")
            print(f"# BOARD-ONLY ({name}): no QEMU -M — U-Boot go / OpenOCD @ {entry}")
            print(
                f"# QEMU_SYSTEM={system} QEMU_LOAD_MODE={load} "
                f"(from {name}_defconfig, no write)",
                file=sys.stderr,
            )
            return 0
        print(f"-M {qmachine} {extra}".strip())
        print(
            f"# QEMU_SYSTEM={system} QEMU_LOAD_MODE={load} "
            f"(from {name}_defconfig, no write)",
            file=sys.stderr,
        )
        return 0
    preset = read_config_file(CONFIG_PATH)
    if not preset:
        cmd_defconfig("virt")
        preset = read_config_file(CONFIG_PATH)
    system = preset.get("QEMU_SYSTEM", '"qemu-system-riscv64"').strip('"')
    qmachine = preset.get("QEMU_MACHINE", '"virt"').strip('"')
    extra = preset.get("QEMU_EXTRA_ARGS", '""').strip('"')
    load = preset.get("QEMU_LOAD_MODE", '"kernel"').strip('"')
    if load == "board" or qmachine in ("board-only",):
        entry = preset.get("CONFIG_ENTRY_POINT") or preset.get("ENTRY_POINT", "0x40200000")
        if isinstance(entry, str) and entry.startswith("CONFIG_"):
            entry = "0x40200000"
        name = str(preset.get("PLATFORM_NAME", "board")).strip('"')
        print(f"# BOARD-ONLY ({name}): no QEMU -M — U-Boot go / OpenOCD @ {entry}")
        print(f"# QEMU_SYSTEM={system} QEMU_LOAD_MODE={load}", file=sys.stderr)
        return 0
    # Args only (Makefile does $(QEMU) $(qemu-args)). Binary is printed for docs.
    print(f"-M {qmachine} {extra}".strip())
    print(f"# QEMU_SYSTEM={system} QEMU_LOAD_MODE={load}", file=sys.stderr)
    return 0


def vals_to_preset(vals: Dict[str, Any], symbols: Dict[str, Symbol]) -> Dict[str, str]:
    preset: Dict[str, str] = {}
    for name, v in vals.items():
        sym = symbols.get(name)
        if sym is None:
            continue
        if sym.type == "bool":
            preset[name] = "y" if v in (True, "y") else "n"
        elif sym.type == "string":
            preset[name] = str(v).strip('"')
        else:
            preset[name] = str(v)
    return preset


def _mconf_dir() -> Path:
    return Path(__file__).resolve().parent / "kconfig"


def cmd_menuconfig() -> int:
    """Run Linux mconf, then sync generated headers. Prefer `make menuconfig`."""
    import subprocess

    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("error: menuconfig requires an interactive TTY", file=sys.stderr)
        print("hint: run `make menuconfig` from a terminal", file=sys.stderr)
        return 1

    kdir = _mconf_dir()
    mconf = kdir / "mconf"
    if not mconf.is_file():
        r = subprocess.run(["make", "-C", str(kdir), "mconf"], cwd=str(ROOT))
        if r.returncode != 0:
            return r.returncode
    env = os.environ.copy()
    env["KCONFIG_CONFIG"] = str(CONFIG_PATH)
    r = subprocess.run([str(mconf), "Kconfig"], cwd=str(ROOT), env=env)
    if r.returncode not in (0, 1):
        # mconf returns 1 on some quit paths; still sync if .config exists
        if not CONFIG_PATH.is_file():
            return r.returncode
    return cmd_sync()


def cmd_menuconfig_test() -> int:
    """Non-interactive: build Linux conf and --olddefconfig our Kconfig."""
    import subprocess
    import tempfile

    kdir = _mconf_dir()
    r = subprocess.run(["make", "-C", str(kdir), "conf"], cwd=str(ROOT))
    if r.returncode != 0:
        print("menuconfig-test FAIL: could not build scripts/kconfig/conf", file=sys.stderr)
        return 1
    conf = kdir / "conf"
    with tempfile.TemporaryDirectory() as td:
        cfg = Path(td) / ".config"
        env = os.environ.copy()
        env["KCONFIG_CONFIG"] = str(cfg)
        r = subprocess.run(
            [str(conf), "--olddefconfig", "Kconfig"],
            cwd=str(ROOT),
            env=env,
            capture_output=True,
            text=True,
        )
        if r.returncode != 0:
            print(r.stderr or r.stdout, file=sys.stderr)
            print("menuconfig-test FAIL: conf --olddefconfig", file=sys.stderr)
            return 1
        text = cfg.read_text()
    for needle in (
        "CONFIG_PLATFORM_VIRT=y",
        "CONFIG_ENTRY_POINT=",
        "CONFIG_RISCV_ISA=",
        "CONFIG_ISA_RV64IMAFDC=y",
        "CONFIG_OUTPUT_FORMAT_ELF=y",
    ):
        if needle not in text:
            print(f"menuconfig-test FAIL: missing {needle!r} in conf output", file=sys.stderr)
            return 1
    # Ensure mconf also links
    r = subprocess.run(["make", "-C", str(kdir), "mconf"], cwd=str(ROOT))
    if r.returncode != 0:
        print("menuconfig-test FAIL: could not build scripts/kconfig/mconf", file=sys.stderr)
        return 1
    print(
        "menuconfig-test OK: Linux conf --olddefconfig + mconf build "
        f"(ENTRY_POINT/ISA present; frontend=scripts/kconfig/mconf)"
    )
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "command",
        choices=["defconfig", "olddefconfig", "menuconfig", "menuconfig-test", "sync", "qemu-args", "list-defconfigs"],
    )
    ap.add_argument(
        "arg",
        nargs="?",
        default=None,
        help="defconfig name, or machine for qemu-args (omit qemu-args → use .config)",
    )
    args = ap.parse_args()
    os.chdir(ROOT)

    if args.command == "list-defconfigs":
        for p in sorted(DEFCONFIG_DIR.glob("*_defconfig")):
            print(p.name)
        return 0
    if args.command == "defconfig":
        return cmd_defconfig(args.arg or "virt")
    if args.command == "olddefconfig":
        return cmd_sync()
    if args.command == "sync":
        return cmd_sync()
    if args.command == "menuconfig":
        return cmd_menuconfig()
    if args.command == "menuconfig-test":
        return cmd_menuconfig_test()
    if args.command == "qemu-args":
        return cmd_qemu_args(args.arg)
    return 1


if __name__ == "__main__":
    sys.exit(main())
