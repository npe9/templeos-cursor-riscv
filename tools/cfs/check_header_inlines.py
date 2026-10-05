#!/usr/bin/env python3
"""A `static inline` in a NASA HEADER is code, and nothing was checking it.

THE HOLE THIS CLOSES. check_coverage.py says so in its own comment -- "`static inline` in a
header is not our business; these are .c files" -- and that was true right up until it was not.
cFS puts real logic in header inlines: `cfe_tbl_regrec.h` has twenty of them,
`cfe_tbl_loadbuff.h` thirteen, `cfe_es_resource.h` twenty-four. 163 across the headers this
port reads. They are indistinguishable from `.c` functions at the call site and they do the
same work, and every one of them was outside every gate.

That they were mostly translated anyway is not reassurance, it is luck: 92 of the 163 are
present because whoever translated the calling source went and found them. The question a gate
has to answer is what happens to the ones nobody went and found.

WHAT IS REQUIRED IS COMPUTED, NOT LISTED. An inline is required when a GATED NASA source calls
it, or when a required inline's own body calls it -- the transitive closure. So the skip set
cannot rot into a hiding place: gating a new `.c` makes its inlines required the same moment,
with no list to remember to update. Of the 71 inlines absent from the translation today, every
single one is uncalled from any gated source, which is why this gate passes on the tree it was
written against and will not pass on the next source gated without them.

THE TYPED-ID WRAPPER FAMILY IS A RULE, NOT AN EXCEPTION LIST. cFS gives each kind of resource
id its own C type purely so a compiler refuses a mix-up -- `CFE_TBL_HandleID_IsDefined`,
`CFE_ES_AppID_IsEqual`, `CFE_SB_PipeId_AsInt` and three dozen siblings whose entire body is one
`CFE_RESOURCEID_*` macro applied to the argument. HolyC has ONE id type, so they all collapse
onto the `CFE_ResourceId_*` function they wrap, and that is what every call site in this port
does. An inline whose body is exactly that shape is therefore satisfied by the presence of the
`CFE_ResourceId_*` function it names -- which is itself checked, so the collapse cannot hide a
missing one. The rule is applied by READING THE BODY, so an inline that wraps a macro AND does
something else does not qualify.

Usage: check_header_inlines.py [-v]
"""
import re, sys, os, glob

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS = os.path.join(ROOT, 'tests', 'scripts')
HCDIRS = [os.path.join(ROOT, 'Kernel', 'Cfs', 'cfe'),
          os.path.join(ROOT, 'Kernel', 'Cfs', 'osal')]

# Where NASA's headers live. The same list check_structs.py and check_padding.py search, and for
# the same reason recorded there: `modules/*/option_inc` and `osal/src/os/shared/src` were each
# missing from a gate once and every type in them was silently skipped.
NASA_DIRS = ['vendor/cFE/modules/*/fsw/src', 'vendor/cFE/modules/*/fsw/inc',
             'vendor/cFE/modules/*/config', 'vendor/cFE/modules/*/option_inc',
             'vendor/osal/src/os/inc', 'vendor/osal/src/os/shared/inc']

# `static inline <return type> NAME(` with the return type allowed to carry `*`, `const` and a
# struct tag. The name is the last identifier before the '('.
INLINE = re.compile(r'static\s+inline\s+((?:[A-Za-z_]\w*|\*)(?:[\s*]+(?:[A-Za-z_]\w*|\*))*?)'
                    r'\s*\**\s*([A-Za-z_]\w*)\s*\(', re.M)

# A body that is nothing but one CFE_RESOURCEID_* macro call (optionally returned, optionally
# parenthesised). This is the typed-id wrapper family; see the note above.
IDWRAP = re.compile(r'^\s*(?:return\s*)?\(?\s*(CFE_RESOURCEID_[A-Z_]+)\s*\(([^;{}]*)\)\s*\)?\s*;?\s*$')

# Which CFE_ResourceId_* function each CFE_RESOURCEID_* macro reduces to in this port. Every
# value is CHECKED to exist in the translation, so a wrong one here is a failure, not a pass.
MACRO_TO_FN = {
    'CFE_RESOURCEID_TEST_DEFINED': 'CFE_ResourceId_IsDefined',
    'CFE_RESOURCEID_TEST_EQUAL':   'CFE_ResourceId_Equal',
    'CFE_RESOURCEID_TO_ULONG':     'CFE_ResourceId_ToInteger',
    'CFE_RESOURCEID_UNWRAP':       'CFE_ResourceId_ToInteger',
    'CFE_RESOURCEID_WRAP':         'CFE_ResourceId_FromInteger',
}


def gated_sources():
    """Every NASA .c any differential smoke script compiles, read FROM the scripts."""
    out = []
    for name in sorted(os.listdir(SCRIPTS)):
        if not name.endswith('.sh'):
            continue
        text = open(os.path.join(SCRIPTS, name), errors='replace').read()
        for m in re.finditer(r'^SRC_C="(.*?)"$', text, re.S | re.M):
            for tok in m.group(1).split():
                if not tok.endswith('.c'):
                    continue
                for var, sub in (('$CFE/', 'vendor/cFE/'), ('$OSAL/', 'vendor/osal/'),
                                 ('$PSP/', 'vendor/psp/')):
                    if tok.startswith(var):
                        p = os.path.join(ROOT, sub + tok[len(var):])
                        if p not in out and os.path.exists(p):
                            out.append(p)
    return out


def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), src, flags=re.S)
    return re.sub(r'//[^\n]*', '', src)


def brace_body(src, open_paren_end):
    """The text between the '{' that follows a declarator and its matching '}'."""
    i = src.find('{', open_paren_end)
    if i < 0:
        return ''
    depth = 0
    for j in range(i, len(src)):
        if src[j] == '{':
            depth += 1
        elif src[j] == '}':
            depth -= 1
            if depth == 0:
                return src[i + 1:j]
    return ''


def header_inlines():
    """{name: (header path, return type, body)} for every static inline NASA declares."""
    out = {}
    for d in NASA_DIRS:
        for f in sorted(glob.glob(os.path.join(ROOT, d, '*.h'))):
            src = strip_comments(open(f, errors='replace').read())
            for m in INLINE.finditer(src):
                # skip to the end of the parameter list, then take the body
                k = src.index('(', m.start(2))
                depth = 0
                end = k
                for j in range(k, len(src)):
                    if src[j] == '(':
                        depth += 1
                    elif src[j] == ')':
                        depth -= 1
                        if depth == 0:
                            end = j + 1
                            break
                params = [q.split()[-1].lstrip('*') for q in src[k + 1:end - 1].split(',')
                          if q.strip() and q.strip() != 'void']
                out[m.group(2)] = (os.path.relpath(f, ROOT), m.group(1).strip(),
                                   brace_body(src, end), params)
    return out


def hc_defined():
    names = set()
    for d in HCDIRS:
        for f in glob.glob(os.path.join(d, '*.HC')):
            src = re.sub(r'//[^\n]*', '', open(f, errors='replace').read())
            for m in re.finditer(
                    r'^(?:U0|I8|U8|I16|U16|I32|U32|I64|U64|F64|Bool|[A-Z][A-Za-z0-9_]*)\s+\**'
                    r'([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*?\)\s*$', src, re.M):
                names.add(m.group(1))
    return names


def called_names(text, universe):
    return {n for n in universe if re.search(r'\b' + re.escape(n) + r'\s*\(', text)}


def main(argv):
    verbose = '-v' in argv
    inlines = header_inlines()

    # THE SCAN IS CHECKED AGAINST AN EXACT NUMBER, not a floor. This started as
    # `if len(inlines) < 100` -- a magic threshold that would have passed happily while the
    # pattern silently missed a few. It nearly did: a throwaway regex written the same day
    # missed `CFE_TBL_LoadBuffSetUsed`, whose `static inline void` sits on the line ABOVE its
    # declarator, and nothing would have said so. The number of inlines PARSED must equal the
    # number of times `static inline` appears in the same files. Any gap is a parse failure
    # and names itself.
    raw = 0
    for d in NASA_DIRS:
        for f in glob.glob(os.path.join(ROOT, d, '*.h')):
            raw += len(re.findall(r'static\s+inline',
                                  strip_comments(open(f, errors='replace').read())))
    if len(inlines) != raw:
        print('FAIL cfs-hdrinline — parsed %d inlines but `static inline` appears %d times.'
              % (len(inlines), raw), file=sys.stderr)
        print('  The difference is declarations the INLINE pattern could not read, and a gate',
              file=sys.stderr)
        print('  is only as good as its scan. A wrapped return type is the known shape:',
              file=sys.stderr)
        print('  `static inline void` on one line and the name on the next.', file=sys.stderr)
        return 1
    if raw < 100:
        print('FAIL cfs-hdrinline — only %d `static inline` in NASA\'s headers; there are over'
              ' 160, so NASA_DIRS is wrong.' % raw, file=sys.stderr)
        return 1

    srcs = gated_sources()
    if not srcs:
        print('FAIL cfs-hdrinline — no gated NASA sources found; SRC_C did not resolve.',
              file=sys.stderr)
        return 1

    # REQUIRED = the transitive closure of "called from a gated .c"
    universe = set(inlines)
    required = set()
    frontier = set()
    for p in srcs:
        frontier |= called_names(strip_comments(open(p, errors='replace').read()), universe)
    while frontier:
        n = frontier.pop()
        if n in required:
            continue
        required.add(n)
        frontier |= called_names(inlines[n][2], universe) - required

    have = hc_defined()
    translated, collapsed, missing = [], [], []
    for n in sorted(required):
        if n in have:
            translated.append(n)
            continue
        m = IDWRAP.match(" ".join(inlines[n][2].split()))
        # AND THE ARGUMENTS MUST BE THE PARAMETERS, NOTHING ELSE. A driven negative control
        # caught this: renaming the translation of CFE_ES_AppRecordIsUsed left the gate PASSING,
        # because its body is CFE_RESOURCEID_TEST_DEFINED(AppRecPtr->AppId) and matching the
        # macro name alone was enough to call it a collapsed typed-id wrapper. It is not one --
        # it reaches into a record, which is logic, and logic has to be translated. A wrapper
        # qualifies only when it passes its own parameters through untouched.
        if m and m.group(1) in MACRO_TO_FN and \
                [q.strip() for q in m.group(2).split(',') if q.strip()] == inlines[n][3]:
            fn = MACRO_TO_FN[m.group(1)]
            if fn in have:
                collapsed.append((n, fn))
                continue
            missing.append((n, inlines[n][0],
                            'collapses onto %s, which the translation does NOT define' % fn))
            continue
        missing.append((n, inlines[n][0], 'no function of this name in the translation'))

    if missing:
        print('FAIL cfs-hdrinline — a NASA header inline a gated source CALLS is not translated.',
              file=sys.stderr)
        print('  A static inline is a function. Being in a header rather than a .c is not a',
              file=sys.stderr)
        print('  reason for no gate to look at it -- that was true of 163 of them until now.',
              file=sys.stderr)
        for n, h, why in missing:
            print('    %-44s %-46s %s' % (n, h, why), file=sys.stderr)
        return 1

    if verbose:
        for n, fn in collapsed:
            print('  collapsed: %-40s -> %s' % (n, fn))
        for n in translated:
            print('  translated: %s' % n)
    # TRANSLATED BUT NOT REQUIRED IS A NUMBER, not a silence. A `_decl.HC` file carries a
    # header's inlines before its .c is gated -- cfe_tbl_loadbuff_decl.HC ships thirteen that
    # nothing yet calls -- and for those, NOTHING checks the bodies: this gate does not
    # require them, check_in_blob cannot see functions no driver references, and the
    # transcript never reaches them. They are translated because somebody was careful, which
    # is exactly the condition this gate was written to stop relying on. So the count is
    # printed on every run: it should FALL as the matching .c sources are gated, and a number
    # that sits still is a set of functions nobody is checking.
    spare = sorted(n for n in have if n in inlines and n not in required)
    print('cfs-hdrinline: %d of %d NASA header inlines are reached by a gated source; %d are '
          'translated by name, %d collapse onto a CFE_ResourceId_* function that is'
          % (len(required), len(inlines), len(translated), len(collapsed)))
    print('               (%d header inlines no gated source calls, so not required yet; of '
          'those %d ARE translated and so have no gate on their bodies until their .c lands)'
          % (len(inlines) - len(required), len(spare)))
    if verbose:
        for n in spare:
            print('  translated but unrequired: %s' % n)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
