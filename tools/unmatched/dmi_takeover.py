# Raw-DMI takeover of hart 1: halt, force M-mode, set pc, resume. Every DMI op is read back and
# retried, because this board's JTAG path has a ~1-3% per-scan error floor that kills OpenOCD's
# unverified examine() but is harmless to a dozen verified ops.
import socket, sys, time
ENTRY=int(sys.argv[1],16) if len(sys.argv)>1 else 0x80200000
HARTSEL=1<<16; DMACTIVE=1; HALTREQ=1<<31; RESUMEREQ=1<<30
s=socket.create_connection(("127.0.0.1",6666),timeout=10)
def tcl(c):
    s.sendall(c.encode()+b"\x1a"); buf=b""
    while not buf.endswith(b"\x1a"):
        d=s.recv(4096)
        if not d: raise SystemExit("tcl closed")
        buf+=d
    return buf[:-1].decode(errors="replace").strip()
def plausible(a,v):
    # A corrupted scan can still be a well-formed number. dmstatus (0x11) has invariants on this
    # board: version field == 2, allnonexistent(15)/anyunavail(12)/allunavail(13) clear, bit 31 clear.
    # 0x80018642 passed a bare "allhalted" mask check once and the hart was not halted at all.
    if a==0x11: return (v&0xf)==2 and not (v&((1<<15)|(1<<12)|(1<<13)|(1<<31)))
    return True
def rd(a):
    # Consensus of two consecutive identical, plausible reads. Costs one extra scan per read and
    # turns a ~2% per-scan corruption floor into a ~0.04% chance of accepting garbage.
    prev=None
    for _ in range(16):
        r=tcl("riscv dmi_read 0x%x"%a)
        if not r.lower().startswith("0x"): prev=None; continue
        v=int(r,16)
        if not plausible(a,v): prev=None; continue
        if prev is not None and v==prev: return v
        prev=v
    raise SystemExit("dmi_read 0x%x: no two consecutive agreeing reads"%a)
def wr(a,v,verify=True):
    for _ in range(8):
        tcl("riscv dmi_write 0x%x 0x%x"%(a,v))
        if not verify: return
        if rd(a)&0xffffffff==v&0xffffffff: return
    raise SystemExit("dmi_write 0x%x=0x%x never read back"%(a,v))
def wait_status(mask, want, secs=2.0):
    t=time.time()
    while time.time()-t<secs:
        v=rd(0x11)
        if (v&mask)==want: return v
    raise SystemExit("dmstatus timeout: mask=0x%x want=0x%x last=0x%x"%(mask,want,v))
def abstract(cmd):
    # `command` (0x17) is readable and reading does not re-trigger, so VERIFY the write landed: the
    # floor once ate a GPR-write command silently — cmderr stayed 0, dpc kept the previous x8, and
    # the hart resumed to 0x4000b0c2 (mcause=1). Nothing on this link is trusted blind any more.
    wr(0x17,cmd,verify=True)
    for _ in range(50):
        cs=rd(0x16)
        if not (cs>>12)&1:           # busy clear
            err=(cs>>8)&7
            if err: wr(0x16,err<<8,verify=False); raise SystemExit("abstract cmderr=%d for cmd 0x%x"%(err,cmd))
            return
    raise SystemExit("abstract command stuck busy")
# The FU740 debug module rejects abstract CSR access (cmderr=2) — GPRs only. CSRs go through the
# program buffer: stage `csrr s0,CSR; ebreak`, run it with postexec, then abstract-read x8.
X8=0x1008; EBREAK=0x00100073
def gpr_read(): abstract((3<<20)|(1<<17)|X8); return rd(0x04)|(rd(0x05)<<32)
def gpr_write(v):
    for _ in range(6):
        wr(0x04,v&0xffffffff); wr(0x05,(v>>32)&0xffffffff); abstract((3<<20)|(1<<17)|(1<<16)|X8)
        if gpr_read()==v: return
    raise SystemExit("x8 never took 0x%x"%v)
def progbuf(*ins):
    for i,w in enumerate(ins): wr(0x20+i,w)
def csr_read(csr):
    progbuf((csr<<20)|(8<<7)|(2<<12)|0x73, EBREAK)          # csrrs x8, csr, x0
    abstract((3<<20)|(1<<18)|X8)                             # postexec only (no transfer)
    return gpr_read()
def csr_write(csr,val):
    gpr_write(val)
    progbuf((csr<<20)|(8<<15)|(1<<12)|0x73, EBREAK)         # csrrw x0, csr, x8
    abstract((3<<20)|(1<<18)|X8)
print("dmstatus before : 0x%x"%rd(0x11))
wr(0x10, DMACTIVE|HARTSEL)                                   # select hart 1
wr(0x10, HALTREQ|DMACTIVE|HARTSEL, verify=False)
st=wait_status(1<<9,1<<9); print("halted          : dmstatus=0x%x"%st)
wr(0x10, DMACTIVE|HARTSEL)                                   # drop haltreq
dcsr=csr_read(0x7b0); dpc=csr_read(0x7b1)
print("dcsr=0x%x (prv=%d)  dpc=0x%x"%(dcsr,dcsr&3,dpc))
def csr_set(csr,val,mask=(1<<64)-1,name=""):
    for _ in range(6):
        csr_write(csr,val)
        got=csr_read(csr)
        if (got&mask)==(val&mask): print("  %-8s = 0x%x"%(name,got)); return got
    raise SystemExit("%s never read back 0x%x (last 0x%x)"%(name,val,got))
# Inherited state (measured): OpenSBI still owns mtvec, and mstatus.MIE / mie as left by the hart.
# Resuming into M-mode with an interrupt pending sent the hello into OpenSBI's trap handler
# (sbi_trap_error). A real crt0 sets mtvec first thing; a takeover must at least mask interrupts.
mstatus=csr_read(0x300); print("mstatus=0x%x (MIE=%d)"%(mstatus,(mstatus>>3)&1))
csr_set(0x304,0,name="mie")
csr_set(0x300,mstatus&~(1<<3),name="mstatus")
csr_set(0x7b0,(dcsr&~3)|3,name="dcsr")
csr_set(0x7b1,ENTRY,name="dpc")
wr(0x10, RESUMEREQ|DMACTIVE|HARTSEL, verify=False)
st=wait_status(1<<17,1<<17); print("resumed         : dmstatus=0x%x"%st)
wr(0x10, DMACTIVE|HARTSEL, verify=False)
print("TAKEOVER DONE -> entry 0x%x in M-mode"%ENTRY)
