// HomeAcctExample.HH — the PRIVATE half of a TempleOS Home account, as lorem ipsum.
//
// Why this file exists
// -------------------
// `Demo/AcctExample/` is Terry Davis's own account, shipped as a worked example. It is not
// self-contained: it names a handful of values that lived in HIS `~/` and were never part of the
// distribution — his web address, his blog paths, the drive letters of his machine, his install
// registration number. Compile any of those files and you get "Undefined variable 'PERSONAL_WEB'"
// and no hint that the answer is "that one was personal; pick your own".
//
// So here is a complete set with placeholder values. Nothing here is Terry's. Every value is
// obviously fake (`lorem.example.invalid`, `ipsum`), so if one ever reaches a real network, a log
// or an ISO label, it is recognisable on sight as a value nobody set.
//
// How to make your own account
// ---------------------------
// See docs/ACCT_EXAMPLE.md. In short: copy `tos/HomeLocalize.HC`, `tos/HomeSys.HC`,
// `tos/HomeWrappers.HC` and `tos/HomeKeyPlugIns.HC` into your `/Home`, copy this file beside them,
// change the values below, and `#include` it from your `~/HomeLocalize`. TempleOS looks in `/Home`
// first and falls back to the distribution root, so a file you have not copied keeps working.
//
// On the host, `~/X` resolves through `HOLYC_HOME_ROOT` (default `/Home`, then the distribution
// root) — host/lexer.c, LoadIncludeFile.

#ifndef HOME_ACCT_EXAMPLE_HH
#define HOME_ACCT_EXAMPLE_HH

// --- Your web presence ---------------------------------------------------------------------------
// Demo/AcctExample/TOS/TOSToHtml.HC turns a `$LK$` doc link into an <a href>, so it needs to know
// where your source is published. TOSBlog.HC writes a dated blog tree in two places: a local
// directory it builds into, and the URL that directory becomes once uploaded.

#define PERSONAL_WEB	"https://lorem.example.invalid/ipsum"
#define BLOG_WEB_BASE	"https://lorem.example.invalid/ipsum/Blog"
#define BLOG_LOCAL_BASE	"B:/Home/Blog"

// --- Your machine --------------------------------------------------------------------------------
// TOS_HDS is the drive letters this machine's hard disks answer to, as one string: "C" for a single
// disk, "CD" for two. Demo/AcctExample/TOS/TOSCfg.HC normally DefinePrint()s it while the file is
// being compiled, by looking at the drives that are actually mounted — which an ahead-of-time
// compiler cannot do, so name it here.

#define TOS_HDS		"C"

// INS_REG_MACHINE_NUM distinguished the machines on one registration. Demo/AcctExample/Registry.HC
// also defines it as 0; this is for the files that read it without including that one.

#define INS_REG_MACHINE_NUM 0

// --- Your clock ----------------------------------------------------------------------------------
// Demo/AcctExample/TOS/TOSNIST.HC converts between a TempleOS CDATE and a NIST timestamp.
// NIST_TIME_OFFSET is the whole-second correction between them — leap seconds, plus whatever your
// time source is out by. Zero means "no correction", which is right until you measure otherwise.

#define NIST_TIME_OFFSET 0

// --- What this file deliberately does NOT define -------------------------------------------------
// These also come up as undefined in Demo/AcctExample/, and they are NOT personal — they are parts
// of the kernel and of Adam that this port has not brought over yet. Defining them here would
// teach the wrong lesson, so they are listed instead of guessed:
//
//   SYS_KERNEL_END, SYS_IDLE_PT, SYS_RAM_REBOOT_END   kernel link-time symbols
//   BDVD_START, BMHD2_BLK_ARRAY                       Adam/Opt/Boot disk layout constants
//   GR_PEN_BRUSHES_NUM, GR_SCRN_ZOOM_MAX              Adam/Gr constants
//   ins_reg (CInsReg), InsRereg                       Adam/Opt/Utils/TOS.HC install registration
//   god (CGodGlbls)                                   Adam/God/GodExt.HC — in the tree, not in the PRJ
//   meter_tops, meter_bottoms                         tos/Apps/Psalmody, a sibling file
//
// docs/DEMO_SURVEY.md keeps the current count of each.

#endif
