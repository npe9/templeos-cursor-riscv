// Worry Dream Machine - Live Interactive REPL
// Type HolyC code over UART, compile and execute it

#include <stdint.h>
#include <stddef.h>
#include "../holyc_compiler.h"

#define UART_BASE 0x10000000
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
static U8 heap_mem[12*1024*1024];  // 12MB heap for compiler structures (reusable)
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
#define MEMFS_FILE_CAP  8192
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
    RuntimeRegister(cc, "Ed",        (void*)Ed,        1);
}

void repl(void) {
    char input[512];
    int pos;
    char c;
    
    // Create compiler once and reuse across REPL iterations
    // This ensures the hash table persists across inputs
    Compiler *cc = CompilerNew("", "repl");
    RuntimeInit(cc);
    
    // Accumulation buffer for multi-line inputs (functions/blocks)
    static char accum[4096];
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
            }
        }
        
        if (is_directive && brace_depth == 0 && paren_depth == 0) should_parse = 1;
        if (!should_parse) {
            // Prompt for more lines
            continue;
        }
        
        // Reinitialize lexer and compiler state for accumulated input (keep hash table)
        if (cc->lex.src) free(cc->lex.src);
        cc->lex.src = strdup(accum);
        cc->lex.ptr = cc->lex.src;
        cc->lex.line = 1;
        cc->lex.col = 1;
        cc->lex.hash_entry = NULL;
        
        // Reset IC chain for new statement
        cc->ic_head = NULL;
        cc->ic_tail = NULL;
        cc->labels = NULL;
        cc->label_counter = 0;
        cc->locals_size = 0;
        
        // Reset accumulation after capturing into lexer
        accum_len = 0;
        brace_depth = 0;
        paren_depth = 0;
        
        if (!cc) continue;
        
        // Parse the input as top-level HolyC (same grammar as a source file): definitions
        // register themselves (functions are compiled by the parser and get an exe_addr);
        // plain statements leave IC behind, which we compile and run right away.
        extern void LexNext(Compiler *cc);
        extern Bool ParseTopLevel(Compiler *cc);
        extern U8 *CompileExpression(Compiler *cc, I64 *size_out);
        LexNext(cc);
        Bool ok = true;
        int defined_fn = 0;
        while (ok && cc->lex.token != TK_EOF) {
            CHashFun *fn_before = cc->last_compiled_func;
            I64 addr_before = fn_before ? fn_before->exe_addr : 0;
            ok = ParseTopLevel(cc);
            if (ok && cc->last_compiled_func &&
                (cc->last_compiled_func != fn_before || cc->last_compiled_func->exe_addr != addr_before) &&
                cc->last_compiled_func->exe_addr) {
                defined_fn++;
            }
        }
        // The last statement's value type is the command-line "answer type" (RT_I0 = void).
        U8 ans_ty = cc->last_expr_type;
        // Everything compiled above (functions, statement) is fresh code: order the I-side.
        __asm__ volatile("fence.i" ::: "memory");
        if (!ok) {
            puts_uart("[ERROR] ");
            puts_uart(cc->error ? cc->error : "parse error");
            puts_uart(" near '");
            puts_uart(cc->lex.token_str ? cc->lex.token_str : "");
            puts_uart("' line ");
            print_hex((U64)cc->lex.line);
            puts_uart("\n");
            cc->error = NULL;
            cc->ic_head = NULL;
            cc->ic_tail = NULL;
            continue;
        }
        (void)defined_fn;   // TempleOS is silent on a successful definition
        if (cc->ic_head) {
            // Statement: compile it as a frame of its own (switch/try temps get real slots);
            // the last value is the answer (match TempleOS LexStmt2Bin:13-14).
            extern void WrapStatementsAsFrame(Compiler *cc);
            extern U8 *CompileAOT(Compiler *cc, I64 *size_out);
            WrapStatementsAsFrame(cc);
            I64 code_size = 0;
            U8 *machine_code = CompileAOT(cc, &code_size);
            cc->ic_head = NULL;
            cc->ic_tail = NULL;
            if (!machine_code || code_size <= 0) {
                puts_uart("[COMPILE FAILED]\n");
                continue;
            }
            __asm__ volatile("fence.i" ::: "memory");
            // TempleOS approach: cast the compiled code to a function and call it (CMain.HC:15,32)
            typedef I64 (*FuncPtr)();
            FuncPtr func_ptr = (FuncPtr)machine_code;
            U64 t0, t1;
            __asm__ volatile("rdtime %0" : "=r"(t0));
            I64 result = func_ptr();
            __asm__ volatile("rdtime %0" : "=r"(t1));
            g_answer = result;
            print_time(t1 - t0);                       // TempleOS CmdLinePmt: "%8.6fs ans=0x%08X=%d"
            if (ans_ty == RT_I0) {
                puts_uart("\n");                        // void statement: timing only, no ans=
            } else if (ans_ty == RT_F64) {
                puts_uart(" ansf="); print_f64((U64)result); puts_uart("\n");
            } else {
                puts_uart(" ans="); print_hex(result); putc_uart('='); print_dec(result); puts_uart("\n");
            }
            free(machine_code);
        }
        
        // Don't free the compiler - reuse it for the next iteration
    }
}

int main(void) {
    repl();
    while (1) __asm__ volatile ("wfi");
}

