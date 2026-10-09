#!/usr/bin/env python3
"""Every #define NASA's header has, the translation has too.

WHAT THE OTHER GATES DO NOT ASK. check_constants.py compares the VALUE of every constant that is
in the translation against NASA's; check_coverage.py compares the set of FUNCTIONS. Neither asks
whether a translated header is COMPLETE -- a #define that was never translated is simply not there
to compare, and every gate passes.

HOW THAT BIT. HS's hs_eventids.HC was extracted with

    grep -E '^#define HS_[A-Z0-9_]+_EID'

which is case-sensitive, and eight of NASA's 77 event ids are the four table validators' pairs --
HS_AMTVal_INF_EID, HS_AMTVal_ERR_EID and six more, each with a lowercase "Val" in the middle. The
pattern matched none of them. The file shipped eight ids short, and the comment at the top asserted
that 50 through 57 were GAPS where features had been removed. They are the ids hs_monitors.c uses
most. check_constants reported 2,108 constants matching and was right: the 2,108 that were there
did match.

What found it was reading another source and seeing a name in a call. That is not a gate.

WHAT THIS COMPARES. Every object-like #define in every NASA header that has a translated
counterpart by basename, against the set of names the translation defines ANYWHERE.

**NOT against the same-named file**, and that distinction is the whole design. This port groups
NASA's constants by subject rather than by header: hk_app.h's five return codes live in
hk_global.HC beside the type they belong to, and hk_utils.h's flag constants live in hk_tbl.HC
beside the structures they describe. A gate that demanded hk_app.HC carry hk_app.h's #defines
would report seven files "missing" constants that are translated and correct -- which is what the
first version of this gate did, and a gate that cries wolf on a deliberate choice gets an
exemption list instead of a fix.

The failure this catches is the one that actually happened: a constant that is **nowhere**. The
reverse direction -- a name the translation invents -- is check_constants' "names NASA does not
define" and is not repeated here.

WHAT IS SKIPPED, AND WHY EACH IS SAFE:

  include guards            `#ifndef FOO_H / #define FOO_H`, which a translation renames to
                            `FOO_HC` by convention. Matched by the guard's own name appearing in
                            the `#ifndef` immediately above it.
  function-like macros      `#define F(x) ...`. A translation may write these out as functions
                            (a header `static inline` does), so a missing NAME is not a missing
                            definition. check_header_inlines owns that question.
  token-paste call sites    `#define HS_PIPE_DEPTH HS_INTERNAL_CFGVAL(PIPE_DEPTH)`. HolyC has no
                            `##`, so the port writes the RESOLVED value and the CFGVAL spelling
                            never appears. The DEFAULT_ name beside it carries the value and IS
                            required, which is the half that matters.
  the eds_ variants         CFE_EDS_ENABLED is off in this configuration, so eds_*.h is not built.

Run it with -v to list what was compared rather than only what was missing.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfs_dirs import HCDIRS, app_dirs  # noqa: E402  -- one copy of these lists

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Where NASA's headers are. The same set check_structs searches, because the question is the same:
# which file is this translated one's counterpart.
NASA_DIRS = app_dirs() + [
    os.path.join(ROOT, "vendor", "osal", "src", "os", "inc"),
    os.path.join(ROOT, "vendor", "osal", "src", "os", "shared", "inc"),
    os.path.join(ROOT, "vendor", "PSP", "fsw", "inc"),
]
for pat in ("fsw/inc", "fsw/src", "config", "option_inc", "private_inc"):
    base = os.path.join(ROOT, "vendor", "cFE", "modules")
    if os.path.isdir(base):
        for m in sorted(os.listdir(base)):
            d = os.path.join(base, m, *pat.split("/"))
            if os.path.isdir(d):
                NASA_DIRS.append(d)
base = os.path.join(ROOT, "vendor", "PSP", "fsw", "modules")
if os.path.isdir(base):
    for m in sorted(os.listdir(base)):
        d = os.path.join(base, m, "inc")
        if os.path.isdir(d):
            NASA_DIRS.append(d)

# An object-like #define: a name NOT followed immediately by `(`.
OBJ = re.compile(r"^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)(?![\w(])")
# A function-like one, for the skip count.
FUN = re.compile(r"^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)\(")
GUARD = re.compile(r"^[ \t]*#[ \t]*ifndef[ \t]+([A-Za-z_]\w*)")
# A definition whose BODY is a call to a macro -- the token-paste shape. `X CFGVAL(Y)` and
# `X MIDVAL(Y)` are the two cFS uses; anything of that form is a call site, not a value.
PASTE = re.compile(r"^[ \t]*#[ \t]*define[ \t]+[A-Za-z_]\w*[ \t]+[A-Za-z_]\w*\([^)]*\)[ \t]*$")

# TRANSLATED FILES WHOSE NAME DOES NOT MATCH THE NASA HEADER THEY CARRY.
#
# The pairing above is by BASENAME, so a translated file called something else is UNPAIRED -- and
# an unpaired file generates no requirement at all, which means the gate reports green on a header
# whose constants are nowhere. That is not hypothetical:
#
# Every app in this port puts its global's TYPES in `*_global.HC` while NASA declares them in
# `*_app.h`. For MD, MM, CS, LC, HK and HS that gap is closed BY ACCIDENT -- each has an
# `*_app.HC` (the translation of *_app.c) which pairs with `*_app.h` by basename and makes its
# constants required. SC's sc_app.c had not been translated yet, so sc_app.h was unpaired, and
# sc_global.HC shipped with ELEVEN of its fifteen object-like defines. Deleting SC_BYTES_IN_WORD
# produced no complaint; the omission surfaced two commits later as a compile failure in
# sc_loads.c, which needed SC_INVALID_CMD_NUMBER.
#
# So the pairing is made EXPLICIT rather than left to depend on which sources happen to be gated.
# `*_global.HC` is checked against `*_app.h` directly, for every app, which also means the
# requirement does not silently disappear if an `*_app.HC` is ever renamed or split.
ALIASES = {
    "md_global":  "md_app",
    "mm_global":  "mm_app",
    "cs_global":  "cs_app",
    "lc_global":  "lc_app",
    "hk_global":  "hk_app",
    "hs_global":  "hs_app",
    "sc_global":  "sc_app",
}

# Pairs where a translated file deliberately carries only part of NASA's header, each with the
# reason. An entry is a CLAIM and a stale one fails, because the names are listed explicitly.
PARTIAL_OK = {}


def nasa_defines(path):
    """(object-like names, function-like count, paste-call count) in one NASA header."""
    names, funs, pastes = set(), 0, 0
    prev_guard = None
    try:
        lines = open(path, errors="replace").read().split("\n")
    except OSError:
        return names, 0, 0
    for i, line in enumerate(lines):
        g = GUARD.match(line)
        if g:
            prev_guard = g.group(1)
            continue
        if FUN.match(line):
            funs += 1
            continue
        if PASTE.match(line):
            pastes += 1
            continue
        m = OBJ.match(line)
        if not m:
            continue
        if m.group(1) == prev_guard:
            continue                     # the include guard itself
        names.add(m.group(1))
    return names, funs, pastes


def hc_defines(path):
    """Every name the translation #defines, object-like or not."""
    out = set()
    for line in open(path, errors="replace").read().split("\n"):
        m = re.match(r"^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)", line)
        if m:
            out.add(m.group(1))
    return out


def main(argv):
    verbose = "-v" in argv
    # NASA header basename -> path. First match wins, and the directory order above is the same
    # one check_structs uses, so a name that exists twice resolves the same way in both.
    index = {}
    for d in NASA_DIRS:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith(".h") and not f.startswith("eds_") and f not in index:
                index[f] = os.path.join(d, f)

    # Every name the TRANSLATION defines, across every translated directory, collected once.
    ALL_HC = set()
    for d in HCDIRS:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith(".HC"):
                ALL_HC |= hc_defines(os.path.join(d, f))

    pairs = 0
    compared = 0
    skipped_fun = 0
    skipped_paste = 0
    missing = []
    unpaired = 0

    for d in HCDIRS:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".HC"):
                continue
            hc = os.path.join(d, f)
            # hs_eventids.HC <-> hs_eventids.h, and also the config/default_ spelling.
            stem = f[:-3]
            cand = (index.get(ALIASES.get(stem, stem) + ".h")
                    or index.get(stem + ".h")
                    or index.get("default_" + stem + ".h"))
            if cand is None:
                unpaired += 1
                continue
            pairs += 1
            want, funs, pastes = nasa_defines(cand)
            skipped_fun += funs
            skipped_paste += pastes
            compared += len(want)
            key = os.path.relpath(hc, ROOT)
            allowed = PARTIAL_OK.get(key, set())
            # ALL_HC, not this file's own defines -- see the module docstring.
            gone = sorted(n for n in want if n not in ALL_HC and n not in allowed)
            if gone:
                missing.append((key, os.path.relpath(cand, ROOT), gone))
            if verbose:
                print("  %-44s <- %-44s %d compared" % (key, os.path.relpath(cand, ROOT),
                                                        len(want)))

    if missing:
        print("FAIL cfs-defines — NASA defines a constant the translation does not. A #define", file=sys.stderr)
        print("  that was never translated is not there for check_constants to compare, so every", file=sys.stderr)
        print("  other gate passes. Translate it, or add it to PARTIAL_OK with the reason.", file=sys.stderr)
        for hc, nasa, gone in missing:
            print("    %s (vs %s) is missing %d:" % (hc, nasa, len(gone)), file=sys.stderr)
            for n in gone:
                print("        %s" % n, file=sys.stderr)
        return 1

    if pairs == 0:
        print("FAIL cfs-defines — no translated file was paired with a NASA header, so this", file=sys.stderr)
        print("  compared NOTHING. The pairing is by basename; check the search path.", file=sys.stderr)
        return 1

    print("cfs-defines: %d constants in %d NASA headers are all defined somewhere in the "
          "translation "
          "(%d function-like and %d token-paste macros not compared, %d translated files have no "
          "NASA header of that name)" % (compared, pairs, skipped_fun, skipped_paste, unpaired))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
