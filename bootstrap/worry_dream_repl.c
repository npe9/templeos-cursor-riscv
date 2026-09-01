// Worry Dream Machine - Live Interactive REPL
// Type HolyC code over UART, compile and execute it

#include <stdint.h>
#include <stddef.h>
#include "../host/holyc_compiler.h"

/* 16550 UART base. Per-platform: overridden with -DUART_BASE=0x... from the Makefile PLATFORM
 * table (default is QEMU virt's UART). */
#ifndef UART_BASE
#define UART_BASE 0x10000000
#endif
#define true 1
#define false 0

// ---- UART: raw byte transport. Knows nothing about terminals. --------------------------
#define UART_RX_CAP 16384  /* power of two; holds a full piped smoke script with headroom */
#define CH_CTRLC    3      /* ASCII ETX — host Ctrl-C over -nographic UART */
#ifndef PLIC_BASE
#define PLIC_BASE   0x0C000000UL
#endif
#ifndef CLINT_BASE
#define CLINT_BASE  0x02000000UL
#endif
#define CLINT_MTIME_OFF     0xBFF8UL
#define CLINT_MTIMECMP_OFF  0x4000UL
#define MEM_MTIME_ADDR      (CLINT_BASE + CLINT_MTIME_OFF)
#define MEM_MTIMECMP_ADDR   (CLINT_BASE + CLINT_MTIMECMP_OFF)
#ifndef VIRTIO_MMIO_BASE
#define VIRTIO_MMIO_BASE 0x10001000UL
#endif
#define UART_IRQ    10     /* QEMU virt 16550 on PLIC */
/* TempleOS throw('Break') — little-endian multi-char I64 ('B'+'r'<<8+…). */
#define EXCEPT_BREAK ((I64)0x6B61657242ULL)

static U8  uart_rx[UART_RX_CAP];
static I64 uart_rh, uart_rt;   /* head = write, tail = read */
static U8  uart_ung[8];
static int uart_ung_n;         /* pushback for ESC peek when the key queue is full */
/* Soft break: set when Ctrl-C (ETX) is seen on UART. g_break_armed during repl_eval.
 * g_break_interactive is 0 during seed boot so piped Ctrl-C is not eaten by Run(). */
static volatile int g_break_pending;
static volatile int g_break_armed;
static int g_break_interactive;

/* Drain 16550 RX into uart_rx. Mask mstatus.MIE for the whole loop — not just mie.MEIE.
 * With global MIE on, any IRQ (UART *or* the break-poll timer) can nest between LSR.DR
 * and RBR, empty the FIFO in a nested uart_hw_drain, and the outer read then sees the
 * stale last RBR value and enqueues a duplicate (interactive typing → "aa" per key).
 * Masking only MEIE left MTIE free to re-enter drain during break-armed eval / UartPut.
 * Ctrl-C still works: UART IRQ or timer poll runs after MIE is restored. */
static void uart_hw_drain(void) {
    I64 mstatus;
    __asm__ volatile("csrr %0, mstatus" : "=r"(mstatus));
    __asm__ volatile("csrc mstatus, %0" :: "r"((I64)(1 << 3))); /* MIE */
    while (*(volatile U8 *)(UART_BASE + 5) & 0x01) {
        U8 ch = *(volatile U8 *)UART_BASE;
        if (ch == CH_CTRLC) {
            g_break_pending = 1;
            /* During eval, consume the break byte so it does not pollute the next prompt. */
            if (g_break_armed) continue;
        }
        I64 n = (uart_rh + 1) & (UART_RX_CAP - 1);
        if (n == uart_rt) break;   /* ring full: byte already taken from HW — drop */
        uart_rx[uart_rh] = ch;
        uart_rh = n;
    }
    if (mstatus & (1 << 3))
        __asm__ volatile("csrs mstatus, %0" :: "r"((I64)(1 << 3)));
}
/* If the next queued RX byte is Ctrl-C, consume it and set g_break_pending.
 * Do NOT scan past other bytes — that would steal a break meant for a later line
 * from an all-at-once pipe (boot Help drains the whole script into the ring). */
static void uart_ring_take_leading_break(void) {
    if (uart_rh == uart_rt) return;
    if (uart_rx[uart_rt] != CH_CTRLC) return;
    uart_rt = (uart_rt + 1) & (UART_RX_CAP - 1);
    g_break_pending = 1;
}
/* Enable 16550 RX IRQ + PLIC + mie.MEIE so Ctrl-C can wake wfi and preempt busy loops.
 * IER is left on after TrapInit; break-armed eval also polls via the CLINT timer. */
static void UartBreakIrqInit(void) {
    *(volatile U8 *)(UART_BASE + 1) = 1;                                   /* IER: received-data */
    *(volatile U32 *)(PLIC_BASE + UART_IRQ * 4) = 1;                       /* priority */
    *(volatile U32 *)(PLIC_BASE + 0x2000) |= (1u << UART_IRQ);             /* enable ctx0 */
    *(volatile U32 *)(PLIC_BASE + 0x200000) = 0;                           /* threshold */
    __asm__ volatile("csrs mie, %0" :: "r"((I64)(1 << 11)));          /* MEIE */
}
static int plic_service_uart(void) {
    volatile U32 *claim = (volatile U32 *)(PLIC_BASE + 0x200004);
    U32 irq = *claim;
    if (irq == UART_IRQ) uart_hw_drain();
    if (irq) *claim = irq;
    return (int)irq;
}
static void UartPut(U8 ch) {
    /* Drain RX while transmitting so the 16550 FIFO cannot overflow during
     * long redraws (Vi/Edit) while piped input is still arriving. */
    uart_hw_drain();
    while (!(*(volatile U8 *)(UART_BASE + 5) & 0x20));
    *(volatile U8 *)UART_BASE = ch;
}
static void UartWrite(const U8 *buf, I64 len) { while (len-- > 0) UartPut(*buf++); }

static void UartUnget(U8 ch) {
    if (uart_ung_n < (int)sizeof(uart_ung)) {
        uart_ung[uart_ung_n++] = ch;
        return;
    }
    /* Pushback stack full: spill into the RX ring (never drop piped input). */
    I64 prev = (uart_rt - 1) & (UART_RX_CAP - 1);
    if (prev == uart_rh) return; /* ring also full — extremely rare */
    uart_rx[prev] = ch;
    uart_rt = prev;
}
static int UartTryGet(U8 *ch) {
    if (uart_ung_n > 0) { *ch = uart_ung[--uart_ung_n]; return 1; }
    uart_hw_drain();
    if (uart_rh == uart_rt) return 0;
    *ch = uart_rx[uart_rt];
    uart_rt = (uart_rt + 1) & (UART_RX_CAP - 1);
    return 1;
}
static U8 UartGet(void) { U8 ch; while (!UartTryGet(&ch)) {} return ch; }

static void putc_uart(char c) { UartPut((U8)c); }   /* Print / puts_uart stay on the UART layer */

static void puts_uart(const char *s) {
    while (*s) {
        if (*s == '\n') putc_uart('\r');
        putc_uart(*s++);
    }
}

static void print_hex(uint64_t val) {
    putc_uart('0'); putc_uart('x');
    for (int i = 15; i >= 0; i--) {
        int d = (val >> (i*4)) & 0xF;
        putc_uart(d < 10 ? '0' + d : 'a' + d - 10);
    }
}

static void print_hex_byte(unsigned char val) {
    int hi = (val >> 4) & 0xF;
    int lo = val & 0xF;
    putc_uart(hi < 10 ? '0' + hi : 'a' + hi - 10);
    putc_uart(lo < 10 ? '0' + lo : 'a' + lo - 10);
}

// TempleOS CmdLinePmt-style command-line echo helpers: unsigned/signed decimal, execution time
// (%8.6fs), and a simple F64 decimal.
static void print_udec(U64 v) {
    char b[24]; int i = 0;
    if (!v) { putc_uart('0'); return; }
    while (v) { b[i++] = '0' + v % 10; v /= 10; }
    while (i--) putc_uart(b[i]);
}
static void print_dec(I64 v) { if (v < 0) { putc_uart('-'); v = -v; } print_udec((U64)v); }
static void print_time(U64 ticks) {   // QEMU virt timebase is 10 MHz -> 10 ticks per microsecond
    U64 us = ticks / 10, sec = us / 1000000, frac = us % 1000000, d = 100000;
    print_udec(sec); putc_uart('.');
    while (d) { putc_uart('0' + (frac / d) % 10); d /= 10; }
    putc_uart('s');
}
static void print_f64(U64 bits) {
    union { U64 b; double d; } u; u.b = bits;
    double v = u.d;
    if (v < 0) { putc_uart('-'); v = -v; }
    U64 ip = (U64)v; double fp = v - (double)ip;
    print_udec(ip); putc_uart('.');
    for (int i = 0; i < 6; i++) { fp *= 10; int dg = (int)fp; putc_uart('0' + dg); fp -= dg; }
}

// Separate code and heap areas to prevent overwriting
/* Fixed memfs arena (seed/fs.hc). Fits in QEMU virt default 128MiB (RAM ends 0x88000000):
 * after C BSS / HolyC heap / 0x87001xxx slots, before MEM_STACK @0x87F00000.
 * 0x85000000 overlapped heap BSS; 0x88000000 needs -m >128M and hung bare `-nographic`. */
#define MEMFS_PHYS_BASE 0x87800000ULL
static U8 code_mem[8*1024*1024];   // 8MB for compiled code (never reused)
static size_t code_pos = 0;
static U8 heap_mem[96*1024*1024];  // 96MB heap (IC/parse; free() is a no-op; large seeds e.g. vim.hc)
static size_t heap_pos = 0;

// Special malloc for CODE - never freed, never reused
void *code_malloc(size_t sz) {
    if (sz == 0) return NULL;
    size_t aligned = (sz + 7) & ~7;
    if (code_pos + aligned > sizeof(code_mem)) {
        return NULL;
    }
    // Ensure code is in executable memory range
    void *p = &code_mem[code_pos];
    code_pos += aligned;
    // Debug: verify address is valid
    U64 addr = (U64)p;
    if (addr < 0x80000000 || addr > 0x90000000) {
        return NULL;  // Invalid address range
    }
    return p;
}

void *malloc(size_t sz) { 
    if (sz == 0) return NULL;
    size_t aligned = (sz + 7) & ~7;
    /* Never grow into the fixed memfs arena (fs.hc / MEM_FS), even if BSS layout shifts. */
    int oom = (heap_pos + aligned > sizeof(heap_mem)) ||
              ((uintptr_t)heap_mem + heap_pos + aligned > (uintptr_t)MEMFS_PHYS_BASE);
    if (oom) {
        puts_uart("[malloc: OUT OF MEMORY! sz=");
        print_hex(sz);
        puts_uart(" pos=");
        print_hex(heap_pos);
        puts_uart("]\n");
        // Reset heap for REPL - free everything except code
        heap_pos = 0;
        void *p = &heap_mem[heap_pos];
        heap_pos += aligned;
        return p;
    }
    void *p = &heap_mem[heap_pos];
    heap_pos += aligned;
    return p;
}
void *calloc(size_t n, size_t sz) { 
    size_t total = n * sz;
    void *p = malloc(total);
    if (!p) return NULL;
    // Zero out memory
    for (size_t i = 0; i < total; i++) ((U8*)p)[i] = 0;
    return p;
}
// Don't free in REPL - we need to keep function code alive!
void free(void *p) { (void)p; }
/* Bare-metal libc bits newly needed by host parser.c (memcmp/realloc/strchr). */
int memcmp(const void *a, const void *b, size_t n) {
    const U8 *x = (const U8 *)a, *y = (const U8 *)b;
    for (size_t i = 0; i < n; i++) if (x[i] != y[i]) return (int)x[i] - (int)y[i];
    return 0;
}
char *strchr(const char *s, int c) {
    if (!s) return 0;
    while (*s) { if ((U8)*s == (U8)c) return (char *)s; s++; }
    return c ? 0 : (char *)s;
}
void *realloc(void *ptr, size_t size) {
    void *n = malloc(size);
    if (n && ptr) {
        U8 *d = (U8 *)n, *s = (U8 *)ptr;
        /* bump allocator: unknown old size — copy up to `size` (parser only grows). */
        for (size_t i = 0; i < size; i++) d[i] = s[i];
    }
    return n;
}
size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
char *strdup(const char *s) {
    size_t n = strlen(s);
    char *d = malloc(n + 1);
    for (size_t i = 0; i <= n; i++) d[i] = s[i];
    return d;
}
char *getenv(const char *name) { (void)name; return 0; }
int strcmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a - *b;
}
int strncmp(const char *a, const char *b, size_t n) {
    while (n && *a && *a == *b) { a++; b++; n--; }
    return n ? (unsigned char)*a - (unsigned char)*b : 0;
}
char *strstr(const char *h, const char *n) {
    if (!h || !n) return 0;
    if (!*n) return (char *)h;
    for (; *h; h++) {
        const char *a = h, *b = n;
        while (*a && *b && *a == *b) { a++; b++; }
        if (!*b) return (char *)h;
    }
    return 0;
}
char *strcpy(char *d, const char *s) {
    char *r = d;
    while ((*d++ = *s++));
    return r;
}
int isspace(int c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }
int isdigit(int c) { return c >= '0' && c <= '9'; }
int isalpha(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
int isalnum(int c) { return isalpha(c) || isdigit(c); }
long long atoll(const char *s) {
    long long v = 0;
    int neg = 0;
    while (isspace(*s)) s++;
    if (*s == '-') { neg = 1; s++; }
    while (isdigit(*s)) v = v * 10 + (*s++ - '0');
    return neg ? -v : v;
}
int atoi(const char *s) { return (int)atoll(s); }
void *memset(void *s, int c, size_t n) {
    U8 *p = s;
    while (n--) *p++ = c;
    return s;
}
void *memcpy(void *d, const void *s, size_t n) {
    U8 *pd = d;
    const U8 *ps = s;
    while (n--) *pd++ = *ps++;
    return d;
}
long long strtoll(const char *s, char **end, int base) { return atoll(s); }
double atof(const char *s) { return 0.0; }
const char _ctype_[256] = {0};
FILE *fopen(const char *p, const char *m) { return NULL; }
int fclose(FILE *f) { return 0; }
size_t fread(void *ptr, size_t size, size_t n, FILE *f) { return 0; }
size_t fwrite(const void *ptr, size_t size, size_t n, FILE *f) { return 0; }
int fseek(FILE *f, long offset, int whence) { return 0; }
long ftell(FILE *f) { return 0; }
/* Bare-metal: satisfy compiler.c host-only fprintf debug without newlib I/O. */
#include <reent.h>
struct _reent impure_data;
struct _reent *_impure_ptr = &impure_data;
int fprintf(FILE *f, const char *fmt, ...) { (void)f; (void)fmt; return 0; }

// Compiler interface - now provided by holyc_compiler.h
extern Bool ParseProgram(Compiler *cc);
extern U8 *CompileAOT(Compiler *cc, I64 *size);

// Code execution space
static U8 *code_area = (U8*)0x80200000;

// Global answer variable (like TempleOS Fs->answer)
static I64 g_answer = 0;

// ---- HolyC runtime (shared with the exec harness: bootstrap/holy_rt.h) -------------------
#define HOLY_RT_PUTC(c) putc_uart(c)
#define HOLY_RT_MALLOC(sz) malloc(sz)
#include "holy_rt.h"
#include "../host/holyc_fmt.h"

static char g_fmt_buf[65536];

static HRT_I64 TermPoll(void);
static HRT_I64 TermKeyGet(void);
static HRT_I64 TermClearEol(void);
static HRT_I64 Exec(char *src);
static char getc_uart(void);
// Line editor: history + Tab completion for the REPL prompt; ed uses plain mode.
enum { RL_HIST = 1, RL_COMPLETE = 2, RL_NO_AUTO_HIST = 4 };
#define RL_MULTILINE_RECALL (-2)
static int repl_read_line_ex(char *buf, int max, int flags, const char *prompt);
static void repl_set_prefill(const char *line);
static int repl_read_line(char *buf, int max);   /* plain (smart Tab) — for ed */
static int rl_pathchar(int c);
static int rl_complete_core(char *buf, int max, int *len, int *cur, int list_ok);
// ---- In-memory filesystem (REPL-only, RAM-backed) ----------------------------------------
// HolyC owns the arena at MEMFS_PHYS_BASE (seed/fs.hc); C seed boot + EdC/EditC share it so
// there is one source of truth. Layout/stride must match HolyC MEMFS_* (65608).
#define MEMFS_MAX_FILES 96
#define MEMFS_FILE_CAP  65536
#define MEMFS_STRIDE    65608
#define MEMFS_CWD_OFF   (MEMFS_MAX_FILES * MEMFS_STRIDE)
typedef struct { int used; char name[64]; char data[MEMFS_FILE_CAP]; int len; } MemFile;
_Static_assert(sizeof(MemFile) == MEMFS_STRIDE, "MemFile stride must match HolyC MEMFS_STRIDE");
#define memfs     ((MemFile *)(uintptr_t)MEMFS_PHYS_BASE)
#define memfs_cwd ((char *)(uintptr_t)(MEMFS_PHYS_BASE + MEMFS_CWD_OFF))
static int memfs_strncmp(const char *a, const char *b, unsigned long n) {   // freestanding: no libc
    for (unsigned long i = 0; i < n; i++) {
        if (a[i] != b[i]) return (unsigned char)a[i] - (unsigned char)b[i];
        if (!a[i]) return 0;
    }
    return 0;
}
static void memfs_resolve(const char *name, char *out) {   // out[64]: cwd applied, . and .. folded
    char tmp[160]; int n = 0, i = 0, o = 0;
    if (name[0] == '/') name++;                            // absolute: skip cwd
    else while (memfs_cwd[n]) { tmp[n] = memfs_cwd[n]; n++; }
    while (name[i] && n < 150) tmp[n++] = name[i++];
    tmp[n] = 0;
    i = 0;
    while (tmp[i]) {
        if (tmp[i] == '.' && (tmp[i+1] == '/' || tmp[i+1] == 0)) { i += tmp[i+1] ? 2 : 1; continue; }
        if (tmp[i] == '.' && tmp[i+1] == '.' && (tmp[i+2] == '/' || tmp[i+2] == 0)) {
            if (o > 0) { o--; while (o > 0 && out[o-1] != '/') o--; }
            i += tmp[i+2] ? 3 : 2; continue;
        }
        while (tmp[i] && tmp[i] != '/' && o < 62) out[o++] = tmp[i++];
        if (tmp[i] == '/') { if (o < 62) out[o++] = '/'; i++; }
    }
    out[o] = 0;
}
static MemFile *memfs_lookup(const char *full) {            // exact stored name, no cwd
    for (int i = 0; i < MEMFS_MAX_FILES; i++)
        if (memfs[i].used && !strcmp(memfs[i].name, full)) return &memfs[i];
    return NULL;
}
static MemFile *memfs_find(const char *name) {
    char full[64]; memfs_resolve(name, full);
    return memfs_lookup(full);
}
static MemFile *memfs_create(const char *name) {
    char fullbuf[64]; memfs_resolve(name, fullbuf);
    MemFile *f = memfs_lookup(fullbuf);                    // already resolved: don't Cd-prefix twice
    if (f) return f;
    for (int i = 0; i < MEMFS_MAX_FILES; i++) if (!memfs[i].used) {
        MemFile *n = &memfs[i];
        n->used = 1; n->len = 0; n->data[0] = 0;
        int j = 0; while (fullbuf[j] && j < 63) { n->name[j] = fullbuf[j]; j++; } n->name[j] = 0;
        return n;
    }
    return NULL;  // table full
}

// Dir() / Ls() -- list the CURRENT directory: files at this level, subdirectories as "name/".
static HRT_I64 Dir(void) {
    int count = 0, cl = 0;
    char shown[16][64]; int ns = 0;                        // subdirs already printed
    while (memfs_cwd[cl]) cl++;
    puts_uart("  /"); puts_uart(memfs_cwd); puts_uart("\n");
    for (int i = 0; i < MEMFS_MAX_FILES; i++) if (memfs[i].used) {
        const char *nm = memfs[i].name;
        int k = 0; while (k < cl && nm[k] == memfs_cwd[k]) k++;
        if (k != cl) continue;                             // not under cwd
        const char *rest = nm + cl;
        const char *slash = rest; while (*slash && *slash != '/') slash++;
        if (*slash) {                                      // deeper: print the subdir once
            int L = (int)(slash - rest);
            int dup = 0;
            for (int d = 0; d < ns; d++) if (!memfs_strncmp(shown[d], rest, L) && !shown[d][L]) dup = 1;
            if (!dup && ns < 16) {
                int c2 = 0; while (c2 < L && c2 < 63) { shown[ns][c2] = rest[c2]; c2++; } shown[ns][c2] = 0; ns++;
                puts_uart("  "); for (int c3 = 0; c3 < L; c3++) putc_uart(rest[c3]); puts_uart("/\n");
                count++;
            }
            continue;
        }
        if (rest[0] == '.') continue;                      // .dir marker, .dirlist, other dotfiles
        puts_uart("  "); puts_uart(rest);
        puts_uart("  "); print_udec(memfs[i].len); puts_uart(" bytes\n");
        count++;
    }
    if (!count) puts_uart("  (empty)\n");
    return count;
}
// Cd("Demo") / Cd("..") / Cd("/") -- change the current directory (flat namespace: any prefix
// is a directory; DirMk plants a marker so empty ones list). Pwd() prints it.
static HRT_I64 Cd(char *name) {
    char tmp[96], full[64]; int i = 0;
    if (!name || !name[0] || (name[0] == '/' && !name[1])) memfs_cwd[0] = 0;
    else {
        while (name[i] && i < 90) { tmp[i] = name[i]; i++; }
        if (i && tmp[i-1] != '/') tmp[i++] = '/';
        tmp[i] = 0;
        memfs_resolve(tmp, full);
        i = 0; while (full[i] && i < 94) { memfs_cwd[i] = full[i]; i++; } memfs_cwd[i] = 0;
    }
    puts_uart("cwd: /"); puts_uart(memfs_cwd); puts_uart("\n");
    return 0;
}
static HRT_I64 Pwd(void) { puts_uart("/"); puts_uart(memfs_cwd); puts_uart("\n"); return 0; }
static HRT_I64 CwdStr(void) { return (HRT_I64)memfs_cwd; }   // the cwd string, for HolyC's Dir
static HRT_I64 IsDir(char *name) {
    char tmp[96], full[64]; int i = 0, cl;
    while (name[i] && i < 90) { tmp[i] = name[i]; i++; }
    if (i && tmp[i-1] != '/') tmp[i++] = '/';
    tmp[i] = 0;
    memfs_resolve(tmp, full);
    cl = 0; while (full[cl]) cl++;
    for (int k = 0; k < MEMFS_MAX_FILES; k++)
        if (memfs[k].used && !memfs_strncmp(memfs[k].name, full, cl)) return 1;
    return 0;
}
static HRT_I64 DirMk(char *name) {
    char tmp[96]; int i = 0;
    while (name[i] && i < 80) { tmp[i] = name[i]; i++; }
    if (i && tmp[i-1] != '/') tmp[i++] = '/';
    tmp[i] = 0;
    for (int j = 0; ".dir"[j]; j++) tmp[i++] = ".dir"[j];
    tmp[i] = 0;
    if (!memfs_create(tmp)) { puts_uart("DirMk: fs full\n"); return -1; }
    return 0;
}
static HRT_I64 DirDel(char *name) {
    char tmp[96], full[64]; int i = 0, cl;
    while (name[i] && i < 90) { tmp[i] = name[i]; i++; }
    if (i && tmp[i-1] != '/') tmp[i++] = '/';
    tmp[i] = 0;
    memfs_resolve(tmp, full);
    cl = 0; while (full[cl]) cl++;
    for (int k = 0; k < MEMFS_MAX_FILES; k++)
        if (memfs[k].used && !memfs_strncmp(memfs[k].name, full, cl) && strcmp(memfs[k].name + cl, ".dir"))
            { puts_uart("DirDel: not empty\n"); return -1; }
    for (int k = 0; k < MEMFS_MAX_FILES; k++)
        if (memfs[k].used && !memfs_strncmp(memfs[k].name, full, cl))
            { memfs[k].used = 0; memfs[k].len = 0; memfs[k].name[0] = 0; }
    return 0;
}
// Cat("name") -- dump a file to the console.
static HRT_I64 Cat(char *name) {
    MemFile *f = memfs_find(name);
    if (!f) { puts_uart("Cat: no such file: "); puts_uart(name); puts_uart("\n"); return -1; }
    for (int i = 0; i < f->len; i++) putc_uart(f->data[i]);
    if (f->len && f->data[f->len - 1] != '\n') putc_uart('\n');
    return f->len;
}
// Del("name") -- free a slot.
static HRT_I64 Del(char *name) {
    MemFile *f = memfs_find(name);
    if (!f) { puts_uart("Del: no such file\n"); return -1; }
    f->used = 0; f->len = 0; f->name[0] = 0;
    return 0;
}
// HolyC sources (.hc/.HH) are auto-formatted via HolyFmtSrc (AST/CST gofmt-like) before commit.
/* Returns 1 if rewritten, 0 if unchanged/skipped, -1 on format error. */
static int memfs_format_inplace(MemFile *f, const char *name) {
    long long n;
    int changed;
    if (!f || !name || !HolyFmtIsHcName(name)) return 0;
    if (!f->data) return -1;
    n = HolyFmtSrc(f->data, g_fmt_buf, (long long)sizeof(g_fmt_buf));
    if (n < 0) return -1;
    if (n > MEMFS_FILE_CAP - 1) n = MEMFS_FILE_CAP - 1;
    changed = (n != f->len);
    if (!changed) {
        long long i;
        for (i = 0; i < n; i++)
            if ((unsigned char)f->data[i] != (unsigned char)g_fmt_buf[i]) {
                changed = 1;
                break;
            }
    }
    if (!changed) return 0;
    for (long long i = 0; i < n; i++) f->data[i] = g_fmt_buf[i];
    f->data[n] = 0;
    f->len = (int)n;
    return 1;
}
static HRT_I64 FileWrite(char *name, char *data, HRT_I64 len) {
    MemFile *f = memfs_create(name);
    if (!f) { puts_uart("FileWrite: fs full\n"); return -1; }
    if (len < 0) len = 0;
    if (len > MEMFS_FILE_CAP - 1) len = MEMFS_FILE_CAP - 1;
    for (HRT_I64 i = 0; i < len; i++) f->data[i] = data[i];
    f->data[len] = 0; f->len = (int)len;
    memfs_format_inplace(f, name);
    return f->len;
}
/* Quiet in-place format for editors (FmtSave). Returns new length or -1. */
static HRT_I64 HcFmtFile(char *name) {
    MemFile *f = memfs_find(name);
    int rc;
    if (!f) return -1;
    if (!HolyFmtIsHcName(name)) return -1;
    rc = memfs_format_inplace(f, name);
    if (rc < 0) return -1;
    return f->len;
}
// FileRead("name") -- pointer to the file's (NUL-terminated) bytes, or 0 if missing.
static HRT_I64 FileRead(char *name) {
    MemFile *f = memfs_find(name);
    return f ? (HRT_I64)f->data : 0;
}
// Directory iteration exposed to HolyC, so Dir can be written (and edited) in HolyC. Files are
// enumerated in used-slot order: FileCount() files, FileName(i)/FileSize(i) for each.
static HRT_I64 FileCount(void) {
    int n = 0; for (int i = 0; i < MEMFS_MAX_FILES; i++) if (memfs[i].used) n++;
    return n;
}
static HRT_I64 FileName(HRT_I64 idx) {
    int k = 0; for (int i = 0; i < MEMFS_MAX_FILES; i++) if (memfs[i].used) { if (k == idx) return (HRT_I64)memfs[i].name; k++; }
    return 0;
}
static HRT_I64 FileSize(HRT_I64 idx) {
    int k = 0; for (int i = 0; i < MEMFS_MAX_FILES; i++) if (memfs[i].used) { if (k == idx) return memfs[i].len; k++; }
    return 0;
}
static HRT_I64 FileLen(char *name) { MemFile *f = memfs_find(name); return f ? f->len : -1; }

// ---- Seed files: kernel primitives shipped as editable HolyC source ----------------------
// These land in the in-memory FS at boot, so the "system" you edit is HolyC from the first
// prompt: `Dir` shows them, `Run("uart.hc")` compiles a primitive into the live symbol table,
// and editing + re-Running it changes the driver in place (callers resolve through the table,
// so redefining UartPut alone also changes UartStr). This is the seam the whole-kernel move
// grows from -- add primitives here (or load them off a disk) and they become redefinable.
#include "seed_files.h"
#include "boot_blob_embed.h"
static void memfs_seed(void) {
    for (unsigned i = 0; i < sizeof(memfs_seed_files) / sizeof(memfs_seed_files[0]); i++) {
        MemFile *f = memfs_create(memfs_seed_files[i].name);
        if (!f) continue;
        const char *b = memfs_seed_files[i].body;
        int n = 0; while (b[n] && n < MEMFS_FILE_CAP - 1) { f->data[n] = b[n]; n++; }
        f->data[n] = 0; f->len = n;
    }
}

// ---- ed(1)-style line editor over the serial console -------------------------------------
// A classic ed subset: addresses . $ N  N,M  , %  and commands a i d p n w q =.
// Line buffer is a fixed 2-D array (no per-line alloc -> nothing to leak).
#define ED_MAX_LINES 512
#define ED_LINE_CAP  256
static char ed_lines[ED_MAX_LINES][ED_LINE_CAP];
static int  ed_n;     // line count
static int  ed_cur;   // current line, 1-based (0 = empty buffer)

static void ed_insert_at(int pos, const char *text) {  // insert one line at 0-based index pos
    if (ed_n >= ED_MAX_LINES) { puts_uart("ed: buffer full\n"); return; }
    for (int k = ed_n; k > pos; k--) memcpy(ed_lines[k], ed_lines[k - 1], ED_LINE_CAP);
    int j = 0; while (text[j] && j < ED_LINE_CAP - 1) { ed_lines[pos][j] = text[j]; j++; }
    ed_lines[pos][j] = 0;
    ed_n++;
}
static void ed_delete_range(int a, int b) {  // 1-based inclusive
    if (a < 1) a = 1; if (b > ed_n) b = ed_n; if (a > b) return;
    int cnt = b - a + 1;
    for (int k = a - 1; k + cnt < ed_n; k++) memcpy(ed_lines[k], ed_lines[k + cnt], ED_LINE_CAP);
    ed_n -= cnt;
}
static void ed_input_block(int at) {  // read lines until "." ; each goes in at index `at`, `at`+1, ...
    char line[ED_LINE_CAP];
    while (1) {
        int len = repl_read_line(line, sizeof(line));
        if (len == 1 && line[0] == '.') break;
        ed_insert_at(at, line);
        at++;
    }
    ed_cur = at;  // current = last line inserted
}
static int ed_parse_addr(const char *s, int *pp, int *have) {
    int p = *pp, v = -1; *have = 0;
    while (s[p] == ' ') p++;
    if      (s[p] == '.') { v = ed_cur; *have = 1; p++; }
    else if (s[p] == '$') { v = ed_n;   *have = 1; p++; }
    else if (s[p] >= '0' && s[p] <= '9') { v = 0; while (s[p] >= '0' && s[p] <= '9') v = v * 10 + (s[p++] - '0'); *have = 1; }
    *pp = p;
    return v;
}
// Ed("name") -- edit (or create) a file. Returns 0.
static HRT_I64 Ed(char *name) {
    MemFile *f = memfs_create(name);
    if (!f) { puts_uart("Ed: fs full\n"); return -1; }
    // load the file into the line buffer, splitting on '\n'
    ed_n = 0;
    { int i = 0; while (i < f->len && ed_n < ED_MAX_LINES) {
        int j = 0;
        while (i < f->len && f->data[i] != '\n' && j < ED_LINE_CAP - 1) ed_lines[ed_n][j++] = f->data[i++];
        ed_lines[ed_n][j] = 0;
        while (i < f->len && f->data[i] != '\n') i++;   // drop any overlong tail
        if (i < f->len && f->data[i] == '\n') i++;
        ed_n++;
    } }
    ed_cur = ed_n;
    puts_uart("ed "); puts_uart(name); puts_uart(": "); print_udec(ed_n);
    puts_uart(" lines. cmds: a i d p n w q =  ('.' ends input)\n");
    char cmd[ED_LINE_CAP];
    while (1) {
        repl_read_line(cmd, sizeof(cmd));
        int p = 0; while (cmd[p] == ' ') p++;
        int a1 = -1, a2 = -1, have1 = 0, have2 = 0;
        if (cmd[p] == ',' || cmd[p] == '%') { a1 = 1; a2 = ed_n; have1 = have2 = 1; p++; }
        else {
            a1 = ed_parse_addr(cmd, &p, &have1);
            if (cmd[p] == ',') { p++; a2 = ed_parse_addr(cmd, &p, &have2); }
        }
        char c = cmd[p];
        switch (c) {
        case 'a': { int at = have1 ? a1 : ed_cur; if (at < 0) at = 0; if (at > ed_n) at = ed_n; ed_input_block(at); break; }
        case 'i': { int at = (have1 ? a1 : ed_cur) - 1; if (at < 0) at = 0; if (at > ed_n) at = ed_n; ed_input_block(at); break; }
        case 'd': { int lo = have1 ? a1 : ed_cur, hi = have2 ? a2 : lo; ed_delete_range(lo, hi);
                    if (ed_cur > ed_n) ed_cur = ed_n; break; }
        case 'p':
        case 'n': { int lo = have1 ? a1 : ed_cur, hi = have2 ? a2 : lo;
                    if (lo < 1) lo = 1; if (hi > ed_n) hi = ed_n;
                    for (int k = lo; k <= hi; k++) {
                        if (c == 'n') { print_udec(k); putc_uart('\t'); }
                        puts_uart(ed_lines[k - 1]); putc_uart('\n');
                    }
                    if (hi >= 1) ed_cur = hi; break; }
        case 'w': { int off = 0;
                    for (int k = 0; k < ed_n; k++) {
                        int j = 0;
                        while (ed_lines[k][j] && off < MEMFS_FILE_CAP - 1) f->data[off++] = ed_lines[k][j++];
                        if (off < MEMFS_FILE_CAP - 1) f->data[off++] = '\n';
                    }
                    f->data[off] = 0; f->len = off;
                    memfs_format_inplace(f, name);
                    off = f->len;
                    /* Reload lines so the buffer matches formatted on-disk text. */
                    if (HolyFmtIsHcName(name)) {
                        ed_n = 0;
                        { int i = 0; while (i < f->len && ed_n < ED_MAX_LINES) {
                            int j = 0;
                            while (i < f->len && f->data[i] != '\n' && j < ED_LINE_CAP - 1)
                                ed_lines[ed_n][j++] = f->data[i++];
                            ed_lines[ed_n][j] = 0;
                            while (i < f->len && f->data[i] != '\n') i++;
                            if (i < f->len && f->data[i] == '\n') i++;
                            ed_n++;
                        } }
                        if (ed_cur > ed_n) ed_cur = ed_n;
                    }
                    puts_uart("wrote "); puts_uart(name); puts_uart(" (");
                    print_udec(off); puts_uart(" bytes)\n"); break; }
        case 'q': putc_uart('\n'); return 0;
        case '!': Exec(&cmd[p + 1]); break;  /* ! <holyc> — run in place (matches HolyC Ed) */
        case '=': { print_udec(have1 ? a1 : ed_cur); putc_uart('\n'); break; }
        case 0:   // bare address prints that line; bare Enter advances one line
            if (have1) { if (a1 >= 1 && a1 <= ed_n) { ed_cur = a1; puts_uart(ed_lines[a1 - 1]); putc_uart('\n'); } }
            else if (ed_cur < ed_n) { ed_cur++; puts_uart(ed_lines[ed_cur - 1]); putc_uart('\n'); }
            break;
        default: puts_uart("?\n"); break;
        }
    }
}

// ---- Terminal core: parser, capability state, geometry, output ---------------------------
// Every UART byte goes through one VT/ANSI state machine. Keyboard events and terminal
// replies (DSR, window size) are separate queues so EditC never sees ESC [ A or ESC [ 24;80 R.
enum { TS_GROUND, TS_ESC, TS_CSI, TS_SS3 };
enum {
    TE_NONE = 0, TE_CHAR,
    TE_UP, TE_DOWN, TE_LEFT, TE_RIGHT,
    TE_HOME, TE_END, TE_DELETE, TE_INSERT, TE_PGUP, TE_PGDN,
    TE_ESCAPE, TE_RESIZE, TE_CURSOR_REPORT, TE_DEVICE_REPORT
};
enum {
    KEY_UP = 0x100, KEY_DOWN, KEY_RIGHT, KEY_LEFT,
    KEY_HOME, KEY_END, KEY_DELETE, KEY_PGUP, KEY_PGDN, KEY_INSERT
};
#define TF_ANSI  1
#define TF_CPR   2
#define TF_COLOR 4
#define TERM_ESC_TICKS    300000UL
#define TERM_PROBE_TICKS 2000000UL
#define TERM_Q 1024

typedef struct { I64 type, a, b; } CTermEvent;
typedef struct {
    int rows, cols, flags;
    int state, nparams, cur_param, got_digit, priv;
    I64 params[8];
    U64 esc_at;
} CTerm;
static CTerm term = { .rows = 24, .cols = 80, .flags = TF_ANSI, .state = TS_GROUND };

static CTermEvent term_keyq[TERM_Q], term_repq[TERM_Q];
static int tkh, tkt, trh, trt;

static int tq_count(int h, int t) { return (h - t + TERM_Q) % TERM_Q; }
static int tq_space(int h, int t) { return TERM_Q - 1 - tq_count(h, t); }

/* 0 = queued, -1 = queue full (caller must not drop the event source). */
static int tq_push(CTermEvent *q, int *h, int *t, CTermEvent e) {
    int n = (*h + 1) % TERM_Q;
    if (n == *t) return -1;
    q[*h] = e; *h = n;
    return 0;
}
static int tq_pop(CTermEvent *q, int *h, int *t, CTermEvent *out) {
    if (*h == *t) return 0;
    *out = q[*t]; *t = (*t + 1) % TERM_Q;
    return 1;
}
static U64 term_now(void) { U64 t; __asm__ volatile("rdtime %0" : "=r"(t)); return t; }

static int term_emit_key(I64 type, I64 a, I64 b) {
    CTermEvent e; e.type = type; e.a = a; e.b = b;
    return tq_push(term_keyq, &tkh, &tkt, e);
}
static int term_emit_reply(I64 type, I64 a, I64 b) {
    CTermEvent e; e.type = type; e.a = a; e.b = b;
    int r = tq_push(term_repq, &trh, &trt, e);
    if (r == 0 && type == TE_RESIZE && a >= 2 && a <= 255 && b >= 2 && b <= 512) {
        term.rows = (int)a; term.cols = (int)b; term.flags |= TF_CPR;
    }
    return r;
}

static void term_handle_csi(U8 final) {
    I64 *p = term.params; I64 n = term.nparams;
    switch (final) {
    case 'A': term_emit_key(TE_UP, 0, 0); break;
    case 'B': term_emit_key(TE_DOWN, 0, 0); break;
    case 'C': term_emit_key(TE_RIGHT, 0, 0); break;
    case 'D': term_emit_key(TE_LEFT, 0, 0); break;
    case 'H': term_emit_key(TE_HOME, 0, 0); break;
    case 'F': term_emit_key(TE_END, 0, 0); break;
    case 'R':
        if (n >= 2) term_emit_reply(TE_CURSOR_REPORT, p[0], p[1]);
        break;
    case 't':
        if (n >= 3 && p[0] == 8) term_emit_reply(TE_RESIZE, p[1], p[2]);
        break;
    case '~':
        switch (n ? p[0] : 0) {
        case 1: case 7: term_emit_key(TE_HOME, 0, 0); break;
        case 2: term_emit_key(TE_INSERT, 0, 0); break;
        case 3: term_emit_key(TE_DELETE, 0, 0); break;
        case 4: case 8: term_emit_key(TE_END, 0, 0); break;
        case 5: term_emit_key(TE_PGUP, 0, 0); break;
        case 6: term_emit_key(TE_PGDN, 0, 0); break;
        }
        break;
    default: break;
    }
}

/* Returns 0 if `ch` was consumed, -1 if blocked on a full queue (ch + any peek
 * must be re-fed; caller should stop polling until space frees). */
static int TermParseByte(U8 ch) {
    switch (term.state) {
    case TS_GROUND:
        if (ch == 27) {
            /* Peek: if the next byte is already queued, finish the sequence now so a
             * lone ESC in a TX-heavy editor never waits on a timeout while RX stalls.
             * Never drop the follower: if the key queue cannot take ESC+char, unget
             * both and ask the caller to wait (old code silently lost ':'). */
            U8 n;
            if (UartTryGet(&n)) {
                if (n == '[') {
                    term.state = TS_CSI; term.nparams = 0; term.cur_param = 0;
                    term.got_digit = 0; term.priv = 0; term.esc_at = term_now();
                    return 0;
                }
                if (n == 'O') { term.state = TS_SS3; term.esc_at = term_now(); return 0; }
                if (tq_space(tkh, tkt) < 2) {
                    UartUnget(n);
                    UartUnget(ch);
                    return -1;
                }
                term_emit_key(TE_ESCAPE, 27, 0);
                return TermParseByte(n);
            }
            term.state = TS_ESC; term.esc_at = term_now();
            return 0;
        }
        if (term_emit_key(TE_CHAR, ch, 0) < 0) {
            UartUnget(ch);
            return -1;
        }
        return 0;
    case TS_ESC:
        term.esc_at = term_now();
        if (ch == '[') {
            term.state = TS_CSI; term.nparams = 0; term.cur_param = 0;
            term.got_digit = 0; term.priv = 0; return 0;
        }
        if (ch == 'O') { term.state = TS_SS3; return 0; }
        if (tq_space(tkh, tkt) < 2) {
            UartUnget(ch);
            /* Stay in TS_ESC so a later poll retries with the follower still available. */
            return -1;
        }
        term.state = TS_GROUND;
        term_emit_key(TE_ESCAPE, 27, 0);
        return TermParseByte(ch);
    case TS_CSI:
        term.esc_at = term_now();
        if (ch >= '0' && ch <= '9') {
            term.cur_param = term.cur_param * 10 + (ch - '0'); term.got_digit = 1; return 0;
        }
        if (ch == ';') {
            if (term.nparams < 8) term.params[term.nparams++] = term.got_digit ? term.cur_param : 0;
            term.cur_param = 0; term.got_digit = 0; return 0;
        }
        if (ch == '?' || ch == '>') { term.priv = ch; return 0; }
        if (ch >= 0x20 && ch < 0x30) return 0;
        if (tq_space(tkh, tkt) < 1 || tq_space(trh, trt) < 1) {
            UartUnget(ch);
            return -1;
        }
        if (term.got_digit && term.nparams < 8) term.params[term.nparams++] = term.cur_param;
        term.state = TS_GROUND;
        term_handle_csi(ch);
        return 0;
    case TS_SS3:
        if (tq_space(tkh, tkt) < 2) {
            UartUnget(ch);
            return -1;
        }
        term.state = TS_GROUND;
        switch (ch) {
        case 'A': term_emit_key(TE_UP, 0, 0); break;
        case 'B': term_emit_key(TE_DOWN, 0, 0); break;
        case 'C': term_emit_key(TE_RIGHT, 0, 0); break;
        case 'D': term_emit_key(TE_LEFT, 0, 0); break;
        case 'H': term_emit_key(TE_HOME, 0, 0); break;
        case 'F': term_emit_key(TE_END, 0, 0); break;
        default: term_emit_key(TE_ESCAPE, 27, 0); return TermParseByte(ch);
        }
        return 0;
    }
    return 0;
}

static void TermCheckTimeouts(void) {
    if (term.state == TS_GROUND || !term.esc_at) return;
    if (term_now() - term.esc_at < TERM_ESC_TICKS) return;
    if (term.state == TS_ESC) {
        if (term_emit_key(TE_ESCAPE, 27, 0) < 0) return; /* try again when space frees */
    }
    term.state = TS_GROUND; term.esc_at = 0;
}

static HRT_I64 UartRxDrain(void) { uart_hw_drain(); return 0; }

static HRT_I64 TermPoll(void) {
    U8 ch;
    /* Always empty the HW FIFO into the ring first — even if the event queues
     * are full — so PutCh/redraw paths cannot drop piped input. */
    uart_hw_drain();
    /* Leave headroom: ESC peek may need two key slots in one parse. */
    while (tq_space(tkh, tkt) >= 2 && tq_space(trh, trt) >= 2) {
        if (!UartTryGet(&ch)) break;
        if (TermParseByte(ch) < 0) break; /* ungot; wait for queue drain */
    }
    TermCheckTimeouts();
    return 0;
}

static I64 term_map_key(CTermEvent *e) {
    switch (e->type) {
    case TE_CHAR:    return e->a;
    case TE_ESCAPE:  return 27;
    case TE_UP:      return KEY_UP;
    case TE_DOWN:    return KEY_DOWN;
    case TE_RIGHT:   return KEY_RIGHT;
    case TE_LEFT:    return KEY_LEFT;
    case TE_HOME:    return KEY_HOME;
    case TE_END:     return KEY_END;
    case TE_DELETE:  return KEY_DELETE;
    case TE_INSERT:  return KEY_INSERT;
    case TE_PGUP:    return KEY_PGUP;
    case TE_PGDN:    return KEY_PGDN;
    default:         return -1;
    }
}

static HRT_I64 TermKeyGet(void) {
    CTermEvent e;
    U8 ch;
    for (;;) {
        if (tq_pop(term_keyq, &tkh, &tkt, &e)) {
            I64 k = term_map_key(&e);
            if (k >= 0) return k;
            continue;
        }
        TermCheckTimeouts();
        /* One UART byte per iteration. Full TermPoll() would drain the ring into
         * keyq and prefetch the next piped REPL line (starving HolyC TermKeyGet
         * after readline returns). EdC/EditC/readline still share this path. */
        uart_hw_drain();
        if (!UartTryGet(&ch)) continue;
        if (TermParseByte(ch) < 0) continue; /* ungot; wait for keyq space */
    }
}
static char getc_uart(void) {
    U8 ch;
    if (!UartTryGet(&ch)) return 0;
    return (char)ch;
}
static HRT_I64 TermGetEvent(I64 p) {
    CTermEvent e;
    TermPoll();
    if (!tq_pop(term_keyq, &tkh, &tkt, &e)) return 0;
    if (p) { I64 *d = (I64 *)p; d[0] = e.type; d[1] = e.a; d[2] = e.b; }
    return 1;
}
static HRT_I64 TermGetReply(I64 p) {
    CTermEvent e;
    TermPoll();
    if (!tq_pop(term_repq, &trh, &trt, &e)) return 0;
    if (p) { I64 *d = (I64 *)p; d[0] = e.type; d[1] = e.a; d[2] = e.b; }
    return 1;
}

static HRT_I64 TermGoto(HRT_I64 row, HRT_I64 col) {
    if (!(term.flags & TF_ANSI)) return 0;
    UartPut(0x1b); UartPut('[');
    print_udec((U64)row); UartPut(';'); print_udec((U64)col); UartPut('H');
    return 0;
}
static HRT_I64 TermClear(void) {
    if (term.flags & TF_ANSI) puts_uart("\x1b[2J\x1b[H");
    return 0;
}
static HRT_I64 TermClearEol(void) {
    if (term.flags & TF_ANSI) puts_uart("\x1b[2K");
    return 0;
}
static HRT_I64 TermHideCursor(void) {
    if (term.flags & TF_ANSI) puts_uart("\x1b[?25l");
    return 0;
}
static HRT_I64 TermShowCursor(void) {
    if (term.flags & TF_ANSI) puts_uart("\x1b[?25h");
    return 0;
}
static HRT_I64 TermRows(void) { return term.rows; }
static HRT_I64 TermCols(void) { return term.cols; }
static HRT_I64 TermFlags(void) { return term.flags; }
static HRT_I64 TermSetSize(HRT_I64 rows, HRT_I64 cols) {
    if (rows >= 2 && rows <= 255) term.rows = (int)rows;
    if (cols >= 2 && cols <= 512) term.cols = (int)cols;
    term.flags &= ~TF_CPR;
    return 0;
}
static HRT_I64 TermProbe(void) {
    static int gave_up;
    CTermEvent e;
    U8 ch;
    /* Fresh editor session: abandon any half-parsed ESC/CSI left from a prior redraw. */
    term.state = TS_GROUND; term.esc_at = 0;
    uart_hw_drain();
    /* Do not TermPoll-drain the ring — that prefetches later piped REPL/editor lines
     * into C keyq and starves HolyC TermKeyGet (Vi after EditC). Peek only. */
    if (tkh != tkt) return (term.flags & TF_CPR) ? 1 : 0;
    /* Bytes waiting in the RX ring mean a pipe/script is feeding us — DSR will not
     * get a reply and the timeout only burns time while more input piles up. */
    if (uart_rh != uart_rt) { gave_up = 1; return 0; }
    if (gave_up || !(term.flags & TF_ANSI)) return 0;
    /* CPR via DSR (ESC[6n after corner push) + xterm window-size (ESC[18t). Host TTY
     * through QEMU -serial stdio/cocoa answers; piped smoke has no emulator and times out. */
    puts_uart("\x1b""7\x1b[999;999H\x1b[6n\x1b[18t");
    U64 t0 = term_now();
    while (term_now() - t0 < TERM_PROBE_TICKS) {
        uart_hw_drain();
        if (UartTryGet(&ch)) {
            if (TermParseByte(ch) < 0) { UartUnget(ch); break; }
        }
        TermCheckTimeouts();
        while (tq_pop(term_repq, &trh, &trt, &e)) {
            if (e.type == TE_CURSOR_REPORT && e.a >= 2 && e.a <= 255 && e.b >= 2 && e.b <= 512) {
                term.rows = (int)e.a; term.cols = (int)e.b; term.flags |= TF_CPR;
            }
            if (e.type == TE_CURSOR_REPORT || e.type == TE_RESIZE) {
                puts_uart("\x1b""8");
                return (term.flags & TF_CPR) ? 1 : 0;
            }
        }
        /* Keystroke (not a probe reply) — abort; leave it queued for TermKeyGet. */
        if (tkh != tkt) {
            puts_uart("\x1b""8");
            return (term.flags & TF_CPR) ? 1 : 0;
        }
    }
    puts_uart("\x1b""8");
    if (!(term.flags & TF_CPR)) gave_up = 1;  /* piped UART: don't pay the timeout again */
    return (term.flags & TF_CPR) ? 1 : 0;
}

static HRT_I64 GetCh(void) {
    CTermEvent e;
    TermPoll();
    if (!tq_pop(term_keyq, &tkh, &tkt, &e)) return 0;
    I64 k = term_map_key(&e);
    return k >= 0 ? k : 0;
}
static HRT_I64 PutCh(HRT_I64 ch) { UartPut((U8)ch); return 0; }
static int  ed_line_len(int i) { int n = 0; while (ed_lines[i][n]) n++; return n; }

static int term_text_rows(void) {
    int n = term.rows - 2;
    return n < 1 ? 1 : n;
}
static void edit_render(const char *name, int top, int cx, int cy, const char *msg) {
    int text_rows = term_text_rows(), cols = term.cols;
    TermHideCursor();
    if (term.flags & TF_ANSI) puts_uart("\x1b[H");
    for (int r = 0; r < text_rows; r++) {
        TermGoto(r + 1, 1); TermClearEol();
        int li = top + r;
        if (li < ed_n) { for (int j = 0; ed_lines[li][j] && j < cols; j++) UartPut((U8)ed_lines[li][j]); }
        else UartPut('~');
    }
    TermGoto(term.rows - 1, 1);
    if (term.flags & TF_ANSI) puts_uart("\x1b[7m");
    TermClearEol(); UartPut(' ');
    puts_uart(name);
    puts_uart("  ln "); print_udec(cy + 1); UartPut('/'); print_udec(ed_n);
    puts_uart("  col "); print_udec(cx + 1);
    puts_uart("   ^O save  ^X exit");
    if (term.flags & TF_ANSI) puts_uart("\x1b[0m");
    TermGoto(term.rows, 1); TermClearEol(); if (msg && msg[0]) puts_uart(msg);
    TermGoto(cy - top + 1, cx + 1);
    TermShowCursor();
}
static int edit_save(MemFile *f, const char *name, char *msgbuf) {  // returns bytes written
    int off = 0;
    for (int k = 0; k < ed_n; k++) {
        int j = 0;
        while (ed_lines[k][j] && off < MEMFS_FILE_CAP - 1) f->data[off++] = ed_lines[k][j++];
        if (off < MEMFS_FILE_CAP - 1) f->data[off++] = '\n';
    }
    f->data[off] = 0; f->len = off;
    memfs_format_inplace(f, name);
    off = f->len;
    if (HolyFmtIsHcName(name)) {
        ed_n = 0;
        { int i = 0; while (i < f->len && ed_n < ED_MAX_LINES) {
            int j = 0;
            while (i < f->len && f->data[i] != '\n' && j < ED_LINE_CAP - 1)
                ed_lines[ed_n][j++] = f->data[i++];
            ed_lines[ed_n][j] = 0;
            while (i < f->len && f->data[i] != '\n') i++;
            if (i < f->len && f->data[i] == '\n') i++;
            ed_n++;
        } }
        if (ed_n < 1) { ed_lines[0][0] = 0; ed_n = 1; }
    }
    // msgbuf: "wrote <name> (<off> bytes)"
    char *p = msgbuf; const char *s = "wrote "; while (*s) *p++ = *s++;
    while (*name) *p++ = *name++;
    *p++ = ' '; *p++ = '(';
    char num[16]; int ni = 0, v = off; if (v == 0) num[ni++] = '0';
    while (v) { num[ni++] = '0' + v % 10; v /= 10; }
    while (ni) *p++ = num[--ni];
    s = " bytes)"; while (*s) *p++ = *s++; *p = 0;
    return off;
}
static HRT_I64 Edit(char *name) {   // EditC: viewport from Term, keys from TermKeyGet
    MemFile *f = memfs_create(name);
    if (!f) { puts_uart("Edit: fs full\n"); return -1; }
    // load the file into ed_lines, splitting on '\n'
    ed_n = 0;
    { int i = 0; while (i < f->len && ed_n < ED_MAX_LINES) {
        int j = 0;
        while (i < f->len && f->data[i] != '\n' && j < ED_LINE_CAP - 1) ed_lines[ed_n][j++] = f->data[i++];
        ed_lines[ed_n][j] = 0;
        while (i < f->len && f->data[i] != '\n') i++;
        if (i < f->len && f->data[i] == '\n') i++;
        ed_n++;
    } }
    if (ed_n == 0) { ed_lines[0][0] = 0; ed_n = 1; }   // always at least one line to edit
    int top = 0, cx = 0, cy = 0, dirty = 0;
    char msgbuf[64]; const char *msg = "";
    TermProbe();
    TermClear();
    edit_render(name, top, cx, cy, msg);
    while (1) {
        I64 k = TermKeyGet();
        int text_rows = term_text_rows();
        int len = ed_line_len(cy);
        msg = "";
        switch (k) {
        case KEY_UP:
            if (cy > 0) { cy--; if (cx > ed_line_len(cy)) cx = ed_line_len(cy); }
            break;
        case KEY_DOWN:
            if (cy < ed_n - 1) { cy++; if (cx > ed_line_len(cy)) cx = ed_line_len(cy); }
            break;
        case KEY_RIGHT:
            if (cx < len) cx++; else if (cy < ed_n - 1) { cy++; cx = 0; }
            break;
        case KEY_LEFT:
            if (cx > 0) cx--; else if (cy > 0) { cy--; cx = ed_line_len(cy); }
            break;
        case KEY_HOME: cx = 0; break;
        case KEY_END:  cx = len; break;
        case KEY_PGUP:
            cy -= text_rows; if (cy < 0) cy = 0;
            if (cx > ed_line_len(cy)) cx = ed_line_len(cy);
            break;
        case KEY_PGDN:
            cy += text_rows; if (cy > ed_n - 1) cy = ed_n - 1;
            if (cx > ed_line_len(cy)) cx = ed_line_len(cy);
            break;
        case KEY_DELETE:
            if (cx < len) { for (int j = cx; ed_lines[cy][j]; j++) ed_lines[cy][j] = ed_lines[cy][j + 1]; dirty = 1; }
            break;
        case 24:   /* ^X exit */
            if (dirty) { msg = "modified -- ^O to save, or ^X again to discard"; dirty = 0;
                         edit_render(name, top, cx, cy, msg); continue; }
            goto edit_done;
        case 15:   /* ^O save */
            edit_save(f, name, msgbuf); msg = msgbuf; dirty = 0;
            break;
        case '\r': case '\n':
            if (ed_n < ED_MAX_LINES) {
                ed_insert_at(cy + 1, &ed_lines[cy][cx]);
                ed_lines[cy][cx] = 0; cy++; cx = 0; dirty = 1;
            }
            break;
        case 127: case 8:
            if (cx > 0) {
                for (int j = cx - 1; ed_lines[cy][j]; j++) ed_lines[cy][j] = ed_lines[cy][j + 1];
                cx--; dirty = 1;
            } else if (cy > 0) {
                int pl = ed_line_len(cy - 1), j = 0;
                while (ed_lines[cy][j] && pl + j < ED_LINE_CAP - 1) { ed_lines[cy - 1][pl + j] = ed_lines[cy][j]; j++; }
                ed_lines[cy - 1][pl + j] = 0;
                ed_delete_range(cy + 1, cy + 1);
                cy--; cx = pl; dirty = 1;
            }
            break;
        default:
            if ((k == '\t' || k == 9)) {
                /* Mid-token → case-insensitive complete; else 2-space indent */
                if (cx > 0 && rl_pathchar((unsigned char)ed_lines[cy][cx - 1])) {
                    int elen = len, ecur = cx;
                    if (rl_complete_core(ed_lines[cy], ED_LINE_CAP, &elen, &ecur, 0)) {
                        len = elen; cx = ecur; dirty = 1;
                    }
                } else if (len + 2 < ED_LINE_CAP) {
                    for (int t = 0; t < 2; t++) {
                        for (int j = len; j >= cx; j--) ed_lines[cy][j + 1] = ed_lines[cy][j];
                        ed_lines[cy][cx] = ' '; cx++; len++;
                    }
                    dirty = 1;
                }
            } else if (k >= 32 && k < 127 && len < ED_LINE_CAP - 1) {
                for (int j = len; j >= cx; j--) ed_lines[cy][j + 1] = ed_lines[cy][j];
                ed_lines[cy][cx] = (char)k; cx++; dirty = 1;
            }
            break;
        }
        if (cy < top) top = cy;
        if (cy >= top + text_rows) top = cy - text_rows + 1;
        edit_render(name, top, cx, cy, msg);
    }
edit_done:
    TermClear();
    return 0;
}
// ---- Shared compile+run path (typed statements AND Run("file")) --------------------------
// The single compiler instance, reused across statements and files so definitions accumulate
// (functions keep their exe_addr, the hash table persists). Promoted to a global so Run() and
// the trap dispatcher -- both reached from JIT'd code -- can see it.
static Compiler *g_cc = 0;

// ---- Per-function source map: TempleOS keeps a source link on every symbol so you can bring
// its definition up in the editor. We do the same -- as each function is compiled, its defining
// source unit is stashed here by name, and Src("Name") brings it back up in Edit and recompiles.
#define SRCMAP_MAX 1024  /* seed HolyC alone defines ~250+ funs; keep headroom for live edits */
static char g_run_file[64];   // set while Run("file") compiles, so srcmap remembers the origin file
static char g_err_file[64];
static I64 g_err_line, g_err_col;
static I64 g_err_have; /* published via HC_SLOT_ERR_*; HolyC ErrGo reads these */

static struct { int used; char name[32]; char file[64]; char *src; } srcmap[SRCMAP_MAX];
static void srcmap_put(const char *name, const char *src) {
    int slot = -1;
    for (int i = 0; i < SRCMAP_MAX; i++) if (srcmap[i].used && !strcmp(srcmap[i].name, name)) { slot = i; break; }
    if (slot < 0) for (int i = 0; i < SRCMAP_MAX; i++) if (!srcmap[i].used) { slot = i; break; }
    if (slot < 0) return;   // table full: leave earlier entries intact
    // Store the whole source, whatever its size -- no fixed cap. free() is a no-op, so a redefine
    // simply allocates a fresh copy (the old one is abandoned on the 12MB heap).
    size_t n = strlen(src);
    char *buf = (char *)malloc(n + 1);
    if (!buf) return;
    for (size_t i = 0; i <= n; i++) buf[i] = src[i];
    srcmap[slot].used = 1;
    srcmap[slot].src = buf;
    int j = 0; while (name[j] && j < 31) { srcmap[slot].name[j] = name[j]; j++; } srcmap[slot].name[j] = 0;
    srcmap[slot].file[0] = 0;
    if (g_run_file[0]) {
        j = 0; while (g_run_file[j] && j < 63) { srcmap[slot].file[j] = g_run_file[j]; j++; }
        srcmap[slot].file[j] = 0;
    }
}
static const char *srcmap_get(const char *name) {
    for (int i = 0; i < SRCMAP_MAX; i++) if (srcmap[i].used && !strcmp(srcmap[i].name, name)) return srcmap[i].src;
    return 0;
}
static void name_dot_hc(const char *name, char *fn) {
    int j = 0; while (name[j] && j < 31) { fn[j] = name[j]; j++; }
    fn[j] = '.'; fn[j+1] = 'h'; fn[j+2] = 'c'; fn[j+3] = 0;
}

/* Stash symbol into HolyC JumpIdent[] so Vi/EditHoly seek+center on open (Src / gd). */
static void src_jump_set(const char *name) {
    CHashGlblVar *ji = g_cc ? (CHashGlblVar *)HashFind("JumpIdent", g_cc->hash_table, HTT_GLBL_VAR) : 0;
    if (!ji || !ji->data_addr) return;
    char *buf = (char *)ji->data_addr;
    if (!name || !name[0]) { buf[0] = 0; return; }
    int i = 0;
    while (name[i] && i < 63) { buf[i] = name[i]; i++; }
    buf[i] = 0;
}

static const char *srcmap_file_of(const char *name) {
    for (int i = 0; i < SRCMAP_MAX; i++)
        if (srcmap[i].used && !strcmp(srcmap[i].name, name) && srcmap[i].file[0]) {
            MemFile *f = memfs_find(srcmap[i].file);
            if (f) return f->name;
        }
    return 0;
}

// Seed comment files may hold optional `// Name --` Man blocks when there is no HolyC
// srcmap entry. c_api.hc / rt.hc are intentionally empty of those (no orphan callable claims).
static int doc_ident_char(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
           (c >= '0' && c <= '9') || c == '_';
}
static char *doc_find_in(char *text, const char *name) {
    if (!text || !name || !name[0]) return 0;
    int nlen = 0; while (name[nlen]) nlen++;
    char *p = text;
    while (*p) {
        if (p[0] == '/' && p[1] == '/' && p[2] == ' ') {
            int k = 0;
            while (k < nlen) {
                char a = p[3 + k], b = name[k];
                if (a >= 'A' && a <= 'Z') a = (char)(a + 32);
                if (b >= 'A' && b <= 'Z') b = (char)(b + 32);
                if (a != b) break;
                k++;
            }
            /* Prefer `// Name --` anchors (Man topics); also accept Name followed by non-ident. */
            if (k == nlen && p[3 + nlen] == ' ' && p[4 + nlen] == '-' && p[5 + nlen] == '-')
                return p;
            if (k == nlen && !doc_ident_char(p[3 + nlen]))
                return p;
        }
        while (*p && *p != '\n') p++;
        if (*p == '\n') p++;
    }
    return 0;
}
static const char *DOC_FILES[] = { "man_topics.hc", 0 }; /* hardware/symbol Man topics */
static char *doc_text_for(const char *name) {
    for (int i = 0; DOC_FILES[i]; i++) {
        MemFile *f = memfs_find(DOC_FILES[i]);
        if (!f) continue;
        f->data[f->len] = 0;
        char *p = doc_find_in(f->data, name);
        if (p) return p;
    }
    return 0;
}
static const char *doc_file_for(const char *name) {
    for (int i = 0; DOC_FILES[i]; i++) {
        MemFile *f = memfs_find(DOC_FILES[i]);
        if (!f) continue;
        f->data[f->len] = 0;
        if (doc_find_in(f->data, name)) return DOC_FILES[i];
    }
    return 0;
}

// Compile one source buffer as top-level HolyC and run any trailing statement. echo=1 prints
// the TempleOS-style "<time>s ans=..." line (the REPL prompt); echo=0 is silent (Run/scripts).
// Safe to call re-entrantly from a registered C function: cc->lex is re-seeded on every call,
// free() is a no-op here, and definitions only append to code_mem / the hash table.
// start_line: 1-based absolute line in the originating file (jumpable diagnostics).
static void repl_eval(const char *src, int echo, int start_line) {
    Compiler *cc = g_cc;
    if (!cc) return;
    if (cc->lex.src) free(cc->lex.src);
    cc->lex.src = strdup(src);
    cc->lex.ptr = cc->lex.src;
    if (g_run_file[0]) {
        if (cc->lex.filename) free(cc->lex.filename);
        cc->lex.filename = strdup(g_run_file);
    } else {
        if (cc->lex.filename) free(cc->lex.filename);
        cc->lex.filename = strdup("repl");
    }
    cc->lex.line = start_line > 0 ? start_line : 1;
    cc->lex.col = 1; cc->lex.hash_entry = NULL;
    cc->ic_head = NULL; cc->ic_tail = NULL; cc->labels = NULL;
    cc->label_counter = 0; cc->locals_size = 0;
    extern void LexNext(Compiler *cc);
    extern Bool ParseTopLevel(Compiler *cc);
    LexNext(cc);
    Bool ok = true;
    while (ok && cc->lex.token != TK_EOF) {
        CHashFun *fn_before = cc->last_compiled_func;
        ok = ParseTopLevel(cc);
        // A newly-compiled function: remember the source unit that defined it, so Src() can
        // bring it back up. (run_source feeds one unit per function, so this is that function.)
        // Asm{} secondary `::` exports (TrapCtxSave, …) share the same unit via asm_extra_exports.
        if (ok && cc->last_compiled_func && cc->last_compiled_func != fn_before && cc->last_compiled_func->str) {
            srcmap_put(cc->last_compiled_func->str, src);
            for (int ei = 0; ei < cc->asm_extra_export_n; ei++)
                srcmap_put(cc->asm_extra_exports[ei], src);
            cc->asm_extra_export_n = 0;
        }
    }
    U8 ans_ty = cc->last_expr_type;
    __asm__ volatile("fence.i" ::: "memory");   // definitions are fresh code: order the I-side
    if (!ok) {
        const char *efile = cc->error_file ? cc->error_file : (g_run_file[0] ? g_run_file : "repl");
        I64 eline = cc->error ? cc->error_line : cc->lex.line;
        I64 ecol = cc->error ? cc->error_col : cc->lex.col;
        if (ecol < 1) ecol = 1;
        /* jumpable: file:line:col: error: message  (ErrGo; opens last site) */
        puts_uart(efile); putc_uart(':'); print_dec(eline); putc_uart(':'); print_dec(ecol);
        puts_uart(": error: "); puts_uart(cc->error ? cc->error : "parse error");
        if (cc->lex.token_str && cc->lex.token_str[0]) {
            puts_uart(" near '"); puts_uart(cc->lex.token_str); puts_uart("'");
        }
        puts_uart("\n");
        {
            int j = 0;
            while (efile[j] && j < 63) { g_err_file[j] = efile[j]; j++; }
            g_err_file[j] = 0;
            g_err_line = eline;
            g_err_col = ecol;
            g_err_have = 1;
        }
        cc->error = NULL; cc->ic_head = NULL; cc->ic_tail = NULL; return;
    }
    if (cc->ic_head) {
        extern void WrapStatementsAsFrame(Compiler *cc);
        extern U8 *CompileAOT(Compiler *cc, I64 *size_out);
        WrapStatementsAsFrame(cc);
        I64 code_size = 0;
        U8 *machine_code = CompileAOT(cc, &code_size);
        cc->ic_head = NULL; cc->ic_tail = NULL;
        if (!machine_code || code_size <= 0) { if (echo) puts_uart("[COMPILE FAILED]\n"); return; }
        __asm__ volatile("fence.i" ::: "memory");
        typedef I64 (*FuncPtr)();
        FuncPtr func_ptr = (FuncPtr)machine_code;
        U64 t0, t1;
        int armed = 0;
        /* Arm Ctrl-C only after interactive boot (not while seeding via Run). */
        if (g_break_interactive) {
            g_break_pending = 0;
            uart_hw_drain();
            uart_ring_take_leading_break();
            g_break_armed = 1;
            armed = 1;
            /* Soft timer poll: wake trapvec periodically to drain UART. */
            {
                volatile U64 *mtime = (volatile U64 *)MEM_MTIME_ADDR;
                volatile U64 *mtimecmp = (volatile U64 *)MEM_MTIMECMP_ADDR;
                *mtimecmp = *mtime + 100000;
                __asm__ volatile("csrs mie, %0" :: "r"((I64)(1 << 7))); /* MTIE */
            }
            /* Ctrl-C already in the RX ring (common with piped scripts): abort
             * before entering JIT. Catchable mid-loop still works via UART/timer
             * IRQ once the statement is running; use Break; to throw('Break'). */
            if (g_break_pending) {
                g_break_armed = 0;
                g_break_pending = 0;
                *(volatile U64 *)MEM_MTIMECMP_ADDR = ~(U64)0;
                puts_uart("\nInterrupted\n");
                free(machine_code);
                return;
            }
        }
        __asm__ volatile("rdtime %0" : "=r"(t0));
        I64 result = func_ptr();
        __asm__ volatile("rdtime %0" : "=r"(t1));
        if (armed) {
            g_break_armed = 0;
            g_break_pending = 0;
            /* Park poll timer so it does not storm between statements. */
            *(volatile U64 *)MEM_MTIMECMP_ADDR = ~(U64)0;
        }
        g_answer = result;
        if (echo) {
            print_time(t1 - t0);
            if (ans_ty == RT_I0)      puts_uart("\n");
            else if (ans_ty == RT_F64){ puts_uart(" ansf="); print_f64((U64)result); puts_uart("\n"); }
            else { puts_uart(" ans="); print_hex(result); putc_uart('='); print_dec(result); puts_uart("\n"); }
        }
        free(machine_code);
    }
}
// Feed a source string through the SAME incremental boundaries the REPL uses for typed input:
// accumulate lines until braces/parens balance and the unit ends in ';' or '}', then compile
// and run that unit before parsing the next. Because each top-level unit runs before the next
// compiles (and top-level declarations are globals that persist), a file can define something
// -- or Run() another file -- on one line and use it on the next. echo=0 (silent, for scripts).
static void run_source(const char *src) {
    static char acc[65536];
    int acc_len = 0, brace = 0, paren = 0;
    const char *p = src;
    char line[512];
    int file_line = 1, unit_start_line = 1;
    while (*p) {
        int n = 0;
        while (*p && *p != '\n' && n < 511) line[n++] = *p++;
        if (*p == '\n') p++;
        line[n] = 0;
        int s = 0; while (s < n && (line[s] == ' ' || line[s] == '\t')) s++;
        int is_dir = (s + 1 < n && line[s] == '#' &&
                      ((line[s+1] >= 'a' && line[s+1] <= 'z') || (line[s+1] >= 'A' && line[s+1] <= 'Z')));
        if (s < n && line[s] == '#' && !is_dir) { file_line++; continue; }   // whole-line '#' comment
        // Whole-line // comments are not statement terminators. Man SYNOPSIS lines look like
        // `//   U0 Dir();` and must not end a run_source unit (or SrcText/Man lose NAME/SYNOPSIS).
        int is_line_slash_comment = (s + 1 < n && line[s] == '/' && line[s+1] == '/');
        /* Boot blob section markers: `// ##### BEGIN uart.hc #####` → SrcFile names. */
        if (is_line_slash_comment && n >= 16) {
            const char *mk = "##### BEGIN ";
            int mi = s + 2;
            while (mi < n && (line[mi] == ' ' || line[mi] == '\t')) mi++;
            int okm = 1;
            for (int k = 0; mk[k]; k++) if (mi + k >= n || line[mi + k] != mk[k]) { okm = 0; break; }
            if (okm) {
                int a = mi + 12, b = a, j = 0;
                while (b < n && line[b] != ' ' && line[b] != '#' && line[b] != '\t') b++;
                while (a < b && j < 63) { g_run_file[j++] = line[a++]; }
                g_run_file[j] = 0;
                file_line = 0; /* next line is line 1 of this seed */
            }
        }
        if (acc_len + n + 2 >= (int)sizeof(acc)) { acc_len = 0; brace = 0; paren = 0; file_line++; continue; }
        if (acc_len == 0) unit_start_line = file_line;
        for (int i = 0; i < n; i++) acc[acc_len++] = line[i];
        acc[acc_len++] = '\n'; acc[acc_len] = 0;
        if (is_line_slash_comment) { file_line++; continue; }
        for (int i = 0; i < n; i++) {
            char c = line[i];
            // Skip string / character literals so `'('` in DefAt etc. does not skew paren depth.
            if (c == '"' || c == '\'') {
                char q = c;
                i++;
                while (i < n && line[i] != q) {
                    if (line[i] == '\\' && i + 1 < n) i++;
                    i++;
                }
                continue;
            }
            if (c == '{') brace++; else if (c == '}') { if (brace > 0) brace--; }
            else if (c == '(') paren++; else if (c == ')') { if (paren > 0) paren--; }
        }
        int go = 0;
        if (brace == 0 && paren == 0) {
            if (n > 0 && line[n-1] == ';') go = 1;
            if (n > 0 && line[n-1] == '}') go = 1;
        }
        if (is_dir && brace == 0 && paren == 0) go = 1;
        file_line++;
        if (!go) continue;
        repl_eval(acc, 0, unit_start_line);
        acc_len = 0; brace = 0; paren = 0;
    }
    if (acc_len > 0) repl_eval(acc, 0, unit_start_line);   // flush any unterminated tail
}
// Run("name") -- compile and execute an in-memory file, unit by unit (see run_source). Closes
// the self-hosting loop: edit a file with Ed/Edit, then Run it.
static HRT_I64 Run(char *name) {
    MemFile *f = memfs_find(name);
    if (!f) { puts_uart("Run: no such file: "); puts_uart(name); puts_uart("\n"); return -1; }
    char saved[64];
    int j = 0; while (g_run_file[j] && j < 63) { saved[j] = g_run_file[j]; j++; } saved[j] = 0;
    j = 0; while (f->name[j] && j < 63) { g_run_file[j] = f->name[j]; j++; } g_run_file[j] = 0;
    f->data[f->len] = 0;
    run_source(f->data);
    j = 0; while (saved[j] && j < 63) { g_run_file[j] = saved[j]; j++; } g_run_file[j] = 0;
    return 0;
}
// Call through the HolyC `editor` global (Kconfig / RVEditorSelected.hc sets editor=&Vi by
// default). Falls back to HolyC Vi, then C Edit, if the variable is missing or null.
static void call_editor(char *name) {
    CHashGlblVar *ed = g_cc ? (CHashGlblVar *)HashFind("editor", g_cc->hash_table, HTT_GLBL_VAR) : 0;
    if (ed && ed->data_addr) {
        void (*fn)(char *) = *(void (**)(char *))ed->data_addr;
        if (fn) { fn(name); return; }
    }
    { CHashFun *vi = g_cc ? (CHashFun *)HashFind("Vi", g_cc->hash_table, HTT_FUN) : 0;
      if (vi && vi->exe_addr) { ((void (*)(char *))vi->exe_addr)(name); return; } }
    Edit(name);
}
// Src("Name") -- bring up a HolyC function's source in the preferred editor (TempleOS
// goto-definition). Prefer originating seed file + JumpIdent seek; fall back to Name.hc.
static HRT_I64 Src(char *name) {
    if (!name || !name[0]) { puts_uart("Src: no source\n"); return -1; }
    src_jump_set(0);
    const char *ofile = srcmap_file_of(name);
    if (ofile) {
        src_jump_set(name);
        call_editor((char *)ofile);
        return 0;  /* view+seek only — do not Run whole seed */
    }
    const char *s = srcmap_get(name);
    if (s) {
        char fn[36];
        name_dot_hc(name, fn);
        MemFile *f = memfs_create(fn);
        if (!f) { puts_uart("Src: fs full\n"); return -1; }
        int n = 0; while (s[n] && n < MEMFS_FILE_CAP - 1) { f->data[n] = s[n]; n++; }
        f->data[n] = 0; f->len = n;
        src_jump_set(name);
        call_editor(fn); Run(fn);
        return 0;
    }
    MemFile *f = memfs_find(name);
    if (!f) {
        char fn[36];
        name_dot_hc(name, fn);
        f = memfs_find(fn);
    }
    if (f) { call_editor(f->name); return 0; }
    { const char *df = doc_file_for(name);
      if (df) { src_jump_set(name); call_editor((char *)df); return 0; } }
    { CHashFun *fn = g_cc ? (CHashFun *)HashFind(name, g_cc->hash_table, HTT_FUN) : 0;
      CHashFun *dis = g_cc ? (CHashFun *)HashFind("DisasmAt", g_cc->hash_table, HTT_FUN) : 0;
      if (fn && fn->exe_addr && dis && dis->exe_addr) {
          puts_uart("Src: no source for "); puts_uart(name); puts_uart(" -- disassembling:\n");
          ((void (*)(HRT_I64, HRT_I64, HRT_I64))dis->exe_addr)((HRT_I64)fn->exe_addr, 2000, 0);
          return 0; } }
    puts_uart("Src: no source for "); puts_uart(name);
    puts_uart(" (not a HolyC function or a file)\n");
    return -1;
}
// SrcFile("Name") -- filename to open for a function (the originating Run() file, or Name.hc
// materialized from the remembered unit). Editors jump in-place with this; Src() still nests
// Edit+Run for the command-line "bring it up and recompile" path.
static char srcfile_buf[64];
static HRT_I64 SrcFile(char *name) {
    if (!name || !name[0]) return 0;
    for (int i = 0; i < SRCMAP_MAX; i++) if (srcmap[i].used && !strcmp(srcmap[i].name, name)) {
        if (srcmap[i].file[0]) {
            MemFile *f = memfs_find(srcmap[i].file);
            if (f) {
                int j = 0; while (f->name[j] && j < 63) { srcfile_buf[j] = f->name[j]; j++; }
                srcfile_buf[j] = 0;
                return (HRT_I64)srcfile_buf;
            }
        }
        if (srcmap[i].src) {
            char fn[36];
            name_dot_hc(name, fn);
            MemFile *f = memfs_create(fn);
            if (!f) { puts_uart("SrcFile: fs full\n"); return 0; }
            const char *s = srcmap[i].src;
            int n = 0; while (s[n] && n < MEMFS_FILE_CAP - 1) { f->data[n] = s[n]; n++; }
            f->data[n] = 0; f->len = n;
            int j = 0; while (f->name[j] && j < 63) { srcfile_buf[j] = f->name[j]; j++; }
            srcfile_buf[j] = 0;
            return (HRT_I64)srcfile_buf;
        }
        break;
    }
    MemFile *f = memfs_find(name);
    if (!f) {
        char fn[36];
        name_dot_hc(name, fn);
        f = memfs_find(fn);
    }
    if (f) {
        int j = 0; while (f->name[j] && j < 63) { srcfile_buf[j] = f->name[j]; j++; }
        srcfile_buf[j] = 0;
        return (HRT_I64)srcfile_buf;
    }
    { const char *df = doc_file_for(name);
      if (df) {
          int j = 0; while (df[j] && j < 63) { srcfile_buf[j] = df[j]; j++; }
          srcfile_buf[j] = 0;
          return (HRT_I64)srcfile_buf;
      } }
    puts_uart("SrcFile: no source for "); puts_uart(name); puts_uart("\n");
    return 0;
}
// Manual sections (Unix man-like, adapted to this REPL). Seed files and known C builtins map
// into a small taxonomy; FunsS groups the symbol table by section, FunsSec filters one.
//   1 shell/cmds   2 files/FS   3 terminal   4 editor   5 debug/runtime   9 internal
static const char *fun_sec_title(int sec) {
    switch (sec) {
    case 1: return "shell/cmds";
    case 2: return "files/FS";
    case 3: return "terminal";
    case 4: return "editor";
    case 5: return "debug/runtime";
    case 9: return "internal";
    default: return "?";
    }
}
static int fun_name_eq(const char *n, const char *p) {
    if (!n || !p) return 0;
    while (*n && *n == *p) { n++; p++; }
    return !*n && !*p;
}
static int fun_name_pfx(const char *n, const char *p) {
    if (!n || !p) return 0;
    while (*p) { if (*n++ != *p++) return 0; }
    return 1;
}
static int fun_sec_from_file(const char *file) {
    const char *b = file;
    for (const char *p = file; *p; p++) if (*p == '/') b = p + 1;
    if (fun_name_eq(b, "man.hc") || fun_name_eq(b, "boot.hc") || fun_name_eq(b, "funs.hc") ||
        fun_name_eq(b, "callers.hc"))
        return 1;
    if (fun_name_eq(b, "dir.hc") || fun_name_eq(b, "files.hc")) return 2;
    if (fun_name_eq(b, "uart.hc") || fun_name_eq(b, "term.hc") || fun_name_eq(b, "str.hc") ||
        fun_name_eq(b, "print.hc"))
        return 3;
    if (fun_name_eq(b, "ed.hc") || fun_name_eq(b, "edit.hc") || fun_name_eq(b, "vim.hc")) return 4;
    if (fun_name_eq(b, "debug.hc") || fun_name_eq(b, "disasm.hc") ||
        fun_name_eq(b, "start.hc") || fun_name_eq(b, "trap.hc") || fun_name_eq(b, "timer.hc") ||
        fun_name_eq(b, "csr.hc") || fun_name_eq(b, "MemMapSelected.hc") ||
        fun_name_eq(b, "man_topics.hc") ||
        fun_name_eq(b, "ds.hc") || fun_name_pfx(b, "ds_"))
        return 5;
    if (fun_name_eq(b, "mem.hc")) return 9;
    return 0;   // unknown .hc -- caller treats as user shell (1)
}
static int fun_sec_from_name(const char *name) {
    // 1 shell/cmds
    if (fun_name_eq(name, "Funs") || fun_name_eq(name, "FunsS") || fun_name_eq(name, "FunsSec") ||
        fun_name_eq(name, "FunSec") || fun_name_eq(name, "FunSecName") || fun_name_eq(name, "Man") ||
        fun_name_eq(name, "Sections") || fun_name_eq(name, "Run") || fun_name_eq(name, "Src") ||
        fun_name_eq(name, "SrcFile") || fun_name_eq(name, "SrcText") || fun_name_eq(name, "Exec") ||
        fun_name_eq(name, "Reset") || fun_name_eq(name, "MemMap") || fun_name_eq(name, "Regs") ||
        fun_name_eq(name, "FunCount") || fun_name_eq(name, "FunName") || fun_name_eq(name, "FunHasSrc") ||
        fun_name_eq(name, "FunPick") || fun_name_eq(name, "FunEd") || fun_name_eq(name, "FunWrite") ||
        fun_name_eq(name, "Callers") || fun_name_eq(name, "WhoCalls") || fun_name_eq(name, "CallersGo") ||
        fun_name_eq(name, "CallersScan") || fun_name_eq(name, "CallerCnt") || fun_name_eq(name, "CallerName"))
        return 1;
    // 2 files/FS
    if (fun_name_eq(name, "Dir") || fun_name_eq(name, "Ls") || fun_name_eq(name, "Cat") ||
        fun_name_eq(name, "Del") || fun_name_eq(name, "Cd") || fun_name_eq(name, "Pwd") ||
        fun_name_eq(name, "DirMk") || fun_name_eq(name, "DirDel") || fun_name_eq(name, "IsDir") ||
        fun_name_eq(name, "CwdStr") || fun_name_pfx(name, "File") || fun_name_eq(name, "Copy") ||
        fun_name_eq(name, "Move") || fun_name_eq(name, "Rename") || fun_name_eq(name, "Find") ||
        fun_name_eq(name, "FindIn") || fun_name_eq(name, "FilesFind") || fun_name_eq(name, "FileFind") ||
        fun_name_eq(name, "Activate") || fun_name_eq(name, "DirEd") || fun_name_eq(name, "DirWrite") ||
        fun_name_eq(name, "WildMatch") || fun_name_eq(name, "ToAbs") || fun_name_eq(name, "InCwd"))
        return 2;
    // 3 terminal
    if (fun_name_eq(name, "GetCh") || fun_name_eq(name, "PutCh") || fun_name_pfx(name, "Term") ||
        fun_name_pfx(name, "Uart"))
        return 3;
    // 4 editor
    if (fun_name_eq(name, "Ed") || fun_name_eq(name, "Edit") || fun_name_eq(name, "EdC") ||
        fun_name_eq(name, "EditC") || fun_name_eq(name, "Vi") || fun_name_eq(name, "editor"))
        return 4;
    // 5 debug/runtime
    if (fun_name_pfx(name, "Disasm") || fun_name_eq(name, "Bp") || fun_name_pfx(name, "Dbg") ||
        fun_name_eq(name, "StkRep") || fun_name_eq(name, "FnAddr") || fun_name_eq(name, "FnSize") ||
        fun_name_eq(name, "FunSegFind") || fun_name_pfx(name, "Sym") || fun_name_eq(name, "SetTrap") ||
        fun_name_pfx(name, "Trap") || fun_name_pfx(name, "Timer") || fun_name_eq(name, "Ecall") ||
        fun_name_eq(name, "OnTick") || fun_name_eq(name, "Boot") || fun_name_eq(name, "TrapVec") ||
        fun_name_eq(name, "Caller") || fun_name_eq(name, "Dr") || fun_name_eq(name, "Dm") ||
        fun_name_eq(name, "Da") || fun_name_eq(name, "Reg") || fun_name_eq(name, "RegHelp") ||
        fun_name_eq(name, "CpuRep") || fun_name_eq(name, "MemMapFind") ||
        fun_name_eq(name, "MemMapDrv") || fun_name_eq(name, "MemMapDrvFind") ||
        fun_name_pfx(name, "GetM") || fun_name_pfx(name, "SetM") ||
        fun_name_eq(name, "GetSatp") || fun_name_eq(name, "SetSatp") ||
        fun_name_eq(name, "GetSScratch") || fun_name_eq(name, "SetSScratch") ||
        fun_name_eq(name, "CSRGet") || fun_name_eq(name, "CSRSet") ||
        fun_name_eq(name, "GetRFlags") || fun_name_eq(name, "SetRFlags") ||
        fun_name_eq(name, "GetMTime") || fun_name_pfx(name, "Ds") ||
        fun_name_eq(name, "Bits") ||
        (name[0] == 'D' && !name[1]))
        return 5;
    return 9;   // holy_rt / RV* / everything else
}
static int fun_sec_of(const char *name) {
    const char *file = srcmap_file_of(name);
    if (file) {
        int s = fun_sec_from_file(file);
        return s ? s : 1;   // user .hc -> shell/cmds
    }
    if (srcmap_get(name)) return 1;   // REPL-defined HolyC, no originating file
    return fun_sec_from_name(name);
}
static HRT_I64 FunSec(char *name) { return name ? fun_sec_of(name) : 0; }
static char fun_sec_name_buf[24];
static HRT_I64 FunSecName(HRT_I64 sec) {
    const char *t = fun_sec_title((int)sec);
    int i = 0; while (t[i] && i < 23) { fun_sec_name_buf[i] = t[i]; i++; }
    fun_sec_name_buf[i] = 0;
    return (HRT_I64)fun_sec_name_buf;
}
// Fun enumeration -- shared by Funs() (print) and FunPick (HolyC interactive picker). Collects
// every HTT_FUN into a sorted buffer; FunCount/FunName/FunHasSrc/FunSec expose it to seed HolyC.
static CHashFun *funs_buf[1024];
static int funs_n;
static int fun_collect(void) {
    funs_n = 0;
    if (!g_cc || !g_cc->hash_table) return 0;
    CHashTable *h = g_cc->hash_table;
    for (I64 b = 0; b <= h->mask && funs_n < 1024; b++)
        for (CHashEntry *e = h->body[b]; e && funs_n < 1024; e = e->next)
            if (e->type & HTT_FUN)
                funs_buf[funs_n++] = (CHashFun *)e;
    for (int i = 1; i < funs_n; i++) {   // insertion sort by name (alphabetical, easy to scan)
        CHashFun *key = funs_buf[i]; int j = i - 1;
        while (j >= 0 && strcmp(funs_buf[j]->str ? funs_buf[j]->str : "", key->str ? key->str : "") > 0) {
            funs_buf[j + 1] = funs_buf[j]; j--;
        }
        funs_buf[j + 1] = key;
    }
    return funs_n;
}
static HRT_I64 FunCount(void) { return fun_collect(); }
static HRT_I64 FunName(HRT_I64 i) {
    if (i < 0 || i >= funs_n) return 0;
    return (HRT_I64)(funs_buf[i]->str ? funs_buf[i]->str : "?");
}
static HRT_I64 FunHasSrc(HRT_I64 i) {
    if (i < 0 || i >= funs_n) return 0;
    return srcmap_get(funs_buf[i]->str) ? 1 : 0;
}
static HRT_I64 FunSecAt(HRT_I64 i) {
    if (i < 0 || i >= funs_n) return 0;
    return fun_sec_of(funs_buf[i]->str);
}
// FunWrite() -- dump sorted function names into .funlist (for FunEd / DolDoc Enter).
static HRT_I64 FunWrite(void) {
    int n = fun_collect();
    MemFile *f = memfs_create(".funlist");
    if (!f) { puts_uart("FunWrite: fs full\n"); return -1; }
    int off = 0;
    for (int i = 0; i < n; i++) {
        const char *nm = funs_buf[i]->str ? funs_buf[i]->str : "?";
        int p = 0;
        while (nm[p] && off < MEMFS_FILE_CAP - 2) f->data[off++] = nm[p++];
        if (off < MEMFS_FILE_CAP - 1) f->data[off++] = '\n';
    }
    f->data[off] = 0;
    f->len = off;
    puts_uart("wrote .funlist ("); print_udec((U64)n);
    puts_uart(" functions, "); print_udec((U64)off); puts_uart(" bytes)\n");
    return n;
}
// Funs() -- list every function in the symbol table, sorted, with [src] marking the ones you
// can Src()/edit. This is the "what can I call or edit" view.
static HRT_I64 Funs(void) {
    int n = fun_collect();
    if (!n) { puts_uart("(no symbol table)\n"); return 0; }
    int editable = 0;
    for (int i = 0; i < n; i++) {
        puts_uart("  "); puts_uart(funs_buf[i]->str ? funs_buf[i]->str : "?");
        if (srcmap_get(funs_buf[i]->str)) { puts_uart("  [src]"); editable++; }
        puts_uart("\n");
    }
    puts_uart("("); print_udec(n); puts_uart(" functions, ");
    print_udec(editable); puts_uart(" Src-editable [src])\n");
    return n;
}
// FunsS() -- same census as Funs, grouped by manual section (then alpha within). Headers are
// "--- N title ---". FunsSec(n) lists only section n. FunPick uses FunSec/FunSecAt for the same map.
static HRT_I64 funs_by_section(int want) {
    int n = fun_collect();
    if (!n) { puts_uart("(no symbol table)\n"); return 0; }
    for (int i = 1; i < n; i++) {
        CHashFun *key = funs_buf[i];
        int ks = fun_sec_of(key->str);
        int j = i - 1;
        while (j >= 0) {
            int js = fun_sec_of(funs_buf[j]->str);
            if (js < ks || (js == ks && strcmp(funs_buf[j]->str ? funs_buf[j]->str : "",
                                               key->str ? key->str : "") <= 0))
                break;
            funs_buf[j + 1] = funs_buf[j]; j--;
        }
        funs_buf[j + 1] = key;
    }
    int editable = 0, shown = 0, last = -1;
    for (int i = 0; i < n; i++) {
        int s = fun_sec_of(funs_buf[i]->str);
        if (want > 0 && s != want) continue;
        if (s != last) {
            puts_uart("--- "); print_udec(s); puts_uart(" ");
            puts_uart(fun_sec_title(s)); puts_uart(" ---\n");
            last = s;
        }
        puts_uart("  "); puts_uart(funs_buf[i]->str ? funs_buf[i]->str : "?");
        if (srcmap_get(funs_buf[i]->str)) { puts_uart("  [src]"); editable++; }
        puts_uart("\n");
        shown++;
    }
    if (!shown) {
        puts_uart("(no functions in section "); print_udec(want); puts_uart(")\n");
        return 0;
    }
    puts_uart("("); print_udec(shown); puts_uart(" functions");
    if (want > 0) { puts_uart(" in section "); print_udec(want); }
    puts_uart(", "); print_udec(editable); puts_uart(" Src-editable [src])\n");
    return shown;
}
static HRT_I64 FunsS(void) { return funs_by_section(0); }
static HRT_I64 FunsSec(HRT_I64 sec) { return funs_by_section((int)sec); }

// ---- Reverse xref: which JIT functions call Name? ----------------------------------------
// REPL calls go through IC_CALL_INDIRECT2: lui/addi[/slli/srli] t0 with &callee->exe_addr,
// then ld t0,0(t0); jalr ra,t0. Recursion uses auipc+jalr to the entry. Scan sized HolyC
// bodies for those patterns; C builtins (size 0) are never reported as callers.
#define CALLERS_MAX 64
static CHashFun *callers_buf[CALLERS_MAX];
static int callers_n;

// Instruction sequence EmitCallArgsAndInvoke emits for a host exe_addr slot pointer.
static int callers_slot_seq(U32 *out, I64 addr) {
    int n = 0;
    U32 hi = (U32)(((addr + 0x800) >> 12) & 0xFFFFF);
    out[n++] = 0x37u | (5u << 7) | (hi << 12);   // lui t0, hi
    I64 lo = addr - (I64)((addr + 0x800) & ~0xFFFLL);
    if (lo)
        out[n++] = 0x13u | (5u << 7) | (5u << 15) | (((U32)lo & 0xFFFu) << 20);  // addi t0,t0,lo
    if (addr & 0x80000000) {
        out[n++] = 0x13u | (5u << 7) | (1u << 12) | (5u << 15) | (32u << 20);  // slli t0,32
        out[n++] = 0x13u | (5u << 7) | (5u << 12) | (5u << 15) | (32u << 20);  // srli t0,32
    }
    out[n++] = 0x03u | (5u << 7) | (3u << 12) | (5u << 15);  // ld t0, 0(t0)
    out[n++] = 0x67u | (1u << 7) | (5u << 15);               // jalr ra, t0
    return n;
}

static int callers_has_slot(CHashFun *caller, I64 slot_addr) {
    if (!caller || !caller->exe_addr || caller->size < 8) return 0;
    U32 seq[8];
    int nseq = callers_slot_seq(seq, slot_addr);
    U32 *code = (U32 *)(U64)caller->exe_addr;
    I64 nwords = (I64)caller->size / 4;
    for (I64 i = 0; i + nseq <= nwords; i++) {
        int ok = 1;
        for (int j = 0; j < nseq; j++) if (code[i + j] != seq[j]) { ok = 0; break; }
        if (ok) return 1;
    }
    return 0;
}

// PC-relative call (EmitJalToLabel): auipc ra,hi; jalr ra,lo(ra) resolving to target.
static int callers_has_direct(CHashFun *caller, I64 target) {
    if (!caller || !caller->exe_addr || !target || caller->size < 8) return 0;
    U32 *code = (U32 *)(U64)caller->exe_addr;
    I64 nwords = (I64)caller->size / 4;
    for (I64 i = 0; i + 1 < nwords; i++) {
        U32 w0 = code[i], w1 = code[i + 1];
        if ((w0 & 0x7Fu) != 0x17u) continue;                 // auipc
        if (((w0 >> 7) & 0x1Fu) != 1u) continue;             // rd = ra
        if ((w1 & 0x7Fu) != 0x67u) continue;                 // jalr
        if (((w1 >> 7) & 0x1Fu) != 1u) continue;             // rd = ra
        if (((w1 >> 15) & 0x1Fu) != 1u) continue;            // rs1 = ra
        I64 pc = (I64)(U64)&code[i];
        I64 auipc_imm = (I64)(I32)(w0 & 0xFFFFF000u);
        I64 jalr_imm = (I64)((I32)w1 >> 20);
        if (pc + auipc_imm + jalr_imm == target) return 1;
    }
    return 0;
}

// CallersScan("Name") -- print numbered HolyC callers of Name; stash names for CallerName(i).
static HRT_I64 CallersScan(char *name) {
    callers_n = 0;
    if (!name || !name[0]) { puts_uart("Callers: need a name\n"); return 0; }
    if (!g_cc || !g_cc->hash_table) { puts_uart("Callers: no symbol table\n"); return 0; }
    CHashFun *target = (CHashFun *)HashFind(name, g_cc->hash_table, HTT_FUN);
    if (!target) { puts_uart("Callers: no such function: "); puts_uart(name); puts_uart("\n"); return 0; }
    I64 slot = (I64)&target->exe_addr;
    I64 entry = (I64)target->exe_addr;
    CHashTable *h = g_cc->hash_table;
    for (I64 b = 0; b <= h->mask && callers_n < CALLERS_MAX; b++)
        for (CHashEntry *e = h->body[b]; e && callers_n < CALLERS_MAX; e = e->next) {
            if (!(e->type & HTT_FUN)) continue;
            CHashFun *f = (CHashFun *)e;
            if (!f->size || !f->exe_addr) continue;   // skip C builtins / undeclared
            if (callers_has_slot(f, slot) || (entry && callers_has_direct(f, entry)))
                callers_buf[callers_n++] = f;
        }
    // Alphabetical (same as Funs) so numbered picks are stable.
    for (int i = 1; i < callers_n; i++) {
        CHashFun *key = callers_buf[i]; int j = i - 1;
        while (j >= 0 && strcmp(callers_buf[j]->str ? callers_buf[j]->str : "",
                                key->str ? key->str : "") > 0) {
            callers_buf[j + 1] = callers_buf[j]; j--;
        }
        callers_buf[j + 1] = key;
    }
    if (!callers_n) {
        puts_uart("Callers: no JIT callers of "); puts_uart(name); puts_uart("\n");
        return 0;
    }
    for (int i = 0; i < callers_n; i++) {
        puts_uart("  "); print_udec((U64)(i + 1)); puts_uart(") ");
        puts_uart(callers_buf[i]->str ? callers_buf[i]->str : "?");
        if (srcmap_get(callers_buf[i]->str)) puts_uart("  [src]");
        puts_uart("\n");
    }
    puts_uart("("); print_udec((U64)callers_n); puts_uart(" callers of ");
    puts_uart(name); puts_uart(")\n");
    return callers_n;
}

static HRT_I64 CallerCnt(void) { return callers_n; }
static HRT_I64 CallerName(HRT_I64 i) {
    if (i < 0 || i >= callers_n || !callers_buf[i] || !callers_buf[i]->str) return 0;
    return (HRT_I64)callers_buf[i]->str;
}

// ---- Live trap handling: install a HolyC trap handler you can edit + recompile in place ----
// Shape (C fallback and HolyC trap.hc share it):
//   mtvec → thin TrapVec (asm: `j TrapCtxSave`, keeps trapped ra)
//        → TrapCtxSave   (asm: 144-byte GPR frame; callable on its own)
//        → trapvec()     (C: SetTrap name → handler; owns all policy)
//        → TrapCtxRestore(asm: reload frame + mret; callable on its own)
// Remaining asm is only GPR save/restore + mret/csrr. Run("trap.hc") can swap the thin
// HolyC TrapVec; slot 0x87000010 always points at C trapvec. Handler:
// I64 OnMyTrap(I64 cause, I64 epc, I64 tval); nonzero = resume PC (mepc). Return 0:
// retry interrupt, skip ecall, dump+abort any other sync fault.
static char g_trap_name[32];
#define TRAP_DISPATCH_SLOT     0x87000010UL
#define TRAP_NAME_FIXED        0x87001090UL  /* 32-byte name buf in host-slot page (HolyC writes here) */
#define TRAP_NAME_BUF_SLOT     0x87001058UL  /* *(U8**) = TRAP_NAME_FIXED for older HolyC */
#define TRAP_DISP_FN_SLOT      0x87001060UL  /* &trapvec for HolyC TrapInit */
#define TRAP_FALLBACK_VEC_SLOT 0x87001068UL  /* C thin TrapVec (mtvec fallback) */
#define TRAP_REENTRY_PTR_SLOT  0x87001080UL  /* &repl_reentry for HolyC Reset */

static void repl_reentry(void);  /* soft-reset target; published for HolyC Reset */

// The saved-register frame is published on EVERY trap to a FIXED address (0x87000100) so a HolyC
// handler -- the debugger's breakpoint trap handler -- can read the trapped registers with a plain
// *(U64*)... peek, no C primitive needed. Layout at 0x87000100 (U64 each): [0]=ra, [1..7]=t0..t6,
// [8..15]=a0..a7, [16]=trapped sp. frame[] from TrapCtxSave matches [0..15] (+ s0 at [16] on stack).
static CHashFun *SymNearest(HRT_I64 addr);
static void trapvec(U64 *frame);
// mcause -> what you actually did wrong. tval is the bad address for access faults and the
// offending opcode for illegal instruction.
static const char *trap_cause_name(I64 cause) {
    if (cause < 0) {
        switch (cause & 0xFF) {
        case 3: return "software interrupt"; case 7: return "timer interrupt";
        case 11: return "external interrupt"; }
        return "interrupt";
    }
    switch (cause) {
    case 0: return "instruction misaligned"; case 1: return "instruction access fault";
    case 2: return "illegal instruction";    case 3: return "breakpoint";
    case 4: return "load misaligned";        case 5: return "load access fault (bad address)";
    case 6: return "store misaligned";       case 7: return "store access fault (bad address)";
    case 8: case 9: case 11: return "ecall";
    case 12: return "instruction page fault"; case 13: return "load page fault";
    case 15: return "store page fault"; }
    return "trap";
}
static void trap_sym(U64 a) {   // " (Foo+0x12)" if a lands in a known function
    CHashFun *f = SymNearest((HRT_I64)a);
    if (!f || !f->str) return;
    U64 off = (U64)a - (U64)f->exe_addr;
    if (f->size == 0 && off >= 0x4000) return;   // a size-unknown C builtin claims everything above it -- don't trust a huge offset
    puts_uart(" ("); puts_uart(f->str); puts_uart("+"); print_hex(off); puts_uart(")");
}
// ---- Fault recovery: catch a synchronous fault, print a symbolic stack dump, and longjmp back
// to the REPL prompt instead of running on past corrupt state. Minimal bare-metal setjmp: the
// callee-saved set (ra, sp, s0-s11) is all C code at -O0 needs.
static U64 g_repl_jb[16];
static int g_repl_jb_ok;
I64 repl_setjmp(U64 *jb);
void repl_longjmp(U64 *jb) __attribute__((noreturn));
__asm__(
    ".text\n.globl repl_setjmp\nrepl_setjmp:\n"
    " sd ra,0(a0)\n sd sp,8(a0)\n sd s0,16(a0)\n sd s1,24(a0)\n sd s2,32(a0)\n sd s3,40(a0)\n"
    " sd s4,48(a0)\n sd s5,56(a0)\n sd s6,64(a0)\n sd s7,72(a0)\n sd s8,80(a0)\n sd s9,88(a0)\n"
    " sd s10,96(a0)\n sd s11,104(a0)\n li a0,0\n ret\n"
    ".globl repl_longjmp\nrepl_longjmp:\n"
    " ld ra,0(a0)\n ld sp,8(a0)\n ld s0,16(a0)\n ld s1,24(a0)\n ld s2,32(a0)\n ld s3,40(a0)\n"
    " ld s4,48(a0)\n ld s5,56(a0)\n ld s6,64(a0)\n ld s7,72(a0)\n ld s8,80(a0)\n ld s9,88(a0)\n"
    " ld s10,96(a0)\n ld s11,104(a0)\n li a0,1\n ret\n"
);
// The JIT prologue is `addi sp,sp,-N; sd ra,0(sp); sd s0,8(sp); addi s0,sp,N` -- decode N from the
// entry instruction so the walker can find the saved pair at s0-N / s0-N+8. Returns 0 if the entry
// isn't the simple form (big frames use a multi-instruction sequence; the walk just stops there).
static I64 jit_frame_size(U64 entry) {
    if (entry < 0x80000000UL || entry >= 0x88000000UL) return 0;
    U32 w = *(U32 *)entry;
    if ((w & 0xFFFFF) != 0x10113) return 0;    /* addi sp, sp, imm */
    I64 imm = ((I32)w) >> 20;
    return imm < 0 ? -imm : 0;
}
#define STK_IN_RAM(a) ((U64)(a) >= 0x80000000UL && (U64)(a) < 0x88000000UL)
static void stk_rep(U64 pc, U64 s0) {
    puts_uart("  stack:\n");
    for (int i = 0; i < 16; i++) {
        puts_uart("    #"); print_udec(i); puts_uart(" "); print_hex(pc); trap_sym(pc); puts_uart("\n");
        CHashFun *f = SymNearest((HRT_I64)pc);
        if (!f || !STK_IN_RAM(s0)) break;
        U64 ra, ps0;
        if (f->size > 0) {                      /* JIT frame: saved pair at s0-N */
            I64 N = jit_frame_size((U64)f->exe_addr);
            if (!N || !STK_IN_RAM(s0 - N)) break;
            ra = *(U64 *)(s0 - N); ps0 = *(U64 *)(s0 - N + 8);
        } else {                                /* C frame (gcc): ra at s0-8, s0 at s0-16 */
            if (!STK_IN_RAM(s0 - 16)) break;
            ra = *(U64 *)(s0 - 8); ps0 = *(U64 *)(s0 - 16);
        }
        if (!STK_IN_RAM(ra) || ra == pc) break;
        pc = ra; s0 = ps0;
    }
}
// mret target after a caught fault: normal machine state (mret restored MIE), then abandon the
// wrecked evaluation and longjmp to the prompt.
__attribute__((used)) static void repl_fault_recover(void) {
    g_break_armed = 0;
    g_break_pending = 0;
    *(volatile U64 *)MEM_MTIMECMP_ADDR = ~(U64)0; /* park break-poll timer */
    puts_uart("-- eval aborted, back to the REPL --\n");
    repl_longjmp(g_repl_jb);
}
/* mret target after Ctrl-C during eval: throw('Break') if try/catch is active, else prompt. */
__attribute__((used, noreturn)) static void repl_break_raise(void) {
    g_break_armed = 0;
    g_break_pending = 0;
    *(volatile U64 *)MEM_MTIMECMP_ADDR = ~(U64)0; /* park break-poll timer */
    if (g_cc && g_cc->try_top_var && g_cc->except_ch_var) {
        I64 *try_top = (I64 *)g_cc->try_top_var->data_addr;
        I64 ctx = *try_top;
        if (ctx) {
            *(I64 *)g_cc->except_ch_var->data_addr = EXCEPT_BREAK;
            *try_top = *(I64 *)ctx;                         /* pop handler */
            I64 new_sp = *(I64 *)(ctx + 8);
            I64 new_s0 = *(I64 *)(ctx + 16);
            I64 catch_pc = *(I64 *)(ctx + 24);
            __asm__ volatile(
                "mv sp, %0\n"
                "mv s0, %1\n"
                "jr %2\n"
                :: "r"(new_sp), "r"(new_s0), "r"(catch_pc) : "memory");
            __builtin_unreachable();
        }
    }
    puts_uart("\nInterrupted\n");
    if (g_repl_jb_ok) repl_longjmp(g_repl_jb);
    for (;;) __asm__ volatile("wfi");
}
// StkRep; -- symbolic backtrace from the current point (TempleOS's stack report).
static HRT_I64 StkRep(void) {
    U64 s0, ra;
    __asm__ volatile("mv %0, s0" : "=r"(s0));
    __asm__ volatile("mv %0, ra" : "=r"(ra));
    stk_rep(ra, STK_IN_RAM(s0 - 16) ? *(U64 *)(s0 - 16) : s0);   /* start at the caller */
    return 0;
}
/* HolyC global `pc` (TempleOS _RIP analogue) — last trap mepc for U(pc-16). */
static I64 *g_hc_pc;
static void hc_pc_publish(I64 epc) {
    if (!g_hc_pc && g_cc) {
        CHashGlblVar *pg = (CHashGlblVar *)HashFind("pc", g_cc->hash_table, HTT_GLBL_VAR);
        if (pg && pg->data_addr) g_hc_pc = (I64 *)pg->data_addr;
    }
    if (g_hc_pc) *g_hc_pc = epc;
}
/* C trapvec — named policy/dispatch. Called from TrapCtxSave with a0 = GPR frame. */
__attribute__((used)) static void trapvec(U64 *frame) {
    I64 cause, epc, tval;
    __asm__ volatile("csrr %0, mcause" : "=r"(cause));
    __asm__ volatile("csrr %0, mepc"   : "=r"(epc));
    __asm__ volatile("csrr %0, mtval"  : "=r"(tval));
    hc_pc_publish(epc);                                   // before resume overwrites mepc
    volatile U64 *dbg = (volatile U64 *)0x87000100;
    for (int k = 0; k < 16; k++) dbg[k] = frame[k];        // publish the trapped registers for HolyC
    dbg[16] = (U64)frame + 144;                            // trapped sp
    dbg[17] = frame[16];                                   // trapped s0 (frame pointer)
    /* External IRQ: claim PLIC + drain UART (Ctrl-C sets g_break_pending). */
    int ext_irq = -1;
    if (cause < 0 && (cause & 0xFF) == 11) ext_irq = plic_service_uart();
    /* Break-poll timer tick: drain UART, re-arm, skip SetTrap (do not spam OnTick/Zap). */
    if (g_break_armed && cause < 0 && (cause & 0xFF) == 7) {
        uart_hw_drain();
        uart_ring_take_leading_break();
        {
            volatile U64 *mtime = (volatile U64 *)MEM_MTIME_ADDR;
            volatile U64 *mtimecmp = (volatile U64 *)MEM_MTIMECMP_ADDR;
            *mtimecmp = *mtime + 100000; /* ~10 ms @ 10 MHz */
        }
        if (g_break_pending) {
            __asm__ volatile("csrw mepc, %0" :: "r"((I64)repl_break_raise));
            return;
        }
        __asm__ volatile("csrw mepc, %0" :: "r"(epc));
        return;
    }
    if (g_break_armed) {
        uart_hw_drain();
        uart_ring_take_leading_break();
    }
    I64 resume = 0;
    char *tname = (char *)TRAP_NAME_FIXED;
    if (!tname[0]) tname = g_trap_name;
    /* UART RX is break/char plumbing — do not run SetTrap (would spam OnTick/Zap per key). */
    int skip_hc = (ext_irq == (int)UART_IRQ);
    CHashFun *f = (!skip_hc && tname[0] && g_cc) ? (CHashFun *)HashFind(tname, g_cc->hash_table, HTT_FUN) : 0;
    if (f && f->exe_addr) {
        typedef I64 (*TrapHandler)(I64, I64, I64);
        resume = ((TrapHandler)f->exe_addr)(cause, epc, tval);   // e.g. OnTrap, DbgTrap, a live-edited Zap
    }
    /* Ctrl-C during eval wins over default interrupt retry / handler resume. */
    if (g_break_armed && g_break_pending) {
        resume = (I64)repl_break_raise;
        __asm__ volatile("csrw mepc, %0" :: "r"(resume));
        return;
    }
    // Handler return 0 (or no SetTrap target) is default handling -- not "skip the faulting insn".
    // A store access fault after Bp() used to fall through here and resume at epc+4, so the REPL
    // never saw what happened. Dump and longjmp back to the prompt instead.
    if (!resume) {
        if (cause < 0) resume = epc;                     // interrupt: retry
        else if (cause == 8 || cause == 9 || cause == 11) resume = epc + 4;  // ecall: skip
        else {
            puts_uart("\n*** FAULT: "); puts_uart(trap_cause_name(cause));
            puts_uart("\n  cause="); print_hex((U64)cause);
            puts_uart("  tval=");    print_hex((U64)tval);
            puts_uart("\n  pc  = "); print_hex((U64)epc);  trap_sym((U64)epc);
            puts_uart("\n  ra  = "); print_hex(frame[0]);  trap_sym(frame[0]);
            puts_uart("\n");
            stk_rep((U64)epc, frame[16]);
            puts_uart("  (Uf the function, or U(pc-16); Dr; for registers)\n");
            resume = g_repl_jb_ok ? (I64)repl_fault_recover : epc + 4;
        }
    }
    __asm__ volatile("csrw mepc, %0" :: "r"(resume));
}
/* TrapCtxRestore — callable: reload 144-byte frame from sp and mret. Asm required for mret. */
__attribute__((used, naked)) void TrapCtxRestore(void) {
    __asm__ volatile(
        "ld ra,0(sp)\n ld t0,8(sp)\n ld t1,16(sp)\n ld t2,24(sp)\n"
        "ld t3,32(sp)\n ld t4,40(sp)\n ld t5,48(sp)\n ld t6,56(sp)\n"
        "ld a0,64(sp)\n ld a1,72(sp)\n ld a2,80(sp)\n ld a3,88(sp)\n"
        "ld a4,96(sp)\n ld a5,104(sp)\n ld a6,112(sp)\n ld a7,120(sp)\n"
        "ld s0,128(sp)\n"
        "addi sp,sp,144\n"
        "mret\n"
    );
}
/* TrapCtxSave — callable: push 144-byte GPR frame, call C trapvec, then TrapCtxRestore.
 * Asm required so GPRs are saved before any C prologue. */
__attribute__((used, naked)) void TrapCtxSave(void) {
    __asm__ volatile(
        "addi sp,sp,-144\n"
        "sd ra,0(sp)\n sd t0,8(sp)\n sd t1,16(sp)\n sd t2,24(sp)\n"
        "sd t3,32(sp)\n sd t4,40(sp)\n sd t5,48(sp)\n sd t6,56(sp)\n"
        "sd a0,64(sp)\n sd a1,72(sp)\n sd a2,80(sp)\n sd a3,88(sp)\n"
        "sd a4,96(sp)\n sd a5,104(sp)\n sd a6,112(sp)\n sd a7,120(sp)\n"
        "sd s0,128(sp)\n"               /* trapped frame pointer — stack walker starts here */
        "mv a0,sp\n"
        "call trapvec\n"
        "j TrapCtxRestore\n"
    );
}
/* Thin mtvec entry: jump (not jal) into TrapCtxSave so trapped ra survives. */
__attribute__((used, naked, aligned(4))) static void TrapVec(void) {
    __asm__ volatile("j TrapCtxSave\n");
}
// SetTrap("name") -- route traps to the HolyC function of that name (resolved live per trap).
// RISC-V: mtvec → TrapVec → TrapCtxSave → C trapvec → SetTrap target → TrapCtxRestore → mret.
static HRT_I64 SetTrap(char *name) {
    char *buf = (char *)TRAP_NAME_FIXED;
    int i = 0;
    if (name) while (name[i] && i < 31) { buf[i] = name[i]; i++; }
    buf[i] = 0;
    /* Keep BSS mirror + slot pointer in sync for any reader. */
    for (i = 0; i < 32; i++) g_trap_name[i] = buf[i];
    return 0;
}
static void trap_publish_slots(void) {
    *(volatile U64 *)TRAP_NAME_BUF_SLOT = TRAP_NAME_FIXED;
    *(volatile U64 *)TRAP_DISP_FN_SLOT = (U64)&trapvec;
    *(volatile U64 *)TRAP_FALLBACK_VEC_SLOT = (U64)&TrapVec;
    *(volatile U64 *)TRAP_REENTRY_PTR_SLOT = (U64)&repl_reentry;
}
// TrapInit() -- publish slots + trapvec, point mtvec at TrapVec (HolyC or C fallback), enable MIE.
// Called at boot so a fault dumps and returns to the REPL instead of hanging in startup.s.
// Run("trap.hc") after editing the thin vector reinstalls it; policy stays in C trapvec.
static HRT_I64 TrapInit(void) {
    trap_publish_slots();
    *(volatile U64 *)TRAP_DISPATCH_SLOT = (U64)&trapvec;
    void *vec = (void *)&TrapVec;
    if (g_cc && g_cc->hash_table) {
        CHashFun *tv = (CHashFun *)HashFind("TrapVec", g_cc->hash_table, HTT_FUN);
        if (tv && tv->exe_addr) vec = (void *)(U64)tv->exe_addr;
        if (!g_trap_name[0]) {
            CHashFun *on = (CHashFun *)HashFind("OnTrap", g_cc->hash_table, HTT_FUN);
            if (on && on->exe_addr) SetTrap("OnTrap");
        }
    }
    __asm__ volatile("csrw mtvec, %0" :: "r"(vec));
    __asm__ volatile("fence.i" ::: "memory");
    __asm__ volatile("csrs mstatus, %0" :: "r"((HRT_I64)(1 << 3)));   // MIE: global interrupt enable
    UartBreakIrqInit();  /* Ctrl-C (UART RX) → PLIC → wake wfi / preempt busy eval */
    return 0;
}
// Ecall() -- raise a synchronous trap (mcause=11, env-call-from-M) so you can watch your handler run.
static HRT_I64 Ecall(void) { __asm__ volatile("ecall"); return 0; }
// TimerArm(interval) -- arm the CLINT machine timer to fire a timer interrupt every `interval`
// mtime ticks (async, mcause bit63|7). Pass a large interval so ticks are occasional, not a flood.
static HRT_I64 TimerArm(HRT_I64 interval) {
    volatile HRT_I64 *mtime    = (volatile HRT_I64 *)MEM_MTIME_ADDR;
    volatile HRT_I64 *mtimecmp = (volatile HRT_I64 *)MEM_MTIMECMP_ADDR;
    *mtimecmp = *mtime + interval;
    __asm__ volatile("csrs mie, %0" :: "r"((HRT_I64)(1 << 7)));       // MTIE
    return 0;
}

// ---- Soft reset: run edited boot assembly and restart --------------------------------------
// The boot code (start.hc: `asm { Boot:: ... }`) is native RISC-V you edit and JIT-assemble to
// RAM. Reset() drops the re-entry address in a fixed slot Boot reads, then jumps into Boot,
// which re-initializes M-mode (CSRs, a fresh stack) and jumps back here to restart the REPL --
// a soft processor reset that runs YOUR edited boot. (A hardware reset via the SiFive test
// device would instead re-run the fixed ROM startup, not the edited code.)
void repl(void);
static void repl_reentry(void) {
    puts_uart("\n[reboot] boot code ran; restarting REPL\n");
    repl();
    while (1) __asm__ volatile("wfi");
}
static HRT_I64 Reset(void) {
    CHashFun *f = g_cc ? (CHashFun *)HashFind("Boot", g_cc->hash_table, HTT_FUN) : 0;
    if (!f || !f->exe_addr) { puts_uart("Reset: no Boot() -- Run(\"start.hc\") first\n"); return -1; }
    *(volatile U64 *)0x87000000 = (U64)&repl_reentry;   // Boot reads the re-entry from this slot
    __asm__ volatile("fence.i" ::: "memory");
    ((void (*)(void))f->exe_addr)();                    // into the edited boot code (never returns)
    return 0;
}

// ---- Inspection: memory map and machine registers -----------------------------------------
/* Live JIT bases published for HolyC MemMapFind("code") / MemMapFind("jit_heap"). */
#define HC_SLOT_CODE_BASE   (0x87001000UL + 0x140) /* U64 — &code_mem[0] */
#define HC_SLOT_HEAP_BASE   (0x87001000UL + 0x148) /* U64 — &heap_mem[0] */
#define HC_SLOT_REG_ONE     (0x87001000UL + 0x150) /* HRT_I64 (*)(char*) — reg_one_stub */

static HRT_I64 MemMap(void) {
    /* Columns: MEM_* | base | note | driver (Kernel/Drv or seed). Virt profile. */
    puts_uart("Memory map (RISC-V QEMU virt; MEM_* in csr.hc; last col = HolyC driver):\n");
    puts_uart("  MEM_RAM        0x80000000  +128M default (memfs @0x87800000)\n");
    puts_uart("  MEM_CODE     @ "); print_hex((U64)&code_mem[0]); puts_uart("  ");
        print_udec(code_pos); putc_uart('/'); print_udec(sizeof(code_mem));
        puts_uart(" B used   [live JIT code_mem]\n");
    puts_uart("  MEM_JIT_HEAP @ "); print_hex((U64)&heap_mem[0]); puts_uart("  ");
        print_udec(heap_pos); putc_uart('/'); print_udec(sizeof(heap_mem));
        puts_uart(" B used   [live C heap_mem]\n");
    puts_uart("  MEM_FS         0x87800000  HolyC memfs arena           fs.hc\n");
    puts_uart("  MEM_HEAP       0x86000000  HolyC MAlloc arena          mem.hc\n");
    puts_uart("  MEM_FB         0x86100000  soft FB (ramfb)             RVFb / ramfb\n");
    puts_uart("  MEM_FIXED      0x87000000  trap/regs + host slots      [plat]\n");
    puts_uart("  MEM_TRAP_SNAP  0x87000100  DbgReg / trap GPRs          trap.hc\n");
    puts_uart("  MEM_REGS_SNAP  0x87000300  Regs() GPR snapshot         Regs / csr.hc\n");
    puts_uart("  MEM_STACK      0x87F00000  Boot/Reset stack (down)     [plat]\n");
    puts_uart("  MEM_UART       "); print_hex((U64)UART_BASE);
        puts_uart("  16550                       RVUart16550 / uart.hc\n");
    puts_uart("  MEM_CLINT      "); print_hex((U64)CLINT_BASE);
        puts_uart("  mtime/mtimecmp              RVTimer / CLINT\n");
    puts_uart("  MEM_PLIC       "); print_hex((U64)PLIC_BASE);
        puts_uart("  external IRQs               RVPlicHw\n");
    puts_uart("  MEM_VIRTIO     "); print_hex((U64)VIRTIO_MMIO_BASE);
        puts_uart(" .. +7*0x1000                 DskVirtioRV / RVVirtioMmio*\n");
    puts_uart("  MEM_FW_CFG     0x10100000  QEMU fw_cfg                 RVFwCfgYes\n");
    puts_uart("  MEM_TEST       0x00100000  SiFive test (off/reboot)    [plat]\n");
    puts_uart("  MEM_COMPILER   (kernel phase3 TOSB embed; n/a on REPL)\n");
    puts_uart("Dig-down: Regs; Reg(\"mstatus\"); MemMapDrvFind(\"uart\"); Man(\"MemMap\"); RegHelp;\n");
    puts_uart("  MemMapFind(\"heap\");  Print(\"%X\\n\", MEM_HEAP);\n");
    return 0;
}
static void reg_line(const char *name, I64 v) {
    puts_uart("  "); puts_uart(name); puts_uart(" = "); print_hex((U64)v); putc_uart('\n');
}
static void reg_line_desc(const char *name, I64 v, const char *desc) {
    puts_uart("  "); puts_uart(name); puts_uart(" = "); print_hex((U64)v);
    if (desc && desc[0]) { puts_uart("  "); puts_uart(desc); }
    putc_uart('\n');
}
static int reg_name_eq(const char *a, const char *b) {
    if (!a || !b) return 0;
    while (*a && *b) {
        char ca = *a, cb = *b;
        if (ca >= 'A' && ca <= 'Z') ca = (char)(ca + 32);
        if (cb >= 'A' && cb <= 'Z') cb = (char)(cb + 32);
        if (ca != cb) return 0;
        a++; b++;
    }
    return !*a && !*b;
}
/* Regs: dump EVERY GPR as it was at the call site, plus M-mode CSRs (with short descriptions).
 * Naked stub snapshots x1..x31 to 0x87000300 before C runs. t6 via sscratch (mscratch is scheduler). */
#define REGS_SNAP_BASE 0x87000300UL
__asm__(
    ".text\n"
    /* Shared body: on entry ra must still be the HolyC return (no call). t6 via sscratch. */
    ".globl regs_snap_stub\n"
    "regs_snap_stub:\n"
    "  csrw sscratch, t6\n"
    "  lui  t6, 0x10E00\n"
    "  slli t6, t6, 3\n"
    "  sd x1, 0x308(t6)\n"
    "  sd x2, 0x310(t6)\n"
    "  sd x3, 0x318(t6)\n"
    "  sd x4, 0x320(t6)\n"
    "  sd x5, 0x328(t6)\n"
    "  sd x6, 0x330(t6)\n"
    "  sd x7, 0x338(t6)\n"
    "  sd x8, 0x340(t6)\n"
    "  sd x9, 0x348(t6)\n"
    "  sd x10, 0x350(t6)\n"
    "  sd x11, 0x358(t6)\n"
    "  sd x12, 0x360(t6)\n"
    "  sd x13, 0x368(t6)\n"
    "  sd x14, 0x370(t6)\n"
    "  sd x15, 0x378(t6)\n"
    "  sd x16, 0x380(t6)\n"
    "  sd x17, 0x388(t6)\n"
    "  sd x18, 0x390(t6)\n"
    "  sd x19, 0x398(t6)\n"
    "  sd x20, 0x3A0(t6)\n"
    "  sd x21, 0x3A8(t6)\n"
    "  sd x22, 0x3B0(t6)\n"
    "  sd x23, 0x3B8(t6)\n"
    "  sd x24, 0x3C0(t6)\n"
    "  sd x25, 0x3C8(t6)\n"
    "  sd x26, 0x3D0(t6)\n"
    "  sd x27, 0x3D8(t6)\n"
    "  sd x28, 0x3E0(t6)\n"
    "  sd x29, 0x3E8(t6)\n"
    "  sd x30, 0x3F0(t6)\n"
    "  csrr t5, sscratch\n"
    "  sd t5, 0x3F8(t6)\n"
    "  ld t5, 0x3F0(t6)\n"
    "  csrr t6, sscratch\n"
    "  j regs_dump_c\n"
    ".globl reg_one_stub\n"
    "reg_one_stub:\n"
    "  csrw sscratch, t6\n"
    "  lui  t6, 0x10E00\n"
    "  slli t6, t6, 3\n"
    "  sd x1, 0x308(t6)\n"
    "  sd x2, 0x310(t6)\n"
    "  sd x3, 0x318(t6)\n"
    "  sd x4, 0x320(t6)\n"
    "  sd x5, 0x328(t6)\n"
    "  sd x6, 0x330(t6)\n"
    "  sd x7, 0x338(t6)\n"
    "  sd x8, 0x340(t6)\n"
    "  sd x9, 0x348(t6)\n"
    "  sd x10, 0x350(t6)\n"
    "  sd x11, 0x358(t6)\n"
    "  sd x12, 0x360(t6)\n"
    "  sd x13, 0x368(t6)\n"
    "  sd x14, 0x370(t6)\n"
    "  sd x15, 0x378(t6)\n"
    "  sd x16, 0x380(t6)\n"
    "  sd x17, 0x388(t6)\n"
    "  sd x18, 0x390(t6)\n"
    "  sd x19, 0x398(t6)\n"
    "  sd x20, 0x3A0(t6)\n"
    "  sd x21, 0x3A8(t6)\n"
    "  sd x22, 0x3B0(t6)\n"
    "  sd x23, 0x3B8(t6)\n"
    "  sd x24, 0x3C0(t6)\n"
    "  sd x25, 0x3C8(t6)\n"
    "  sd x26, 0x3D0(t6)\n"
    "  sd x27, 0x3D8(t6)\n"
    "  sd x28, 0x3E0(t6)\n"
    "  sd x29, 0x3E8(t6)\n"
    "  sd x30, 0x3F0(t6)\n"
    "  csrr t5, sscratch\n"
    "  sd t5, 0x3F8(t6)\n"
    "  ld t5, 0x3F0(t6)\n"
    "  csrr t6, sscratch\n"
    "  j reg_one_c\n"
);
HRT_I64 regs_snap_stub(void);
HRT_I64 reg_one_stub(char *name);
static const char *gpr_abi[32] = {
    "zero","ra","sp","gp","tp","t0","t1","t2","s0","s1",
    "a0","a1","a2","a3","a4","a5","a6","a7","s2","s3","s4","s5","s6","s7","s8","s9",
    "s10","s11","t3","t4","t5","t6"
};
static const char *gpr_desc[32] = {
    "hardwired zero",
    "return address",
    "stack pointer",
    "global pointer",
    "thread pointer",
    "temp", "temp", "temp",
    "saved / frame ptr", "saved",
    "arg/ret 0", "arg/ret 1", "arg 2", "arg 3", "arg 4", "arg 5", "arg 6", "arg 7",
    "saved", "saved", "saved", "saved", "saved", "saved", "saved", "saved", "saved", "saved",
    "temp", "temp", "temp", "temp"
};
typedef struct {
    const char *name; int csr; const char *desc; int writable; const char *api;
} CsrInfo;
static const CsrInfo csr_tab[] = {
    {"sstatus",    0x100, "supervisor status", 1, "GetSStatus/SetSStatus"},
    {"sie",        0x104, "supervisor interrupt enable", 1, "GetSie/SetSie"},
    {"stvec",      0x105, "supervisor trap vector", 1, "GetStvec/SetStvec"},
    {"sscratch",   0x140, "S-mode scratch (Regs snap uses)", 1, "GetSScratch/SetSScratch"},
    {"sepc",       0x141, "supervisor exception PC", 1, "GetSepc/SetSepc"},
    {"scause",     0x142, "supervisor trap cause", 1, "GetScause/SetScause"},
    {"stval",      0x143, "supervisor bad addr / insn", 1, "GetStval/SetStval"},
    {"sip",        0x144, "supervisor interrupt pending", 1, "GetSip/SetSip"},
    {"satp",       0x180, "supervisor addr xlate / ASID", 1, "GetSatp/SetSatp"},
    {"mstatus",    0x300, "machine status (MIE/FS/...)", 1, "GetMStatus/SetMStatus"},
    {"misa",       0x301, "ISA / extension bitmap (WARL)", 1, "GetMIsa/SetMIsa"},
    {"medeleg",    0x302, "machine exception delegation", 1, "GetMedeleg/SetMedeleg"},
    {"mideleg",    0x303, "machine interrupt delegation", 1, "GetMideleg/SetMideleg"},
    {"mie",        0x304, "machine interrupt enable", 1, "GetMie/SetMie"},
    {"mtvec",      0x305, "trap vector base", 1, "GetMtvec/SetMtvec"},
    {"mcounteren", 0x306, "counter access for lower priv", 1, "GetMCounterEn/SetMCounterEn"},
    {"mscratch",   0x340, "scratch for M-mode trap/sched", 1, "GetMScratch/SetMScratch"},
    {"mepc",       0x341, "exception PC (mret target)", 1, "GetMepc/SetMepc"},
    {"mcause",     0x342, "trap cause (interrupt|code)", 1, "GetMcause/SetMcause"},
    {"mtval",      0x343, "bad addr / faulting insn", 1, "GetMtval/SetMtval"},
    {"mip",        0x344, "machine interrupt pending", 1, "GetMip/SetMip"},
    {"mcycle",     0xB00, "cycle counter (M-mode)", 0, "GetMCycle (RO)"},
    {"minstret",   0xB02, "retired instructions (M-mode)", 0, "GetMInstret (RO)"},
    {"cycle",      0xC00, "cycle (needs mcounteren)", 0, "GetCycle (RO)"},
    {"instret",    0xC02, "instret (needs mcounteren)", 0, "GetInstret (RO)"},
    {"mhartid",    0xF14, "hardware thread id (RO)", 0, "GetMHartId (RO)"},
    {0, 0, 0, 0, 0}
};
static I64 csr_read_by_num(int csr) {
    I64 v = 0;
    switch (csr) {
    case 0x100: __asm__ volatile("csrr %0, sstatus"    : "=r"(v)); break;
    case 0x104: __asm__ volatile("csrr %0, sie"        : "=r"(v)); break;
    case 0x105: __asm__ volatile("csrr %0, stvec"      : "=r"(v)); break;
    case 0x140: __asm__ volatile("csrr %0, sscratch"   : "=r"(v)); break;
    case 0x141: __asm__ volatile("csrr %0, sepc"       : "=r"(v)); break;
    case 0x142: __asm__ volatile("csrr %0, scause"     : "=r"(v)); break;
    case 0x143: __asm__ volatile("csrr %0, stval"      : "=r"(v)); break;
    case 0x144: __asm__ volatile("csrr %0, sip"        : "=r"(v)); break;
    case 0x180: __asm__ volatile("csrr %0, satp"       : "=r"(v)); break;
    case 0x300: __asm__ volatile("csrr %0, mstatus"    : "=r"(v)); break;
    case 0x301: __asm__ volatile("csrr %0, misa"       : "=r"(v)); break;
    case 0x302: __asm__ volatile("csrr %0, medeleg"    : "=r"(v)); break;
    case 0x303: __asm__ volatile("csrr %0, mideleg"    : "=r"(v)); break;
    case 0x304: __asm__ volatile("csrr %0, mie"        : "=r"(v)); break;
    case 0x305: __asm__ volatile("csrr %0, mtvec"      : "=r"(v)); break;
    case 0x306: __asm__ volatile("csrr %0, mcounteren" : "=r"(v)); break;
    case 0x340: __asm__ volatile("csrr %0, mscratch"   : "=r"(v)); break;
    case 0x341: __asm__ volatile("csrr %0, mepc"       : "=r"(v)); break;
    case 0x342: __asm__ volatile("csrr %0, mcause"     : "=r"(v)); break;
    case 0x343: __asm__ volatile("csrr %0, mtval"      : "=r"(v)); break;
    case 0x344: __asm__ volatile("csrr %0, mip"        : "=r"(v)); break;
    case 0xB00: __asm__ volatile("csrr %0, mcycle"     : "=r"(v)); break;
    case 0xB02: __asm__ volatile("csrr %0, minstret"   : "=r"(v)); break;
    case 0xC00: __asm__ volatile("csrr %0, cycle"      : "=r"(v)); break;
    case 0xC02: __asm__ volatile("csrr %0, instret"    : "=r"(v)); break;
    case 0xF14: __asm__ volatile("csrr %0, mhartid"    : "=r"(v)); break;
    default: return 0;
    }
    return v;
}
static int gpr_index(const char *name) {
    char buf[8];
    int i;
    if (!name || !name[0]) return -1;
    if ((name[0] == 'x' || name[0] == 'X') && name[1] >= '0' && name[1] <= '9') {
        i = 0; name++;
        while (*name >= '0' && *name <= '9') i = i * 10 + (*name++ - '0');
        if (!*name && i >= 0 && i < 32) return i;
        return -1;
    }
    for (i = 0; i < 32; i++) if (reg_name_eq(name, gpr_abi[i])) return i;
    /* REG_SP style */
    if (name[0] == 'R' || name[0] == 'r') {
        if (name[1] == 'E' || name[1] == 'e') {
            if (name[2] == 'G' || name[2] == 'g') {
                const char *p = name + 3;
                if (*p == '_') p++;
                for (i = 0; i < 32; i++) if (reg_name_eq(p, gpr_abi[i])) return i;
            }
        }
    }
    (void)buf;
    return -1;
}
__attribute__((used)) static HRT_I64 regs_dump_c(void) {
    volatile U64 *r = (volatile U64 *)REGS_SNAP_BASE;
    I64 v;
    char pad[16];
    int i, k, j;
    puts_uart("GPRs at Regs() call site (xN / ABI / REG_* ; see RegHelp):\n");
    for (i = 1; i < 32; i++) {
        k = 0;
        pad[k++] = 'x';
        if (i >= 10) pad[k++] = (char)('0' + i / 10);
        pad[k++] = (char)('0' + i % 10);
        while (k < 4) pad[k++] = ' ';
        for (j = 0; gpr_abi[i][j]; j++) pad[k++] = gpr_abi[i][j];
        while (k < 8) pad[k++] = ' ';
        pad[k] = 0;
        reg_line_desc(pad, (I64)r[i], gpr_desc[i]);
    }
    puts_uart("CSRs (CSR_* / GetMStatus… ; Reg(\"mstatus\"); Man(\"Regs\")):\n");
    for (i = 0; csr_tab[i].name; i++) {
        v = csr_read_by_num(csr_tab[i].csr);
        reg_line_desc(csr_tab[i].name, v, csr_tab[i].desc);
    }
    reg_line_desc("mtime   ", *(volatile I64 *)MEM_MTIME_ADDR, "CLINT cycle (MMIO, not CSR)");
    puts_uart("Dig-down: Reg(\"sp\"); Reg(\"mstatus\"); GetMStatus; SetMStatus(v); RegHelp;\n");
    return 0;
}
__attribute__((used)) static HRT_I64 reg_one_c(void) {
    volatile U64 *r = (volatile U64 *)REGS_SNAP_BASE;
    char *name = (char *)(U64)r[10]; /* a0 at snap time */
    I64 v;
    int i, gi;
    char pad[16];
    if (!name || !name[0]) {
        puts_uart("Reg: need a name — Reg(\"sp\"); Reg(\"mstatus\"); RegHelp;\n");
        return -1;
    }
    gi = gpr_index(name);
    if (gi >= 0) {
        int k = 0, j;
        pad[k++] = 'x';
        if (gi >= 10) pad[k++] = (char)('0' + gi / 10);
        pad[k++] = (char)('0' + gi % 10);
        while (k < 4) pad[k++] = ' ';
        for (j = 0; gpr_abi[gi][j]; j++) pad[k++] = gpr_abi[gi][j];
        while (k < 8) pad[k++] = ' ';
        pad[k] = 0;
        reg_line_desc(pad, (I64)r[gi], gpr_desc[gi]);
        return (HRT_I64)r[gi];
    }
    for (i = 0; csr_tab[i].name; i++) {
        if (reg_name_eq(name, csr_tab[i].name)) {
            v = csr_read_by_num(csr_tab[i].csr);
            reg_line_desc(csr_tab[i].name, v, csr_tab[i].desc);
            puts_uart("  "); puts_uart(csr_tab[i].api);
            puts_uart(";  CSRGet(CSR_");
            for (const char *p = csr_tab[i].name; *p; p++)
                putc_uart((char)(*p >= 'a' && *p <= 'z' ? *p - 32 : *p));
            puts_uart(");\n");
            return v;
        }
    }
    if (reg_name_eq(name, "mtime")) {
        v = *(volatile I64 *)MEM_MTIME_ADDR;
        reg_line_desc("mtime   ", v, "CLINT cycle (MMIO)");
        return v;
    }
    puts_uart("Reg: unknown \""); puts_uart(name);
    puts_uart("\" — try RegHelp; or Regs;\n");
    return -1;
}
// Exec("holyc") -- compile and run one HolyC statement/definition, echoing its answer. Lets the
// editors call HolyC in place (Ed's `!`, Edit's `^E`): test the function you're editing, poke a
// register, call anything. Re-entrant (the editor is itself JIT'd code calling back in).
static HRT_I64 Exec(char *src) {
    repl_eval(src, 1, 1);
    return 0;
}
// FnAddr("name") -- resolve a function name to its entry address. The one bit of reflection that
// must touch the compiler's hash table (there is no HolyC nameof); everything HolyC-side that
// wants an address by name goes through this (e.g. Disasm("Foo") in disasm.hc).
static HRT_I64 FnAddr(char *name) {
    CHashFun *f = g_cc ? (CHashFun *)HashFind(name, g_cc->hash_table, HTT_FUN) : 0;
    return f ? (HRT_I64)f->exe_addr : 0;
}
// FnSize("name") -- the function's code size from its hash entry (TempleOS records it; 0 for a
// C builtin, whose size the compiler never saw -- Uf falls back to the ret heuristic there).
static HRT_I64 FnSize(char *name) {
    CHashFun *f = g_cc ? (CHashFun *)HashFind(name, g_cc->hash_table, HTT_FUN) : 0;
    return f ? (HRT_I64)f->size : 0;
}

// The reverse of FnAddr: addr -> the function that contains it. There is no per-entry size in the
// hash table, so we symbolize by nearest-below -- the function with the greatest exe_addr <= addr.
// SymBase returns that entry's exe_addr (0 if none below), so HolyC's disassembler can print
// `<Name+0xoff>` with off = addr - SymBase(addr). SymName returns the name pointer (0 if none).
// Both walk the same HTT_FUN entries Funs() lists.
static CHashFun *SymNearest(HRT_I64 addr) {
    if (!g_cc || !g_cc->hash_table) return 0;
    CHashTable *h = g_cc->hash_table;
    CHashFun *best = 0;
    for (I64 b = 0; b <= h->mask; b++)
        for (CHashEntry *e = h->body[b]; e; e = e->next)
            if ((e->type & HTT_FUN)) {
                CHashFun *f = (CHashFun *)e;
                if (f->exe_addr && (I64)f->exe_addr <= (I64)addr &&
                    (f->size == 0 || (I64)addr < (I64)f->exe_addr + f->size) &&   // sized: must contain addr
                    (!best || (I64)f->exe_addr > (I64)best->exe_addr))
                    best = f;
            }
    return best;
}
static HRT_I64 SymBase(HRT_I64 addr) { CHashFun *f = SymNearest(addr); return f ? (HRT_I64)f->exe_addr : 0; }
static HRT_I64 SymName(HRT_I64 addr) { CHashFun *f = SymNearest(addr); return f && f->str ? (HRT_I64)f->str : 0; }
// FunSegFind(addr, &off) -- TempleOS's reverse map: name of the symbol containing addr, offset
// written through the pointer. THE debugging primitive: faults, backtraces, and Da() all print
// Foo+0x34 through this instead of raw PCs.
static HRT_I64 FunSegFind(HRT_I64 addr, HRT_I64 off_p) {
    CHashFun *f = SymNearest(addr);
    if (!f) { if (off_p) *(I64 *)off_p = 0; return 0; }
    if (off_p) *(I64 *)off_p = (I64)addr - (I64)f->exe_addr;
    return f->str ? (HRT_I64)f->str : 0;
}
// SrcText("name") -- defining source unit, or an optional DOC_FILES Man block (none today).
static HRT_I64 SrcText(char *name) {
    const char *s = srcmap_get(name);
    if (s) return (HRT_I64)s;
    return (HRT_I64)doc_text_for(name);
}

/* Host ABI slots at 0x87001000 — NOT hash-table builtins. HolyC reads these; the only
 * host services are the bootstrap compiler entry (HcCompileSrc) and published pointers
 * into bootstrap state (UART ring, hash table, srcmap, err metadata, trap name). */
#define HC_SLOT_BASE        0x87001000UL
#define HC_SLOT_COMPILE     (HC_SLOT_BASE + 0x00)
#define HC_SLOT_RUN_FILE    (HC_SLOT_BASE + 0x08)  /* char g_run_file[64] */
/* 0x10 / 0x18: retired MEMFS/CWD publishes — HolyC owns arena at MEMFS_PHYS_BASE */
#define HC_SLOT_UART_RX     (HC_SLOT_BASE + 0x20)
#define HC_SLOT_UART_RH     (HC_SLOT_BASE + 0x28)
#define HC_SLOT_UART_RT     (HC_SLOT_BASE + 0x30)
#define HC_SLOT_UART_CAP    (HC_SLOT_BASE + 0x38)
#define HC_SLOT_CC          (HC_SLOT_BASE + 0x40)
#define HC_SLOT_SRCMAP      (HC_SLOT_BASE + 0x48)
#define HC_SLOT_SRCMAP_MAX  (HC_SLOT_BASE + 0x50)
#define HC_SLOT_TRAP_NAME   (HC_SLOT_BASE + 0x58)
#define HC_SLOT_TRAP_DISP   (HC_SLOT_BASE + 0x60)
#define HC_SLOT_TRAP_VEC    (HC_SLOT_BASE + 0x68)
#define HC_SLOT_HASH        (HC_SLOT_BASE + 0x70)
#define HC_SLOT_CALL_ED     (HC_SLOT_BASE + 0x78)
#define HC_SLOT_REENTRY     (HC_SLOT_BASE + 0x80)
#define HC_SLOT_UART_DRAIN  (HC_SLOT_BASE + 0x88)  /* unused — HolyC UartRxDrain */
#define HC_SLOT_UART_GET    (HC_SLOT_BASE + 0xB0)  /* unused — HolyC HcUartGet */
#define HC_SLOT_ED          (HC_SLOT_BASE + 0xB8)  /* HRT_I64 (*)(char*) — C Ed (HolyC loads once, then calls) */
#define HC_SLOT_FMT         (HC_SLOT_BASE + 0xC0)  /* I64 (*)(char *src) — HolyFmtSrc into g_fmt_buf */
#define HC_SLOT_FMT_BUF     (HC_SLOT_BASE + 0xC8)  /* char g_fmt_buf[65536] */
#define HC_SLOT_FMT_FILE    (HC_SLOT_BASE + 0xD8)  /* I64 (*)(char *name) — format memfs file in place */
#define HC_SLOT_TERM_KEYGET (HC_SLOT_BASE + 0xD0)  /* HRT_I64 (*)(void) — C TermKeyGet repair hatch */
#define HC_SLOT_EDIT        (HC_SLOT_BASE + 0xE0)  /* HRT_I64 (*)(char*) — C Edit */
#define HC_SLOT_CALLERS     (HC_SLOT_BASE + 0xE8)  /* HRT_I64 (*)(char*) — C CallersScan */
/* 0xF0..0x108: retired TERM_PROBE/ROWS/COLS/FLAGS — HolyC term.hc owns geometry */
#define HC_SLOT_TERM_SETSZ  (HC_SLOT_BASE + 0x110) /* HRT_I64 (*)(I64,I64) — C TermSetSize */
/* Inspection APIs kept in C (live JIT sizes / GPR snap / callers_buf). HolyC once-indirects. */
#define HC_SLOT_CALLER_NAME (HC_SLOT_BASE + 0x118) /* HRT_I64 (*)(I64) — C CallerName → char* */
#define HC_SLOT_CALLER_CNT  (HC_SLOT_BASE + 0x120) /* HRT_I64 (*)(void) — C CallerCnt */
#define HC_SLOT_MEMMAP      (HC_SLOT_BASE + 0x128) /* HRT_I64 (*)(void) — C MemMap */
#define HC_SLOT_REGS        (HC_SLOT_BASE + 0x130) /* HRT_I64 (*)(void) — regs_snap_stub */
#define HC_SLOT_STKREP      (HC_SLOT_BASE + 0x138) /* HRT_I64 (*)(void) — C StkRep */
/* ErrGo metadata — HolyC ErrGo reads these; no RuntimeRegister */
#define HC_SLOT_ERR_FILE    (HC_SLOT_BASE + 0x158) /* char * → g_err_file */
#define HC_SLOT_ERR_LINE    (HC_SLOT_BASE + 0x160) /* I64 * → g_err_line */
#define HC_SLOT_ERR_COL     (HC_SLOT_BASE + 0x168) /* I64 * → g_err_col */
#define HC_SLOT_ERR_HAVE    (HC_SLOT_BASE + 0x170) /* I64 * → g_err_have */
/* #define table (HTT_DEFINE_STR) — Tab completes MEM_* / UART_* / … from live macros */
#define HC_SLOT_DEFINE      (HC_SLOT_BASE + 0x178) /* CHashTable * → cc->define_table */
/* HC_SLOT_CODE_BASE / HEAP_BASE / REG_ONE: see MemMap section (0x140/0x148/0x150) */

static HRT_I64 HcCompileSrc(char *src) {
    if (!src) return -1;
    run_source(src);
    return 0;
}

/* HolyC FmtSrc calls here once-indirect (a0=src only). Result text at HC_SLOT_FMT_BUF. */
static HRT_I64 HcFmtSrc(char *src) {
    if (!src) return -1;
    return (HRT_I64)HolyFmtSrc(src, g_fmt_buf, (long long)sizeof(g_fmt_buf));
}

static void HostSlotsInstall(Compiler *cc) {
    *(volatile U64 *)HC_SLOT_COMPILE    = (U64)&HcCompileSrc;
    *(volatile U64 *)HC_SLOT_RUN_FILE   = (U64)&g_run_file[0];
    *(volatile U64 *)HC_SLOT_UART_RX    = (U64)&uart_rx[0];
    *(volatile U64 *)HC_SLOT_UART_RH    = (U64)&uart_rh;
    *(volatile U64 *)HC_SLOT_UART_RT    = (U64)&uart_rt;
    *(volatile U64 *)HC_SLOT_UART_CAP   = (U64)UART_RX_CAP;
    *(volatile U64 *)HC_SLOT_CC         = (U64)&g_cc;
    *(volatile U64 *)HC_SLOT_SRCMAP     = (U64)&srcmap[0];
    *(volatile U64 *)HC_SLOT_SRCMAP_MAX = (U64)SRCMAP_MAX;
    *(volatile U64 *)HC_SLOT_TRAP_NAME  = TRAP_NAME_FIXED;
    *(volatile U64 *)HC_SLOT_TRAP_DISP  = (U64)&trapvec;
    *(volatile U64 *)HC_SLOT_TRAP_VEC   = (U64)&TrapVec;
    *(volatile U64 *)HC_SLOT_HASH       = cc && cc->hash_table ? (U64)cc->hash_table : 0;
    *(volatile U64 *)HC_SLOT_DEFINE     = cc && cc->define_table ? (U64)cc->define_table : 0;
    *(volatile U64 *)HC_SLOT_CALL_ED    = (U64)&call_editor;
    *(volatile U64 *)HC_SLOT_REENTRY    = (U64)&repl_reentry;
    *(volatile U64 *)HC_SLOT_UART_DRAIN = (U64)&uart_hw_drain;
    *(volatile U64 *)HC_SLOT_UART_GET   = (U64)&UartGet;
    *(volatile U64 *)HC_SLOT_ED         = (U64)&Ed;
    *(volatile U64 *)HC_SLOT_FMT        = (U64)&HcFmtSrc;
    *(volatile U64 *)HC_SLOT_FMT_BUF    = (U64)&g_fmt_buf[0];
    *(volatile U64 *)HC_SLOT_FMT_FILE   = (U64)&HcFmtFile;
    *(volatile U64 *)HC_SLOT_TERM_KEYGET = (U64)&TermKeyGet;
    *(volatile U64 *)HC_SLOT_EDIT        = (U64)&Edit;
    *(volatile U64 *)HC_SLOT_CALLERS     = (U64)&CallersScan;
    *(volatile U64 *)HC_SLOT_TERM_SETSZ  = (U64)&TermSetSize;
    *(volatile U64 *)HC_SLOT_CALLER_NAME = (U64)&CallerName;
    *(volatile U64 *)HC_SLOT_CALLER_CNT  = (U64)&CallerCnt;
    *(volatile U64 *)HC_SLOT_MEMMAP      = (U64)&MemMap;
    *(volatile U64 *)HC_SLOT_REGS        = (U64)&regs_snap_stub;
    *(volatile U64 *)HC_SLOT_STKREP      = (U64)&StkRep;
    *(volatile U64 *)HC_SLOT_ERR_FILE    = (U64)&g_err_file[0];
    *(volatile U64 *)HC_SLOT_ERR_LINE    = (U64)&g_err_line;
    *(volatile U64 *)HC_SLOT_ERR_COL     = (U64)&g_err_col;
    *(volatile U64 *)HC_SLOT_ERR_HAVE    = (U64)&g_err_have;
    *(volatile U64 *)HC_SLOT_CODE_BASE   = (U64)&code_mem[0];
    *(volatile U64 *)HC_SLOT_HEAP_BASE   = (U64)&heap_mem[0];
    *(volatile U64 *)HC_SLOT_REG_ONE     = (U64)&reg_one_stub;
}

static void RuntimeInit(Compiler *cc) {
    // Fs + host slots only. No TempleOS RuntimeRegister — OS APIs are HolyC seeds.
    if (cc->fs_var && cc->except_ch_var) *(I64 *)cc->fs_var->data_addr = (I64)cc->except_ch_var->data_addr;
    HostSlotsInstall(cc);
}

/* C-side seed boot (before HolyC Run exists). Order matches gen_boot_blob.py BOOT_ORDER.
 * Per-seed Run() so SrcFile / FunSec map to real seed names (blob boot collapses to boot_blob.hc). */
static void BootHolyCRuntime(void) {
    static const char *order[] = {
        "MemMapSelected.hc", /* Kconfig MEM_*; must precede uart.hc / csr.hc */
        "uart.hc", "mem.hc", "print.hc", "str.hc", "fs.hc", "run.hc",
        "math.hc", "term.hc", "sym.hc", "csr.hc",
        "ds.hc", "ds_csr.hc", "ds_uart.hc", "ds_clint.hc", "ds_plic.hc",
        "fmt.hc",
        "dir.hc", "asm_complete.hc", "complete.hc", "ed.hc", "edit.hc", "start.hc", "trap.hc",
        "debug.hc", "disasm.hc", "vim.hc", "RVEditorSelected.hc",
        "man.hc", "files.hc", "funs.hc", "callers.hc", "boot.hc",
        0
    };
    int i;
    for (i = 0; order[i]; i++) {
        HostSlotsInstall(g_cc); /* refresh hash/define pointers after Compiler grows */
        if (g_cc && g_cc->hash_table)
            *(volatile U64 *)HC_SLOT_HASH = (U64)g_cc->hash_table;
        if (g_cc && g_cc->define_table)
            *(volatile U64 *)HC_SLOT_DEFINE = (U64)g_cc->define_table;
        Run((char *)order[i]);
    }
    (void)repl_boot_blob; /* keep embed linked for make repl-blob */
}

// ---- REPL line editor: history (Up/Down) + Tab completion --------------------------------
// History records each completed compile unit (full accum buffer — multi-line functions as one
// entry with embedded newlines). Up/Down walk the ring; any edit leaves history browse mode
// but keeps the recalled text. Tab completes the token before the cursor: path-like
// tokens (contain '.' or '/', or follow '"') against memfs names (cwd-relative); otherwise
// against HTT_FUN|HTT_GLBL_VAR plus #defines (HTT_DEFINE_STR: MEM_*, UART_*, …) from the
// live define_table (case-insensitive). Inside asm{}: opcodes / GPRs / CSR names
// (tables mirror bootstrap/seed/asm_complete.hc). One match fills with canonical casing;
// several share a common prefix (also CI) or are listed.
#define HIST_MAX 48
#define HIST_LINE_CAP 512
#define HIST_UNIT_CAP 4096
#define HIST_CAP HIST_LINE_CAP
#define COMP_MAX 64
#define RL_ASM_OP 0
#define RL_ASM_REG 1
#define RL_ASM_CSR 2
#define RL_ASM_NONE 3

static char hist_ring[HIST_MAX][HIST_UNIT_CAP];
static int hist_n, hist_head;   /* n entries; head = next write slot */
static int g_rl_hist_age = -1;  /* Up/Down browse index; persists across read_line calls */
static const char *g_rl_hist_recall_unit; /* multiline Up: full entry for repl() */
static const char *g_rl_prefill;          /* optional line prefill before read */
static int g_rl_ctrlc_hit;
static int g_rl_hist_accum_clear; /* Down/single-line recall: drop partial multiline accum */
static char g_rl_hist_lastline[HIST_LINE_CAP];
static const char *g_rl_accum;
static int g_rl_accum_len;

static void rl_set_accum_ctx(const char *acc, int len) {
    g_rl_accum = acc;
    g_rl_accum_len = len > 0 ? len : 0;
}

/* Keep in sync with bootstrap/seed/asm_complete.hc AsmCompOps / Regs / Csrs. */
static const char *const rl_asm_ops[] = {
    "add","addi","and","andi","or","ori","xor","xori",
    "sub","sll","slli","srl","srli","sra","srai","slt","slti","sltu",
    "mul","div","divu","rem","remu",
    "lui","auipc","li","mv","not","neg",
    "ld","lw","lwu","lh","lhu","lb","lbu","sd","sw","sh","sb",
    "jalr","j","call","beq","bne","blt","bge","bltu","bgeu","beqz","bnez",
    "ret","nop","wfi","mret","sret","ecall","ebreak","fencei","fence.i",
    "csrr","csrw","csrs","csrrw","csrrs","csrrc",
    "csrrwi","csrrsi","csrrci","csrwi","csrsi","csrci",
    "rdtime","sfencevma","lifp",
    "lr.d","lr.w","lrd","lrw","sc.d","sc.w","scd","scw",
    "amoswap.d","amoadd.d","amoxor.d","amoand.d","amoor.d",
    "amomin.d","amomax.d","amominu.d","amomaxu.d",
    "amoswap.w","amoadd.w","amoxor.w","amoand.w","amoor.w",
    "amomin.w","amomax.w","amominu.w","amomaxu.w",
    "amoswapd","amoaddd","amoxord","amoandd","amoord",
    "amomind","amomaxd","amominud","amomaxud",
    "amoswapw","amoaddw","amoxorw","amoandw","amoorw",
    "amominw","amomaxw","amominuw","amomaxuw",
    "fsqrtd","faddd","fsubd","fmuld","fdivd","fled","fltd","feqd",
    "fmvdx","fmvxd","fcvtdl","fcvtld_rtz","fcvtld_rdn","fcvtld_rmm",
    0
};
static const char *const rl_asm_regs[] = {
    "zero","ra","sp","gp","tp","fp",
    "t0","t1","t2","t3","t4","t5","t6",
    "s0","s1","s2","s3","s4","s5","s6","s7","s8","s9","s10","s11",
    "a0","a1","a2","a3","a4","a5","a6","a7",
    "x0","x1","x2","x3","x4","x5","x6","x7","x8","x9",
    "x10","x11","x12","x13","x14","x15","x16","x17",
    "x18","x19","x20","x21","x22","x23","x24","x25",
    "x26","x27","x28","x29","x30","x31",
    "ft0","ft1","ft2","ft3","ft4","ft5","ft6","ft7","ft8","ft9","ft10","ft11",
    "fs0","fs1","fs2","fs3","fs4","fs5","fs6","fs7","fs8","fs9","fs10","fs11",
    "fa0","fa1","fa2","fa3","fa4","fa5","fa6","fa7",
    "f0","f1","f2","f3","f4","f5","f6","f7","f8","f9",
    "f10","f11","f12","f13","f14","f15","f16","f17",
    "f18","f19","f20","f21","f22","f23","f24","f25",
    "f26","f27","f28","f29","f30","f31",
    0
};
static const char *const rl_asm_csrs[] = {
    "mstatus","misa","medeleg","mideleg","mie","mtvec","mcounteren",
    "mscratch","mepc","mcause","mtval","mip",
    "mcycle","minstret","cycle","time","instret","mhartid",
    "sstatus","sie","stvec","sscratch","sepc","scause","stval","sip","satp",
    0
};

static void hist_push(const char *line) {
    int i = 0;
    if (!line || !line[0]) return;
    if (hist_n > 0) {
        int prev = hist_head ? hist_head - 1 : HIST_MAX - 1;
        if (!strcmp(hist_ring[prev], line)) return;
    }
    while (line[i] && i < HIST_UNIT_CAP - 1) { hist_ring[hist_head][i] = line[i]; i++; }
    hist_ring[hist_head][i] = 0;
    hist_head = (hist_head + 1) % HIST_MAX;
    if (hist_n < HIST_MAX) hist_n++;
}
static void hist_push_unit(const char *unit, int ulen) {
    int s = 0, e = ulen - 1;
    if (!unit || ulen <= 0) return;
    while (s < ulen && (unit[s] == ' ' || unit[s] == '\t' || unit[s] == '\n')) s++;
    while (e >= s && (unit[e] == ' ' || unit[e] == '\t' || unit[e] == '\n')) e--;
    if (e < s) return;
    {
        char norm[HIST_UNIT_CAP];
        int n = e - s + 1;
        if (n >= HIST_UNIT_CAP) n = HIST_UNIT_CAP - 1;
        for (int i = 0; i < n; i++) norm[i] = unit[s + i];
        norm[n] = 0;
        hist_push(norm);
    }
}
static void repl_set_prefill(const char *line) { g_rl_prefill = line; }
static void repl_scan_depths(const char *text, int n, int *bd, int *pd) {
    int brace = 0, paren = 0;
    for (int i = 0; i < n; i++) {
        char ch = text[i];
        if (ch == '"' || ch == '\'') {
            char q = ch;
            i++;
            while (i < n && text[i] != q) {
                if (text[i] == '\\' && i + 1 < n) i++;
                i++;
            }
            continue;
        }
        if (ch == '{') brace++;
        else if (ch == '}') { if (brace > 0) brace--; }
        else if (ch == '(') paren++;
        else if (ch == ')') { if (paren > 0) paren--; }
    }
    *bd = brace; *pd = paren;
}
/* Multiline Up: replay prefix lines, return last line length in input (for editing). */
static int repl_hist_recall_multiline(const char *unit, char *input, int input_max,
                                      char *accum, int accum_max, int *accum_len,
                                      int *bd, int *pd) {
    const char *last_nl = 0, *p = unit;
    int ulen = 0;
    if (!unit) return 0;
    while (unit[ulen]) ulen++;
    repl_scan_depths(unit, ulen, bd, pd);
    while (*p) {
        const char *nl = strchr(p, '\n');
        if (!nl) break;
        last_nl = nl;
        p = nl + 1;
    }
    if (!last_nl) {
        int i = 0;
        while (unit[i] && i < input_max - 1) { input[i] = unit[i]; i++; }
        input[i] = 0;
        *accum_len = 0;
        return i;
    }
    {
        int prefix = (int)(last_nl - unit) + 1;
        if (prefix >= accum_max) prefix = accum_max - 1;
        for (int i = 0; i < prefix; i++) accum[i] = unit[i];
        accum[prefix] = 0;
        *accum_len = prefix;
    }
    p = unit;
    puts_uart("\n");
    {
        int first = 1;
        while (p <= last_nl) {
            const char *nl = strchr(p, '\n');
            if (!nl || nl > last_nl) break;
            if (first) { puts_uart("> "); first = 0; }
            else puts_uart("... ");
            for (const char *q = p; q < nl; q++) putc_uart(*q);
            puts_uart("\n");
            p = nl + 1;
        }
    }
    {
        const char *last = last_nl + 1;
        int llen = 0;
        while (last[llen] && last[llen] != '\n') llen++;
        if (llen >= input_max) llen = input_max - 1;
        for (int i = 0; i < llen; i++) input[i] = last[i];
        input[llen] = 0;
        for (int i = 0; i < llen && i < HIST_LINE_CAP - 1; i++) g_rl_hist_lastline[i] = last[i];
        g_rl_hist_lastline[llen < HIST_LINE_CAP ? llen : HIST_LINE_CAP - 1] = 0;
        return llen;
    }
}
static const char *hist_get(int age) {   /* 0 = most recent */
    if (age < 0 || age >= hist_n) return 0;
    int idx = hist_head - 1 - age;
    while (idx < 0) idx += HIST_MAX;
    return hist_ring[idx];
}
/* Boot demos: push oldest→newest so first Up recalls Help;, then 1+2*3;, … */
static void hist_seed(void) {
    static const char *const seed[] = {
        "Fmt(\"boot.hc\");",
        "Uf(\"Print\");",
        "asm { li a7,4 addi a7,a7,-1 }; Reg(\"a7\");",
        "Cat(\"boot.hc\");",
        "Dir;",
        "Regs;",
        "MemMap;",
        "Src(\"Dir\");",
        "Man(\"Print\");",
        "Man(\"Clint\");",
        "1+2*3;",
        "Help;",
        0
    };
    for (int i = 0; seed[i]; i++) hist_push(seed[i]);
}

static int rl_ident(int c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || c == '_';
}
static int rl_pathchar(int c) {
    return rl_ident(c) || c == '.' || c == '/' || c == '-' || c == '+';
}
static int rl_ch_eq_i(int a, int b) {
    if (a >= 'A' && a <= 'Z') a += 32;
    if (b >= 'A' && b <= 'Z') b += 32;
    return a == b;
}
static int rl_prefix_eq(const char *s, const char *p, int plen) {
    int i = 0;
    while (i < plen) {
        if (!s[i] || !rl_ch_eq_i((unsigned char)s[i], (unsigned char)p[i])) return 0;
        i++;
    }
    return 1;
}
static int rl_common_prefix(const char **names, int n) {
    int i = 0;
    if (n <= 0) return 0;
    for (;;) {
        char c = names[0][i];
        if (!c) return i;
        for (int j = 1; j < n; j++)
            if (!names[j][i] || !rl_ch_eq_i((unsigned char)names[j][i], (unsigned char)c))
                return i;
        i++;
    }
}
static void rl_add_match(const char **out, int *n, const char *s, const char *pfx, int plen) {
    int i;
    if (!s || !s[0] || *n >= COMP_MAX) return;
    if (!rl_prefix_eq(s, pfx, plen)) return;
    for (i = 0; i < *n; i++) if (!strcmp(out[i], s)) return;
    out[(*n)++] = s;
}
static int rl_str_eq_i(const char *a, const char *b) {
    int i = 0;
    if (!a || !b) return 0;
    while (a[i] || b[i]) {
        if (!rl_ch_eq_i((unsigned char)a[i], (unsigned char)b[i])) return 0;
        i++;
    }
    return 1;
}
static int rl_asm_csr_opnd(const char *mn) {
    if (rl_str_eq_i(mn, "csrw") || rl_str_eq_i(mn, "csrs") ||
        rl_str_eq_i(mn, "csrwi") || rl_str_eq_i(mn, "csrsi") ||
        rl_str_eq_i(mn, "csrci")) return 0;
    if (rl_str_eq_i(mn, "csrr") || rl_str_eq_i(mn, "csrrw") ||
        rl_str_eq_i(mn, "csrrs") || rl_str_eq_i(mn, "csrrc") ||
        rl_str_eq_i(mn, "csrrwi") || rl_str_eq_i(mn, "csrrsi") ||
        rl_str_eq_i(mn, "csrrci")) return 1;
    return -1;
}
static int rl_asm_imm_opnd(const char *mn) {
    if (rl_str_eq_i(mn, "li") || rl_str_eq_i(mn, "lui") ||
        rl_str_eq_i(mn, "auipc") || rl_str_eq_i(mn, "lifp")) return 1;
    if (rl_str_eq_i(mn, "addi") || rl_str_eq_i(mn, "andi") ||
        rl_str_eq_i(mn, "ori") || rl_str_eq_i(mn, "xori") ||
        rl_str_eq_i(mn, "slti") || rl_str_eq_i(mn, "slli") ||
        rl_str_eq_i(mn, "srli") || rl_str_eq_i(mn, "srai")) return 2;
    if (rl_str_eq_i(mn, "csrrwi") || rl_str_eq_i(mn, "csrrsi") ||
        rl_str_eq_i(mn, "csrrci")) return 2;
    if (rl_str_eq_i(mn, "csrwi") || rl_str_eq_i(mn, "csrsi") ||
        rl_str_eq_i(mn, "csrci")) return 1;
    return -1;
}
static int rl_asm_tokchar(int c) {
    return rl_ident(c) || c == '.' || c == '-' || c == '+';
}
static int rl_asm_inside(const char *pre, int npre, const char *buf, int cur) {
    int st = 0, depth = 0, i, c, q;
    const char *chunks[2];
    int lens[2];
    int ci;
    chunks[0] = pre; lens[0] = npre;
    chunks[1] = buf; lens[1] = cur;
    for (ci = 0; ci < 2; ci++) {
        const char *s = chunks[ci];
        int n = lens[ci];
        if (!s || n <= 0) continue;
        for (i = 0; i < n; i++) {
            c = (unsigned char)s[i];
            if (c == '"' || c == '\'') {
                q = c; i++;
                while (i < n && (unsigned char)s[i] != q) {
                    if (s[i] == '\\' && i + 1 < n) i++;
                    i++;
                }
                if (st == 1) st = 0;
                continue;
            }
            if (st == 0 && rl_ident(c) && (i == 0 || !rl_ident((unsigned char)s[i - 1]))) {
                if ((c == 'a' || c == 'A') && i + 2 < n &&
                    rl_ch_eq_i((unsigned char)s[i + 1], 's') &&
                    rl_ch_eq_i((unsigned char)s[i + 2], 'm') &&
                    (i + 3 >= n || !rl_ident((unsigned char)s[i + 3]))) {
                    st = 1; i += 2; continue;
                }
            }
            if (st == 1) {
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;
                if (c == '{') { st = 2; depth = 1; continue; }
                st = 0;
            }
            if (st == 2) {
                if (c == '{') depth++;
                else if (c == '}') {
                    if (depth > 0) depth--;
                    if (depth == 0) st = 0;
                }
            }
        }
    }
    return st == 2 && depth > 0;
}
static int rl_asm_kind(const char *buf, int cur) {
    int i = cur, start, t0, commas = 0, opnd, csr_i, imm_i, j;
    char mn[48];
    while (i > 0 && rl_asm_tokchar((unsigned char)buf[i - 1])) i--;
    start = i;
    while (start > 0) {
        char c = buf[start - 1];
        if (c == '{' || c == ';' || c == '\n') break;
        start--;
    }
    while (start < i && (buf[start] == ' ' || buf[start] == '\t')) start++;
    t0 = start;
    while (t0 < i && rl_asm_tokchar((unsigned char)buf[t0])) t0++;
    if (t0 == i) return RL_ASM_OP;
    j = 0;
    while (start + j < t0 && j < 47) { mn[j] = buf[start + j]; j++; }
    mn[j] = 0;
    while (t0 < i) { if (buf[t0] == ',') commas++; t0++; }
    opnd = commas;
    csr_i = rl_asm_csr_opnd(mn);
    if (csr_i >= 0 && opnd == csr_i) return RL_ASM_CSR;
    imm_i = rl_asm_imm_opnd(mn);
    if (imm_i >= 0 && opnd == imm_i) return RL_ASM_NONE;
    return RL_ASM_REG;
}
static int rl_collect_asm(const char **out, int kind, const char *pfx, int plen) {
    int n = 0, i;
    const char *const *list;
    if (kind == RL_ASM_NONE) return 0;
    if (kind == RL_ASM_OP) list = rl_asm_ops;
    else if (kind == RL_ASM_CSR) list = rl_asm_csrs;
    else list = rl_asm_regs;
    for (i = 0; list[i]; i++) rl_add_match(out, &n, list[i], pfx, plen);
    return n;
}
static int rl_collect_syms(const char **out, const char *pfx, int plen) {
    int n = 0;
    if (!g_cc) return 0;
    if (g_cc->hash_table) {
        CHashTable *h = g_cc->hash_table;
        for (I64 b = 0; b <= h->mask && n < COMP_MAX; b++)
            for (CHashEntry *e = h->body[b]; e && n < COMP_MAX; e = e->next)
                if ((e->type & (HTT_FUN | HTT_GLBL_VAR)) && e->str)
                    rl_add_match(out, &n, e->str, pfx, plen);
    }
    /* Live #defines (csr.hc MEM_*, UART_*, VIRTIO_*, …) — same table the lexer expands. */
    if (g_cc->define_table) {
        CHashTable *d = g_cc->define_table;
        for (I64 b = 0; b <= d->mask && n < COMP_MAX; b++)
            for (CHashEntry *e = d->body[b]; e && n < COMP_MAX; e = e->next)
                if ((e->type & HTT_DEFINE_STR) && e->str)
                    rl_add_match(out, &n, e->str, pfx, plen);
    }
    return n;
}
static int rl_collect_files(const char **out, const char *pfx, int plen) {
    int n = 0, cl = 0;
    while (memfs_cwd[cl]) cl++;
    for (int i = 0; i < MEMFS_MAX_FILES && n < COMP_MAX; i++) {
        if (!memfs[i].used) continue;
        const char *nm = memfs[i].name;
        int k = 0; while (k < cl && nm[k] == memfs_cwd[k]) k++;
        if (k != cl) continue;
        const char *rest = nm + cl;
        if (rest[0] == '.') continue;   /* .dir markers */
        rl_add_match(out, &n, rest, pfx, plen);
        /* also match full stored name if the user typed past cwd */
        if (cl) rl_add_match(out, &n, nm, pfx, plen);
    }
    return n;
}

static void rl_redraw(const char *prompt, const char *buf, int len, int cur) {
    putc_uart('\r');
    TermClearEol();
    if (prompt) puts_uart(prompt);
    for (int i = 0; i < len; i++) putc_uart(buf[i]);
    for (int i = len; i > cur; i--) putc_uart('\b');
}

static void rl_set_from(char *buf, int max, int *len, int *cur, const char *src) {
    int i = 0;
    if (!src) src = "";
    while (src[i] && i < max - 1) { buf[i] = src[i]; i++; }
    buf[i] = 0; *len = i; *cur = i;
}

static int rl_complete_core(char *buf, int max, int *len, int *cur, int list_ok) {
    int end = *cur, start = end, pathish = 0, nm = 0, fill, i, old, delta, need, in_asm, akind;
    const char *matches[COMP_MAX];
    char pfx[HIST_CAP];
    if (end > 0 && (buf[end - 1] == '"' || buf[end - 1] == '\'')) return 0;
    while (start > 0 && rl_pathchar((unsigned char)buf[start - 1])) start--;
    if (start < end) {
        for (i = start; i < end; i++)
            if (buf[i] == '.' || buf[i] == '/') pathish = 1;
        if (start > 0 && buf[start - 1] == '"') pathish = 1;
    }
    if (end - start >= HIST_CAP) return 0;
    for (i = 0; i < end - start; i++) pfx[i] = buf[start + i];
    pfx[i] = 0;
    in_asm = rl_asm_inside(g_rl_accum, g_rl_accum_len, buf, end);
    if (in_asm && !pathish) {
        akind = rl_asm_kind(buf, end);
        nm = rl_collect_asm(matches, akind, pfx, end - start);
        if (!nm) return 0;
    } else if (pathish) nm = rl_collect_files(matches, pfx, end - start);
    else {
        nm = rl_collect_syms(matches, pfx, end - start);
        if (!nm) nm = rl_collect_files(matches, pfx, end - start);
    }
    if (!nm) return 0;
    old = end - start;
    fill = (nm == 1) ? (int)strlen(matches[0]) : rl_common_prefix(matches, nm);
    delta = fill - old;
    if (*len + delta >= max) {
        delta = max - 1 - *len;
        fill = old + delta;
        if (fill < old) fill = old;
        delta = fill - old;
    }
    need = (delta != 0);
    if (!need)
        for (i = 0; i < fill; i++)
            if (buf[start + i] != matches[0][i]) { need = 1; break; }
    if (need && fill >= 0) {
        if (delta > 0) {
            for (i = *len; i >= end; i--) buf[i + delta] = buf[i];
        } else if (delta < 0) {
            for (i = end; i <= *len; i++) buf[i + delta] = buf[i];
        }
        for (i = 0; i < fill; i++) buf[start + i] = matches[0][i];
        *len += delta; *cur = start + fill; buf[*len] = 0;
    }
    if (list_ok && nm > 1 && fill <= old) {
        puts_uart("\n");
        for (i = 0; i < nm; i++) {
            puts_uart("  "); puts_uart(matches[i]); puts_uart("\n");
        }
        return nm; /* caller redraws after list */
    }
    return need ? nm : (nm > 0 ? nm : 0);
}

static int rl_do_complete(char *buf, int max, int *len, int *cur, const char *prompt) {
    int nm = rl_complete_core(buf, max, len, cur, 1);
    if (nm) rl_redraw(prompt, buf, *len, *cur);
    return nm;
}

/* Editor/plain Tab: complete a partial token; otherwise 2-space indent. */
static void rl_smart_tab(char *buf, int max, int *len, int *cur, const char *prompt) {
    if (*cur > 0 && rl_pathchar((unsigned char)buf[*cur - 1])) {
        rl_do_complete(buf, max, len, cur, prompt);
        return;
    }
    if (*len + 2 < max) {
        for (int t = 0; t < 2; t++) {
            for (int i = *len; i >= *cur; i--) buf[i + 1] = buf[i];
            buf[(*cur)++] = ' '; (*len)++;
        }
        if (prompt) rl_redraw(prompt, buf, *len, *cur);
    }
}

// Read one line via TermKeyGet. flags: RL_HIST / RL_COMPLETE / RL_NO_AUTO_HIST. Returns length,
// or RL_MULTILINE_RECALL when Up selects a multiline history entry (see g_rl_hist_recall_unit).
static int repl_read_line_ex(char *buf, int max, int flags, const char *prompt) {
    int len = 0, cur = 0;
    char draft[HIST_LINE_CAP];
    if (!prompt) prompt = "> ";
    draft[0] = 0;
    buf[0] = 0;
    if (max > HIST_LINE_CAP) max = HIST_LINE_CAP;
    if (g_rl_prefill) {
        rl_set_from(buf, max, &len, &cur, g_rl_prefill);
        g_rl_prefill = NULL;
    }
    /* Abandon half-parsed ESC/CSI left by a prior full-screen redraw timeout. */
    term.state = TS_GROUND;
    term.esc_at = 0;
    rl_redraw(prompt, buf, len, cur);

    while (1) {
        I64 k = TermKeyGet();
        if (k == 0) continue;

        if ((flags & RL_HIST) && (k == KEY_UP || k == KEY_DOWN)) {
            if (k == KEY_UP) {
                if (g_rl_hist_age + 1 >= hist_n) continue;
                if (g_rl_hist_age < 0) {
                    int i = 0; while (i < len && i < HIST_LINE_CAP - 1) { draft[i] = buf[i]; i++; }
                    draft[i] = 0;
                }
                g_rl_hist_age++;
                {
                    const char *ent = hist_get(g_rl_hist_age);
                    if (ent && strchr(ent, '\n')) {
                        g_rl_hist_recall_unit = ent;
                        buf[0] = 0;
                        return RL_MULTILINE_RECALL;
                    }
                    rl_set_from(buf, max, &len, &cur, ent);
                }
                rl_redraw(prompt, buf, len, cur);
                continue;
            }
            /* KEY_DOWN */
            if (g_rl_hist_age < 0) continue;
            g_rl_hist_age--;
            if (g_rl_hist_age < 0) {
                rl_set_from(buf, max, &len, &cur, draft);
                g_rl_hist_accum_clear = 1;
            } else {
                const char *ent = hist_get(g_rl_hist_age);
                if (ent && strchr(ent, '\n')) {
                    g_rl_hist_recall_unit = ent;
                    buf[0] = 0;
                    return RL_MULTILINE_RECALL;
                }
                rl_set_from(buf, max, &len, &cur, ent);
                g_rl_hist_accum_clear = 1;
            }
            rl_redraw(prompt, buf, len, cur);
            continue;
        }

        if (k == KEY_LEFT) {
            if (cur > 0) { cur--; putc_uart('\b'); }
            continue;
        }
        if (k == KEY_RIGHT) {
            if (cur < len) { putc_uart(buf[cur]); cur++; }
            continue;
        }
        if (k == KEY_HOME) {
            while (cur > 0) { putc_uart('\b'); cur--; }
            continue;
        }
        if (k == KEY_END) {
            while (cur < len) { putc_uart(buf[cur]); cur++; }
            continue;
        }
        if (k == KEY_DELETE) {
            if (cur < len) {
                g_rl_hist_age = -1;
                for (int i = cur; i < len; i++) buf[i] = buf[i + 1];
                len--; buf[len] = 0;
                rl_redraw(prompt, buf, len, cur);
            }
            continue;
        }
        if (k >= 256) continue;   /* ignore PgUp/etc. on the command line */

        char c = (char)k;
        if (c == CH_CTRLC) {
            /* Prompt interrupt: drop the draft line and return empty (caller continues). */
            puts_uart("^C\nInterrupted\n");
            buf[0] = 0;
            g_break_pending = 0;
            g_rl_ctrlc_hit = 1;
            return 0;
        }
        if (c == '\r' || c == '\n') {
            buf[len] = 0;
            puts_uart("\n");
            if ((flags & RL_HIST) && !(flags & RL_NO_AUTO_HIST) && len > 0) hist_push(buf);
            g_rl_hist_age = -1;
            return len;
        }
        if (c == 127 || c == 8) {   /* Backspace */
            if (cur > 0) {
                g_rl_hist_age = -1;
                for (int i = cur - 1; i < len; i++) buf[i] = buf[i + 1];
                len--; cur--; buf[len] = 0;
                rl_redraw(prompt, buf, len, cur);
            }
            continue;
        }
        if (c == '\t') {
            if (flags & RL_COMPLETE) {
                g_rl_hist_age = -1;
                rl_do_complete(buf, max, &len, &cur, prompt);
            } else {
                /* Ed input / plain: mid-token → CI complete; else 2-space indent */
                g_rl_hist_age = -1;
                rl_smart_tab(buf, max, &len, &cur, prompt);
            }
            continue;
        }
        if (c >= 32 && c < 127 && len < max - 1) {
            g_rl_hist_age = -1;
            for (int i = len; i >= cur; i--) buf[i + 1] = buf[i];
            buf[cur++] = c; len++; buf[len] = 0;
            /* fast path when appending at end */
            if (cur == len) putc_uart(c);
            else rl_redraw(prompt, buf, len, cur);
        }
    }
}

static int repl_read_line(char *buf, int max) {
    return repl_read_line_ex(buf, max, 0, 0);
}

// BCPL-style implicit ';' after a balanced line must not split `U32 f(...)` from `{` — the
// body would compile as a bare block and lose parameters (dot_prod: undefined `n` in for cond).
static int repl_defer_bcpl_semi(const char *line, int n) {
    int s = 0, e = n - 1;
    while (s < n && (line[s] == ' ' || line[s] == '\t')) s++;
    while (e >= s && (line[e] == ' ' || line[e] == '\t')) e--;
    if (e < s || line[e] != ')') return 0;
    for (int i = s; i <= e; i++)
        if (line[i] == '{') return 0;
    static const char *types[] = {
        "I0", "U0", "I8", "U8", "I16", "U16", "I32", "U32", "I64", "U64", "F64", "Bool", 0
    };
    for (int t = 0; types[t]; t++) {
        const char *ty = types[t];
        int tl = 0; while (ty[tl]) tl++;
        if (e - s + 1 <= tl) continue;
        if (memcmp(line + s, ty, (size_t)tl) != 0) continue;
        char c = line[s + tl];
        if (c != ' ' && c != '\t' && c != '*') continue;
        return 1;
    }
    return 0;
}

void repl(void) {
    char input[512];
    int pos;
    
    // Create compiler once and reuse across REPL iterations
    // This ensures the hash table persists across inputs
    g_cc = CompilerNew("", "repl");
    Compiler *cc = g_cc;
    /* Arena is outside BSS — zero before seed so unused slots read as free. */
    memset((void *)(uintptr_t)MEMFS_PHYS_BASE, 0, (size_t)MEMFS_CWD_OFF + 96);
    /* `lock` stmt AMO word (HOLYC_STMT_LOCK_ADDR) — outside BSS, start unlocked. */
    *(volatile U64 *)0x87001F00ULL = 0;
    memfs_seed();   // ship editable HolyC seeds into the shared HolyC arena
    RuntimeInit(cc); /* Fs + host slots only — zero RuntimeRegister */
    // C TrapVec→TrapCtxSave→trapvec until HolyC trap.hc installs its thin TrapVec.
    TrapInit();
    g_repl_jb_ok = 1;
    if (repl_setjmp(g_repl_jb))
        puts_uart("-- boot aborted, back to the REPL --\n");
    else
        BootHolyCRuntime();
    TrapInit();   /* refresh mtvec if HolyC TrapInit ran */
    /* Seed pc to a real code addr so `pc;` / U(pc-16) work before any fault. */
    {
        CHashFun *ufn = g_cc ? (CHashFun *)HashFind("U", g_cc->hash_table, HTT_FUN) : 0;
        if (ufn && ufn->exe_addr) hc_pc_publish((I64)ufn->exe_addr);
        else hc_pc_publish((I64)(uintptr_t)(void *)&TrapVec);
    }
    g_break_interactive = 1;  /* Ctrl-C armed for prompt eval / Run from here on */
    hist_seed();  /* Up recalls Help;, Man, MemMap, asm demos, … */

    // Accumulation buffer for multi-line inputs (functions/blocks)
    static char accum[16384];
    int accum_len = 0;
    int brace_depth = 0;
    int paren_depth = 0;
    
    while (1) {
        const char *prompt = (accum_len > 0 || brace_depth > 0 || paren_depth > 0) ? "... " : "> ";
        rl_set_accum_ctx(accum, accum_len);
        pos = repl_read_line_ex(input, (int)sizeof(input),
                                RL_HIST | RL_COMPLETE | RL_NO_AUTO_HIST, prompt);

        if (pos == RL_MULTILINE_RECALL && g_rl_hist_recall_unit) {
            repl_hist_recall_multiline(g_rl_hist_recall_unit, input, (int)sizeof(input),
                                       accum, (int)sizeof(accum), &accum_len,
                                       &brace_depth, &paren_depth);
            repl_set_prefill(g_rl_hist_lastline);
            g_rl_hist_recall_unit = 0;
            continue;
        } else if (pos == 0) {
            if (g_rl_ctrlc_hit) {
                accum_len = 0; brace_depth = 0; paren_depth = 0;
                g_rl_ctrlc_hit = 0;
                g_rl_hist_accum_clear = 0;
            }
            continue;
        }

        if (g_rl_hist_accum_clear) {
            accum_len = 0; brace_depth = 0; paren_depth = 0;
            g_rl_hist_accum_clear = 0;
        }
        
        // Skip comment-only lines starting with '#'
        int i_start = 0;
        while (i_start < pos && (input[i_start] == ' ' || input[i_start] == '\t')) i_start++;
        // '#' + letter is a preprocessor directive (#define, #include, …) and goes to the
        // lexer as its own line; anything else starting with '#' is treated as a comment.
        int is_directive = (i_start + 1 < pos && input[i_start] == '#' &&
                            ((input[i_start+1] >= 'a' && input[i_start+1] <= 'z') ||
                             (input[i_start+1] >= 'A' && input[i_start+1] <= 'Z')));
        if (i_start < pos && input[i_start] == '#' && !is_directive) {
            continue;
        }
        int is_line_slash_comment = (i_start + 1 < pos && input[i_start] == '/' &&
                                     input[i_start+1] == '/');
        
        // Append this line to accumulation buffer (with a newline)
        if (accum_len + pos + 2 < (int)sizeof(accum)) {
            for (int i = 0; i < pos; i++) accum[accum_len++] = input[i];
            accum[accum_len++] = '\n';
            accum[accum_len] = '\0';
        } else {
            puts_uart("[ERROR] Input too long\n");
            accum_len = 0; brace_depth = 0; paren_depth = 0;
            continue;
        }
        
        // // comments are not statements (same rule as run_source for Man SYNOPSIS lines).
        if (is_line_slash_comment) continue;

        // Track simple brace/paren depth to detect statement/function completion
        for (int i = 0; i < pos; i++) {
            char ch = input[i];
            if (ch == '"' || ch == '\'') {
                char q = ch;
                i++;
                while (i < pos && input[i] != q) {
                    if (input[i] == '\\' && i + 1 < pos) i++;
                    i++;
                }
                continue;
            }
            if (ch == '{') brace_depth++;
            else if (ch == '}') { if (brace_depth > 0) brace_depth--; }
            else if (ch == '(') paren_depth++;
            else if (ch == ')') { if (paren_depth > 0) paren_depth--; }
        }
        
        // Determine if we should attempt to parse now
        int should_parse = 0;
        // If in a block, wait until braces balance back to zero
        if (brace_depth == 0) {
            // If not in parens and line ends with ';', treat as complete statement/expression
            if (paren_depth == 0) {
                if (pos > 0 && input[pos-1] == ';') should_parse = 1;
                // Or if this line closed a block '}'
                if (pos > 0 && input[pos-1] == '}') should_parse = 1;
                // BCPL style: a balanced, complete-looking line ends the statement at the
                // newline -- supply the ';' implicitly. A trailing ',' means continuation, and a
                // directive (#define/#include) must NOT gain a ';' -- it would join the macro body.
                if (!should_parse && !is_directive && pos > 0 && input[pos-1] != ',' &&
                    !repl_defer_bcpl_semi(input, pos)) {
                    if (accum_len + 1 < (int)sizeof(accum)) {
                        accum[accum_len - 1] = ';';       // overwrite the '\n' we appended
                        accum[accum_len++] = '\n';
                        accum[accum_len] = '\0';
                    }
                    should_parse = 1;
                }
            }
        }
        
        if (is_directive && brace_depth == 0 && paren_depth == 0) should_parse = 1;
        if (!should_parse) {
            // Prompt for more lines
            continue;
        }
        
        // Compile and run the accumulated input, echoing the TempleOS-style answer line.
        // The same path serves Run("file") (with echo off) -- see repl_eval() above.
        // Arm the fault-recovery point: a caught synchronous fault longjmps back here with 1,
        // the wrecked evaluation is dropped, and the prompt returns.
        g_repl_jb_ok = 1;
        if (repl_setjmp(g_repl_jb)) {
            accum_len = 0; brace_depth = 0; paren_depth = 0;
            continue;
        }
        repl_eval(accum, 1, 1);
        hist_push_unit(accum, accum_len);
        accum_len = 0;
        brace_depth = 0;
        paren_depth = 0;

        // Don't free the compiler - reuse it for the next iteration
    }
}

int main(void) {
    repl();
    while (1) __asm__ volatile ("wfi");
}

