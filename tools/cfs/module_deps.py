#!/usr/bin/env python3
"""Where a cFS module's call cycles are, so an incremental gating order can be planned.

WHAT THIS ANSWERS, AND WHAT IT DOES NOT. It finds the strongly connected components of the
cross-source call graph. A component of one source can be gated on its own. A component of
several cannot, WITHOUT STAND-INS -- and whether that is acceptable is a judgement this tool
does not make.

CALIBRATED, and the calibration corrected the first conclusion drawn from it. Run with
`--fresh` (pretend nothing is gated), ES comes back as a FOURTEEN-source cycle -- and ES was in
fact gated one source at a time, with stubs that were later deleted in batches. So a cycle is
not a wall. The tool discriminates; what it reports is the SHAPE, and the cost of an incremental
path through a cycle is the stand-ins it forces.

AND THE CALIBRATION SENTENCE ITSELF WENT STALE TWICE, which is worth leaving on the record in a
docstring whose job is to say why the numbers can be trusted. It said TWELVE for ES until the
`[&ref]` edges were added (a reference with no following paren is how a handler reaches a
function-pointer table, and there were 14 sources once those counted), and it said "EVS, by
contrast, is fully acyclic: seven singletons" until the owner map stopped attributing
CFE_EVS_ProcessCommandPacket to the EDS variant -- EVS has a 2-source cycle,
cfe_evs_dispatch.c with cfe_evs_task.c, and always did in the configuration this port builds.
A calibration claim is a measurement with a date on it, not a property.

WHAT DID NOT MOVE ACROSS EITHER FIX, and so is the actual anchor: tbl's EIGHT-source cycle,
time's THREE and sbr's TWO. None of those runs through a dispatch file, so none of them was
ever mis-attributed, and the tbl number is the one the plan was written against.

AND THEN THE PREFIX LIST WENT WRONG A THIRD AND FOURTH TIME, which is why there is no longer
one. `CFE_\w+` found nothing inside MD; `(?:CFE|MD)_\w+` found nothing inside MM -- ten clean
singletons in size order, no edges at all. Removing the alternation entirely also corrected a
module: EVS's private helpers are named `EVS_SendEvent`, `EVS_AddLog`,
`EVS_GenerateEventTelemetry` with NO `CFE_` prefix, so those edges were never counted and EVS
reported a 2-source cycle. Its real cycle is FIVE -- cfe_evs.c, _dispatch.c, _log.c, _task.c
and _utils.c. Measured across all twelve: EVS is the only answer that changed, and es's 14,
sb's 4, tbl's 8, time's 3 and 2, sbr's 2, ta's 2 and md's 2 are byte-identical.

MM's answer, for the record: fully ACYCLIC, ten singletons in a real topological order --
mm_utils, mm_mem8, mm_mem16, mm_mem32, mm_dump, mm_load, mm_cmds, mm_dispatch, mm_app. Note
mm_app is LAST, after mm_dispatch: MM_SendHkCmd lives in mm_cmds.c rather than the app, so
unlike MD there is no app/dispatch cycle.

THE JUDGEMENT IS PER EDGE: is the stand-in a SEAM, or is it upstream LOGIC?

  ES, gating cfe_es_apps.c first      StartAppTask, AppCreate, CleanUpApp -- things the
                                      driver supplies anyway. Stubs were right.
  TBL, gating cfe_tbl_regrec.c first  CFE_TBL_LocateLoadBufferByID and
                                      CFE_TBL_GetNextLocalBufferId, which implement a
                                      buffer-id SERIAL ENCODING (a category field separating
                                      shared load buffers from a table's dedicated one, packed
                                      into the resource id). That is loadbuff's logic. A
                                      faithful copy in the driver puts upstream logic where no
                                      gate compares it against NASA -- worse than a stub,
                                      because it looks like a translation.

So tbl's eight-source cycle is gated as one piece not because the graph forbids otherwise, but
because the cheapest break in it costs more than it saves.

WHAT IS AND IS NOT AN EDGE. A call to a function defined in another .c is one. A call to a
`static inline` in a HEADER is NOT -- a header inline travels with whoever needs it, and
check_header_inlines.py requires exactly the ones a gated source reaches. Without that
distinction every module looks like one big cycle and the tool says nothing.

CALIBRATED AGAIN WHEN IT LEARNED ABOUT APPS, and the second calibration was the one that
mattered. An app's own functions are MD_*, not CFE_*, and the edge patterns were CFE-only. Run
against MD that way -- path widened, pattern not -- it reports SEVEN INDEPENDENT SINGLETONS in
pure size order: no edges at all, and a licence to gate md_dispatch.c second when every handler
it names lives in md_cmds.c. The most confident possible wrong answer, and nothing in the output
hints that a prefix went unmatched. The widening is driven by that control, and the eleven cFE
modules are byte-identical across it (376 lines of --cuts output) because a name is only an edge
when one of THIS module's sources defines it.

MD's answer, once it can see it: fully ACYCLIC in this configuration. The one cycle is
md_app.c <-> md_eds_dispatch.c, and md_eds_dispatch.c is the EDS variant CMake does not select
here, so all six gated sources are singletons and the order costs no stand-ins at all:

  md_utils.c -> md_dwell_pkt.c -> md_dwell_tbl.c -> md_cmds.c -> md_app.c -> md_dispatch.c

Which is NOT CMake's APP_SRC_FILES order (dwell_tbl, utils, dwell_pkt, cmds, app). Build order
is not dependency order; that is the whole reason this tool exists.

Usage: module_deps.py [--fresh] [--cuts] <module> [...]   e.g. module_deps.py --cuts tbl
                      a module is a cFE one (vendor/cFE/modules/<mod>) or an APP (vendor/<MOD>)
"""
import re, sys, os, glob, itertools

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS = os.path.join(ROOT, 'tests', 'scripts')

# NO PREFIX LIST AT ALL, AND THAT IS THE FIX FOR A BUG THAT HAPPENED THREE TIMES. This pattern
# was `CFE_\w+`, which found no edges inside MD and reported five independent singletons in pure
# size order -- the most confident possible wrong answer. It became `(?:CFE|MD)_\w+`, and then MM
# arrived and reported TEN clean singletons with no edges, for exactly the same reason. A
# hard-coded alternation of prefixes is a list someone has to remember to extend, and the failure
# is silent and confident.
#
# Matching ANY identifier is safe and strictly better, because a name only becomes an edge when
# one of THIS module's own sources DEFINES it -- `owner` is built from `defines()` over those
# sources and nothing else. Every libc call, every local, every cFE API the module merely uses
# falls out at that lookup. The eleven cFE modules and MD are byte-identical across the change.
SYM = r'\b([A-Za-z_]\w*)'


def strip(src):
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), src, flags=re.S)
    return re.sub(r'//[^\n]*', '', src)


def gated():
    out = set()
    for n in sorted(os.listdir(SCRIPTS)):
        if not n.endswith('.sh'):
            continue
        for m in re.finditer(r'^SRC_C="(.*?)"$', open(os.path.join(SCRIPTS, n),
                                                      errors='replace').read(), re.S | re.M):
            for t in m.group(1).split():
                if t.endswith('.c'):
                    out.add(os.path.basename(t))
    return out


def defines(path):
    """Function names DEFINED at file scope in this .c (static or not)."""
    src = strip(open(path, errors='replace').read())
    names, lines = set(), src.split('\n')
    i = 0
    while i < len(lines):
        if lines[i][:1].isalpha() or lines[i][:1] == '_':
            buf, j = lines[i], i
            while buf.count('(') > buf.count(')') and j + 1 < len(lines) and j - i < 12:
                j += 1
                buf += ' ' + lines[j].strip()
            m = re.match(r'^[A-Za-z_][\w \t\*]*?\b(\w+)\s*\([^;]*\)\s*$', ' '.join(buf.split()))
            if m:
                for nxt in lines[j + 1:]:
                    if nxt.strip() == '':
                        continue
                    if nxt.lstrip().startswith('{'):
                        names.add(m.group(1))
                    break
                i = j + 1
                continue
        i += 1
    return names


def header_inlines(*dirs):
    out = set()
    for f in [f for d in dirs for f in glob.glob(os.path.join(d, '*.h'))]:
        out |= set(re.findall(r'static\s+inline\s+[\w\s\*]+?(\w+)\s*\(',
                              strip(open(f, errors='replace').read())))
    return out


def cmake_unconditional(src_dir):
    """Sources CMakeLists.txt names at if()-depth 0, i.e. in every configuration.

    check_manifest.py owns this parse and is the authority on it; this is the same depth walk,
    reduced to the one question the owner map needs -- "is this file in the build whatever the
    configuration" -- so module_deps does not have to decide which branch is taken.
    """
    cm = os.path.join(os.path.dirname(os.path.dirname(src_dir)), 'CMakeLists.txt')
    if not os.path.exists(cm):
        return []
    txt = re.sub(r'#[^\n]*', '', open(cm, errors='replace').read())
    out, depth = [], 0
    for line in txt.split('\n'):
        if re.match(r'\s*if\s*\(', line):
            depth += 1
        elif re.match(r'\s*endif\s*\(', line):
            depth = max(0, depth - 1)
        if depth == 0:
            out += re.findall(r'fsw/src/([A-Za-z0-9_.-]+\.c)', line)
    return out


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    # --fresh pretends NOTHING is gated. It is how this tool is CALIBRATED: ES, SB, EVS and
    # TIME were each gated one source at a time, so run this way they must come back as
    # singletons all the way down. A spurious multi-source component there would mean the call
    # regex is over-reporting edges, and tbl's 8-source result could not be trusted either --
    # which matters, because the next increment is planned on that number's authority.
    fresh = '--fresh' in argv
    cuts = '--cuts' in argv
    argv = [a for a in argv if a not in ('--fresh', '--cuts')]
    g = set() if fresh else gated()
    for mod in argv:
        d = os.path.join(ROOT, 'vendor', 'cFE', 'modules', mod, 'fsw', 'src')
        # An APP is a repository of its own, not a module directory under cFE. Same shape
        # otherwise -- sources in fsw/src -- so only the path and the public header dir differ.
        hdr = [d]
        if not os.path.isdir(d):
            d = os.path.join(ROOT, 'vendor', mod.upper(), 'fsw', 'src')
            hdr = [d, os.path.join(ROOT, 'vendor', mod.upper(), 'fsw', 'inc')]
            if not os.path.isdir(d):
                print('%s: no sources at vendor/cFE/modules/%s/fsw/src or vendor/%s/fsw/src'
                      % (mod, mod, mod.upper()))
                continue
        srcs = sorted(glob.glob(os.path.join(d, '*.c')))
        inl = header_inlines(*hdr)
        # A NAME CAN BE DEFINED BY MORE THAN ONE SOURCE, and `owner[n] = b` kept whichever
        # was scanned LAST -- which for every CMake-conditional pair is the wrong one.
        # cfe_X_dispatch.c and cfe_X_eds_dispatch.c both define CFE_X_TaskPipe;
        # md_dispatch.c and md_eds_dispatch.c both define MD_TaskPipe; cfe_msg_msgid_v1.c and
        # _v2.c define the same six accessors. The loser was the file the configuration
        # ACTUALLY BUILDS, because `_eds_` and `_v2` sort after the plain name, so every edge
        # onto one of those names pointed at a source that is not in the build.
        #
        # What it cost: MD came back with md_app.c <-> md_eds_dispatch.c as its cycle and
        # md_dispatch.c LAST in the order -- when md_app.c calls MD_TaskPipe from
        # md_dispatch.c, so that file has to come FIRST. config came back as a 2-source cycle
        # that only exists through the EDS variant. ES and EVS named the wrong dispatch file
        # in a 14-source and a 2-source cycle.
        #
        # RESOLVED BY WHAT THE CONFIGURATION BUILDS, not by a name pattern. The preference is
        # (1) a definer the driver's SRC_C actually compiles, (2) a definer CMake lists
        # unconditionally, (3) alphabetical, printed as an ambiguity. Note that (1) is read
        # even under --fresh: `--fresh` pretends nothing has been TRANSLATED yet, which is a
        # different question from which branch of the build is under test.
        owner, body, lines, multi = {}, {}, {}, {}
        for p in srcs:
            b = os.path.basename(p)
            body[b] = strip(open(p, errors='replace').read())
            lines[b] = body[b].count('\n') + 1
            for n in defines(p):
                multi.setdefault(n, []).append(b)
        built = gated()                      # what the drivers compile, --fresh or not
        uncond = set(cmake_unconditional(d))
        ambiguous = []
        for n, fs in multi.items():
            pick = [f for f in fs if f in built] or [f for f in fs if f in uncond]
            if not pick:
                pick = sorted(fs)
                if len(fs) > 1:
                    ambiguous.append(n)
            owner[n] = pick[0]
        # edges: file -> files whose .c defines something it NEEDS, and WHICH functions
        #
        # TWO KINDS OF NEED, AND THE SECOND ONE WAS MISSING. A CALL is `name(`; a REFERENCE is
        # the bare name, which is how a function reaches a table of function pointers. That is
        # not a corner case here: cfe_tbl_dispatch.c's whole content is
        # CFE_TBL_CmdHandlerTbl[], fourteen `CFE_TBL_ENTRY(..., CFE_TBL_LoadCmd, ...)` rows
        # naming handlers that live in cfe_tbl_task_cmds.c -- and because none of them is
        # SPELLED with a following paren, this tool reported dispatch.c as ready to gate before
        # task_cmds.c and listed it third in a nine-source ordering. Wrong, and wrong in the
        # direction that costs: a confident order you then plan against.
        #
        # The reference pattern deliberately excludes a following `(` so the two are counted
        # separately and a caller can see which kind an edge is.
        edge, edge_fns = {}, {}
        for b, src in body.items():
            mine = {n for n, o in owner.items() if o == b}
            need = set()
            calls = set(re.findall(SYM + r'\s*\(', src))
            refs = set(re.findall(SYM + r'\b(?!\s*\()', src))
            for n in sorted(calls | refs):
                if n in mine or n in inl:
                    continue
                if n in owner:
                    need.add(owner[n])
                    if owner[n] != b:
                        tag = n if n in calls else n + ' [&ref]'
                        edge_fns.setdefault((b, owner[n]), []).append(tag)
            edge[b] = need

        # Tarjan SCC over the ungated subgraph
        un = [b for b in sorted(body) if b not in g]
        idx, low, on, stack, out, c = {}, {}, set(), [], [], [0]

        def sc(v):
            idx[v] = low[v] = c[0]; c[0] += 1
            stack.append(v); on.add(v)
            for w in sorted(edge.get(v, ())):
                if w in g or w not in un:
                    continue
                if w not in idx:
                    sc(w); low[v] = min(low[v], low[w])
                elif w in on:
                    low[v] = min(low[v], idx[w])
            if low[v] == idx[v]:
                comp = []
                while True:
                    w = stack.pop(); on.discard(w); comp.append(w)
                    if w == v:
                        break
                out.append(sorted(comp))

        sys.setrecursionlimit(10000)
        for v in un:
            if v not in idx:
                sc(v)

        print("=== %s: %d sources, %d gated, %d to go" % (mod, len(body), len(body) - len(un), len(un)))
        print("    (a header `static inline` is NOT a dependency -- it travels with its caller)")
        done = set(g)
        order, left = [], {tuple(c) for c in out}
        while left:
            ready = [c for c in left if all(w in done or w in c for v in c for w in edge.get(v, ()) if w in un)]
            if not ready:
                break
            ready.sort(key=lambda c: sum(lines[v] for v in c))
            for c in ready:
                order.append(c); done |= set(c); left.discard(c)
        for c in order:
            tot = sum(lines[v] for v in c)
            tag = ("  <-- CALL CYCLE of %d sources: gating any one alone needs"
                   " stand-ins for the others" % len(c)) if len(c) > 1 else ""
            print("    %5d lines  %s%s" % (tot, ", ".join(c), tag))
        if left:
            print("    unordered (cycle through an already-listed group): %s" %
                  ", ".join(sorted(v for c in left for v in c)))
        # A SOURCE CMAKE SELECTS CONDITIONALLY IS LISTED BUT IS NOT NECESSARILY WANTED, and
        # saying so is the difference between a count and a claim. This tool reads the call
        # graph, not cFS's build conditions -- `cfe_*_eds_*.c` are the EDS variants, and
        # CFE_EDS_ENABLED is 0 in this configuration, so they are listed above and correctly
        # absent from the translation. tools/cfs/check_manifest.py is the one that decides
        # which branch a configuration takes; this tool must not be read as disagreeing.
        # --cuts: for every CYCLE, the cheapest subsets to gate first.
        #
        # "Gate the whole component" is the lazy reading of an SCC and it was wrong here. The
        # question is not whether the graph has a cycle, it is HOW MANY FUNCTIONS you must
        # stand in for to gate a subset of it -- and that number varies enormously with the
        # subset. For tbl, gating `regrec` alone needs stand-ins for loadbuff's buffer-id
        # SERIAL ENCODING (bad); gating `loadbuff + regrec` TOGETHER makes those real and
        # needs four stand-ins that are all thin seams (fine). Same cycle, 1,027 lines instead
        # of 3,900, and the difference is invisible unless you enumerate.
        if cuts:
            for comp in [c for c in order if len(c) > 1]:
                print("    --- cheapest first groups inside the %d-source cycle" % len(comp))
                if len(comp) > 16:
                    print("        (component too large to enumerate)")
                    continue
                rank = []
                for r in range(1, len(comp)):
                    for sub in itertools.combinations(comp, r):
                        S = set(sub)
                        # An ALREADY GATED source is available, not a stand-in. Counting
                        # one (cfe_tbl_handlelink.c, gated two commits ago) inflated every
                        # row by 1 and made two groups look equally priced when they are not.
                        need = [(y, n) for (x, y), ns in edge_fns.items()
                                if x in S and y not in S and y not in g for n in ns]
                        rank.append((len(need), sum(lines[v] for v in sub), sub, need))
                # THE TRADE-OFF CURVE, not a single winner. Sorting by stand-in count
                # alone crowns a 3,619-line group because it happens to need one stub, which
                # is useless advice. What a reader needs is: for each price in stand-ins,
                # what is the SMALLEST group it buys -- then they judge whether those
                # particular stand-ins are seams or logic, which no tool can decide.
                byc = {}
                for cnt, ln, sub, need in rank:
                    if cnt not in byc or ln < byc[cnt][0]:
                        byc[cnt] = (ln, sub, need)
                for cnt in sorted(byc)[:6]:
                    ln, sub, need = byc[cnt]
                    print("        %2d stand-in(s), %5d lines : %s" %
                          (cnt, ln, ", ".join(v.replace('cfe_', '').replace('.c', '') for v in sub)))
                    for y, n in sorted(need):
                        print("              %-38s from %s" % (n, y))

        dup = sorted((n, fs) for n, fs in multi.items() if len(fs) > 1)
        if dup:
            print("    defined by MORE THAN ONE source. The edge goes to the one this"
                  " configuration BUILDS:")
            for n, fs in dup:
                mark = "  <-- AMBIGUOUS" if n in ambiguous else ""
                print("        %-32s %s -> %s%s"
                      % (n, ", ".join(sorted(fs)), owner[n], mark))
        cond = sorted(v for c in order for v in c if '_eds_' in v)
        if cond:
            print("    of those, CMake-conditional (EDS variants, not in this configuration --"
                  " check_manifest.py decides): %s" % ", ".join(cond))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
