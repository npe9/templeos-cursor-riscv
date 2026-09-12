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
class CNinePClient
{
  I64 tp_kind;
  U16 tag;
  U32 msize;
  U32 root_fid;
  U32 next_fid;
};
#endif
