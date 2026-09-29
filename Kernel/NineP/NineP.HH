// NineP.HH — 9P2000.L client types (transport-agnostic core).
// Opcode values match QEMU hw/9pfs/9p.h (9P2000.L uses Tlopen=12; Tread/Tclunk stay 116/120).
#ifndef NINEP_HH
#define NINEP_HH
#define P9_MSIZE_DEFAULT 65536
#define P9_NOFID         0xFFFFFFFF
#define P9_IOHDRSZ       24
#define P9_WRITE_CHUNK   4096
#define P9_TVERSION      100
#define P9_RVERSION      101
#define P9_TATTACH       104
#define P9_RATTACH       105
#define P9_TWALK         110
#define P9_RWALK         111
#define P9_TLOPEN        12
#define P9_RLOPEN        13
#define P9_TLCREATE      14
#define P9_RLCREATE      15
#define P9_TMKDIR        72
#define P9_RMKDIR        73
#define P9_TREAD         116
#define P9_RREAD         117
#define P9_TWRITE        118
#define P9_RWRITE        119
#define P9_TREADDIR      40
#define P9_RREADDIR      41
#define P9_TCLUNK        120
#define P9_RCLUNK        121
#define P9_TREMOVE       122
#define P9_RREMOVE       123
#define P9_O_RDONLY      0
#define P9_O_WRONLY      1
#define P9_O_RDWR        2
#define P9_O_TRUNC       0x200 // P9_DOTL_TRUNC 00001000
#define P9_O_DIRECTORY   0x10000 // P9_DOTL_DIRECTORY 00200000 (not DMDIR)
#define P9_MODE_FILE     0x1A4
#define P9_MODE_DIR      0x1ED
#define P9_QTDIR         0x80
#define NINEP_TP_NONE    0
#define NINEP_TP_MMIO    1
#define NINEP_TP_PCI     2
#define NINEP_TP_ETH     3
// 9P over raw Ethernet. 0x88B6 is in the IEEE 802.1 local-experimental range, and one step up from
// the 0x88B5 the GEM TX probe uses so a capture can tell the two apart at a glance.
#define NINEP_ETH_TYPE   0x88B6
// One 9P message per Ethernet frame, so the transport never fragments. 1500 - 14 = 1486 usable;
// keep a round number under it. The client honours whatever msize the server agrees to in
// Rversion (NinePClientVersion stores it), so capping here needs no client change at all -- it
// only requires the server to answer with something this size or smaller, and >= 512.
#define NINEP_ETH_MSIZE  1280
#define NINEP_ETH_CAP    1486
#define P9_DIALECT_NONE  0
#define P9_DIALECT_2000  1
// plain 9P2000 — Inferno Styx, Plan 9. Topen/Tcreate/Tstat, stat-based directory reads.
#define P9_DIALECT_2000L 2
// 9P2000.L — QEMU virtfs. Tlopen/Tlcreate/Tmkdir/Treaddir.
class CNinePClient
{
  I64 tp_kind;
  U16 tag;
  U32 msize;
  U32 root_fid;
  U32 next_fid;
  I64 dialect;
  // which the SERVER agreed to, not which we asked for -- see NinePClientVersion
};
#endif
