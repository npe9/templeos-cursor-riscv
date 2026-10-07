#!/usr/bin/env python3
"""Every printf conversion in a gated NASA source must be one the HolyC formatter implements.

WHY THIS GATE EXISTS. Kernel/Cfs/CfsStr.HC's StrPrintNV handles a FIXED set of conversions and
emits anything else literally -- deliberately, so an unhandled case shows up in a transcript
rather than vanishing. But "shows up in a transcript" is only true of a format string some
exercise actually reaches. MM's mm_utils.c prints "Addr = %p" in six of its events, and %p
appeared in NO previously gated source, so until it was added the HolyC half would have written
the two characters `%p` where C wrote an address -- and nothing in the suite would have said so
until an exercise happened to drive one of those six events.

Worse than misprinting its own field: an unhandled conversion DOES NOT CONSUME ITS ARGUMENT, so
every argument after it on the line shifts by one. The same hazard already bit this port once --
the note on 'z' in CfsStr.HC records cfe_sb_api.c's "%zu" doing exactly that.

So this is the static half of the formatter's contract, and the transcript is the dynamic half.
Neither sees what the other sees: this gate reads format strings nobody calls, and the transcript
compares bytes for the ones that are called.

THE SUPPORTED SET IS READ OUT OF THE FORMATTER, not listed here. A conversion added to CfsStr.HC
widens this gate automatically; a conversion deleted from it narrows the gate in the same commit.
A hand-written list here would be a second opinion about the formatter that could rot away from
it, which is the shape of the stale-UNPAIRED_OK defect recorded in docs/CFS_PLAN.md.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfs_text import strip_comments

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FORMATTER = os.path.join(ROOT, "Kernel", "Cfs", "CfsStr.HC")

# Format strings that do NOT reach StrPrintNV. Keyed by the literal itself, with the reason, and
# narrow on purpose: a bare filename exemption would hide every future format string in the file.
NOT_OURS = {
    # cfe_time_api.c hands this to the C library's strftime, not to a printf -- a different
    # conversion language entirely, in which %Y, %j, %H, %M and %S are calendar fields.
    #
    # WHAT THIS EXEMPTION SAID FIRST WAS WRONG, and the correction is the point: it claimed the
    # call site was inside CFE_TIME_PrintUtc, which is "#if'd out of this port, and
    # check_coverage records that exclusion". Measured: the function is CFE_TIME_Print, it is
    # NOT excluded -- the three exclusions in cfe_time_api.c are CFE_TIME_ExternalGPS, _MET and
    # _Time -- and it IS translated, with a deviation recorded at the top of cfe_time_api.HC
    # (NASA calls gmtime_r and strftime; this port has no libc, so the calendar is written out).
    # So the exemption holds for the reason below and NOT for the reason first given. A stale
    # exemption reason that is a false claim about NASA is already on this project's list of
    # recurring shapes (see check_structs' UNPAIRED_OK note in docs/CFS_PLAN.md).
    "%Y-%j-%H:%M:%S": "strftime(), not a printf -- a different conversion language entirely",
}

# C's flags and precision. The formatter parses an optional '0' and an optional decimal width and
# NOTHING ELSE, so a '-', '+', ' ', '#' or '.' would be seen as an unknown conversion -- which
# does not consume the argument. Checked separately from the conversion letter because the
# failure is identical and the cause is not.
SPEC = re.compile(r"%([-+ #0]*)([0-9]*)(\.[0-9]*)?(hh|h|ll|l|z|j|t|L)?(.)", re.S)
STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def supported():
    """The conversion letters and length modifiers StrPrintNV compares *Fmt against."""
    src = open(FORMATTER).read()
    # Only the body of StrPrintNV: the file's other functions do not parse formats.
    start = src.index("I64 StrPrintNV(")
    body = src[start:]
    letters = set(re.findall(r"\*Fmt == '(.)'", body))
    # '%' and '0' are compared for too, and neither is a conversion: the first is the escape and
    # the second is the zero-pad flag.
    letters -= {"%", "0"}
    return letters


def literals(path):
    """Adjacent C string literals, concatenated as the preprocessor would.

    COMMENTS OUT FIRST, and the reason is the bug this project found in three other gates the
    same day: a string in a comment is not a format string. A NASA doc comment containing, say,
    `%q` would have failed this gate on a conversion the compiler never sees -- the mirror image
    of the stripper defect in tools/cfs/cfs_text.py, in the gate written to catch format bugs.

    MEASURED BEFORE APPLYING, because cfs_text.strip_comments is NOT string-aware and a real
    format string containing `//` would be blanked by it. Across the 96 gated sources: 773
    literals contain a `%`, ZERO of them are comment-only, and ZERO code strings disappear. So
    the change is a no-op today and closes the exposure.
    """
    src = strip_comments(open(path).read())
    out = []
    i = 0
    while True:
        m = STRING.search(src, i)
        if not m:
            break
        parts = [m.group(1)]
        j = m.end()
        while True:
            n = STRING.match(src, j) or STRING.search(src, j)
            # adjacent means only whitespace in between
            if n and src[j:n.start()].strip() == "":
                parts.append(n.group(1))
                j = n.end()
            else:
                break
        text = "".join(parts).replace("\\%", "%")
        out.append((src.count("\n", 0, m.start()) + 1, text))
        i = j
    return out


def main(argv):
    ok = set(supported())
    if not ok:
        print("FAIL cfs-formats — read no conversions out of CfsStr.HC's StrPrintNV", file=sys.stderr)
        return 1
    mods = {"l", "z"}
    convs = ok - mods
    bad = []
    seen = {}
    scanned = 0
    for path in argv:
        for line, text in literals(path):
            if "%" not in text:
                continue
            if text in NOT_OURS:
                continue
            for m in SPEC.finditer(text):
                flags, width, prec, length, conv = m.groups()
                if conv == "%":
                    continue
                scanned += 1
                spec = m.group(0)
                why = None
                if conv not in convs:
                    why = "conversion %%%s is not implemented" % conv
                elif set(flags) - {"0"}:
                    why = "flag(s) %r are not implemented" % "".join(sorted(set(flags) - {"0"}))
                elif prec:
                    why = "a precision (%r) is not implemented" % prec
                elif length and length not in mods and length != "ll":
                    why = "length modifier %r is not implemented" % length
                if why:
                    bad.append((os.path.relpath(path, ROOT), line, spec, why))
                else:
                    seen[spec] = seen.get(spec, 0) + 1
    if bad:
        print("FAIL cfs-formats — StrPrintNV would not consume these, so every argument after", file=sys.stderr)
        print("     them on the line shifts by one:", file=sys.stderr)
        for path, line, spec, why in bad[:40]:
            print("  %s:%d  %-8s %s" % (path, line, spec, why), file=sys.stderr)
        print("     Implement it in Kernel/Cfs/CfsStr.HC, or record the call site in", file=sys.stderr)
        print("     tools/cfs/check_formats.py's NOT_OURS with the reason it is not a printf.", file=sys.stderr)
        return 1
    print("cfs-formats: %d conversions in %d NASA sources, %d distinct forms, all implemented "
          "by StrPrintNV (%s)" % (scanned, len(argv), len(seen),
                                  " ".join("%%%s" % c for c in sorted(convs))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
