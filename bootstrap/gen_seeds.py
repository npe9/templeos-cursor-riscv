#!/usr/bin/env python3
# Generate seed_files.h (the memfs_seed_files[] table) from bootstrap/seed/.
# Hierarchical memfs names (Lib/print.hc, Tutorials/A01_….hc, …) plus .dir markers.
# Basenames stay unique so Run("print.hc") still works via FsFind fallback.
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from seed_layout import DIRS, iter_seed_files  # noqa: E402


def esc(s):
    return (s.replace('\\', '\\\\').replace('"', '\\"')
             .replace('\n', '\\n').replace('\t', '\\t').replace('\r', '\\r'))


seed_dir, out_path = sys.argv[1], sys.argv[2]
out = ["// GENERATED from bootstrap/seed/ by gen_seeds.py -- do not edit by hand.\n",
       "static const struct { const char *name; const char *body; } memfs_seed_files[] = {\n"]
n_dir = 0
n_file = 0
for d in DIRS:
    out.append('  { "%s/.dir", "" },\n' % d)
    n_dir += 1
for host_p, mem_name in iter_seed_files(seed_dir):
    out.append('  { "%s", "%s" },\n' % (mem_name, esc(open(host_p, encoding='utf-8').read())))
    n_file += 1
out.append("};\n")
n = n_dir + n_file
if n > 96:
    sys.exit("error: %d memfs entries exceed MEMFS_MAX=96" % n)
open(out_path, 'w').write(''.join(out))
print("wrote %s (%d dirs + %d files = %d slots)" % (out_path, n_dir, n_file, n))
