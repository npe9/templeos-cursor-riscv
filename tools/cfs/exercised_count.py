#!/usr/bin/env python3
"""Which of an app's NASA functions did the exercise actually RUN?

APPLE'S gcov IGNORES -f, so there are no "function X called N returned" records to read. The
first version of this tool parsed for exactly those, found none, and reported "0 of 56 NASA
functions run" -- while the transcript plainly showed every one of them running. A measuring tool
that cannot find its subject and reports a number anyway is the blind-spot shape this whole suite
is built around, so: the count of parsed line records is printed, and zero is a hard failure.

PER-FUNCTION EXECUTION IS DERIVED FROM **LINE** COUNTS. Find each function's definition line in
NASA's source, then walk forward to the first line gcov marked executable (a count, or ##### for
zero) and read it. That line is the function's first statement, so its count is the function's
entry count.

The DENOMINATOR is NASA's own function list, taken from the source rather than from the gcov
output -- a function gcov dropped entirely must read as a miss, not vanish from the total.
"""
import glob
import os
import re
import sys

app = sys.argv[1]
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def gcov_counts(path):
    """line number -> execution count, for the lines gcov considered executable."""
    out = {}
    for raw in open(path, errors="replace"):
        parts = raw.split(":", 2)
        if len(parts) < 3:
            continue
        cnt, ln = parts[0].strip(), parts[1].strip()
        if not ln.isdigit() or cnt == "-":
            continue
        out[int(ln)] = 0 if cnt[0] in "#=" else int(cnt.rstrip("*"))
    return out


DEF = re.compile(r"^[A-Za-z_][\w \t\*]*?\b((?:%s|%s)_\w+)\s*\(" % (app, app.upper()))

# **WHICH SOURCES ARE GATED, READ FROM THE SMOKE'S OWN SRC_C.**
#
# The first six apps were gated and exercised in one commit each, so every source under
# fsw/src was in the build and a missing .gcov could only mean the measurement had failed --
# which is what the exit below is for, and it has fired.
#
# SC is being gated source by source. Globbing fsw/src then demanded a .gcov for sc_app.c,
# sc_cmds.c and sc_dispatch.c, which are not compiled yet, and the gate refused to run at all.
# Deleting the exit would have been the wrong repair: it is the only thing standing between this
# tool and the "0 of 56 functions" it once printed from no data.
#
# So the denominator is now the sources the smoke actually COMPILES, and the ones it does not are
# listed by name. A gated source with no .gcov is still a hard failure; an ungated one is reported
# as ungated, and the printed total says which of the two it was.
def gated_sources(app):
    smoke = os.path.join(ROOT, "tests", "scripts", "run_cfs_xlat_smoke.sh")
    txt = open(smoke, errors="replace").read()
    return set(re.findall(r"\$%s/fsw/src/(\w+\.c)" % app.upper(), txt))


GATED = gated_sources(app)
if not GATED:
    sys.exit("FAIL exercised -- the smoke names no $%s/fsw/src source, so there is nothing to"
             " measure and a number here would be from no data" % app.upper())

tot = run = 0
nrecords = 0
ungated = []
for src in sorted(glob.glob("%s/vendor/%s/fsw/src/*.c" % (ROOT, app))):
    base = os.path.basename(src)
    if base.endswith("_eds_dispatch.c"):
        continue  # excluded by the build: CFE_EDS_ENABLED is off
    if base not in GATED:
        ungated.append(base)
        continue
    gcov = base + ".gcov"
    if not os.path.exists(gcov):
        sys.exit("FAIL exercised -- no %s, so %s measured NOTHING" % (gcov, base))
    counts = gcov_counts(gcov)
    nrecords += len(counts)
    lines = open(src, errors="replace").read().split("\n")
    names, miss = [], []
    for i, l in enumerate(lines):
        m = DEF.match(l)
        if not m or l.rstrip().endswith(";"):
            continue
        names.append(m.group(1))
        hit = None
        for j in range(i + 1, min(i + 120, len(lines))):
            if (j + 1) in counts:
                hit = counts[j + 1]
                break
        if not hit:
            miss.append(m.group(1))
    tot += len(names)
    run += len(names) - len(miss)
    print("  %s %-22s %2d/%-2d %s" % ("OK  " if not miss else "MISS", base,
                                      len(names) - len(miss), len(names), " ".join(miss)))
if nrecords == 0:
    sys.exit("FAIL exercised -- parsed no line records at all; this measured nothing")
print("%s-exercised: %d of %d NASA functions run by the exercise (%d gcov line records%s)"
      % (app.lower(), run, tot, nrecords,
         "" if not ungated else "; NOT GATED and so NOT counted: " + " ".join(sorted(ungated))))
