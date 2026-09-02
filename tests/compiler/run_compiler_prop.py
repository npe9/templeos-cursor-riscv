#!/usr/bin/env python3
"""Property-based HolyC compiler semantic equivalence across optimization tiers.

Generates random valid HolyC programs (arithmetic, comparisons, control flow,
local vars, small helpers), compiles each at multiple host opt tiers, links with
the exec oracle harness, runs under qemu-system-riscv64, and requires identical
main() return values (ORACLE line) across tiers.

Opt tiers are environment-driven (holyc-riscv has no -O0/-O1 CLI):
  no_opt     HOLYC_NO_OPT=1
  no_tier2   HOLYC_NO_TIER2=1  (Tier-1 peephole only)
  no_promote HOLYC_NO_PROMOTE=1
  default    (full default O1 mode 3 + Tier-2)
"""

from __future__ import annotations

import os
import random
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "tests" / "exec" / "harness"
REPLAY_SOURCES = [
    "tests/exec/cases/e_literal_42.hc",
    "tests/exec/cases/e_mul_42.hc",
    "tests/exec/cases/e_negative.hc",
    "tests/exec/cases/e_bitwise_and.hc",
    "tests/exec/cases/e_for_sum.hc",
    "tests/exec/cases/e_fib6.hc",
    "tests/exec/cases/e_call_two_arg.hc",
    "tests/compiler/cases/c_if_loop.hc",
    "tests/compiler/cases/c_if_same_arms.hc",
    "tests/compiler/cases/c_const_if.hc",
]

OPT_TIERS: Dict[str, Dict[str, str]] = {
    "no_opt": {"HOLYC_NO_OPT": "1"},
    "no_tier2": {"HOLYC_NO_TIER2": "1"},
    "no_promote": {"HOLYC_NO_PROMOTE": "1"},
    "default": {},
}

BINOPS = ["+", "-", "*", "&", "|", "^"]
CMP_OPS = ["==", "!=", "<", ">", "<=", ">="]


@dataclass
class PropProgram:
    name: str
    source: str
    kind: str = "generated"


@dataclass
class RunTools:
    holyc: Path
    gcc: str
    ld: str
    objcopy: str
    qemu: str
    timeout: str
    timeout_sec: str


@dataclass
class HarnessCtx:
    outdir: Path
    crt0: Path
    oracle_out: Path
    link_script: Path


def parse_tiers(spec: str) -> List[Tuple[str, Dict[str, str]]]:
    names = [s.strip() for s in spec.split(",") if s.strip()]
    if len(names) < 2:
        raise ValueError("need at least two tiers to compare")
    out: List[Tuple[str, Dict[str, str]]] = []
    for n in names:
        if n not in OPT_TIERS:
            raise KeyError(f"unknown tier {n!r} (known: {', '.join(OPT_TIERS)})")
        out.append((n, dict(OPT_TIERS[n])))
    return out


def discover_tools() -> Optional[RunTools]:
    holyc = Path(os.environ.get("HOLYC_BIN", ROOT / "holyc-riscv"))
    prefix = os.environ.get("RISCV_PREFIX", "riscv64-unknown-elf-")
    gcc = f"{prefix}gcc"
    ld = f"{prefix}ld"
    objcopy = f"{prefix}objcopy"
    qemu = os.environ.get("QEMU_SYSTEM_RISCV", "qemu-system-riscv64")
    timeout = ""
    if shutil.which("timeout"):
        timeout = "timeout"
    elif shutil.which("gtimeout"):
        timeout = "gtimeout"
    else:
        return None
    for tool in (str(holyc), gcc, ld, objcopy, qemu, timeout):
        if tool != str(holyc) and not shutil.which(tool):
            return None
    if not holyc.is_file():
        return None
    return RunTools(
        holyc=holyc,
        gcc=gcc,
        ld=ld,
        objcopy=objcopy,
        qemu=qemu,
        timeout=timeout,
        timeout_sec=os.environ.get("QEMU_TIMEOUT_SEC", "3"),
    )


def ensure_harness(outdir: Path, tools: RunTools) -> HarnessCtx:
    outdir.mkdir(parents=True, exist_ok=True)
    crt0 = outdir / "crt0.o"
    oracle_out = outdir / "oracle_out.o"
    flags = [
        "-march=rv64imafdc",
        "-mabi=lp64d",
        "-mcmodel=medany",
        "-O2",
        "-g",
        "-nostdlib",
        "-ffreestanding",
        "-fno-builtin",
    ]
    for src, obj in (
        (HARNESS / "oracle_out.c", oracle_out),
        (HARNESS / "crt0.S", crt0),
    ):
        subprocess.run([tools.gcc, *flags, "-c", str(src), "-o", str(obj)], check=True)
    return HarnessCtx(
        outdir=outdir,
        crt0=crt0,
        oracle_out=oracle_out,
        link_script=HARNESS / "link_exec.ld",
    )


def compile_blob(
    tools: RunTools, hc_path: Path, blob_path: Path, tier_env: Dict[str, str]
) -> Tuple[int, str]:
    env = os.environ.copy()
    env.update(tier_env)
    env["HOLYC_INCLUDE_ROOT"] = str(ROOT)
    r = subprocess.run(
        [str(tools.holyc), str(hc_path), "-o", str(blob_path)],
        capture_output=True,
        text=True,
        env=env,
    )
    err = (r.stderr or r.stdout or "").strip()
    return r.returncode, err


def link_and_run(
    tools: RunTools, ctx: HarnessCtx, blob_path: Path, elf_path: Path
) -> Tuple[bool, str, str]:
    work = blob_path.parent
    work.mkdir(parents=True, exist_ok=True)
    shutil.copy2(blob_path, work / "blob.bin")
    subprocess.run(
        [tools.objcopy, "-I", "binary", "-O", "elf64-littleriscv", "blob.bin", "blob_in.o"],
        check=True,
        capture_output=True,
        cwd=work,
    )
    subprocess.run(
        [
            tools.ld,
            "-T",
            str(ctx.link_script),
            "-nostdlib",
            "--no-warn-mismatch",
            "-o",
            elf_path.name,
            str(ctx.crt0),
            str(ctx.oracle_out),
            "blob_in.o",
        ],
        check=True,
        capture_output=True,
        cwd=work,
    )
    elf = work / elf_path.name
    r = subprocess.run(
        [
            tools.timeout,
            tools.timeout_sec,
            tools.qemu,
            "-M",
            "virt",
            "-bios",
            "none",
            "-kernel",
            str(elf),
            "-nographic",
        ],
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )
    out = r.stdout + r.stderr
    oracle = ""
    for line in out.splitlines():
        if line.startswith("ORACLE "):
            oracle = line[7:].strip().lower().replace(" ", "")
            break
    ok = bool(oracle)
    return ok, oracle, out


def rand_const(rng: random.Random) -> int:
    # Small ints; bias toward values that exercise sign extension and bit ops.
    pick = rng.random()
    if pick < 0.15:
        return rng.choice([0, 1, -1, 2, -2, 127, -128, 255, 256, 1024, -1024])
    if pick < 0.25:
        return rng.randint(0, 0xFFFF)
    return rng.randint(-500, 500)


def gen_var_names(rng: random.Random, n: int) -> List[str]:
    pool = ["a", "b", "c", "d", "e", "x", "y", "z", "t", "u", "v", "w"]
    rng.shuffle(pool)
    return pool[:n]


def gen_expr(
    rng: random.Random,
    depth: int,
    vars: Sequence[str],
    *,
    allow_div: bool = True,
) -> str:
    if depth <= 0 or (vars and rng.random() < 0.35):
        if vars and rng.random() < 0.65:
            return rng.choice(vars)
        return str(rand_const(rng))
    roll = rng.random()
    if roll < 0.12:
        inner = gen_expr(rng, depth - 1, vars, allow_div=allow_div)
        return f"(-({inner}))"
    if roll < 0.18 and vars:
        return f"(!({gen_expr(rng, depth - 1, vars, allow_div=False)}))"
    if roll < 0.28 and allow_div:
        rhs = gen_expr(rng, depth - 1, vars, allow_div=False)
        op = rng.choice(["/", "%"])
        if op == "/":
            return f"(({gen_expr(rng, depth - 1, vars, allow_div=False)}) / (({rhs}) ? ({rhs}) : 1))"
        return f"(({gen_expr(rng, depth - 1, vars, allow_div=False)}) % (({rhs}) ? ({rhs}) : 1))"
    if roll < 0.38:
        sh = rng.randint(0, 15)
        return f"(({gen_expr(rng, depth - 1, vars, allow_div=allow_div)}) << {sh})"
    if roll < 0.48:
        sh = rng.randint(0, 15)
        return f"(({gen_expr(rng, depth - 1, vars, allow_div=allow_div)}) >> {sh})"
    op = rng.choice(BINOPS)
    left = gen_expr(rng, depth - 1, vars, allow_div=allow_div)
    right = gen_expr(rng, depth - 1, vars, allow_div=allow_div)
    return f"(({left}) {op} ({right}))"


def gen_cmp(rng: random.Random, depth: int, vars: Sequence[str]) -> str:
    op = rng.choice(CMP_OPS)
    left = gen_expr(rng, max(0, depth - 1), vars, allow_div=False)
    right = gen_expr(rng, max(0, depth - 1), vars, allow_div=False)
    return f"(({left}) {op} ({right}))"


def wrap_main(body: str) -> str:
    return f"I64 main() {{\n{body}\n}}\n"


def gen_expr_return(rng: random.Random, depth: int) -> PropProgram:
    n = rng.randint(0, 3)
    names = gen_var_names(rng, n)
    lines: List[str] = []
    for nm in names:
        lines.append(f"  I64 {nm} = {rand_const(rng)};")
    ret = gen_expr(rng, depth, names)
    lines.append(f"  return {ret};")
    return PropProgram("expr", wrap_main("\n".join(lines)), "expr_return")


def gen_if_else(rng: random.Random, depth: int) -> PropProgram:
    names = gen_var_names(rng, rng.randint(1, 3))
    lines = [f"  I64 {nm} = {rand_const(rng)};" for nm in names]
    acc = "r"
    lines.append(f"  I64 {acc};")
    cond = gen_cmp(rng, depth, names)
    then_v = gen_expr(rng, max(1, depth - 1), names)
    else_v = gen_expr(rng, max(1, depth - 1), names)
    lines.extend(
        [
            f"  if ({cond}) {{",
            f"    {acc} = {then_v};",
            "  } else {",
            f"    {acc} = {else_v};",
            "  }",
            f"  return {acc};",
        ]
    )
    return PropProgram("if_else", wrap_main("\n".join(lines)), "if_else")


def gen_while_acc(rng: random.Random, depth: int) -> PropProgram:
    names = gen_var_names(rng, 2)
    a, i = names[0], names[1]
    limit = rng.randint(1, int(os.environ.get("COMPILER_PROP_MAX_LOOP", "8")))
    body = gen_expr(rng, max(1, depth - 1), [a, i], allow_div=False)
    lines = [
        f"  I64 {a} = {rand_const(rng)};",
        f"  I64 {i} = 0;",
        f"  while ({i} < {limit}) {{",
        f"    {a} = {a} + ({body});",
        f"    {i} = {i} + 1;",
        "  }",
        f"  return {a};",
    ]
    return PropProgram("while", wrap_main("\n".join(lines)), "while_acc")


def gen_nested_if(rng: random.Random, depth: int) -> PropProgram:
    names = gen_var_names(rng, 2)
    x, y = names[0], names[1]
    lines = [
        f"  I64 {x} = {rand_const(rng)};",
        f"  I64 {y} = {rand_const(rng)};",
        "  I64 r;",
        f"  if ({gen_cmp(rng, depth, names)}) {{",
        f"    if ({gen_cmp(rng, depth, names)}) {{",
        f"      r = {gen_expr(rng, depth - 1, names)};",
        "    } else {",
        f"      r = {gen_expr(rng, depth - 1, names)};",
        "    }",
        "  } else {",
        f"    r = {gen_expr(rng, depth - 1, names)};",
        "  }",
        "  return r;",
    ]
    return PropProgram("nested_if", wrap_main("\n".join(lines)), "nested_if")


def gen_helper_call(rng: random.Random, depth: int) -> PropProgram:
    fn = rng.choice(["F", "G", "H"])
    pnames = gen_var_names(rng, 2)
    a, b = pnames[0], pnames[1]
    body = gen_expr(rng, depth, [a, b])
    main_vars = gen_var_names(rng, 2)
    v1, v2 = main_vars[0], main_vars[1]
    src = (
        f"I64 {fn}(I64 {a}, I64 {b}) {{\n"
        f"  return {body};\n"
        f"}}\n\n"
        f"I64 main() {{\n"
        f"  I64 {v1} = {rand_const(rng)};\n"
        f"  I64 {v2} = {rand_const(rng)};\n"
        f"  return {fn}({v1}, {v2});\n"
        f"}}\n"
    )
    return PropProgram("helper", src, "helper_call")


GENERATORS = [
    (0.30, gen_expr_return),
    (0.25, gen_if_else),
    (0.20, gen_while_acc),
    (0.15, gen_nested_if),
    (0.10, gen_helper_call),
]


def pick_generator(rng: random.Random):
    r = rng.random()
    acc = 0.0
    for w, fn in GENERATORS:
        acc += w
        if r <= acc:
            return fn
    return GENERATORS[-1][1]


def gen_program(rng: random.Random, idx: int, depth: int) -> PropProgram:
    fn = pick_generator(rng)
    prog = fn(rng, depth)
    prog.name = f"prop_{idx}_{prog.kind}"
    return prog


def load_replay(name: str, src_rel: str) -> PropProgram:
    path = ROOT / src_rel
    return PropProgram(name, path.read_text(), "replay")


@dataclass
class TierOutcome:
    compile_rc: int = 0
    compile_err: str = ""
    ran: bool = False
    oracle: str = ""
    blob_size: int = 0
    run_log: str = ""


def run_case(
    tools: RunTools,
    ctx: HarnessCtx,
    work: Path,
    prog: PropProgram,
    tiers: Sequence[Tuple[str, Dict[str, str]]],
) -> Tuple[bool, str]:
    work.mkdir(parents=True, exist_ok=True)
    hc = work / f"{prog.name}.hc"
    hc.write_text(prog.source)

    outcomes: Dict[str, TierOutcome] = {}
    for tier_name, tier_env in tiers:
        out = TierOutcome()
        blob = work / f"{prog.name}_{tier_name}.bin"
        elf = work / f"{prog.name}_{tier_name}.elf"
        rc, err = compile_blob(tools, hc, blob, tier_env)
        out.compile_rc = rc
        out.compile_err = err
        if rc != 0:
            outcomes[tier_name] = out
            continue
        out.blob_size = blob.stat().st_size
        ok, oracle, raw = link_and_run(tools, ctx, blob, elf)
        out.ran = ok
        out.oracle = oracle
        out.run_log = raw
        outcomes[tier_name] = out

    rc_set = {outcomes[t].compile_rc for t, _ in tiers}
    if len(rc_set) != 1:
        detail = {t: outcomes[t].compile_rc for t, _ in tiers}
        return False, f"compile mismatch rc={detail}"

    if outcomes[tiers[0][0]].compile_rc != 0:
        return False, f"compile failed: {outcomes[tiers[0][0]].compile_err}"

    if any(not outcomes[t].ran for t, _ in tiers):
        bad = {t: outcomes[t].ran for t, _ in tiers}
        return False, f"run failure tiers={bad}"

    oracles = [outcomes[t].oracle for t, _ in tiers]
    if len(set(oracles)) != 1:
        detail = ", ".join(f"{t}={outcomes[t].oracle}" for t, _ in tiers)
        return False, f"semantic mismatch: {detail}"

    return True, oracles[0]


def run_props(
    tools: RunTools,
    tiers: Sequence[Tuple[str, Dict[str, str]]],
    rng: random.Random,
    trials: int,
    depth: int,
    tmp: Path,
) -> Tuple[int, int]:
    ctx = ensure_harness(tmp / "harness", tools)
    ok = fail = 0
    for i in range(trials):
        prog = gen_program(rng, i, depth)
        passed, msg = run_case(tools, ctx, tmp / "cases", prog, tiers)
        if passed:
            ok += 1
        else:
            fail += 1
            print(f"FAIL {prog.name}: {msg}", file=sys.stderr)
            fail_path = tmp / "cases" / f"{prog.name}.hc"
            if fail_path.is_file():
                print(f"  source: {fail_path}", file=sys.stderr)
    return ok, fail


def run_replay(
    tools: RunTools,
    tiers: Sequence[Tuple[str, Dict[str, str]]],
    tmp: Path,
) -> Tuple[int, int]:
    ctx = ensure_harness(tmp / "harness_replay", tools)
    ok = fail = 0
    for rel in REPLAY_SOURCES:
        name = Path(rel).stem
        prog = load_replay(f"replay_{name}", rel)
        passed, msg = run_case(tools, ctx, tmp / "replay", prog, tiers)
        if passed:
            ok += 1
        else:
            fail += 1
            print(f"FAIL {prog.name}: {msg}", file=sys.stderr)
    return ok, fail


def main() -> int:
    seed = int(os.environ.get("COMPILER_PROP_SEED", "42"))
    trials = int(os.environ.get("COMPILER_PROP_TRIALS", "60"))
    depth = int(os.environ.get("COMPILER_PROP_EXPR_DEPTH", "4"))
    tier_spec = os.environ.get("COMPILER_PROP_TIERS", "no_opt,default")

    tools = discover_tools()
    if tools is None:
        print(
            "error: need holyc-riscv, riscv64-unknown-elf-{gcc,ld,objcopy}, "
            "qemu-system-riscv64, timeout/gtimeout",
            file=sys.stderr,
        )
        return 2

    try:
        tiers = parse_tiers(tier_spec)
    except (KeyError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    rng = random.Random(seed)
    tmp = Path(tempfile.mkdtemp(prefix="holyc_compiler_prop_"))

    print(
        f"compiler-prop: seed={seed} trials={trials} depth={depth} "
        f"tiers={','.join(t for t, _ in tiers)}"
    )

    rep_ok, rep_fail = run_replay(tools, tiers, tmp)
    print(f"  replay: {rep_ok}/{len(REPLAY_SOURCES)} curated sources checked")

    gen_ok, gen_fail = run_props(tools, tiers, rng, trials, depth, tmp)

    total_fail = rep_fail + gen_fail
    total_ok = rep_ok + gen_ok
    print(
        f"✓ compiler-prop: generated {gen_ok}/{trials}, replay {rep_ok}/{len(REPLAY_SOURCES)} "
        f"(failures {total_fail})"
    )
    if total_fail:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
