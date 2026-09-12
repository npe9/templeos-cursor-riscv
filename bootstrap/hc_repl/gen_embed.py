#!/usr/bin/env python3
"""Generate seed_embed.hc: MemfsSeed() FileWrite()s for the AOT HolyC REPL.

Embeds a curated slice of bootstrap/seed/*.hc (same boot order as gen_boot_blob.py)
plus hc_repl sources so Dir/Cat/Src expose the real seed tree on the HolyC-only path.
"""
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
OUT = os.path.join(os.path.dirname(__file__), "seed_embed.hc")
SEED = os.path.join(ROOT, "bootstrap", "seed")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from seed_layout import DIRS, memfs_path  # noqa: E402

# Keep in sync with bootstrap/gen_boot_blob.py BOOT_ORDER (subset for AOT memfs size).
SEED_BOOT_ORDER = [
    "MemMapSelected.hc",
    "uart.hc",
    "frame.hc",
    "console.hc",
    "tty.hc",
    "mem.hc",
    "print.hc",
    "str.hc",
    "fs.hc",
    "run.hc",
    "dir.hc",
    "files.hc",
    "home_wrappers.hc",
    "boot.hc",
    "log.hc",
    "sys.hc",
    "tutorial.hc",
    # U/Uf/UA source for Src/Cat — U and Uf sit at the tail, so this one needs
    # the full body (a 12000-byte truncation would cut them off).
    "disasm.hc",
    # 9P client + GDB RSP stub: both are AOT-#included in repl.hc (the thin JitTry
    # evaluator cannot build them), so these copies are for Cat/Src only. Full bodies
    # — the Mount9p usage block and GdbHelp both sit past a 12000-byte truncation.
    "ninep.hc",
    "gdbstub.hc",
    # G4 Man / Funs — full bodies for ManUnitFor / DocFileFor (not truncated)
    "man.hc",
    "man_topics.hc",
    "funs.hc",
    # G3: editors AOT-#included; skip embedding huge vim/term/ed bodies.
    "RVEditorSelected.hc",
]
# dbg/rl seeds are AOT-#included; omit from MemfsSeed to keep boot under smoke timeouts.
# Those lanes may add truncated Cat copies later.

# hc_repl sources + tiny demos (Src/Dir smoke). Names collide with seed/ → hc_repl/ prefix.
HC_REPL_FILES = [
    ("Home/hello.hc", None),
    ("Home/README.txt", None),
    ("uart.hc", "bootstrap/hc_repl/uart.hc"),
    ("fs.hc", "bootstrap/hc_repl/fs.hc"),
    ("fs_dump_changes.hc", "bootstrap/hc_repl/fs_dump_changes.hc"),
    ("dir.hc", "bootstrap/hc_repl/dir.hc"),
    ("ide_bridge.hc", "bootstrap/hc_repl/ide_bridge.hc"),
    ("ide_src.hc", "bootstrap/hc_repl/ide_src.hc"),
    ("eval.hc", "bootstrap/hc_repl/eval.hc"),
    ("exepubs.hc", "bootstrap/hc_repl/exepubs.hc"),
    ("jit.hc", "bootstrap/hc_repl/jit.hc"),
    ("start.hc", "bootstrap/hc_repl/start.hc"),
    ("repl.hc", "bootstrap/hc_repl/repl.hc"),
]

HELLO = r'''// hello.hc -- tiny memfs demo for Src/Dir
U0 Hello()
{
  "Hello from HolyC memfs\n";
}
'''

README = """HolyC AOT REPL (repl-holyc.elf)
================================
Built on Mac by holyc-riscv into a RISC-V ELF.
Guest: UART, memfs, Print, MAlloc, Dir, Src→editor (Vi/Ed), DumpFile, ExePutS — all HolyC.
Entry: asm{_start} in start.hc (no startup.s). No 0x87001xxx host slots.
A2: ExePutS→Jit bridge here; guest Cmp = make repl-cmp (build/repl-cmp.elf). Do not grow jit.hc.
Editors: seed ed.hc / edit.hc / vim.hc AOT-included (G3). Man/Funs: man lane.
DumpFile/DumpMem/DumpChanges/FsChanges: compiled in (seed/fs.hc + files.hc + fs_dump_changes.hc).
ZMODEM / ZmodemSendChanges: legacy bootstrap/repl.elf only (not in this AOT image).
Man/FunsList/SrcFile: AOT-included (G4). Tab/complete/multiline: G5 (complete.hc + readline.hc).
Interactive FunPick: legacy until parity.
"""

# Default truncate keeps MemfsSeed fast; Man topic pages need full text (G4).
MAX_EMBED = 12000
MEMFS_CAP = 65536
FULL_EMBED_BASENAMES = frozenset(
    {
        "man_topics.hc",
        "man.hc",
        "funs.hc",
        "disasm.hc",
        "ninep.hc",
        "gdbstub.hc",
    }
)


def c_escape(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
        .replace("\r", "\\r")
    )


def seed_path(name: str) -> str:
    base = os.path.basename(name)
    p = os.path.join(SEED, base)
    if os.path.isfile(p):
        return p
    p = os.path.join(SEED, "tutorials", base)
    if os.path.isfile(p):
        return p
    p = os.path.join(SEED, "datasheet", base)
    if os.path.isfile(p):
        return p
    return os.path.join(SEED, base)


def read_body(embed_name: str, rel: str | None) -> str:
    base = os.path.basename(embed_name)
    if base == "hello.hc" and rel is None:
        return HELLO
    if base == "README.txt" and rel is None:
        return README
    if rel == "__dir__":
        return ""
    if rel:
        path = os.path.join(ROOT, rel)
    else:
        path = seed_path(embed_name)
    with open(path, encoding="utf-8") as f:
        return f.read()


def embed_entries():
    seen: set[str] = set()
    seed_bases: set[str] = set()
    out: list[tuple[str, str | None]] = []
    for d in DIRS:
        marker = f"{d}/.dir"
        if marker not in seen:
            seen.add(marker)
            out.append((marker, "__dir__"))
    for name in SEED_BOOT_ORDER:
        dest = memfs_path(name)
        seed_bases.add(os.path.basename(dest))
        if dest not in seen:
            seen.add(dest)
            out.append((dest, None))
    for name, rel in HC_REPL_FILES:
        base = os.path.basename(name)
        if rel and base in seed_bases:
            embed_name = f"hc_repl/{base}"
        else:
            embed_name = name
        if embed_name in seen:
            continue
        seen.add(embed_name)
        out.append((embed_name, rel))
    return out


def main() -> int:
    lines = [
        "// GENERATED by gen_embed.py — do not edit by hand.\n",
        "U0 MemfsSeed()\n{\n",
    ]
    files = embed_entries()
    for embed_name, rel in files:
        body = read_body(embed_name, rel)
        base = os.path.basename(embed_name)
        limit = MEMFS_CAP if base in FULL_EMBED_BASENAMES else MAX_EMBED
        if len(body) > limit:
            body = body[:limit] + "\n/* …truncated for embed… */\n"
        esc = c_escape(body)
        lines.append(f'  FileWrite("{embed_name}", "{esc}", {len(body)});\n')
    lines.append("}\n")
    text = "".join(lines)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"wrote {OUT} ({len(files)} files, {len(text)} bytes source)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
