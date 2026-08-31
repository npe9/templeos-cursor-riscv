#!/usr/bin/env python3
"""Minimal Kconfig for TempleOS/RISC-V — no external dependencies.

Supports: mainmenu, source, menu/endmenu, choice/endchoice, config (bool/hex/int/string),
default (with optional `if`), depends on, help.

Commands:
  defconfig [FILE]   apply configs/*_defconfig or named file (default: virt_defconfig)
  olddefconfig       fill missing symbols from defaults using current .config
  menuconfig         simple interactive TUI (stdin)
  sync               rewrite autoconf headers from .config
  qemu-args          print suggested qemu-system-riscv64 args from .config
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


class Kconfig:
    def __init__(self) -> None:
        self.symbols: Dict[str, Symbol] = {}
        self.choices: Dict[str, Choice] = {}
        self.menus: List[Menu] = []
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
        "# use: make -C templeos-riscv menuconfig / defconfig)",
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
        ("CONFIG_FW_CFG_BASE", "RV_CFG_FW_CFG_BASE"),
        ("CONFIG_RTC_BASE", "RV_CFG_RTC_BASE"),
        ("CONFIG_KERNEL_ENTRY", "RV_CFG_KERNEL_ENTRY"),
        ("CONFIG_KERNEL_LINK_ADDR", "RV_CFG_KERNEL_LINK_ADDR"),
        ("CONFIG_DRAM_BASE", "RV_CFG_DRAM_BASE"),
        ("CONFIG_SYS_FIXED_AREA", "RV_CFG_SYS_FIXED_AREA"),
        ("CONFIG_FB_SOFT_BASE", "RV_CFG_FB_SOFT_BASE"),
    ]
    h_lines.append("")
    hc_lines.append("")
    for src, dst in aliases:
        # strip CONFIG_ from name key
        key = src[len("CONFIG_") :]
        if key in vals and symbols[key].type != "bool":
            h_lines.append(f"#define {dst} CONFIG_{key}")
            hc_lines.append(f"#define {dst} CONFIG_{key}")

    # RISCV_VIRT kept for existing #ifdef RISCV_VIRT sites (Goldfish RTC path)
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
    elif vals.get("UART_STUB"):
        uart = '#include "RVUartStub.HC"\n'
    else:
        uart = '#include "RVUart16550.HC"\n'
    (drv / "RVUartSelected.HH").write_text(hdr + uart)

    if vals.get("HAS_PLIC"):
        (drv / "RVPlicSelected.HH").write_text(hdr + '#include "RVPlicHw.HC"\n')
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
    fb.append('#include "RVFwCfgYes.HC"\n' if vals.get("HAS_FW_CFG") else '#include "RVFwCfgNo.HC"\n')
    (drv / "RVFbSelected.HH").write_text(hdr + "".join(fb))


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


def cmd_qemu_args() -> int:
    preset = read_config_file(CONFIG_PATH)
    if not preset:
        cmd_defconfig("virt")
        preset = read_config_file(CONFIG_PATH)
    system = preset.get("QEMU_SYSTEM", '"qemu-system-riscv64"').strip('"')
    machine = preset.get("QEMU_MACHINE", '"virt"').strip('"')
    extra = preset.get("QEMU_EXTRA_ARGS", '""').strip('"')
    # Args only (Makefile does $(QEMU) $(qemu-args)). Binary is printed for docs.
    print(f"-M {machine} {extra}".strip())
    print(f"# QEMU_SYSTEM={system}", file=sys.stderr)
    return 0


def cmd_menuconfig() -> int:
    k = load_kconfig()
    preset = read_config_file(CONFIG_PATH)
    vals = resolve_defaults(k, preset)

    def show() -> None:
        print()
        print("=" * 60)
        print(k.mainmenu)
        print("=" * 60)
        # Platform choice first
        for ch in k.choices.values():
            if "PLATFORM_VIRT" in ch.members:
                print(f"\n[{ch.prompt}]")
                for i, m in enumerate(ch.members, 1):
                    mark = "*" if vals.get(m) else " "
                    p = k.symbols[m].prompt or m
                    exp = " [experimental]" if m != "PLATFORM_VIRT" and m != "PLATFORM_SIFIVE_U" and vals.get("PLATFORM_EXPERIMENTAL") and m.startswith("PLATFORM_") else ""
                    if k.symbols[m].help and "experimental" in k.symbols[m].help.lower():
                        exp = " [experimental]"
                    print(f"  {i}) [{mark}] {m}: {p}{exp}")
                break
        print("\nKey addresses:")
        for key in ("UART_BASE", "CLINT_BASE", "PLIC_BASE", "KERNEL_ENTRY", "VIRTIO_MMIO_BASE", "QEMU_MACHINE"):
            if key in vals:
                print(f"  CONFIG_{key} = {vals[key]}")
        print("\nCommands: 1-N select platform | s save | q quit | a addresses | h help")

    show()
    plat_choice = None
    for ch in k.choices.values():
        if "PLATFORM_VIRT" in ch.members:
            plat_choice = ch
            break

    while True:
        try:
            cmd = input("> ").strip()
        except EOFError:
            print()
            break
        if cmd in ("q", "quit"):
            break
        if cmd in ("s", "save"):
            write_config_file(CONFIG_PATH, vals, k._order, k.symbols)
            write_autoconf(vals, k.symbols)
            print("saved .config + autoconf headers")
            continue
        if cmd in ("h", "help"):
            print("Select platform number to switch machine defaults; 'a' edits hex addresses;")
            print("'s' writes templeos-riscv/.config and Kernel/RVAutoConf.HH.")
            continue
        if cmd == "a":
            for key in ("UART_BASE", "CLINT_BASE", "PLIC_BASE", "KERNEL_ENTRY", "KERNEL_LINK_ADDR", "DRAM_BASE"):
                cur = vals.get(key, "")
                nv = input(f"  {key} [{cur}]: ").strip()
                if nv:
                    vals[key] = _fmt_hex(nv) if key.endswith("BASE") or "ADDR" in key or key == "DRAM_BASE" else nv
            # force custom-ish: keep platform as-is
            continue
        if cmd.isdigit() and plat_choice:
            idx = int(cmd) - 1
            if 0 <= idx < len(plat_choice.members):
                sel = plat_choice.members[idx]
                for m in plat_choice.members:
                    vals[m] = m == sel
                # Re-resolve defaults for dependent symbols (clear non-platform presets)
                seed = {m: ("y" if m == sel else "n") for m in plat_choice.members}
                # Keep manual? Fresh from platform
                vals = resolve_defaults(k, seed)
                print(f"selected {sel}")
                show()
            continue
        show()

    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "command",
        choices=["defconfig", "olddefconfig", "menuconfig", "sync", "qemu-args", "list-defconfigs"],
    )
    ap.add_argument("arg", nargs="?", default="virt")
    args = ap.parse_args()
    os.chdir(ROOT)

    if args.command == "list-defconfigs":
        for p in sorted(DEFCONFIG_DIR.glob("*_defconfig")):
            print(p.name)
        return 0
    if args.command == "defconfig":
        return cmd_defconfig(args.arg)
    if args.command == "olddefconfig":
        return cmd_sync()
    if args.command == "sync":
        return cmd_sync()
    if args.command == "menuconfig":
        return cmd_menuconfig()
    if args.command == "qemu-args":
        return cmd_qemu_args()
    return 1


if __name__ == "__main__":
    sys.exit(main())
