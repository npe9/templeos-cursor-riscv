# Self-hosting HolyC (seed)

HolyC sources here are built **on the host** with `../holyc-riscv`, then linked as the guest at `0x80100000` when you run `make selfhost`.

- **`toy_eval.hc`** — Currently returns `2 + 3 * 4` (ORACLE `0xe`) to validate the selfhost image. A fuller recursive parser hit codegen limitations for this bare call layout; extend the compiler or simplify calling conventions before reviving string parsing here.

Bootstrap path:

1. `make -C .. holyc-riscv`
2. `make -C .. -C templeos-riscv selfhost`
3. `make -C .. -C templeos-riscv qemu-selfhost`

End goal: a HolyC-implemented compiler in this directory, produced by the C bootstrap compiler, running only on TempleOS/RISC-V.
