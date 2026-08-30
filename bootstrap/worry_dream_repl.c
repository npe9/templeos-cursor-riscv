// Worry Dream Machine - Live Interactive REPL
// Type HolyC code over UART, compile and execute it

#include <stdint.h>
#include <stddef.h>
#include "../holyc_compiler.h"

/* 16550 UART base. Per-platform: overridden with -DUART_BASE=0x... from the Makefile PLATFORM
 * table (default is QEMU virt's UART). */
#ifndef UART_BASE
#define UART_BASE 0x10000000
#endif
#define true 1
#define false 0

// UART
static void putc_uart(char c) {
    while (!(*(volatile U8*)(UART_BASE + 5) & 0x20));
    *(volatile U8*)UART_BASE = c;
}

static char getc_uart(void) {
    // Non-blocking: return 0 if no data available
    if (!(*(volatile U8*)(UART_BASE + 5) & 0x01)) {
        return 0;
    }
    return *(volatile U8*)UART_BASE;
}

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
static U8 code_mem[4*1024*1024];   // 4MB for compiled code (never reused)
static size_t code_pos = 0;
static U8 heap_mem[32*1024*1024];  // 32MB heap (JIT code + IC live here; free() is a no-op)
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
    if (heap_pos + aligned > sizeof(heap_mem)) {
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
size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
char *strdup(const char *s) {
    size_t n = strlen(s);
    char *d = malloc(n + 1);
    for (size_t i = 0; i <= n; i++) d[i] = s[i];
    return d;
}
int strcmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a - *b;
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

static void RuntimeRegister(Compiler *cc, const char *name, void *fn, I64 argc) {
    CHashFun *f = calloc(1, sizeof(CHashFun));
    f->str = strdup(name);
    f->type = HTT_FUN;
    f->raw_type = HolyRtRetVoid(name) ? RT_I0 : (HolyRtRetF64(name) ? RT_F64 : RT_I64);
    f->param_typed = true;
    f->param_f64_mask = HolyRtF64Mask(name);
    f->exe_addr = (I64)fn;
    f->arg_cnt = argc;
    HashAdd((CHashEntry *)f, cc->hash_table);
}
// Read one line from the UART into buf (dumb serial: no cursor, backspace-aware). Returns length.
static int repl_read_line(char *buf, int max) {
    int i = 0; char c;
    while (1) {
        c = getc_uart();
        if (c == 0) continue;
        if (c == '\r' || c == '\n') { putc_uart('\r'); putc_uart('\n'); break; }
        if ((c == 127 || c == 8) && i > 0) { i--; puts_uart("\b \b"); continue; }
        if (i < max - 1 && c >= 32 && c < 127) { buf[i++] = c; putc_uart(c); }
    }
    buf[i] = 0;
    return i;
}
// ---- In-memory filesystem (REPL-only, RAM-backed) ----------------------------------------
// Fixed slots with a fixed per-file capacity: free() is a no-op here, so we never realloc --
// a file's storage is claimed once and rewritten in place. HolyC-callable: Dir/Cat/Del/Ed and
// the programmatic FileWrite/FileRead.
#define MEMFS_MAX_FILES 32
#define MEMFS_FILE_CAP  16384
typedef struct { int used; char name[32]; char data[MEMFS_FILE_CAP]; int len; } MemFile;
static MemFile memfs[MEMFS_MAX_FILES];

static MemFile *memfs_find(const char *name) {
    for (int i = 0; i < MEMFS_MAX_FILES; i++)
        if (memfs[i].used && !strcmp(memfs[i].name, name)) return &memfs[i];
    return NULL;
}
static MemFile *memfs_create(const char *name) {
    MemFile *f = memfs_find(name);
    if (f) return f;
    for (int i = 0; i < MEMFS_MAX_FILES; i++) if (!memfs[i].used) {
        MemFile *n = &memfs[i];
        n->used = 1; n->len = 0; n->data[0] = 0;
        int j = 0; while (name[j] && j < 31) { n->name[j] = name[j]; j++; } n->name[j] = 0;
        return n;
    }
    return NULL;  // table full
}

// Dir() / Ls() -- list every file with its byte count.
static HRT_I64 Dir(void) {
    int count = 0;
    for (int i = 0; i < MEMFS_MAX_FILES; i++) if (memfs[i].used) {
        puts_uart("  "); puts_uart(memfs[i].name);
        puts_uart("  "); print_udec(memfs[i].len); puts_uart(" bytes\n");
        count++;
    }
    if (!count) puts_uart("  (no files)\n");
    return count;
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
// FileWrite("name", buf, len) -- overwrite a file from a HolyC buffer (creating it if needed).
static HRT_I64 FileWrite(char *name, char *data, HRT_I64 len) {
    MemFile *f = memfs_create(name);
    if (!f) { puts_uart("FileWrite: fs full\n"); return -1; }
    if (len < 0) len = 0;
    if (len > MEMFS_FILE_CAP - 1) len = MEMFS_FILE_CAP - 1;
    for (HRT_I64 i = 0; i < len; i++) f->data[i] = data[i];
    f->data[len] = 0; f->len = (int)len;
    return len;
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
                    puts_uart("wrote "); puts_uart(name); puts_uart(" (");
                    print_udec(off); puts_uart(" bytes)\n"); break; }
        case 'q': putc_uart('\n'); return 0;
        case '=': { print_udec(have1 ? a1 : ed_cur); putc_uart('\n'); break; }
        case 0:   // bare address prints that line; bare Enter advances one line
            if (have1) { if (a1 >= 1 && a1 <= ed_n) { ed_cur = a1; puts_uart(ed_lines[a1 - 1]); putc_uart('\n'); } }
            else if (ed_cur < ed_n) { ed_cur++; puts_uart(ed_lines[ed_cur - 1]); putc_uart('\n'); }
            break;
        default: puts_uart("?\n"); break;
        }
    }
}

// ---- Edit("name"): a basic full-screen terminal editor (ANSI) ----------------------------
// Nano-style and modeless: type to insert, arrow keys move, Enter splits a line, Backspace
// deletes (joining lines at column 0), ^O writes, ^X exits. Reuses the memfs and the ed_lines
// buffer. Assumes an 80x24 ANSI terminal (QEMU -nographic puts the host TTY in raw mode, so
// single keys and escape sequences arrive as-is).
#define SCR_ROWS   24
#define SCR_COLS   80
#define TEXT_ROWS  (SCR_ROWS - 2)   // rows 1..22 text, 23 status (reverse video), 24 message

static char getc_block(void) { char c; do { c = getc_uart(); } while (c == 0); return c; }
// Char I/O exposed to HolyC so the editors can be written in HolyC: GetCh() blocks for one byte,
// PutCh(ch) writes one raw byte (ANSI escapes and control chars included).
static HRT_I64 GetCh(void) { return (HRT_I64)(unsigned char)getc_block(); }
static HRT_I64 PutCh(HRT_I64 ch) { putc_uart((char)ch); return 0; }
static int  ed_line_len(int i) { int n = 0; while (ed_lines[i][n]) n++; return n; }

static void scr_goto(int row, int col) {  // 1-based
    puts_uart("\x1b["); print_udec(row); putc_uart(';'); print_udec(col); putc_uart('H');
}
static void edit_render(const char *name, int top, int cx, int cy, const char *msg) {
    puts_uart("\x1b[H");
    for (int r = 0; r < TEXT_ROWS; r++) {
        scr_goto(r + 1, 1); puts_uart("\x1b[2K");
        int li = top + r;
        if (li < ed_n) { for (int j = 0; ed_lines[li][j] && j < SCR_COLS; j++) putc_uart(ed_lines[li][j]); }
        else putc_uart('~');
    }
    scr_goto(SCR_ROWS - 1, 1); puts_uart("\x1b[7m\x1b[2K ");   // status bar, reverse video
    puts_uart(name);
    puts_uart("  ln "); print_udec(cy + 1); putc_uart('/'); print_udec(ed_n);
    puts_uart("  col "); print_udec(cx + 1);
    puts_uart("   ^O save  ^X exit"); puts_uart("\x1b[0m");
    scr_goto(SCR_ROWS, 1); puts_uart("\x1b[2K"); if (msg && msg[0]) puts_uart(msg);
    scr_goto(cy - top + 1, cx + 1);                            // place the cursor
}
static int edit_save(MemFile *f, const char *name, char *msgbuf) {  // returns bytes written
    int off = 0;
    for (int k = 0; k < ed_n; k++) {
        int j = 0;
        while (ed_lines[k][j] && off < MEMFS_FILE_CAP - 1) f->data[off++] = ed_lines[k][j++];
        if (off < MEMFS_FILE_CAP - 1) f->data[off++] = '\n';
    }
    f->data[off] = 0; f->len = off;
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
static HRT_I64 Edit(char *name) {
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
    puts_uart("\x1b[2J");
    edit_render(name, top, cx, cy, msg);
    while (1) {
        char c = getc_block();
        msg = "";
        if (c == 24) {                                  // ^X exit
            if (dirty) { msg = "modified -- ^O to save, or ^X again to discard"; dirty = 0;
                         edit_render(name, top, cx, cy, msg); continue; }
            break;
        } else if (c == 15) {                           // ^O save
            edit_save(f, name, msgbuf); msg = msgbuf; dirty = 0;
        } else if (c == 27) {                           // ESC: arrow keys ESC [ A/B/C/D
            char b1 = getc_block();
            if (b1 == '[') {
                char b2 = getc_block();
                int len = ed_line_len(cy);
                if (b2 == 'A') { if (cy > 0) { cy--; if (cx > ed_line_len(cy)) cx = ed_line_len(cy); } }
                else if (b2 == 'B') { if (cy < ed_n - 1) { cy++; if (cx > ed_line_len(cy)) cx = ed_line_len(cy); } }
                else if (b2 == 'C') { if (cx < len) cx++; else if (cy < ed_n - 1) { cy++; cx = 0; } }
                else if (b2 == 'D') { if (cx > 0) cx--; else if (cy > 0) { cy--; cx = ed_line_len(cy); } }
                else if (b2 == '3') { getc_block();       // Delete key: ESC [ 3 ~
                    if (cx < len) { for (int j = cx; ed_lines[cy][j]; j++) ed_lines[cy][j] = ed_lines[cy][j + 1]; dirty = 1; }
                }
            }
        } else if (c == '\r' || c == '\n') {            // split line at cursor
            if (ed_n < ED_MAX_LINES) {
                ed_insert_at(cy + 1, &ed_lines[cy][cx]);
                ed_lines[cy][cx] = 0; cy++; cx = 0; dirty = 1;
            }
        } else if (c == 127 || c == 8) {                // backspace
            if (cx > 0) {
                for (int j = cx - 1; ed_lines[cy][j]; j++) ed_lines[cy][j] = ed_lines[cy][j + 1];
                cx--; dirty = 1;
            } else if (cy > 0) {                        // join with previous line
                int pl = ed_line_len(cy - 1), j = 0;
                while (ed_lines[cy][j] && pl + j < ED_LINE_CAP - 1) { ed_lines[cy - 1][pl + j] = ed_lines[cy][j]; j++; }
                ed_lines[cy - 1][pl + j] = 0;
                ed_delete_range(cy + 1, cy + 1);        // remove the (now-merged) current line
                cy--; cx = pl; dirty = 1;
            }
        } else if (c >= 32 && c < 127) {                // printable: insert at cursor
            int len = ed_line_len(cy);
            if (len < ED_LINE_CAP - 1) {
                for (int j = len; j >= cx; j--) ed_lines[cy][j + 1] = ed_lines[cy][j];
                ed_lines[cy][cx] = c; cx++; dirty = 1;
            }
        }
        // keep the cursor on-screen (vertical scroll)
        if (cy < top) top = cy;
        if (cy >= top + TEXT_ROWS) top = cy - TEXT_ROWS + 1;
        edit_render(name, top, cx, cy, msg);
    }
    puts_uart("\x1b[2J\x1b[H");   // leave a clean screen for the REPL prompt
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
#define SRCMAP_MAX 128
static struct { int used; char name[32]; char *src; } srcmap[SRCMAP_MAX];
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
}
static const char *srcmap_get(const char *name) {
    for (int i = 0; i < SRCMAP_MAX; i++) if (srcmap[i].used && !strcmp(srcmap[i].name, name)) return srcmap[i].src;
    return 0;
}

// Compile one source buffer as top-level HolyC and run any trailing statement. echo=1 prints
// the TempleOS-style "<time>s ans=..." line (the REPL prompt); echo=0 is silent (Run/scripts).
// Safe to call re-entrantly from a registered C function: cc->lex is re-seeded on every call,
// free() is a no-op here, and definitions only append to code_mem / the hash table.
static void repl_eval(const char *src, int echo) {
    Compiler *cc = g_cc;
    if (!cc) return;
    if (cc->lex.src) free(cc->lex.src);
    cc->lex.src = strdup(src);
    cc->lex.ptr = cc->lex.src;
    cc->lex.line = 1; cc->lex.col = 1; cc->lex.hash_entry = NULL;
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
        if (ok && cc->last_compiled_func && cc->last_compiled_func != fn_before && cc->last_compiled_func->str)
            srcmap_put(cc->last_compiled_func->str, src);
    }
    U8 ans_ty = cc->last_expr_type;
    __asm__ volatile("fence.i" ::: "memory");   // definitions are fresh code: order the I-side
    if (!ok) {
        puts_uart("[ERROR] "); puts_uart(cc->error ? cc->error : "parse error");
        puts_uart(" near '"); puts_uart(cc->lex.token_str ? cc->lex.token_str : "");
        puts_uart("' line "); print_hex((U64)cc->lex.line); puts_uart("\n");
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
        __asm__ volatile("rdtime %0" : "=r"(t0));
        I64 result = func_ptr();
        __asm__ volatile("rdtime %0" : "=r"(t1));
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
    static char acc[16384];
    int acc_len = 0, brace = 0, paren = 0;
    const char *p = src;
    char line[512];
    while (*p) {
        int n = 0;
        while (*p && *p != '\n' && n < 511) line[n++] = *p++;
        if (*p == '\n') p++;
        line[n] = 0;
        int s = 0; while (s < n && (line[s] == ' ' || line[s] == '\t')) s++;
        int is_dir = (s + 1 < n && line[s] == '#' &&
                      ((line[s+1] >= 'a' && line[s+1] <= 'z') || (line[s+1] >= 'A' && line[s+1] <= 'Z')));
        if (s < n && line[s] == '#' && !is_dir) continue;   // whole-line '#' comment
        if (acc_len + n + 2 >= (int)sizeof(acc)) { acc_len = 0; brace = 0; paren = 0; continue; }
        for (int i = 0; i < n; i++) acc[acc_len++] = line[i];
        acc[acc_len++] = '\n'; acc[acc_len] = 0;
        for (int i = 0; i < n; i++) { char c = line[i];
            if (c == '{') brace++; else if (c == '}') { if (brace > 0) brace--; }
            else if (c == '(') paren++; else if (c == ')') { if (paren > 0) paren--; } }
        int go = 0;
        if (brace == 0 && paren == 0) {
            if (n > 0 && line[n-1] == ';') go = 1;
            if (n > 0 && line[n-1] == '}') go = 1;
        }
        if (is_dir && brace == 0 && paren == 0) go = 1;
        if (!go) continue;
        repl_eval(acc, 0);
        acc_len = 0; brace = 0; paren = 0;
    }
    if (acc_len > 0) repl_eval(acc, 0);   // flush any unterminated tail
}
// Run("name") -- compile and execute an in-memory file, unit by unit (see run_source). Closes
// the self-hosting loop: edit a file with Ed/Edit, then Run it.
static HRT_I64 Run(char *name) {
    MemFile *f = memfs_find(name);
    if (!f) { puts_uart("Run: no such file: "); puts_uart(name); puts_uart("\n"); return -1; }
    f->data[f->len] = 0;
    run_source(f->data);
    return 0;
}
// Src("Name") -- bring up a HolyC function's source in the editor (TempleOS goto-definition),
// then recompile it: writes the remembered source to "Name.hc", opens Edit, and Run()s it on
// exit, so what you edit becomes the live definition. Only works for functions defined in HolyC
// (the C built-ins like Ed/Dir/Edit have no HolyC source until they are reimplemented as such).
static HRT_I64 Src(char *name) {
    const char *s = srcmap_get(name);
    if (s) {
        // A HolyC function: materialize its (arbitrary-size) source into <name>.hc, edit, recompile.
        char fn[36];
        int j = 0; while (name[j] && j < 31) { fn[j] = name[j]; j++; }
        fn[j] = '.'; fn[j+1] = 'h'; fn[j+2] = 'c'; fn[j+3] = 0;
        MemFile *f = memfs_create(fn);
        if (!f) { puts_uart("Src: fs full\n"); return -1; }
        int n = 0; while (s[n] && n < MEMFS_FILE_CAP - 1) { f->data[n] = s[n]; n++; }
        f->data[n] = 0; f->len = n;
        Edit(fn); Run(fn);
        return 0;
    }
    // Not a known function: maybe it's a file itself -- the boot script, a driver source, a data
    // file. Edit "name" (or "name.hc") in place and Run it, so you can edit the boot process too.
    MemFile *f = memfs_find(name);
    if (!f) {
        char fn[36];
        int j = 0; while (name[j] && j < 31) { fn[j] = name[j]; j++; }
        fn[j] = '.'; fn[j+1] = 'h'; fn[j+2] = 'c'; fn[j+3] = 0;
        f = memfs_find(fn);
    }
    if (f) { Edit(f->name); Run(f->name); return 0; }
    // No HolyC source and no file: if it's a function (a C built-in, say), disassemble it instead.
    { CHashFun *fn = g_cc ? (CHashFun *)HashFind(name, g_cc->hash_table, HTT_FUN) : 0;
      CHashFun *dis = g_cc ? (CHashFun *)HashFind("DisasmAt", g_cc->hash_table, HTT_FUN) : 0;
      if (fn && fn->exe_addr && dis && dis->exe_addr) {
          puts_uart("Src: no source for "); puts_uart(name); puts_uart(" -- disassembling:\n");
          // C callers don't evaluate HolyC default args -- pass max/end explicitly.
          ((void (*)(HRT_I64, HRT_I64, HRT_I64))dis->exe_addr)((HRT_I64)fn->exe_addr, 2000, 0);   // the HolyC DisasmAt (disasm.hc)
          return 0; } }
    puts_uart("Src: no source for "); puts_uart(name);
    puts_uart(" (not a HolyC function or a file)\n");
    return -1;
}
// Funs() -- list every function in the symbol table (the hash table): name, entry address,
// return type, and [src] if it has HolyC source you can Src()/edit. This is the "what can I
// call or edit" view -- TempleOS keeps the same symbol table you browse for autocomplete.
// Funs() -- list every function in the symbol table, sorted, with [src] marking the ones you
// can Src()/edit. This is the "what can I call or edit" view.
static CHashFun *funs_buf[1024];
static HRT_I64 Funs(void) {
    if (!g_cc || !g_cc->hash_table) { puts_uart("(no symbol table)\n"); return 0; }
    CHashTable *h = g_cc->hash_table;
    int n = 0;
    for (I64 b = 0; b <= h->mask && n < 1024; b++)
        for (CHashEntry *e = h->body[b]; e && n < 1024; e = e->next)
            if (e->type & HTT_FUN) funs_buf[n++] = (CHashFun *)e;
    for (int i = 1; i < n; i++) {   // insertion sort by name (alphabetical, easy to scan)
        CHashFun *key = funs_buf[i]; int j = i - 1;
        while (j >= 0 && strcmp(funs_buf[j]->str ? funs_buf[j]->str : "", key->str ? key->str : "") > 0) {
            funs_buf[j + 1] = funs_buf[j]; j--;
        }
        funs_buf[j + 1] = key;
    }
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

// ---- Live interrupt handling: install a HolyC ISR you can edit + recompile in place --------
// mtvec points at a FIXED trampoline (the register-save frame and mret can't be hot-swapped).
// The trampoline dispatches to whatever HolyC function name is currently registered, resolved
// afresh on every trap -- so editing the handler and Run()-ing it takes effect immediately, no
// reinstall. Handler signature:  I64 MyIsr(I64 cause, I64 epc, I64 tval);  a nonzero return is
// the address to resume at (else: skip a synchronous exception, retry an interrupt).
static char g_isr_name[32];

// The saved-register frame is published on EVERY trap to a FIXED address (0x87000100) so a HolyC
// handler -- the debugger's breakpoint ISR -- can read the trapped registers with a plain
// *(U64*)... peek, no C primitive needed. Layout at 0x87000100 (U64 each): [0]=ra, [1..7]=t0..t6,
// [8..15]=a0..a7, [16]=trapped sp. frame[] from repl_trap_vector matches [0..15].
__attribute__((used)) static void repl_trap_dispatch(U64 *frame) {
    I64 cause, epc, tval;
    __asm__ volatile("csrr %0, mcause" : "=r"(cause));
    __asm__ volatile("csrr %0, mepc"   : "=r"(epc));
    __asm__ volatile("csrr %0, mtval"  : "=r"(tval));
    volatile U64 *dbg = (volatile U64 *)0x87000100;
    for (int k = 0; k < 16; k++) dbg[k] = frame[k];        // publish the trapped registers for HolyC
    dbg[16] = (U64)frame + 128;                            // trapped sp
    I64 resume = 0;
    CHashFun *f = g_isr_name[0] && g_cc ? (CHashFun *)HashFind(g_isr_name, g_cc->hash_table, HTT_FUN) : 0;
    if (f && f->exe_addr) {
        typedef I64 (*Isr)(I64, I64, I64);
        resume = ((Isr)f->exe_addr)(cause, epc, tval);   // e.g. the HolyC debugger's DbgTrap
    } else {
        puts_uart("[trap cause="); print_hex((U64)cause);
        puts_uart(" epc=");        print_hex((U64)epc);
        puts_uart(" tval=");       print_hex((U64)tval); puts_uart("]\n");
    }
    if (!resume) resume = (cause >= 0) ? epc + 4 : epc;   // exception: skip; interrupt: retry
    __asm__ volatile("csrw mepc, %0" :: "r"(resume));
}
__attribute__((used, naked, aligned(4))) static void repl_trap_vector(void) {
    __asm__ volatile(
        "addi sp,sp,-128\n"
        "sd ra,0(sp)\n sd t0,8(sp)\n sd t1,16(sp)\n sd t2,24(sp)\n"
        "sd t3,32(sp)\n sd t4,40(sp)\n sd t5,48(sp)\n sd t6,56(sp)\n"
        "sd a0,64(sp)\n sd a1,72(sp)\n sd a2,80(sp)\n sd a3,88(sp)\n"
        "sd a4,96(sp)\n sd a5,104(sp)\n sd a6,112(sp)\n sd a7,120(sp)\n"
        "mv a0,sp\n"                     /* pass the saved-register frame to the dispatcher */
        "call repl_trap_dispatch\n"
        "ld ra,0(sp)\n ld t0,8(sp)\n ld t1,16(sp)\n ld t2,24(sp)\n"
        "ld t3,32(sp)\n ld t4,40(sp)\n ld t5,48(sp)\n ld t6,56(sp)\n"
        "ld a0,64(sp)\n ld a1,72(sp)\n ld a2,80(sp)\n ld a3,88(sp)\n"
        "ld a4,96(sp)\n ld a5,104(sp)\n ld a6,112(sp)\n ld a7,120(sp)\n"
        "addi sp,sp,128\n"
        "mret\n"
    );
}
// SetIsr("name") -- route traps to the HolyC function of that name (resolved live per trap).
static HRT_I64 SetIsr(char *name) {
    int i = 0; while (name[i] && i < 31) { g_isr_name[i] = name[i]; i++; } g_isr_name[i] = 0;
    return 0;
}
// TrapInit() -- install the trampoline and enable machine interrupts. Opt-in: until you call
// this, a fault still hangs (startup's halt vector), which is the behavior debugging relies on.
static HRT_I64 TrapInit(void) {
    __asm__ volatile("csrw mtvec, %0" :: "r"(&repl_trap_vector));
    __asm__ volatile("csrs mstatus, %0" :: "r"((HRT_I64)(1 << 3)));   // MIE: global interrupt enable
    return 0;
}
// Ecall() -- raise a synchronous trap (mcause=11, env-call-from-M) so you can watch your ISR run.
static HRT_I64 Ecall(void) { __asm__ volatile("ecall"); return 0; }
// TimerArm(interval) -- arm the CLINT machine timer to fire the ISR every `interval` mtime ticks
// (async, mcause bit63|7). Pass a large interval so ticks are occasional, not a flood.
static HRT_I64 TimerArm(HRT_I64 interval) {
    volatile HRT_I64 *mtime    = (volatile HRT_I64 *)0x0200BFF8;
    volatile HRT_I64 *mtimecmp = (volatile HRT_I64 *)0x02004000;
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
static HRT_I64 MemMap(void) {
    puts_uart("Memory map (RISC-V QEMU virt; [plat]=platform constant, [live]=measured now):\n");
    puts_uart("  RAM          0x80000000  +128M                       [plat]\n");
    puts_uart("  code_mem   @ "); print_hex((U64)&code_mem[0]); puts_uart("  ");
        print_udec(code_pos); putc_uart('/'); print_udec(sizeof(code_mem)); puts_uart(" B used   [live JIT code]\n");
    puts_uart("  heap_mem   @ "); print_hex((U64)&heap_mem[0]); puts_uart("  ");
        print_udec(heap_pos); putc_uart('/'); print_udec(sizeof(heap_mem)); puts_uart(" B used   [live]\n");
    puts_uart("  UART 16550   0x10000000                              [plat]\n");
    puts_uart("  CLINT        0x02000000  mtime .0BFF8 mtimecmp .04000 [plat]\n");
    puts_uart("  PLIC         0x0C000000                              [plat]\n");
    puts_uart("  virtio-mmio  0x10001000 .. 0x10008000                [plat]\n");
    puts_uart("  SiFive test  0x00100000  (0x5555 off, 0x7777 reboot) [plat]\n");
    return 0;
}
static void reg_line(const char *name, I64 v) { puts_uart("  "); puts_uart(name); puts_uart(" = "); print_hex((U64)v); putc_uart('\n'); }
// Regs: dump EVERY GPR as it was at the call site, plus the M-mode CSRs. A C body can't do the
// GPRs -- the prologue has already clobbered the caller-saved ones -- so a naked stub snapshots
// x1..x31 to the fixed block 0x87000300 (x_n at 0x300+8n) before any C runs, then tail-calls the
// printer (ra is untouched, so the printer returns straight to the REPL). t6 is bounced through
// sscratch: mscratch belongs to the task scheduler, and sscratch is unused by this M-mode kernel
// and never written by hardware, so an interrupt mid-stub can't lose it (the trampoline
// saves/restores GPRs, and sscratch survives).
#define REGS_SNAP_BASE 0x87000300UL
__asm__(
    ".text\n"
    ".globl regs_snap_stub\n"
    "regs_snap_stub:\n"
    "  csrw sscratch, t6\n"
    "  lui  t6, 0x10E00\n"      /* lui 0x87000 would sign-extend bit 31 (-> 0xFFFFFFFF87000000); */
    "  slli t6, t6, 3\n"        /* build 0x87000000 as 0x10E00000 << 3 instead                  */
    "sd x1, 0x308(t6)\n"
    "sd x2, 0x310(t6)\n"
    "sd x3, 0x318(t6)\n"
    "sd x4, 0x320(t6)\n"
    "sd x5, 0x328(t6)\n"
    "sd x6, 0x330(t6)\n"
    "sd x7, 0x338(t6)\n"
    "sd x8, 0x340(t6)\n"
    "sd x9, 0x348(t6)\n"
    "sd x10, 0x350(t6)\n"
    "sd x11, 0x358(t6)\n"
    "sd x12, 0x360(t6)\n"
    "sd x13, 0x368(t6)\n"
    "sd x14, 0x370(t6)\n"
    "sd x15, 0x378(t6)\n"
    "sd x16, 0x380(t6)\n"
    "sd x17, 0x388(t6)\n"
    "sd x18, 0x390(t6)\n"
    "sd x19, 0x398(t6)\n"
    "sd x20, 0x3A0(t6)\n"
    "sd x21, 0x3A8(t6)\n"
    "sd x22, 0x3B0(t6)\n"
    "sd x23, 0x3B8(t6)\n"
    "sd x24, 0x3C0(t6)\n"
    "sd x25, 0x3C8(t6)\n"
    "sd x26, 0x3D0(t6)\n"
    "sd x27, 0x3D8(t6)\n"
    "sd x28, 0x3E0(t6)\n"
    "sd x29, 0x3E8(t6)\n"
    "sd x30, 0x3F0(t6)\n"
    "  csrr t5, sscratch\n"
    "  sd t5, 0x3F8(t6)\n"      /* original t6 (x31) */
    "  ld t5, 0x3F0(t6)\n"      /* restore t5 */
    "  csrr t6, sscratch\n"     /* restore t6 */
    "  j regs_dump_c\n"
);
HRT_I64 regs_snap_stub(void);
__attribute__((used)) static HRT_I64 regs_dump_c(void) {
    static const char *rn[32] = {"zero","ra","sp","gp","tp","t0","t1","t2","s0","s1",
        "a0","a1","a2","a3","a4","a5","a6","a7","s2","s3","s4","s5","s6","s7","s8","s9",
        "s10","s11","t3","t4","t5","t6"};
    volatile U64 *r = (volatile U64 *)REGS_SNAP_BASE;
    I64 v;
    char pad[12];
    puts_uart("GPRs at the Regs() call site (xN / ABI name):\n");
    for (int i = 1; i < 32; i++) {
        int k = 0;
        pad[k++] = 'x';                                   /* "x10 a0  " -- number and ABI name */
        if (i >= 10) pad[k++] = (char)('0' + i / 10);
        pad[k++] = (char)('0' + i % 10);
        while (k < 4) pad[k++] = ' ';
        for (int j = 0; rn[i][j]; j++) pad[k++] = rn[i][j];
        while (k < 8) pad[k++] = ' ';
        pad[k] = 0;
        reg_line(pad, (I64)r[i]);
    }
    puts_uart("M-mode CSRs (the real machine state):\n");
    __asm__ volatile("csrr %0, mstatus"  : "=r"(v)); reg_line("mstatus ", v);
    __asm__ volatile("csrr %0, misa"     : "=r"(v)); reg_line("misa    ", v);
    __asm__ volatile("csrr %0, mtvec"    : "=r"(v)); reg_line("mtvec   ", v);
    __asm__ volatile("csrr %0, mie"      : "=r"(v)); reg_line("mie     ", v);
    __asm__ volatile("csrr %0, mip"      : "=r"(v)); reg_line("mip     ", v);
    __asm__ volatile("csrr %0, mepc"     : "=r"(v)); reg_line("mepc    ", v);
    __asm__ volatile("csrr %0, mcause"   : "=r"(v)); reg_line("mcause  ", v);
    __asm__ volatile("csrr %0, mtval"    : "=r"(v)); reg_line("mtval   ", v);
    __asm__ volatile("csrr %0, mscratch" : "=r"(v)); reg_line("mscratch", v);
    __asm__ volatile("csrr %0, mhartid"  : "=r"(v)); reg_line("mhartid ", v);
    reg_line("mtime   ", *(volatile I64 *)0x0200BFF8);
    return 0;
}
// Exec("holyc") -- compile and run one HolyC statement/definition, echoing its answer. Lets the
// editors call HolyC in place (Ed's `!`, Edit's `^E`): test the function you're editing, poke a
// register, call anything. Re-entrant (the editor is itself JIT'd code calling back in).
static HRT_I64 Exec(char *src) {
    repl_eval(src, 1);
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
                    (!best || (I64)f->exe_addr > (I64)best->exe_addr))
                    best = f;
            }
    return best;
}
static HRT_I64 SymBase(HRT_I64 addr) { CHashFun *f = SymNearest(addr); return f ? (HRT_I64)f->exe_addr : 0; }
static HRT_I64 SymName(HRT_I64 addr) { CHashFun *f = SymNearest(addr); return f && f->str ? (HRT_I64)f->str : 0; }

static void RuntimeInit(Compiler *cc) {
    // Fs -> the task block (Fs->except_ch)
    if (cc->fs_var && cc->except_ch_var) *(I64 *)cc->fs_var->data_addr = (I64)cc->except_ch_var->data_addr;
    for (HRT_I64 i = 0; i < HOLY_RT_COUNT; i++)
        RuntimeRegister(cc, holy_rt_table[i].name, holy_rt_table[i].fn, holy_rt_table[i].argc);
    // In-memory filesystem + editor (REPL-native, HolyC-callable)
    RuntimeRegister(cc, "Dir",       (void*)Dir,       0);
    RuntimeRegister(cc, "Ls",        (void*)Dir,       0);
    RuntimeRegister(cc, "Cat",       (void*)Cat,       1);
    RuntimeRegister(cc, "Del",       (void*)Del,       1);
    RuntimeRegister(cc, "FileWrite", (void*)FileWrite, 3);
    RuntimeRegister(cc, "FileRead",  (void*)FileRead,  1);
    RuntimeRegister(cc, "FileCount", (void*)FileCount, 0);
    RuntimeRegister(cc, "FileName",  (void*)FileName,  1);
    RuntimeRegister(cc, "FileSize",  (void*)FileSize,  1);
    RuntimeRegister(cc, "FileLen",   (void*)FileLen,   1);
    RuntimeRegister(cc, "GetCh",     (void*)GetCh,     0);
    RuntimeRegister(cc, "PutCh",     (void*)PutCh,     1);
    RuntimeRegister(cc, "Ed",        (void*)Ed,        1);
    RuntimeRegister(cc, "Edit",      (void*)Edit,      1);
    // C escape hatches: always-available editors under fixed names, so a broken HolyC ed.hc/
    // edit.hc (which redefine Ed/Edit) can still be repaired -- EdC/EditC can't be shadowed.
    RuntimeRegister(cc, "EdC",       (void*)Ed,        1);
    RuntimeRegister(cc, "EditC",     (void*)Edit,      1);
    // Self-hosting: compile+run a file, and edit/compile/install an interrupt handler in place
    RuntimeRegister(cc, "Run",       (void*)Run,       1);
    RuntimeRegister(cc, "Src",       (void*)Src,       1);
    RuntimeRegister(cc, "Funs",      (void*)Funs,      0);
    RuntimeRegister(cc, "MemMap",    (void*)MemMap,    0);
    RuntimeRegister(cc, "Regs",      (void*)regs_snap_stub, 0);
    RuntimeRegister(cc, "Exec",      (void*)Exec,      1);
    RuntimeRegister(cc, "FnAddr",    (void*)FnAddr,    1);
    RuntimeRegister(cc, "FnSize",    (void*)FnSize,    1);   // code size from the hash entry (0 = C builtin)
    RuntimeRegister(cc, "SymBase",   (void*)SymBase,   1);   // addr -> exe_addr of nearest-below fn
    RuntimeRegister(cc, "SymName",   (void*)SymName,   1);   // addr -> name string of that fn (0 if none)
    RuntimeRegister(cc, "SetIsr",    (void*)SetIsr,    1);
    RuntimeRegister(cc, "TrapInit",  (void*)TrapInit,  0);
    RuntimeRegister(cc, "Ecall",     (void*)Ecall,     0);
    RuntimeRegister(cc, "TimerArm",  (void*)TimerArm,  1);
    RuntimeRegister(cc, "Reset",     (void*)Reset,     0);
}

void repl(void) {
    char input[512];
    int pos;
    char c;
    
    // Create compiler once and reuse across REPL iterations
    // This ensures the hash table persists across inputs
    g_cc = CompilerNew("", "repl");
    Compiler *cc = g_cc;
    RuntimeInit(cc);
    memfs_seed();   // ship the editable kernel primitives into the FS
    // The system boots its own HolyC: auto-Run boot.hc (loads drivers, prints a banner).
    // Silent (echo off) except boot.hc's own output. Edit boot.hc to change startup.
    { MemFile *bf = memfs_find("boot.hc");
      if (bf) { bf->data[bf->len] = 0; run_source(bf->data); } }
    
    // Accumulation buffer for multi-line inputs (functions/blocks)
    static char accum[16384];
    int accum_len = 0;
    int brace_depth = 0;
    int paren_depth = 0;
    
    while (1) {
        puts_uart("> ");
        pos = 0;
        
        // Read line
        while (1) {
            c = getc_uart();
            if (c == 0) {
                // No data available, continue waiting
                continue;
            }
            if (c == '\r' || c == '\n') {
                input[pos] = '\0';
                puts_uart("\n");
                break;
            }
            if (c == 127 || c == 8) {  // Backspace
                if (pos > 0) {
                    pos--;
                    puts_uart("\b \b");
                }
                continue;
            }
            if (pos < 511 && c >= 32 && c < 127) {
                input[pos++] = c;
                putc_uart(c);
            } else if (c == '\t' && pos < 511) {   // TABs (common in TempleOS sources) become a space
                input[pos++] = ' ';
                putc_uart(' ');
            }
        }
        
        if (pos == 0) continue;
        
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
        
        // Track simple brace/paren depth to detect statement/function completion
        for (int i = 0; i < pos; i++) {
            char ch = input[i];
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
                if (!should_parse && !is_directive && pos > 0 && input[pos-1] != ',') {
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
        repl_eval(accum, 1);
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

