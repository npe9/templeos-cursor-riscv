#!/usr/bin/env python3
"""Guard the trailing autorun of every Demo/**/*.HC so #include-ing one does not RUN it.

A stock demo ends with its own entry point as a top-level statement ("Execute when #included").
That is right in TempleOS, where you open the file to play the game; it is wrong for anything that
includes the file to measure it, and it produced a phantom kernel bug once already — the
"JobsHndlr bug" was Demo/Graphics/Lines.HC's unguarded `Main;` running at load.

The first pass (commit 803dfbc2) matched only a bare `Name;` alone on a line and so missed
`Name;  //comment`, `Name;<TAB>//comment` and `Name(args);` — 18 files, including four whose
L1-TRAP in docs/DEMO_SURVEY.md was the autorun rather than the include.

Two files are deliberately NOT guarded, because the trailing statement is the file's whole point
rather than a demo run:
  Demo/ParenWarn.HC             Option(OPTf_WARN_PAREN,OFF) — a compile-time directive
  Demo/AcctExample/HomeKeyPlugIns.HC  KeyDevAdd(...) — a Home file installing itself at boot

Byte-preserving: these files carry DolDoc binary, so latin-1 in and out, and only ASCII inserted.

    tools/guard_demo_autoruns.py [--apply]
"""
import pathlib, re, sys

CALL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(\([^()]*\))?\s*;\s*(//.*)?$")
KEEP = {"Demo/ParenWarn.HC", "Demo/AcctExample/HomeKeyPlugIns.HC"}

def main():
    apply = "--apply" in sys.argv
    n = 0
    for p in sorted(pathlib.Path(".").glob("Demo/**/*.HC")):
        txt = p.read_bytes().decode("latin-1")
        if "RV_NO_DEMO_AUTORUN" in txt:
            continue
        lines = txt.split("\n")
        i = next((j for j in range(len(lines) - 1, -1, -1) if lines[j].strip()), None)
        if i is None:
            continue
        m = CALL.match(lines[i].strip())
        if not m or m.group(1) in ("endif", "else"):
            continue
        if str(p) in KEEP:
            print("KEEP  %-44s %s" % (p, lines[i].strip()[:48]))
            continue
        print("GUARD %-44s %s" % (p, lines[i].strip()[:48]))
        n += 1
        if apply:
            lines[i:i + 1] = ["#ifndef RV_NO_DEMO_AUTORUN", lines[i], "#endif"]
            p.write_bytes("\n".join(lines).encode("latin-1"))
    print("%d file(s)%s" % (n, "" if apply else " would change (pass --apply)"))

main()
