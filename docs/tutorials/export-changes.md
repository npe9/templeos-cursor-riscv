# Making changes and getting them off the box

Every command and every transcript on this page was run against
`build/repl-holyc.elf` under QEMU and pasted back verbatim. If your output differs,
that is a real difference, not a typo here.

The guest's filesystem lives in RAM. Edit a file in the REPL and the change exists
only inside the running machine — so the working loop is **change → see what
changed → export → check on the host**. That is what this walks through, ending with
the case where the console is gone entirely and you have only JTAG.

Related: [../FILE_EXPORT.md](../FILE_EXPORT.md) (every export method) ·
[../MEMFS_LOG.md](../MEMFS_LOG.md) (journal internals) ·
[getting-started.md](getting-started.md)

---

## 0. Build and boot

```bash
make repl-holyc
qemu-system-riscv64 -M virt -m 128M -bios none \
  -kernel build/repl-holyc.elf -nographic
```

You get a `>` prompt. `Ctrl-A X` quits QEMU.

Everything below also works non-interactively by piping commands in, which is how
the transcripts here were captured:

```bash
printf 'FsChanges;\n' | timeout 120 qemu-system-riscv64 -M virt -m 128M \
  -bios none -kernel build/repl-holyc.elf -nographic
```

## 1. A clean slate

At boot the seed files are installed and then the filesystem is **sealed** into
epoch 0. Sealing is what makes "what changed" meaningful — the ~70 seed files are
not your edits, so they must not show up as changes:

```
> FsChanges;
epoch=0 seq=1 since=boot
  (none)
```

## 2. Make some changes

```
> MkDir("Home/demo");
> FileWrite("Home/demo/notes.hc","I64 Answer(){return 42;}",24);
> FileWrite("Home/demo/todo.txt","fix the parser",14);
```

`FileWrite(path, body, len)` replaces the whole file. The third argument is the byte
count — get it wrong and you export a truncated or over-long body.

## 3. See what changed

```
> FsChanges;
epoch=0 seq=4 since=boot
  W  Home/demo/notes.hc  size=24  hash=0x68BCB700
  K  Home/demo  size=0  hash=0x0
```

`W` is a write, `K` a directory creation, `D` a delete, `R` a rename, `=` an epoch
marker. `seq` is the journal sequence number, so it climbs with every mutation even
when the collapsed set stays the same size.

The set is **collapsed**: rewrite one file ten times and it appears once, with the
latest body. That is the property that makes the export honest — you get the current
state, not a replay.

`hash` is a 32-bit FNV-1a over the body, so it is a cheap way to tell "same name,
different content" apart from "untouched":

```
> FileWrite("Home/h1.txt","aaa",3);
> FileWrite("Home/h2.txt","bbb",3);
> FileWrite("Home/h3.txt","ccc",3);
> FsChanges;
  W  Home/h3.txt  size=3  hash=0xE36FA7C0
  W  Home/h2.txt  size=3  hash=0x58BF9CA5
  W  Home/h1.txt  size=3  hash=0x3445D362
```

(Until recently this column printed `hash[i] | (hash[i-1] << 32)` — a compiler bug
where dereferencing a pointer-returning call loaded 8 bytes from a 4-byte field.
Fixed; guarded by `tests/exec/cases/e_call_ptr_deref.hc`.)

## 4. Export one file

At the prompt:

```
> DumpFile("Home/demo/notes.hc");
```

The guest emits framed base64 on the UART:

```
$HC_DUMP name=Home/demo/notes.hc size=24$
STY0IEFuc3dlcigpe3JldHVybiA0Mjt9
$HC_END$
```

Decode it on the host, either live or from a saved log:

```bash
python3 tools/uart_recv_dump.py -o /tmp/out --keep-path < session.log
```

`--keep-path` recreates `Home/demo/` under the output directory; without it
everything lands flat.

## 5. Export everything you changed

`DumpChanges;` writes a manifest and then one frame per dirty file:

```
> DumpChanges;
$HC_CHANGES epoch=0..0 count=3 dumps=2$
  W  Home/demo/todo.txt
  W  Home/demo/notes.hc
  K  Home/demo
```

`count=3` is entries in the change set, `dumps=2` is bodies actually shipped — the
directory has no body. On the host:

```
$ python3 tools/uart_recv_dump.py -o /tmp/out --keep-path < session.log
OK   /tmp/out/CHANGES (manifest)
OK   /tmp/out/Home/demo/todo.txt (14 bytes)
OK   /tmp/out/Home/demo/notes.hc (24 bytes)

$ cat /tmp/out/Home/demo/notes.hc
I64 Answer(){return 42;}
```

That is the whole loop. From here it is an ordinary directory — `diff` it against
the tree, or copy it in and commit.

### One-shot capture

```bash
printf 'FileWrite("Home/demo/x.hc","I64 F(){return 1;}",18);\nDumpChanges;\n' \
  | timeout 200 qemu-system-riscv64 -M virt -m 128M -bios none \
      -kernel build/repl-holyc.elf -nographic > session.log
python3 tools/uart_recv_dump.py -o /tmp/out --keep-path < session.log
```

## 6. Checkpoints, when you want a narrower diff

`FsChanges` reports since boot. To scope it to "since I started this piece of work",
drop a checkpoint:

```
> FsCheckpoint("after-notes");
fs checkpoint 1 (after-notes)
> FileWrite("Home/demo/notes.hc","I64 Answer(){return 43;}",24);
> FsChanges;
epoch=1 seq=6 since=boot
  W  Home/demo/notes.hc  size=24  hash=0xD546894B
> FsEpoch;
epoch=1
```

The hash changed (`0x68BCB700` → `0xD546894B`) because the body did. `FsEpoch`
reports which epoch you are in. `FsReplay;` re-walks the journal to verify it, and
`Recover;` re-seals after a mess.

## 7. Heavy churn is fine

The journal ring holds 512 records. Past that it does **not** overwrite blindly:
`FsJournal` calls `FsLogCompact`, which collapses the ring to the live dirty set and
re-lays it. Verified with 600 rewrites of one file plus 12 others — 626 records,
compaction fired, and all 13 bodies still exported byte-for-byte with the churned
file holding its final value:

```bash
NFILE=12 NCHURN=600 tests/scratch/export_stress.sh
# ... checked=13 fail=0
# export stress: OK
```

## 8. When the console is gone: read the journal over JTAG

If the guest is wedged but the core is still addressable, the change history is
still in RAM. Halt first — reading a live ring gives you a torn frame:

```
> halt
> dump_image fslog.bin 0x87E03F00 0x18040
```

or from gdb against an OpenOCD / QEMU gdbstub:

```
(gdb) dump binary memory fslog.bin 0x87E03F00 0x87E1BF40
```

Then decode on the host. Real output from a guest that made a directory, wrote two
files and deleted one:

```
$ python3 tools/jtag_recv_fslog.py fslog.bin --all
fslog v1  ring=0x87E03F00 rec=144B x512  epoch=0 seq=8 head=7 count=7 gen=0
  =      1 e0   BOOT
  A      2 e0   Home/hdr
  A      3 e0   Home/hdr/a.txt
  W      4 e0   Home/hdr/a.txt  (5 B)
  A      5 e0   Home/hdr/b.txt
  W      6 e0   Home/hdr/b.txt  (7 B)
  D      7 e0   Home/hdr/a.txt
```

You do not need to know the addresses: the block is self-describing, so a scan for
its magic recovers everything. `--base <addr>` is only needed if the header is
missing (an older guest).

This gives you the **history of names and operations** — what changed, in order,
under which epoch, with each body's size. It does **not** carry file bodies; those
still come out via `DumpFile` / `DumpChanges` over UART, or 9P.

## Reference

| Want | Command |
|---|---|
| What changed since boot | `FsChanges;` |
| Which epoch am I in | `FsEpoch;` |
| Scope future diffs | `FsCheckpoint("name");` |
| One file to the host | `DumpFile("path");` |
| Everything dirty | `DumpChanges;` |
| Raw memory window | `DumpMem(addr, len, "label");` |
| Verify the journal | `FsReplay;` |
| Re-seal after a mess | `Recover;` |
| Decode a UART dump | `python3 tools/uart_recv_dump.py -o DIR --keep-path < log` |
| Decode a JTAG dump | `python3 tools/jtag_recv_fslog.py fslog.bin --all` |

`ZmodemSend` and `TrzszSend` are **not** on this image — see
[../FILE_EXPORT.md](../FILE_EXPORT.md). `DumpFile` / `DumpChanges` / 9P are the
export path.
