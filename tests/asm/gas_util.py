"""Shared GNU gas + holyc-riscv --asm-dump helpers for assembler differential tests."""

from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[2]

GAS_CANDIDATES = (
    "riscv64-unknown-elf-as",
    "riscv64-linux-gnu-as",
)


def detect_gas() -> Tuple[Optional[str], Optional[str], bool]:
    """Return (as_path, objdump_path, have_gas). Honors RISCV_AS / RISCV_OBJDUMP."""
    as_override = os.environ.get("RISCV_AS")
    if as_override:
        as_path = as_override
    else:
        as_path = None
        for cand in GAS_CANDIDATES:
            r = subprocess.run(["which", cand], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                as_path = r.stdout.strip()
                break

    if not as_path:
        return None, None, False

    obj_override = os.environ.get("RISCV_OBJDUMP")
    if obj_override:
        objdump_path = obj_override
    else:
        prefix = as_path.removesuffix("-as")
        objdump_path = f"{prefix}-objdump"
        if subprocess.run(["which", objdump_path], capture_output=True).returncode != 0:
            return as_path, None, False

    return as_path, objdump_path, True


def default_march() -> str:
    return os.environ.get("ASM_STRESS_GAS_MARCH", "rv64ima_zicsr_zifencei")


def wrap_hc(insns: Sequence[str]) -> str:
    lines = ["asm {", "  T::"]
    for ln in insns:
        lines.append("    " + ln)
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def host_dump(
    bin_path: Path, insns: Sequence[str], tmp: Path, tag: str = "case"
) -> Tuple[int, List[str], str]:
    path = tmp / f"{tag}.hc"
    path.write_text(wrap_hc(insns))
    r = subprocess.run(
        [str(bin_path), "--asm-dump", str(path)], capture_output=True, text=True
    )
    words = [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
    return r.returncode, words, (r.stderr or "").strip()


def _gas_u20_imm(token: str) -> str:
    """HolyC accepts signed U-type fields; GNU gas wants 0..0xFFFFF (non-negative syntax)."""
    t = token.strip()
    try:
        v = int(t, 0)
    except ValueError:
        return t
    if v < 0:
        return f"0x{v & 0xFFFFF:X}"
    return t


def gas_src_from_insns(insns: Sequence[str]) -> str:
    """Map HolyC label L: to gas local labels 1: / 1f / 1b; normalize U-type imms."""
    out: List[str] = []
    seen_L = False
    for ln in insns:
        if ln == "L:" or (ln.endswith(":") and ln[:-1].isalnum()):
            out.append("1:")
            seen_L = True
            continue
        s = ln
        if ", L" in s:
            s = s.replace(", L", ", 1b" if seen_L else ", 1f")
        if s.startswith("j L"):
            s = s.replace("j L", "j 1b" if seen_L else "j 1f", 1)
        parts = s.split(None, 2)
        if len(parts) == 3 and parts[0].lower() in ("lui", "auipc"):
            rd, imm_tok = parts[1].rstrip(","), parts[2]
            s = f"{parts[0]} {rd}, {_gas_u20_imm(imm_tok)}"
        out.append(s)
    return "\n".join(out)


def words_disasm(
    objdump_path: str, words: Sequence[str], tmp: Path, tag: str
) -> List[str]:
    """Disassemble raw instruction words (hex strings) via a minimal .text blob."""
    if not words:
        return []
    d = Path(tempfile.mkdtemp(dir=tmp, prefix=f"wd_{tag}_"))
    raw = d / "t.bin"
    with open(raw, "wb") as f:
        for w in words:
            f.write(int(w, 16).to_bytes(4, "little"))
    out = subprocess.check_output(
        [objdump_path, "-D", "-b", "binary", "-m", "riscv:rv64", "-M", "no-aliases", str(raw)],
        text=True,
    )
    lines: List[str] = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and ":" in parts[0]:
            mnem = parts[-1].strip()
            if mnem:
                lines.append(mnem)
    return lines


def gas_dump(
    as_path: str,
    objdump_path: str,
    src: str,
    tmp: Path,
    march: Optional[str] = None,
) -> Tuple[Optional[List[str]], str]:
    """Assemble gas source; return (words, error). words is None on assemble failure."""
    march = march or default_march()
    d = Path(tempfile.mkdtemp(dir=tmp, prefix="gas_"))
    s = d / "t.s"
    o = d / "t.o"
    with open(s, "w") as f:
        f.write(".text\n.globl _start\n_start:\n")
        for line in src.strip().splitlines():
            line = line.strip()
            if line:
                f.write("  " + line + "\n")
    r = subprocess.run(
        [as_path, f"-march={march}", str(s), "-o", str(o)],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        if any(tok in src for tok in ("fadd", "fa", "ft", "fs", "fmv")):
            m2 = "rv64imafd_zicsr_zifencei"
            r = subprocess.run(
                [as_path, f"-march={m2}", str(s), "-o", str(o)],
                capture_output=True,
                text=True,
            )
            if r.returncode != 0:
                return None, r.stderr
        else:
            return None, r.stderr
    out = subprocess.check_output(
        [objdump_path, "-d", "-M", "no-aliases", str(o)], text=True
    )
    words: List[str] = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and ":" in parts[0]:
            hx = parts[1].strip().split()[0]
            if len(hx) == 8 and all(c in "0123456789abcdef" for c in hx):
                words.append(hx)
    return words, ""
