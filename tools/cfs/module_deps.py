#!/usr/bin/env python3
"""Where a cFS module's call cycles are, so an incremental gating order can be planned.

WHAT THIS ANSWERS, AND WHAT IT DOES NOT. It finds the strongly connected components of the
cross-source call graph. A component of one source can be gated on its own. A component of
several cannot, WITHOUT STAND-INS -- and whether that is acceptable is a judgement this tool
does not make.

CALIBRATED, and the calibration corrected the first conclusion drawn from it. Run with
`--fresh` (pretend nothing is gated), ES comes back as a TWELVE-source cycle -- and ES was in
fact gated one source at a time, with stubs that were later deleted in batches. So a cycle is
not a wall. EVS, by contrast, is fully acyclic: seven singletons in dependency order. The tool
discriminates; what it reports is the SHAPE, and the cost of an incremental path through a
cycle is the stand-ins it forces.

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

Usage: module_deps.py <module> [...]   e.g. module_deps.py tbl
"""
import re, sys, os, glob

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS = os.path.join(ROOT, 'tests', 'scripts')


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


def header_inlines(d):
    out = set()
    for f in glob.glob(os.path.join(d, '*.h')):
        out |= set(re.findall(r'static\s+inline\s+[\w\s\*]+?(\w+)\s*\(',
                              strip(open(f, errors='replace').read())))
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
    argv = [a for a in argv if a != '--fresh']
    g = set() if fresh else gated()
    for mod in argv:
        d = os.path.join(ROOT, 'vendor', 'cFE', 'modules', mod, 'fsw', 'src')
        srcs = sorted(glob.glob(os.path.join(d, '*.c')))
        inl = header_inlines(d)
        owner, body, lines = {}, {}, {}
        for p in srcs:
            b = os.path.basename(p)
            body[b] = strip(open(p, errors='replace').read())
            lines[b] = body[b].count('\n') + 1
            for n in defines(p):
                owner[n] = b
        # edges: file -> files whose .c defines something it calls
        edge = {}
        for b, src in body.items():
            mine = {n for n, o in owner.items() if o == b}
            need = set()
            for n in set(re.findall(r'\b(CFE_\w+)\s*\(', src)):
                if n in mine or n in inl:
                    continue
                if n in owner:
                    need.add(owner[n])
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
        cond = sorted(v for c in order for v in c if '_eds_' in v)
        if cond:
            print("    of those, CMake-conditional (EDS variants, not in this configuration --"
                  " check_manifest.py decides): %s" % ", ".join(cond))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
