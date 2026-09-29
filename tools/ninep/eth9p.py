#!/usr/bin/env python3
"""9P2000.L server that speaks raw Ethernet, for Kernel/NineP/NinePEth.HC.

Two link modes, one protocol implementation:

  --mode qemu     listen on TCP; QEMU connects with `-netdev socket,connect=HOST:PORT`.
                  QEMU's socket netdev frames each packet with a 4-byte big-endian length,
                  so this is a raw Ethernet link with no privileges and no tap device --
                  which is what makes an automated gate possible at all.

  --mode raw      an AF_PACKET socket on a real interface, for the board. Linux only and
                  needs privileges; on a Mac, run this on another host on the same segment.

Only the eleven request types Kernel/NineP/NinePClient.HC actually sends are implemented.
Anything else gets Rlerror(ENOSYS) rather than silence, because a client hanging on an
unanswered request is the worst failure mode here and the hardest to read.
"""
import argparse, errno, os, socket, struct, sys, time

ETH_TYPE = 0x88B6
SRV_MAC = bytes([0x02, 0x00, 0x00, 0x00, 0x00, 0x02])
MSIZE = 1280

Tversion, Rversion = 100, 101
Tattach, Rattach = 104, 105
Twalk, Rwalk = 110, 111
Tlopen, Rlopen = 12, 13
Tlcreate, Rlcreate = 14, 15
Tmkdir, Rmkdir = 72, 73
Tread, Rread = 116, 117
Twrite, Rwrite = 118, 119
Treaddir, Rreaddir = 40, 41
Tclunk, Rclunk = 120, 121
Tremove, Rremove = 122, 123
Rlerror = 7

QTDIR, QTFILE = 0x80, 0x00


def s_str(b, off):
    n = struct.unpack_from("<H", b, off)[0]
    return b[off + 2:off + 2 + n].decode("utf-8", "replace"), off + 2 + n


def p_str(s):
    e = s.encode("utf-8")
    return struct.pack("<H", len(e)) + e


def qid_of(path):
    st = os.stat(path)
    t = QTDIR if os.path.isdir(path) else QTFILE
    return struct.pack("<BIQ", t, 0, st.st_ino & 0xFFFFFFFFFFFFFFFF)


class Server:
    def __init__(self, root, verbose=False):
        self.root = os.path.realpath(root)
        self.fids = {}          # fid -> path
        self.opened = {}        # fid -> open file object or listing
        self.verbose = verbose
        self.counts = {}

    def log(self, *a):
        if self.verbose:
            print(*a, file=sys.stderr, flush=True)

    def safe(self, path):
        """Refuse to serve outside the share root. A 9P client is not a threat model here,
        but a walk containing '..' is an easy accident and silently serving / is not a
        failure anyone would notice until it mattered."""
        rp = os.path.realpath(path)
        if rp != self.root and not rp.startswith(self.root + os.sep):
            return None
        return rp

    def reply(self, typ, tag, body=b""):
        return struct.pack("<IBH", 7 + len(body), typ, tag) + body

    def err(self, tag, ecode):
        return self.reply(Rlerror, tag, struct.pack("<I", ecode))

    def handle(self, msg):
        if len(msg) < 7:
            return None
        size, typ, tag = struct.unpack_from("<IBH", msg, 0)
        if size != len(msg):
            msg = msg[:size]
        self.counts[typ] = self.counts.get(typ, 0) + 1
        o = 7
        try:
            if typ == Tversion:
                msz = struct.unpack_from("<I", msg, o)[0]
                ver, _ = s_str(msg, o + 4)
                self.log("Tversion msize=%d ver=%s" % (msz, ver))
                use = min(msz, MSIZE)
                # The client requires >= 512 and honours whatever we say; cap to one frame.
                return self.reply(Rversion, tag, struct.pack("<I", use) + p_str("9P2000.L"))

            if typ == Tattach:
                fid, afid = struct.unpack_from("<II", msg, o)
                uname, o2 = s_str(msg, o + 8)
                aname, o3 = s_str(msg, o2)
                self.log("Tattach fid=%d aname=%s uname=%s" % (fid, aname, uname))
                self.fids[fid] = self.root
                return self.reply(Rattach, tag, qid_of(self.root))

            if typ == Twalk:
                fid, newfid, nw = struct.unpack_from("<IIH", msg, o)
                o2 = o + 10
                names = []
                for _ in range(nw):
                    nm, o2 = s_str(msg, o2)
                    names.append(nm)
                base = self.fids.get(fid)
                if base is None:
                    return self.err(tag, errno.EBADF)
                qids, cur = [], base
                for nm in names:
                    cand = self.safe(os.path.join(cur, nm))
                    if cand is None or not os.path.exists(cand):
                        break
                    cur = cand
                    qids.append(qid_of(cur))
                if len(qids) != len(names):
                    if not qids:
                        return self.err(tag, errno.ENOENT)
                else:
                    self.fids[newfid] = cur
                self.log("Twalk %s -> %d qids" % ("/".join(names) or "(clone)", len(qids)))
                if not names:
                    self.fids[newfid] = base
                return self.reply(Rwalk, tag, struct.pack("<H", len(qids)) + b"".join(qids))

            if typ == Tlopen:
                fid, flags = struct.unpack_from("<II", msg, o)
                path = self.fids.get(fid)
                if path is None:
                    return self.err(tag, errno.EBADF)
                if os.path.isdir(path):
                    ents = [".", ".."] + sorted(os.listdir(path))
                    self.opened[fid] = ("dir", ents)
                else:
                    mode = "r+b" if (flags & 3) else "rb"
                    if flags & 0x200:       # O_TRUNC
                        mode = "w+b"
                    self.opened[fid] = ("file", open(path, mode))
                self.log("Tlopen fid=%d %s flags=0x%x" % (fid, path, flags))
                return self.reply(Rlopen, tag, qid_of(path) + struct.pack("<I", MSIZE - 24))

            if typ == Tlcreate:
                fid, = struct.unpack_from("<I", msg, o)
                name, o2 = s_str(msg, o + 4)
                flags, mode, gid = struct.unpack_from("<III", msg, o2)
                base = self.fids.get(fid)
                if base is None:
                    return self.err(tag, errno.EBADF)
                path = self.safe(os.path.join(base, name))
                if path is None:
                    return self.err(tag, errno.EACCES)
                f = open(path, "w+b")
                self.fids[fid] = path
                self.opened[fid] = ("file", f)
                self.log("Tlcreate %s" % path)
                return self.reply(Rlcreate, tag, qid_of(path) + struct.pack("<I", MSIZE - 24))

            if typ == Tmkdir:
                dfid, = struct.unpack_from("<I", msg, o)
                name, o2 = s_str(msg, o + 4)
                base = self.fids.get(dfid)
                if base is None:
                    return self.err(tag, errno.EBADF)
                path = self.safe(os.path.join(base, name))
                if path is None:
                    return self.err(tag, errno.EACCES)
                os.makedirs(path, exist_ok=True)
                self.log("Tmkdir %s" % path)
                return self.reply(Rmkdir, tag, qid_of(path))

            if typ == Tread:
                fid, off, count = struct.unpack_from("<IQI", msg, o)
                ent = self.opened.get(fid)
                if ent is None or ent[0] != "file":
                    return self.err(tag, errno.EBADF)
                count = min(count, MSIZE - 24)
                ent[1].seek(off)
                data = ent[1].read(count)
                self.log("Tread fid=%d off=%d -> %d" % (fid, off, len(data)))
                return self.reply(Rread, tag, struct.pack("<I", len(data)) + data)

            if typ == Twrite:
                fid, off, count = struct.unpack_from("<IQI", msg, o)
                data = msg[o + 16:o + 16 + count]
                ent = self.opened.get(fid)
                if ent is None or ent[0] != "file":
                    return self.err(tag, errno.EBADF)
                ent[1].seek(off)
                ent[1].write(data)
                ent[1].flush()
                self.log("Twrite fid=%d off=%d %d bytes" % (fid, off, len(data)))
                return self.reply(Rwrite, tag, struct.pack("<I", len(data)))

            if typ == Treaddir:
                fid, off, count = struct.unpack_from("<IQI", msg, o)
                ent = self.opened.get(fid)
                if ent is None or ent[0] != "dir":
                    return self.err(tag, errno.EBADF)
                names = ent[1]
                base = self.fids[fid]
                out, idx = b"", int(off)
                budget = min(count, MSIZE - 24)
                while idx < len(names):
                    nm = names[idx]
                    p = os.path.join(base, nm) if nm not in (".", "..") else base
                    try:
                        q = qid_of(p)
                    except OSError:
                        idx += 1
                        continue
                    dt = 4 if os.path.isdir(p) else 8      # DT_DIR / DT_REG
                    rec = q + struct.pack("<Q", idx + 1) + struct.pack("<B", dt) + p_str(nm)
                    if len(out) + len(rec) > budget:
                        break
                    out += rec
                    idx += 1
                self.log("Treaddir fid=%d off=%d -> %d bytes" % (fid, off, len(out)))
                return self.reply(Rreaddir, tag, struct.pack("<I", len(out)) + out)

            if typ == Tclunk:
                fid, = struct.unpack_from("<I", msg, o)
                e = self.opened.pop(fid, None)
                if e and e[0] == "file":
                    e[1].close()
                self.fids.pop(fid, None)
                return self.reply(Rclunk, tag)

            if typ == Tremove:
                fid, = struct.unpack_from("<I", msg, o)
                path = self.fids.pop(fid, None)
                self.opened.pop(fid, None)
                if path is None:
                    return self.err(tag, errno.EBADF)
                if os.path.isdir(path):
                    os.rmdir(path)
                else:
                    os.remove(path)
                return self.reply(Rremove, tag)

            self.log("unhandled type %d" % typ)
            return self.err(tag, errno.ENOSYS)
        except FileNotFoundError:
            return self.err(tag, errno.ENOENT)
        except OSError as e:
            return self.err(tag, e.errno or errno.EIO)


def frame_out(dst, payload):
    f = SRV_MAC and (dst + SRV_MAC + struct.pack(">H", ETH_TYPE) + payload)
    if len(f) < 60:
        f += b"\0" * (60 - len(f))
    return f


def serve_qemu(srv, port, seconds):
    ls = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind(("127.0.0.1", port))
    ls.listen(1)
    print("eth9p: listening on 127.0.0.1:%d, root=%s" % (port, srv.root), flush=True)
    ls.settimeout(seconds)
    try:
        cs, _ = ls.accept()
    except socket.timeout:
        print("eth9p: no QEMU connected", flush=True)
        return 1
    print("eth9p: QEMU connected", flush=True)
    cs.settimeout(seconds)
    buf = b""
    deadline = time.time() + seconds
    served = 0
    while time.time() < deadline:
        try:
            chunk = cs.recv(65536)
        except socket.timeout:
            break
        if not chunk:
            break
        buf += chunk
        while len(buf) >= 4:
            n = struct.unpack(">I", buf[:4])[0]
            if len(buf) < 4 + n:
                break
            frm, buf = buf[4:4 + n], buf[4 + n:]
            if len(frm) < 14:
                continue
            if struct.unpack(">H", frm[12:14])[0] != ETH_TYPE:
                continue
            rsp = srv.handle(frm[14:])
            if rsp is None:
                continue
            out = frame_out(frm[6:12], rsp)
            cs.sendall(struct.pack(">I", len(out)) + out)
            served += 1
    print("eth9p: served %d requests %s" % (served, srv.counts), flush=True)
    return 0 if served else 1


def serve_raw(srv, iface, seconds):
    try:
        s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_TYPE))
    except AttributeError:
        print("eth9p: --mode raw needs AF_PACKET (Linux). Run this on a host on the "
              "board's segment, or use --mode qemu.", file=sys.stderr)
        return 2
    s.bind((iface, 0))
    s.settimeout(seconds)
    print("eth9p: raw on %s, root=%s" % (iface, srv.root), flush=True)
    deadline, served = time.time() + seconds, 0
    while time.time() < deadline:
        try:
            frm = s.recv(2048)
        except socket.timeout:
            break
        if len(frm) < 14 or struct.unpack(">H", frm[12:14])[0] != ETH_TYPE:
            continue
        rsp = srv.handle(frm[14:])
        if rsp is None:
            continue
        s.send(frame_out(frm[6:12], rsp))
        served += 1
    print("eth9p: served %d requests %s" % (served, srv.counts), flush=True)
    return 0 if served else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--mode", choices=("qemu", "raw"), default="qemu")
    ap.add_argument("--port", type=int, default=9199)
    ap.add_argument("--iface", default="eth0")
    ap.add_argument("--seconds", type=float, default=40.0)
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()
    srv = Server(a.root, a.verbose)
    if a.mode == "qemu":
        return serve_qemu(srv, a.port, a.seconds)
    return serve_raw(srv, a.iface, a.seconds)


if __name__ == "__main__":
    sys.exit(main())
