#!/usr/bin/env python3
# Generate seed_files.h (the memfs_seed_files[] table) from bootstrap/seed/*.hc.
# The seeds are real HolyC files so large ones (the editors) stay maintainable and syntax-checkable.
import sys, glob, os
def esc(s):
    return (s.replace('\\', '\\\\').replace('"', '\\"')
             .replace('\n', '\\n').replace('\t', '\\t').replace('\r', '\\r'))
seed_dir, out_path = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(seed_dir, '*.hc')))
out = ["// GENERATED from bootstrap/seed/*.hc by gen_seeds.py -- do not edit by hand.\n",
       "static const struct { const char *name; const char *body; } memfs_seed_files[] = {\n"]
for p in files:
    out.append('  { "%s", "%s" },\n' % (os.path.basename(p), esc(open(p, encoding='utf-8').read())))
out.append("};\n")
open(out_path, 'w').write(''.join(out))
print("wrote %s (%d seeds)" % (out_path, len(files)))
