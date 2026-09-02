#!/usr/bin/env python3
"""Differential assembler tests: holyc-riscv --asm-dump vs GNU gas.

Compares instruction encodings for immediates, pseudos, branches, and rejection
behavior. Skips gracefully when no RISC-V GNU toolchain is installed.

See tests/asm/README.md and cases/gnu_diff.jsonl.
"""

from __future__ import annotations

import json
import os
import random
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, List, Optional, Sequence, Tuple

from gas_util import (
    ROOT,
    default_march,
    detect_gas,
    gas_dump,
    gas_src_from_insns,
    host_dump,
    words_disasm,
    wrap_hc,
)
from run_asm_prop import GENERATORS, PropCase, host_dump_batch

CASES_DIR = Path(__file__).resolve().parent / "cases"
GNU_DIFF = CASES_DIR / "gnu_diff.jsonl"
POSITIVE = CASES_DIR / "positive.jsonl"
NEGATIVE = CASES_DIR / "negative.jsonl"

# OOR / reject negatives from negative.jsonl included in both_reject sweep.
NEGATIVE_BOTH_REJECT = frozenset(
    {
        "addi_oor",
        "addi_oor_neg",
        "ld_oor",
        "sd_oor",
        "slli_oor",
        "lui_oor_addr",
        "jalr_oor",
        "csr_oor",
        "zimm_oor",
    }
)

# Focus generators for imm/pseudo/branch differential (subset of asm-prop).
FOCUS_GENERATORS: List[Tuple[str, Callable]] = [
    g for g in GENERATORS
    if g[0]
    in (
        "addi",
        "andi",
        "ori",
        "xori",
        "slti",
        "lui",
        "auipc",
        "ld",
        "sd",
        "li_narrow",
        "mv",
        "not",
        "neg",
        "zero",
        "beqz",
        "bnez",
        "beq",
        "bne",
        "blt",
        "bge",
        "bltu",
        "bgeu",
        "j",
        "jalr",
    )
]


@dataclass
class DiffCase:
    name: str
    insns: List[str]
    mode: str = "match"  # match | both_reject | holyc_reject | host_only
    gas: Optional[str] = None  # override gas source (str) or False to skip
    words: Optional[List[str]] = None  # optional host golden for host_only
    why: str = ""
    source: str = "curated"


@dataclass
class Stats:
    match_ok: int = 0
    match_fail: int = 0
    reject_ok: int = 0
    reject_fail: int = 0
    host_only_ok: int = 0
    host_only_fail: int = 0
    gen_ok: int = 0
    gen_fail: int = 0
    pos_replay_ok: int = 0
    pos_replay_fail: int = 0
    skipped_no_gas: int = 0


def load_jsonl(path: Path) -> List[dict]:
    if not path.is_file():
        return []
    out = []
    with open(path) as f:
        for line in f:
            if line.strip():
                out.append(json.loads(line))
    return out


def case_from_gnu_diff(row: dict) -> DiffCase:
    return DiffCase(
        name=row["name"],
        insns=row["insns"],
        mode=row.get("mode", "match"),
        gas=row.get("gas"),
        words=row.get("words"),
        why=row.get("why", ""),
        source="gnu_diff",
    )


def cases_from_positive(rows: Sequence[dict]) -> List[DiffCase]:
    out: List[DiffCase] = []
    for row in rows:
        if row.get("gas") is False:
            continue
        out.append(
            DiffCase(
                name=f"pos_{row['name']}",
                insns=row["insns"],
                mode="match",
                gas=row["gas"] if isinstance(row.get("gas"), str) else None,
                words=row.get("words"),
                source="positive",
            )
        )
    return out


def cases_from_negative(rows: Sequence[dict]) -> List[DiffCase]:
    out: List[DiffCase] = []
    for row in rows:
        if row["name"] not in NEGATIVE_BOTH_REJECT:
            continue
        out.append(
            DiffCase(
                name=f"neg_{row['name']}",
                insns=row["insns"],
                mode="both_reject",
                why=row.get("why", ""),
                source="negative",
            )
        )
    return out


def gas_source(case: DiffCase) -> Optional[str]:
    if case.gas is False:
        return None
    if isinstance(case.gas, str):
        return case.gas
    return gas_src_from_insns(case.insns)


def print_mismatch_teaching(
    case_name: str,
    insns: Sequence[str],
    hwords: List[str],
    gwords: List[str],
    objdump_path: Optional[str],
    tmp: Path,
) -> None:
    print(f"FAIL {case_name}: gas {gwords} != host {hwords}", file=sys.stderr)
    print(f"  insns: {list(insns)}", file=sys.stderr)
    print(f"  HolyC words: {hwords}", file=sys.stderr)
    print(f"  GNU   words: {gwords}", file=sys.stderr)
    if not objdump_path:
        return
    try:
        hd = words_disasm(objdump_path, hwords, tmp, f"h_{case_name}")
        gd = words_disasm(objdump_path, gwords, tmp, f"g_{case_name}")
    except (subprocess.CalledProcessError, OSError) as e:
        print(f"  (disasm unavailable: {e})", file=sys.stderr)
        return
    n = max(len(hd), len(gd), 1)
    print("  disasm (HolyC | GNU):", file=sys.stderr)
    for i in range(n):
        hln = hd[i] if i < len(hd) else ""
        gln = gd[i] if i < len(gd) else ""
        print(f"    {hln}  |  {gln}", file=sys.stderr)


def run_match(
    case: DiffCase,
    bin_path: Path,
    as_path: str,
    objdump_path: str,
    tmp: Path,
    march: str,
    stats: Stats,
    have_gas: bool,
) -> bool:
    rc, hwords, herr = host_dump(bin_path, case.insns, tmp, case.name)
    if rc != 0 or not hwords:
        print(
            f"FAIL {case.name}: host assemble failed rc={rc} {herr}",
            file=sys.stderr,
        )
        stats.match_fail += 1
        return False

    gsrc = gas_source(case)
    if not have_gas or gsrc is None:
        stats.skipped_no_gas += 1
        if case.words and hwords != case.words:
            print(
                f"FAIL {case.name}: host {hwords} != golden {case.words}",
                file=sys.stderr,
            )
            stats.match_fail += 1
            return False
        stats.match_ok += 1
        return True

    gwords, gerr = gas_dump(as_path, objdump_path, gsrc, tmp, march)
    if gwords is None:
        print(f"FAIL {case.name}: gas assemble failed: {gerr}", file=sys.stderr)
        stats.match_fail += 1
        return False
    if gwords != hwords:
        print_mismatch_teaching(
            case.name, case.insns, hwords, gwords, objdump_path, tmp
        )
        if gsrc:
            print(f"  gas src:\n{gsrc}", file=sys.stderr)
        stats.match_fail += 1
        return False
    stats.match_ok += 1
    return True


def run_reject(
    case: DiffCase,
    bin_path: Path,
    as_path: str,
    objdump_path: str,
    tmp: Path,
    march: str,
    stats: Stats,
    have_gas: bool,
    require_gas_reject: bool,
) -> bool:
    rc, hwords, herr = host_dump(bin_path, case.insns, tmp, case.name)
    if rc == 0 and hwords:
        print(
            f"FAIL {case.name}: expected host reject, got {hwords}",
            file=sys.stderr,
        )
        stats.reject_fail += 1
        return False

    if not have_gas:
        stats.skipped_no_gas += 1
        stats.reject_ok += 1
        return True

    gsrc = gas_source(case)
    if gsrc is None:
        stats.reject_ok += 1
        return True

    gwords, gerr = gas_dump(as_path, objdump_path, gsrc, tmp, march)
    if gwords is not None:
        if require_gas_reject:
            print(
                f"FAIL {case.name}: expected gas reject, got {gwords}\n  gas src:\n{gsrc}",
                file=sys.stderr,
            )
            stats.reject_fail += 1
            return False
        # holyc_reject: gas may accept (different pseudo expansion policy)
    stats.reject_ok += 1
    return True


def run_host_only(
    case: DiffCase,
    bin_path: Path,
    stats: Stats,
) -> bool:
    rc, hwords, herr = host_dump(bin_path, case.insns, tmp_global, case.name)
    if rc != 0 or not hwords:
        print(
            f"FAIL {case.name}: host assemble failed rc={rc} {herr}",
            file=sys.stderr,
        )
        stats.host_only_fail += 1
        return False
    if case.words and hwords != case.words:
        print(
            f"FAIL {case.name}: host {hwords} != golden {case.words}",
            file=sys.stderr,
        )
        stats.host_only_fail += 1
        return False
    stats.host_only_ok += 1
    return True


tmp_global: Path = Path("/tmp")  # set in main


def run_generated(
    bin_path: Path,
    as_path: str,
    objdump_path: str,
    tmp: Path,
    march: str,
    rng: random.Random,
    trials: int,
    batch: int,
    stats: Stats,
    have_gas: bool,
) -> None:
    if not have_gas:
        stats.skipped_no_gas += trials
        return

    for start in range(0, trials, batch):
        chunk: List[PropCase] = []
        for i in range(min(batch, trials - start)):
            tag, gen = rng.choice(FOCUS_GENERATORS)
            c = gen(rng)
            c.name = f"gen_{start + i}_{tag}"
            chunk.append(c)

        rc, got_chunks, err = host_dump_batch(bin_path, chunk, tmp)
        if rc != 0:
            print(f"FAIL gen batch rc={rc}: {err}", file=sys.stderr)
            stats.gen_fail += len(chunk)
            continue

        for c, hwords in zip(chunk, got_chunks):
            gsrc = gas_src_from_insns(c.insns)
            gwords, gerr = gas_dump(as_path, objdump_path, gsrc, tmp, march)
            if gwords is None:
                print(f"FAIL {c.name}: gas failed: {gerr}", file=sys.stderr)
                stats.gen_fail += 1
            elif gwords != hwords:
                print_mismatch_teaching(
                    c.name, c.insns, hwords, gwords, objdump_path, tmp
                )
                stats.gen_fail += 1
            else:
                stats.gen_ok += 1


def dedupe_cases(cases: Sequence[DiffCase]) -> List[DiffCase]:
    seen = set()
    out: List[DiffCase] = []
    for c in cases:
        key = (c.mode, tuple(c.insns))
        if key in seen:
            continue
        seen.add(key)
        out.append(c)
    return out


def main() -> int:
    global tmp_global

    seed = int(os.environ.get("ASM_GNU_DIFF_SEED", "42"))
    gen_trials = int(os.environ.get("ASM_GNU_DIFF_GEN", "120"))
    batch = int(os.environ.get("ASM_GNU_DIFF_BATCH", "30"))
    include_positive = os.environ.get("ASM_GNU_DIFF_POSITIVE", "1") != "0"
    bin_path = Path(os.environ.get("HOLYC_BIN", ROOT / "holyc-riscv"))

    if not bin_path.is_file():
        print(f"error: missing {bin_path} (run make holyc-riscv)", file=sys.stderr)
        return 1

    as_path, objdump_path, have_gas = detect_gas()
    march = default_march()
    tmp_global = Path(tempfile.mkdtemp(prefix="holyc_asm_gnu_diff_"))

    cases: List[DiffCase] = []
    cases.extend(case_from_gnu_diff(r) for r in load_jsonl(GNU_DIFF))
    if include_positive:
        cases.extend(cases_from_positive(load_jsonl(POSITIVE)))
    cases.extend(cases_from_negative(load_jsonl(NEGATIVE)))
    cases = dedupe_cases(cases)

    stats = Stats()
    gas_label = as_path if have_gas else "none"
    print(
        f"asm-gnu-diff: {len(cases)} curated/replay cases, gen={gen_trials}, "
        f"gas={gas_label}, march={march}"
    )

    for case in cases:
        ok = True
        if case.mode == "match":
            ok = run_match(
                case, bin_path, as_path or "", objdump_path or "", tmp_global, march, stats, have_gas
            )
        elif case.mode in ("both_reject", "holyc_reject"):
            ok = run_reject(
                case,
                bin_path,
                as_path or "",
                objdump_path or "",
                tmp_global,
                march,
                stats,
                have_gas,
                require_gas_reject=(case.mode == "both_reject"),
            )
        elif case.mode == "host_only":
            ok = run_host_only(case, bin_path, stats)
        else:
            print(f"FAIL {case.name}: unknown mode {case.mode}", file=sys.stderr)
            ok = False

        if ok:
            print(f"OK   {case.name} [{case.source}]")

    rng = random.Random(seed)
    run_generated(
        bin_path,
        as_path or "",
        objdump_path or "",
        tmp_global,
        march,
        rng,
        gen_trials,
        batch,
        stats,
        have_gas,
    )

    total_fail = (
        stats.match_fail
        + stats.reject_fail
        + stats.host_only_fail
        + stats.gen_fail
        + stats.pos_replay_fail
    )
    gen_summary = (
        f"generated {stats.gen_ok}/{gen_trials} ok"
        if have_gas
        else f"generated skipped (no gas, {gen_trials} trials)"
    )
    print(
        f"✓ asm-gnu-diff: match {stats.match_ok} ok / {stats.match_fail} fail, "
        f"reject {stats.reject_ok} ok / {stats.reject_fail} fail, "
        f"host_only {stats.host_only_ok} ok / {stats.host_only_fail} fail, "
        f"{gen_summary}"
    )
    if not have_gas:
        print(
            f"  (no GNU gas — install riscv64-unknown-elf-as for full cross-check; "
            f"skipped gas on {stats.skipped_no_gas} cases)"
        )
    else:
        print(f"  gas skipped (host_only / no override): {stats.skipped_no_gas}")

    if total_fail:
        print(f"asm-gnu-diff: FAILED ({total_fail})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
