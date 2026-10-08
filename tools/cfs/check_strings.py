#!/usr/bin/env python3
"""Every string literal in the translation must appear VERBATIM in the NASA source it came from.

WHY THIS GATE EXISTS, and it is a gap that stayed open for 109 sources. check_formats.py reads
the *conversions* out of a format string and checks the HolyC formatter implements each one. It
says nothing whatever about the text around them -- which is most of the string, and is the part
a ground display greps. An event text retyped by hand, a dropped word, a changed capital, a
singular made plural: every one of those passes check_formats, passes the differential (because
BOTH halves print the translation's wording -- the oracle is compiled from NASA's C, but the
transcript only compares the two halves to each other), and reaches a flight operator as a line
their decoder does not recognise.

It was found the way these things are found here: writing CS's cs_memory_cmds.HC by a name-map
transform from its twin cs_eeprom_cmds.HC, a one-off check that every quoted string in the
generated file appeared verbatim in NASA's own cs_memory_cmds.c caught two real defects --
NASA's dropped `CFE_` prefix and NASA's double space. A check worth running once on one file is
worth running on all 109.

AND THE FIRST FULL RUN FOUND A DRIFT OF MY OWN. mm_mem32.HC printed "Reducing from %u to %u"
where NASA prints "%d to %d" -- because the twin mm_mem16.c uses %u, and I had quietly made
NASA's two inconsistent siblings consistent. That is the exact opposite of a 1:1 translation, it
is unreachable through the command path (upstream note #12), and nothing else could have seen it.

### The four normalisations, and why each is not a hole

1.  **C adjacent-literal concatenation is folded** in the NASA text: `"a" "b"` becomes `"ab"`.
    NASA wraps long event texts across lines; HolyC has no concatenation, so the translation
    writes one literal. Without this, every wrapped string in cFE is a failure.
2.  **Length modifiers are dropped from conversions on both sides**: `%ld` and `%d` compare
    equal, `%zu` and `%u` compare equal. StrPrintNV implements no length modifiers by design
    (see CfsStr.HC), so the translation cannot carry them. `%d` against `%u` still FAILS -- that
    is a different conversion, not a different width, and it is what caught mm_mem32.
3.  **`\\'` compares equal to `'`.** NASA escapes an apostrophe inside a double-quoted string in
    cfe_tbl_load.c; it is the same byte.
4.  **`__func__` substitution.** cFE's syslog calls are `("%s: ...", __func__, ...)`; HolyC has
    no `__func__`, so the translation writes the function's name into the text. A literal that
    begins `Name: ` or `Name()` matches a NASA literal that begins `%s: ` or `%s()`. 39 strings
    across cFE take this path.

### What a PASS means, exactly, and the three things it does not mean

Each literal is looked for in the paired `<base>.c` and `<base>.h` first. A literal not there is
looked for in the WHOLE NASA corpus, and counted separately -- those are real: strings that live
in a platform-config header the translation inlined (`/ram/cfe_es_perf.dat`), or a message a
translated file took from a sibling. That fallback is the weak part of the gate and is reported
as its own number so the number can be watched rather than trusted.

It does NOT check the reverse direction, for now: a NASA literal missing from the translation is
not reported. (The reverse pass is cheap and is the obvious next widening; it needs an exempt
list for the strings in `#if`-excluded code, which this direction does not.)

It does NOT check argument lists -- see check_variadic and check_formats.

It does NOT check `#include` lines, which name HolyC files that have no business being in NASA.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfs_dirs import HCDIRS, ROOT, app_dirs                       # noqa: E402
from cfs_text import strip_comments_keep_strings                  # noqa: E402

# A double-quoted literal with C escapes. Deliberately refuses to span a newline: both trees
# write every literal on one line, and a regex that could span would swallow the code between
# two unrelated strings.
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

# C adjacent-literal concatenation: the quote pair BETWEEN two literals, with any whitespace
# (including newlines) between them. Folding it is what makes NASA's wrapped event texts one
# string. It cannot join two genuinely separate arguments -- those have a comma between them.
CONCAT = re.compile(r'"\s*"', re.S)

# printf length modifiers, to be dropped. The conversion character is KEPT: %ld -> %d.
LENGTH = re.compile(r'(%[-+ #0]*[0-9*]*(?:\.[0-9*]+)?)(?:hh|ll|[lhzjt])([diouxXeEfgGaAcspn])')

# A leading identifier where NASA writes __func__. `Name:` or `Name()` only -- an unanchored
# rule would let any literal starting with a word match any literal starting with %s.
FUNCNAME = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)(?=:|\(\))')

# Literals shorter than this are not compared: "\n", "%s", "/" and friends appear everywhere and
# a match would mean nothing. The four defects this gate exists to catch are all sentences.
MIN_LEN = 4

# (holyc file, literal) pairs that are in the translation and in no NASA source, WITH THE REASON.
# Empty is the honest state: nothing in the tree needs one. A new entry here is a claim about
# NASA that the next reader can check.
EXEMPT = {
    # NASA builds this by PREPROCESSOR TOKEN PASTING in cfe_version.h:
    #     #define CFE_SRC_VERSION CFE_BUILD_BASELINE "+dev" CFE_STR(CFE_BUILD_NUMBER)
    # HolyC has no `#` stringising operator, so cfe_config_init.HC writes the RESULT and carries
    # the recipe in a comment on the line above. The three inputs -- CFE_BUILD_BASELINE,
    # "+dev" and CFE_BUILD_NUMBER -- are each checked against NASA by check_constants, so the
    # pieces are gated even though the paste is not.
    ("cfe_config_init.HC", "v7.0.1+dev1"): "preprocessor token paste; the three inputs are gated"
      " individually by check_constants",
}


def normalise(text):
    return LENGTH.sub(r"\1\2", text.replace("\\'", "'"))


def literals_of(path):
    """(line number, literal) for every literal in a translated file, comments removed.

    Block comments by regex and `//` by the string-aware stripper -- in that order, and
    cfs_text.strip_comments_keep_strings' docstring says why the other order cannot work.
    """
    text = open(path, errors="replace").read()
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    out = []
    for n, line in enumerate(strip_comments_keep_strings(text).split("\n"), 1):
        if "#include" in line:
            continue
        for m in LITERAL.finditer(line):
            if len(m.group(1)) >= MIN_LEN:
                out.append((n, m.group(1)))
    return out


def main():
    # NASA sources, by basename, plus the whole corpus for the fallback.
    by_name = {}
    every = []
    for root in [os.path.join(ROOT, "vendor", "cFE"), os.path.join(ROOT, "vendor", "osal")] + \
            list(app_dirs()):
        for dirpath, _, filenames in os.walk(root):
            for fn in filenames:
                if fn.endswith((".c", ".h")):
                    path = os.path.join(dirpath, fn)
                    by_name.setdefault(fn, []).append(path)
                    every.append(path)
    if not every:
        print("FAIL cfs-strings — no NASA sources found under vendor/; this gate would pass on "
              "an empty haystack, which is the not-found shape it exists to avoid.",
              file=sys.stderr)
        return 1

    def haystack(paths):
        return normalise(CONCAT.sub("", "".join(open(p, errors="replace").read()
                                                for p in paths)))

    corpus = None
    compared = paired = via_func = via_corpus = exempt = 0
    unpaired_files = 0
    bad = []
    for hcdir in HCDIRS:
        if not os.path.isdir(hcdir):
            continue
        for fn in sorted(os.listdir(hcdir)):
            if not fn.endswith(".HC"):
                continue
            base = fn[:-3]
            sources = by_name.get(base + ".c", []) + by_name.get(base + ".h", [])
            if not sources:
                # A HolyC file with no NASA file of that name: this port's own glue
                # (CfsStr.HC, the *_offset.HC generated tables). check_coverage is the gate
                # that decides which NASA sources must exist; this one only compares text.
                unpaired_files += 1
                continue
            hay = haystack(sources)
            for line, raw in literals_of(os.path.join(hcdir, fn)):
                compared += 1
                lit = normalise(raw)
                if lit in hay:
                    paired += 1
                    continue
                m = FUNCNAME.match(lit)
                if m and ("%s" + lit[m.end():]) in hay:
                    via_func += 1
                    continue
                if (fn, raw) in EXEMPT:
                    exempt += 1
                    continue
                if corpus is None:
                    corpus = haystack(every)
                if lit in corpus:
                    via_corpus += 1
                    continue
                bad.append((os.path.join(os.path.basename(hcdir), fn), line, raw,
                            os.path.relpath(sources[0], ROOT)))

    if bad:
        print("FAIL cfs-strings — these literals are in the translation and in NO NASA source.",
              file=sys.stderr)
        print("     A retyped event text passes every other gate AND the differential, because", file=sys.stderr)
        print("     both halves print the translation's wording:", file=sys.stderr)
        for path, line, lit, src in bad[:40]:
            print("  %s:%d\n      has: %r\n      not in: %s" % (path, line, lit, src),
                  file=sys.stderr)
        if len(bad) > 40:
            print("  ... and %d more" % (len(bad) - 40), file=sys.stderr)
        print("     Fix the translation to NASA's text, or record the pair in"
              " tools/cfs/check_strings.py's EXEMPT with the reason.", file=sys.stderr)
        return 1

    print("cfs-strings: %d literals verbatim in the NASA source they were translated from "
          "(%d paired, %d via __func__, %d elsewhere in NASA, %d exempt; %d HolyC files have "
          "no NASA file of that name)"
          % (compared, paired, via_func, via_corpus, exempt, unpaired_files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
