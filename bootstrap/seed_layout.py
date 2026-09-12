#!/usr/bin/env python3
"""Memfs install paths for bootstrap/seed/*.hc (REPL arena, not host paths).

TempleOS-ish directories (Home, Tmp, Apps, Doc, …). Seed *basenames* stay unique so
Cat("print.hc") / Run("A01_RV64I.hc") resolve via basename fallback during the
flat → tree transition. Kernel/Drv stay out of REPL memfs.
"""
from __future__ import annotations

import glob
import os

# Empty dirs need .dir markers so Dir lists them. Others also get markers so
# Cd/Dir work before any file is created in that folder.
DIRS = (
    "Home",
    "Tmp",
    "Boot",
    "Lib",
    "Apps",
    "Asm",
    "Doc",
    "Doc/Datasheet",
    "Tutorials",
)

# Top-level seed/*.hc → parent directory (basename unchanged).
FILE_DIR = {
    "MemMapSelected.hc": "Boot",
    "RVEditorSelected.hc": "Boot",
    "boot.hc": "Boot",
    "ops.hc": "Boot",
    "start.hc": "Boot",
    "rt.hc": "Boot",
    "c_api.hc": "Boot",
    "trap.hc": "Boot",
    "timer.hc": "Boot",
    "debug.hc": "Boot",
    "crash.hc": "Boot",
    "hwdbg.hc": "Boot",
    "gdbstub.hc": "Boot",
    "dbg_jit_sym.hc": "Boot",
    "uart.hc": "Lib",
    "tty.hc": "Lib",
    "frame.hc": "Lib",
    "console.hc": "Lib",
    "mem.hc": "Lib",
    "print.hc": "Lib",
    "str.hc": "Lib",
    "log.hc": "Lib",
    "sys.hc": "Lib",
    "fs.hc": "Lib",
    "run.hc": "Lib",
    # G28 soft BlkDev letter tables (Let2Drv / RVSoftLetPlant) — sibling of fs.hc.
    "soft_let.hc": "Lib",
    "math.hc": "Lib",
    "term.hc": "Lib",
    "dir.hc": "Lib",
    "files.hc": "Lib",
    # Stock ships F/R/FD/RD as ~/HomeWrappers.HC — keep the /Home metaphor.
    "home_wrappers.hc": "Home",
    "fmt.hc": "Lib",
    "complete.hc": "Lib",
    "readline.hc": "Lib",
    "sym.hc": "Lib",
    "ninep.hc": "Lib",
    "csr.hc": "Lib",
    "ds.hc": "Lib",
    "funs.hc": "Apps",
    "callers.hc": "Apps",
    "edit.hc": "Apps",
    "ed.hc": "Apps",
    "vim.hc": "Apps",
    "zmodem.hc": "Apps",
    "trzsz.hc": "Apps",
    "asm_doc.hc": "Asm",
    "asm_complete.hc": "Asm",
    "disasm.hc": "Asm",
    "man.hc": "Doc",
    "man_topics.hc": "Doc",
    "tutorial.hc": "Doc",
}


def memfs_path(rel: str) -> str:
    """Host-relative seed path or basename → memfs path (no leading /)."""
    rel = rel.replace("\\", "/").lstrip("/")
    if rel.startswith("tutorials/"):
        return "Tutorials/" + os.path.basename(rel)
    if rel.startswith("datasheet/"):
        return "Doc/Datasheet/" + os.path.basename(rel)
    base = os.path.basename(rel)
    d = FILE_DIR.get(base)
    if not d:
        raise KeyError(
            "unmapped seed file %r — add it to FILE_DIR in seed_layout.py" % (rel,)
        )
    return d + "/" + base


def iter_seed_files(seed_dir: str):
    """Yield (host_path, memfs_name) for every shipped seed."""
    files = sorted(glob.glob(os.path.join(seed_dir, "*.hc")))
    tut = sorted(glob.glob(os.path.join(seed_dir, "tutorials", "*.hc")))
    ds = sorted(glob.glob(os.path.join(seed_dir, "datasheet", "*.hc")))
    for p in files:
        yield p, memfs_path(os.path.basename(p))
    for p in tut:
        yield p, memfs_path("tutorials/" + os.path.basename(p))
    for p in ds:
        yield p, memfs_path("datasheet/" + os.path.basename(p))
