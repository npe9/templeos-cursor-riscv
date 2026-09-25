#!/usr/bin/env python3
"""Guard the trailing autorun of every Demo/**/*.HC so #include-ing one does not RUN it.

A stock demo ends with its own entry point as a top-level statement ("Execute when #included").
That is right in TempleOS, where you open the file to play the game. It is wrong for anything that
includes the file to measure it, and it has produced a phantom kernel bug three times:

  * the "JobsHndlr bug" was Demo/Graphics/Lines.HC's unguarded `Main;` running at load;
  * a pass matching only a bare `Name;` alone on a line missed `Name;  //comment`,
    `Name;<TAB>//comment` and `Name(args);` — 16 files, four of them counted as L1-TRAP for a fault
    their own autorun reached;
  * Demo/Games/TheDead.HC and BlackDiamond.HC were "silent L1-HANGs with no top-level code at all".
    Both end in `TheDead;` / `BlackDiamond;` followed by a DolDoc BINARY TAIL, so a pass that took
    the last non-blank line of the file never saw the call. TheDead was spinning in RVSnd.

Hence the rule here: the autorun is the last non-blank line **that is source** — every byte printable
ASCII or tab — which skips a DolDoc tail. A line already wrapped in `#ifndef RV_NO_DEMO_AUTORUN` is
left alone, so the tool is idempotent and reports nothing to do on a clean tree.

It deliberately guards ONE statement, the trailing one, and not every top-level call. A demo that IS
a sequence of top-level statements (Demo/Carry.HC, Demo/Progress.HC, Demo/LastClass.HC) has that
sequence as its content; guarding all of it would make Demo/Carry.HC stop hanging by not running,
which hides the `IC_CARRY` gap instead of measuring it. `docs/DEMO_SURVEY.md` says per program where
the trailing guard is not the whole story.

KEEP names the files whose trailing statement is the file's whole point rather than a demo run.

Byte-preserving: these files carry DolDoc binary, so latin-1 in and out, and only ASCII inserted.

    tools/guard_demo_autoruns.py [--apply]
"""
import pathlib, re, sys

CALL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(\([^()]*\))?\s*;\s*(//.*)?$")
GUARD = "#ifndef RV_NO_DEMO_AUTORUN"
SRC_BYTES = set(range(0x20, 0x7F)) | {0x09}
KEEP = {
    "Demo/ParenWarn.HC",                   # Option(OPTf_WARN_PAREN,OFF) — a compile-time directive
    "Demo/AcctExample/HomeKeyPlugIns.HC",  # KeyDevAdd(...) — a Home file installing itself at boot
}


def is_source(line):
    return all(ord(c) in SRC_BYTES for c in line)


def main():
    apply = "--apply" in sys.argv
    n = 0
    for p in sorted(pathlib.Path(".").glob("Demo/**/*.HC")):
        lines = p.read_bytes().decode("latin-1").split("\n")
        i = next((j for j in range(len(lines) - 1, -1, -1)
                  if lines[j].strip() and is_source(lines[j])), None)
        if i is None:
            continue
        m = CALL.match(lines[i].strip())
        if not m or m.group(1) in ("endif", "else"):
            continue
        prev = next((lines[j] for j in range(i - 1, -1, -1) if lines[j].strip()), "")
        if prev.strip() == GUARD:
            continue
        if str(p) in KEEP:
            print("KEEP  %-42s %d: %s" % (p, i + 1, lines[i].strip()[:46]))
            continue
        print("GUARD %-42s %d: %s" % (p, i + 1, lines[i].strip()[:46]))
        n += 1
        if apply:
            lines[i:i + 1] = [GUARD, lines[i], "#endif"]
            p.write_bytes("\n".join(lines).encode("latin-1"))
    print("%d file(s)%s" % (n, "" if apply else " would change (pass --apply)"))


main()
