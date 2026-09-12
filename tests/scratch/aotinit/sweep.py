#!/usr/bin/env python3
"""Scratch: which file-scope initializers actually landed in the repl-holyc blob?

The AOT bakes constant initializer bytes into the data section, but an initializer
whose value is a *string literal address* is emitted as a top-level runtime store —
and repl-holyc enters at _start -> ReplMain, which never runs those. Read the blob
data straight out of build/hc_repl.blob.bin using the HOLYC_MAP offsets.
"""
import os
import re
import struct
import sys

ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

sym = {}
for line in open(os.path.join(ROOT, "build/repl.map")):
    off, _, name = line.strip().partition(" ")
    sym.setdefault(name, int(off, 16))

blob = open(os.path.join(ROOT, "build/hc_repl.blob.bin"), "rb").read()
repl = open(os.path.join(ROOT, "bootstrap/hc_repl/repl.hc")).read()
includes = re.findall(r'"(/bootstrap/[^"]*)"', repl)

DECL = re.compile(r"^[A-Za-z_]\w*\s+\*?\s*(\w+)\s*(\[[^\]]*\])?\s*=\s*(.+)")

rows = []
for inc in includes:
    path = ROOT + inc
    if not os.path.isfile(path):
        continue
    for lineno, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        if not line[:1].strip() or line.startswith(("/", "#")):
            continue
        m = DECL.match(line)
        if not m:
            continue
        name, arr, init = m.group(1), m.group(2) or "", m.group(3)
        rows.append((os.path.basename(inc), lineno, name, arr, init))

print("%-16s %-24s %-8s %s" % ("symbol", "file:line", "kind", "blob value(s)"))
for base, lineno, name, arr, init in rows:
    kind = "str" if '"' in init else ("addr" if "&" in init else "const")
    if name not in sym:
        print("%-16s %-24s %-8s NOT IN MAP" % (name + arr, f"{base}:{lineno}", kind))
        continue
    off = sym[name]
    n = 4 if arr else 1
    vals = struct.unpack_from("<%dQ" % n, blob, off)
    flag = ""
    if kind != "const" and not any(vals):
        flag = "   <== ZERO IN AOT IMAGE"
    print("%-16s %-24s %-8s %s%s"
          % (name + arr, f"{base}:{lineno}", kind,
             " ".join(hex(v) for v in vals), flag))
