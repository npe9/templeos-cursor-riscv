/* HolyC AST/CST formatter — see holyc_fmt.h for rules and hybrid boundary. */

#include "holyc_fmt.h"

#include <stdlib.h>
#include <string.h>

#define FMT_SPACES 2
#define FT_EOF 0
#define FT_IDENT 1
#define FT_KW 2
#define FT_NUM 3
#define FT_STR 4
#define FT_CHAR 5
#define FT_OP 6
#define FT_COMMENT 7
#define FT_PREPROC 8
#define FT_PUNCT 9

/* Keyword ids stored in FmtTok.aux when kind==FT_KW */
#define FK_IF 1
#define FK_ELSE 2
#define FK_WHILE 3
#define FK_FOR 4
#define FK_DO 5
#define FK_SWITCH 6
#define FK_CASE 7
#define FK_DEFAULT 8
#define FK_TRY 9
#define FK_CATCH 10
#define FK_ASM 11
#define FK_CLASS 12
#define FK_UNION 13
#define FK_ENUM 14
#define FK_RETURN 15
#define FK_GOTO 16
#define FK_BREAK 17
#define FK_CONTINUE 18
#define FK_OTHER 99

typedef struct {
  int kind;
  int aux;          /* FK_* for keywords; opening char for some punct */
  const char *s;    /* pointer into source or static op text */
  int len;
  int line;
} FmtTok;

typedef enum {
  FN_FILE = 1,
  FN_PREPROC,
  FN_COMMENT,
  FN_BLANK,
  FN_ASM,
  FN_BLOCK,
  FN_IF,
  FN_WHILE,
  FN_FOR,
  FN_DO,
  FN_SWITCH,
  FN_CASE,
  FN_DEFAULT,
  FN_TRY,
  FN_LABEL,
  FN_UNIT,   /* header tokens + optional block (fn/class/enum/…) */
  FN_STMT,   /* token list ending with ; */
  FN_ELSE
} FmtKind;

typedef struct FmtNode {
  FmtKind kind;
  FmtTok *toks;
  int ntoks;
  int trailing_semi; /* class/union/enum: keep `};` on one line for REPL run_source */
  char *text; /* PREPROC / COMMENT / ASM interior (owned) */
  struct FmtNode **kids;
  int nkids;
  struct FmtNode *els; /* IF / DO(while)/ TRY(catch) trailing */
} FmtNode;

typedef struct {
  const char *src;
  const char *p;
  const char *end;
  int line;
  FmtTok *toks;
  int ntoks;
  int captoks;
} FmtLex;

typedef struct {
  FmtTok *toks;
  int ntoks;
  int i;
} FmtParse;

typedef struct {
  char *buf;
  long long cap;
  long long len;
  int err;
} FmtOut;

/* ─── small utils ─── */

static int fmt_ident_start(int c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' ||
         (unsigned char)c >= 128;
}
static int fmt_ident(int c) {
  return fmt_ident_start(c) || (c >= '0' && c <= '9');
}
static int fmt_ws(int c) { return c == ' ' || c == '\t' || c == '\r'; }

int HolyFmtIsHcName(const char *name) {
  const char *base;
  int n;
  if (!name || !name[0]) return 0;
  base = name;
  while (*base) base++;
  while (base > name && base[-1] != '/' && base[-1] != '\\') base--;
  n = 0;
  while (base[n]) n++;
  if (n < 3 || base[n - 3] != '.') return 0;
  if ((base[n - 2] == 'h' || base[n - 2] == 'H') &&
      (base[n - 1] == 'c' || base[n - 1] == 'C' ||
       base[n - 1] == 'h' || base[n - 1] == 'H'))
    return 1;
  return 0;
}

static void *fmt_xmalloc(size_t n) {
  void *p = malloc(n ? n : 1);
  return p;
}
static char *fmt_xstrndup(const char *s, int n) {
  char *d = (char *)fmt_xmalloc((size_t)n + 1);
  if (!d) return NULL;
  memcpy(d, s, (size_t)n);
  d[n] = 0;
  return d;
}

static void fout_emit(FmtOut *o, int c) {
  if (o->err) return;
  if (o->len + 1 >= o->cap) {
    o->err = 1;
    return;
  }
  o->buf[o->len++] = (char)c;
}
static void fout_emit_n(FmtOut *o, const char *s, int n) {
  int i;
  for (i = 0; i < n; i++) fout_emit(o, (unsigned char)s[i]);
}
static void fout_emit_s(FmtOut *o, const char *s) {
  if (!s) return;
  while (*s) fout_emit(o, (unsigned char)*s++);
}
static void fout_indent(FmtOut *o, int depth) {
  int i, n = depth * FMT_SPACES;
  for (i = 0; i < n; i++) fout_emit(o, ' ');
}

/* ─── keyword table ─── */

static int fmt_kw_id(const char *s, int n) {
  static const struct {
    const char *name;
    int id;
  } kws[] = {
      {"if", FK_IF},         {"else", FK_ELSE},   {"while", FK_WHILE},
      {"for", FK_FOR},       {"do", FK_DO},       {"switch", FK_SWITCH},
      {"case", FK_CASE},     {"default", FK_DEFAULT}, {"try", FK_TRY},
      {"catch", FK_CATCH},   {"asm", FK_ASM},     {"class", FK_CLASS},
      {"union", FK_UNION},   {"enum", FK_ENUM},   {"return", FK_RETURN},
      {"goto", FK_GOTO},     {"break", FK_BREAK}, {"continue", FK_CONTINUE},
  };
  size_t i;
  for (i = 0; i < sizeof(kws) / sizeof(kws[0]); i++) {
    if ((int)strlen(kws[i].name) == n && !memcmp(s, kws[i].name, (size_t)n))
      return kws[i].id;
  }
  return 0;
}

/* ─── lexer ─── */

static int flex_push(FmtLex *L, int kind, int aux, const char *s, int len) {
  FmtTok *t;
  if (L->ntoks + 1 > L->captoks) {
    int nc = L->captoks ? L->captoks * 2 : 256;
    FmtTok *nt = (FmtTok *)realloc(L->toks, (size_t)nc * sizeof(FmtTok));
    if (!nt) return 0;
    L->toks = nt;
    L->captoks = nc;
  }
  t = &L->toks[L->ntoks++];
  t->kind = kind;
  t->aux = aux;
  t->s = s;
  t->len = len;
  t->line = L->line;
  return 1;
}

static void flex_skip_ws_no_nl(FmtLex *L) {
  while (L->p < L->end && fmt_ws((unsigned char)*L->p)) L->p++;
}

static int flex_lex_one(FmtLex *L) {
  const char *start;
  int c, c2, n, kid;

  flex_skip_ws_no_nl(L);
  if (L->p >= L->end) return 0;

  c = (unsigned char)*L->p;
  c2 = (L->p + 1 < L->end) ? (unsigned char)L->p[1] : 0;

  if (c == '\n') {
    L->p++;
    L->line++;
    return 1; /* newlines are separators, not tokens — blank detection in parse */
  }

  /* Preprocessor: whole directive (with \\ continuations) */
  if (c == '#') {
    start = L->p;
    while (L->p < L->end) {
      if (*L->p == '\\' && L->p + 1 < L->end && L->p[1] == '\n') {
        L->p += 2;
        L->line++;
        continue;
      }
      if (*L->p == '\n') break;
      L->p++;
    }
    return flex_push(L, FT_PREPROC, 0, start, (int)(L->p - start));
  }

  /* Comments */
  if (c == '/' && c2 == '/') {
    start = L->p;
    L->p += 2;
    while (L->p < L->end && *L->p != '\n') L->p++;
    return flex_push(L, FT_COMMENT, 0, start, (int)(L->p - start));
  }
  if (c == '/' && c2 == '*') {
    start = L->p;
    L->p += 2;
    while (L->p + 1 < L->end && !(*L->p == '*' && L->p[1] == '/')) {
      if (*L->p == '\n') L->line++;
      L->p++;
    }
    if (L->p + 1 < L->end) L->p += 2;
    return flex_push(L, FT_COMMENT, 0, start, (int)(L->p - start));
  }

  /* String */
  if (c == '"') {
    start = L->p;
    L->p++;
    while (L->p < L->end && *L->p != '"') {
      if (*L->p == '\\' && L->p + 1 < L->end) {
        L->p += 2;
        continue;
      }
      if (*L->p == '\n') L->line++;
      L->p++;
    }
    if (L->p < L->end) L->p++;
    return flex_push(L, FT_STR, 0, start, (int)(L->p - start));
  }

  /* Char literal */
  if (c == '\'') {
    start = L->p;
    L->p++;
    while (L->p < L->end && *L->p != '\'') {
      if (*L->p == '\\' && L->p + 1 < L->end) {
        L->p += 2;
        continue;
      }
      if (*L->p == '\n') L->line++;
      L->p++;
    }
    if (L->p < L->end) L->p++;
    return flex_push(L, FT_CHAR, 0, start, (int)(L->p - start));
  }

  /* Identifier / keyword */
  if (fmt_ident_start(c)) {
    start = L->p;
    L->p++;
    while (L->p < L->end && fmt_ident((unsigned char)*L->p)) L->p++;
    n = (int)(L->p - start);
    kid = fmt_kw_id(start, n);
    if (kid)
      return flex_push(L, FT_KW, kid, start, n);
    return flex_push(L, FT_IDENT, 0, start, n);
  }

  /* Number (incl. 0x / 0b / 0o / floats) */
  if ((c >= '0' && c <= '9') ||
      (c == '.' && c2 >= '0' && c2 <= '9')) {
    start = L->p;
    if (c == '0' && (c2 == 'x' || c2 == 'X' || c2 == 'b' || c2 == 'B' ||
                     c2 == 'o' || c2 == 'O' || c2 == 'd' || c2 == 'D')) {
      L->p += 2;
      while (L->p < L->end &&
             (fmt_ident((unsigned char)*L->p) || *L->p == '.'))
        L->p++;
    } else {
      while (L->p < L->end &&
             ((*L->p >= '0' && *L->p <= '9') || *L->p == '.' || *L->p == 'e' ||
              *L->p == 'E' ||
              ((*L->p == '+' || *L->p == '-') && L->p > start &&
               (L->p[-1] == 'e' || L->p[-1] == 'E'))))
        L->p++;
    }
    return flex_push(L, FT_NUM, 0, start, (int)(L->p - start));
  }

  /* Multi-char operators */
  {
    static const char *ops[] = {
        "...", "<<=" , ">>=", "<=>", /* keep long first */
        "==", "!=", "<=", ">=", "<<", ">>", "&&", "||", "^^",
        "++", "--", "+=", "-=", "*=", "/=", "&=", "|=", "^=", "%=",
        "->", "::", "$$", NULL};
    int i;
    for (i = 0; ops[i]; i++) {
      int ol = (int)strlen(ops[i]);
      if (L->end - L->p >= ol && !memcmp(L->p, ops[i], (size_t)ol)) {
        start = L->p;
        L->p += ol;
        return flex_push(L, FT_OP, 0, start, ol);
      }
    }
  }

  /* Single punct / op */
  start = L->p;
  L->p++;
  if (strchr("=+-*/%&|^~!<>?:.@`", c))
    return flex_push(L, FT_OP, c, start, 1);
  return flex_push(L, FT_PUNCT, c, start, 1);
}

static int flex_tokenize(FmtLex *L) {
  L->toks = NULL;
  L->ntoks = 0;
  L->captoks = 0;
  L->p = L->src;
  L->end = L->src + strlen(L->src);
  L->line = 1;
  while (L->p < L->end) {
    const char *before = L->p;
    if (!flex_lex_one(L)) return 0;
    if (L->p == before && L->p < L->end) {
      /* safety: skip one char to avoid infinite loop */
      L->p++;
    }
  }
  return flex_push(L, FT_EOF, 0, L->end, 0);
}

/* ─── AST helpers ─── */

static FmtNode *fnode_new(FmtKind k) {
  FmtNode *n = (FmtNode *)fmt_xmalloc(sizeof(FmtNode));
  if (!n) return NULL;
  memset(n, 0, sizeof(*n));
  n->kind = k;
  return n;
}

static int fnode_add(FmtNode *parent, FmtNode *kid) {
  FmtNode **nk;
  if (!kid) return 0;
  nk = (FmtNode **)realloc(parent->kids, (size_t)(parent->nkids + 1) * sizeof(FmtNode *));
  if (!nk) return 0;
  parent->kids = nk;
  parent->kids[parent->nkids++] = kid;
  return 1;
}

static int fnode_set_toks(FmtNode *n, FmtTok *t, int nt) {
  if (nt <= 0) {
    n->toks = NULL;
    n->ntoks = 0;
    return 1;
  }
  n->toks = (FmtTok *)fmt_xmalloc((size_t)nt * sizeof(FmtTok));
  if (!n->toks) return 0;
  memcpy(n->toks, t, (size_t)nt * sizeof(FmtTok));
  n->ntoks = nt;
  return 1;
}

static void fnode_free(FmtNode *n) {
  int i;
  if (!n) return;
  for (i = 0; i < n->nkids; i++) fnode_free(n->kids[i]);
  free(n->kids);
  fnode_free(n->els);
  free(n->toks);
  free(n->text);
  free(n);
}

/* ─── parser ─── */

static FmtTok *fp_cur(FmtParse *P) {
  if (P->i >= P->ntoks) return &P->toks[P->ntoks - 1];
  return &P->toks[P->i];
}
static int fp_kind(FmtParse *P) { return fp_cur(P)->kind; }
static int fp_aux(FmtParse *P) { return fp_cur(P)->aux; }
static void fp_next(FmtParse *P) {
  if (P->i < P->ntoks - 1) P->i++;
}
static int fp_is_kw(FmtParse *P, int k) {
  return fp_kind(P) == FT_KW && fp_aux(P) == k;
}
static int fp_is_punct(FmtParse *P, int c) {
  return fp_kind(P) == FT_PUNCT && fp_aux(P) == c;
}

static FmtNode *parse_item(FmtParse *P);
static FmtNode *parse_block(FmtParse *P);

static int fp_skip_comments_into(FmtParse *P, FmtNode *parent) {
  while (fp_kind(P) == FT_COMMENT || fp_kind(P) == FT_PREPROC) {
    FmtNode *c = fnode_new(fp_kind(P) == FT_PREPROC ? FN_PREPROC : FN_COMMENT);
    if (!c) return 0;
    c->text = fmt_xstrndup(fp_cur(P)->s, fp_cur(P)->len);
    if (!c->text) {
      fnode_free(c);
      return 0;
    }
    if (!fnode_add(parent, c)) {
      fnode_free(c);
      return 0;
    }
    fp_next(P);
  }
  return 1;
}

/* Collect balanced (...) tokens starting at current '(' */
static int fp_collect_parens(FmtParse *P, FmtTok **out, int *nout) {
  int depth = 0, start = P->i, n;
  if (!fp_is_punct(P, '(')) return 0;
  do {
    if (fp_kind(P) == FT_EOF) return 0;
    if (fp_is_punct(P, '(')) depth++;
    else if (fp_is_punct(P, ')')) depth--;
    fp_next(P);
  } while (depth > 0);
  n = P->i - start;
  *out = &P->toks[start];
  *nout = n;
  return 1;
}

static FmtNode *parse_block(FmtParse *P) {
  FmtNode *blk = fnode_new(FN_BLOCK);
  if (!blk) return NULL;
  if (!fp_is_punct(P, '{')) {
    fnode_free(blk);
    return NULL;
  }
  fp_next(P);
  while (fp_kind(P) != FT_EOF && !fp_is_punct(P, '}')) {
    FmtNode *it;
    if (!fp_skip_comments_into(P, blk)) {
      fnode_free(blk);
      return NULL;
    }
    if (fp_is_punct(P, '}')) break;
    if (fp_kind(P) == FT_EOF) break;
    it = parse_item(P);
    if (!it) {
      fnode_free(blk);
      return NULL;
    }
    if (!fnode_add(blk, it)) {
      fnode_free(it);
      fnode_free(blk);
      return NULL;
    }
  }
  if (fp_is_punct(P, '}')) fp_next(P);
  return blk;
}

/* Parse asm { ... } — interior preserved as raw text from first '{' to match. */
static FmtNode *parse_asm(FmtParse *P) {
  FmtNode *n;
  const char *start, *end;
  int depth;
  if (!fp_is_kw(P, FK_ASM)) return NULL;
  fp_next(P);
  while (fp_kind(P) == FT_COMMENT) fp_next(P);
  if (!fp_is_punct(P, '{')) return NULL;
  /* Reconstruct interior from token spans: from after '{' to before matching '}' */
  start = fp_cur(P)->s + 1; /* after '{' */
  depth = 0;
  do {
    if (fp_kind(P) == FT_EOF) break;
    if (fp_is_punct(P, '{')) depth++;
    else if (fp_is_punct(P, '}')) depth--;
    if (depth == 0) {
      end = fp_cur(P)->s;
      fp_next(P);
      break;
    }
    fp_next(P);
    end = fp_cur(P)->s;
  } while (1);
  n = fnode_new(FN_ASM);
  if (!n) return NULL;
  /* Drop the newline immediately after '{' / before '}' so re-indent is idempotent. */
  while (start < end && (*start == '\r' || *start == '\n')) start++;
  while (end > start && (end[-1] == '\r' || end[-1] == '\n' || end[-1] == ' ' ||
                         end[-1] == '\t'))
    end--;
  if (end > start)
    n->text = fmt_xstrndup(start, (int)(end - start));
  else
    n->text = fmt_xstrndup("", 0);
  if (!n->text) {
    fnode_free(n);
    return NULL;
  }
  return n;
}

static FmtNode *parse_ctrl_body(FmtParse *P) {
  if (fp_is_punct(P, '{')) return parse_block(P);
  return parse_item(P);
}

static FmtNode *parse_if(FmtParse *P) {
  FmtNode *n = fnode_new(FN_IF);
  FmtTok *pt;
  int pn;
  FmtNode *body, *e;
  if (!n) return NULL;
  fp_next(P); /* if */
  if (!fp_collect_parens(P, &pt, &pn) || !fnode_set_toks(n, pt, pn)) {
    fnode_free(n);
    return NULL;
  }
  body = parse_ctrl_body(P);
  if (!body || !fnode_add(n, body)) {
    fnode_free(body);
    fnode_free(n);
    return NULL;
  }
  if (fp_is_kw(P, FK_ELSE)) {
    fp_next(P);
    e = fnode_new(FN_ELSE);
    if (!e) {
      fnode_free(n);
      return NULL;
    }
    if (fp_is_kw(P, FK_IF)) {
      body = parse_if(P);
    } else {
      body = parse_ctrl_body(P);
    }
    if (!body || !fnode_add(e, body)) {
      fnode_free(body);
      fnode_free(e);
      fnode_free(n);
      return NULL;
    }
    n->els = e;
  }
  return n;
}

static FmtNode *parse_while(FmtParse *P) {
  FmtNode *n = fnode_new(FN_WHILE);
  FmtTok *pt;
  int pn;
  FmtNode *body;
  if (!n) return NULL;
  fp_next(P);
  if (!fp_collect_parens(P, &pt, &pn) || !fnode_set_toks(n, pt, pn)) {
    fnode_free(n);
    return NULL;
  }
  body = parse_ctrl_body(P);
  if (!body || !fnode_add(n, body)) {
    fnode_free(body);
    fnode_free(n);
    return NULL;
  }
  return n;
}

static FmtNode *parse_for(FmtParse *P) {
  FmtNode *n = fnode_new(FN_FOR);
  FmtTok *pt;
  int pn;
  FmtNode *body;
  if (!n) return NULL;
  fp_next(P);
  if (!fp_collect_parens(P, &pt, &pn) || !fnode_set_toks(n, pt, pn)) {
    fnode_free(n);
    return NULL;
  }
  body = parse_ctrl_body(P);
  if (!body || !fnode_add(n, body)) {
    fnode_free(body);
    fnode_free(n);
    return NULL;
  }
  return n;
}

static FmtNode *parse_do(FmtParse *P) {
  FmtNode *n = fnode_new(FN_DO);
  FmtNode *body;
  FmtTok *pt;
  int pn;
  if (!n) return NULL;
  fp_next(P);
  body = parse_ctrl_body(P);
  if (!body || !fnode_add(n, body)) {
    fnode_free(body);
    fnode_free(n);
    return NULL;
  }
  if (!fp_is_kw(P, FK_WHILE)) return n;
  fp_next(P);
  if (fp_collect_parens(P, &pt, &pn)) {
    /* stash while-cond on els as a tiny STMT-like node */
    FmtNode *w = fnode_new(FN_STMT);
    if (w && fnode_set_toks(w, pt, pn)) n->els = w;
    else fnode_free(w);
  }
  if (fp_is_punct(P, ';')) fp_next(P);
  return n;
}

static FmtNode *parse_switch(FmtParse *P) {
  FmtNode *n = fnode_new(FN_SWITCH);
  FmtTok *pt;
  int pn;
  FmtNode *body;
  if (!n) return NULL;
  fp_next(P);
  if (!fp_collect_parens(P, &pt, &pn) || !fnode_set_toks(n, pt, pn)) {
    fnode_free(n);
    return NULL;
  }
  body = parse_ctrl_body(P);
  if (!body || !fnode_add(n, body)) {
    fnode_free(body);
    fnode_free(n);
    return NULL;
  }
  return n;
}

static FmtNode *parse_try(FmtParse *P) {
  FmtNode *n = fnode_new(FN_TRY);
  FmtNode *body, *c;
  if (!n) return NULL;
  fp_next(P);
  body = parse_ctrl_body(P);
  if (!body || !fnode_add(n, body)) {
    fnode_free(body);
    fnode_free(n);
    return NULL;
  }
  if (fp_is_kw(P, FK_CATCH)) {
    fp_next(P);
    c = fnode_new(FN_ELSE); /* reuse ELSE slot as catch body wrapper */
    if (!c) {
      fnode_free(n);
      return NULL;
    }
    body = parse_ctrl_body(P);
    if (!body || !fnode_add(c, body)) {
      fnode_free(body);
      fnode_free(c);
      fnode_free(n);
      return NULL;
    }
    n->els = c;
  }
  return n;
}

/* Generic statement / declaration / function: tokens until ; or {block} */
static FmtNode *parse_unit_or_stmt(FmtParse *P) {
  int start = P->i;
  int depth_p = 0, depth_b = 0, depth_s = 0;

  while (fp_kind(P) != FT_EOF) {
    FmtTok *t = fp_cur(P);

    if (depth_p == 0 && depth_b == 0 && depth_s == 0) {
      if (t->kind == FT_PUNCT && t->aux == '{') {
        /* `T x = { … };` aggregate init — not a function/class body. */
        if (P->i > 0) {
          FmtTok *prev = &P->toks[P->i - 1];
          if (prev->kind == FT_OP && prev->len == 1 && prev->s[0] == '=') {
            /* fall through: consume braces inside stmt until ';' */
          } else {
            FmtNode *n = fnode_new(FN_UNIT);
            FmtNode *blk;
            int nt = P->i - start;
            if (!n) return NULL;
            if (nt > 0 && !fnode_set_toks(n, &P->toks[start], nt)) {
              fnode_free(n);
              return NULL;
            }
            blk = parse_block(P);
            if (!blk || !fnode_add(n, blk)) {
              fnode_free(blk);
              fnode_free(n);
              return NULL;
            }
            /* class/union/enum require `};` — keep on one line for REPL run_source. */
            if (fp_is_punct(P, ';')) {
              n->trailing_semi = 1;
              fp_next(P);
            }
            return n;
          }
        } else {
          FmtNode *n = fnode_new(FN_UNIT);
          FmtNode *blk;
          int nt = P->i - start;
          if (!n) return NULL;
          if (nt > 0 && !fnode_set_toks(n, &P->toks[start], nt)) {
            fnode_free(n);
            return NULL;
          }
          blk = parse_block(P);
          if (!blk || !fnode_add(n, blk)) {
            fnode_free(blk);
            fnode_free(n);
            return NULL;
          }
          if (fp_is_punct(P, ';')) {
            n->trailing_semi = 1;
            fp_next(P);
          }
          return n;
        }
      }
      if (t->kind == FT_PUNCT && t->aux == ';') {
        FmtNode *n = fnode_new(FN_STMT);
        int nt;
        fp_next(P);
        nt = P->i - start;
        if (!n) return NULL;
        if (!fnode_set_toks(n, &P->toks[start], nt)) {
          fnode_free(n);
          return NULL;
        }
        return n;
      }
    }

    if (t->kind == FT_PUNCT) {
      if (t->aux == '(') depth_p++;
      else if (t->aux == ')') {
        if (depth_p > 0) depth_p--;
      } else if (t->aux == '[') depth_s++;
      else if (t->aux == ']') {
        if (depth_s > 0) depth_s--;
      } else if (t->aux == '{') depth_b++;
      else if (t->aux == '}') {
        if (depth_b > 0) depth_b--;
      }
    }
    fp_next(P);
  }

  /* Trailing tokens without ; — emit as stmt */
  {
    FmtNode *n = fnode_new(FN_STMT);
    int nt = P->i - start;
    if (!n) return NULL;
    if (nt > 0 && !fnode_set_toks(n, &P->toks[start], nt)) {
      fnode_free(n);
      return NULL;
    }
    return n;
  }
}

static FmtNode *parse_item(FmtParse *P) {
  /* Labels: IDENT ':' not followed by ':' (not ::) and not a ternary mid-expr —
   * only when ':' is immediately next. */
  if (fp_kind(P) == FT_IDENT) {
    int save = P->i;
    fp_next(P);
    if (fp_is_punct(P, ':') || (fp_kind(P) == FT_OP && fp_cur(P)->len == 1 &&
                                fp_cur(P)->s[0] == ':')) {
      /* not :: */
      if (!(fp_kind(P) == FT_OP && fp_cur(P)->len == 2)) {
        FmtNode *n = fnode_new(FN_LABEL);
        if (!n) return NULL;
        if (!fnode_set_toks(n, &P->toks[save], 1)) {
          fnode_free(n);
          return NULL;
        }
        fp_next(P); /* : */
        return n;
      }
    }
    P->i = save;
  }

  if (fp_is_kw(P, FK_CASE)) {
    FmtNode *n = fnode_new(FN_CASE);
    int start = P->i;
    if (!n) return NULL;
    fp_next(P);
    while (fp_kind(P) != FT_EOF &&
           !(fp_is_punct(P, ':') ||
             (fp_kind(P) == FT_OP && fp_cur(P)->len == 1 && fp_cur(P)->s[0] == ':')))
      fp_next(P);
    if (fp_kind(P) != FT_EOF) fp_next(P); /* : */
    if (!fnode_set_toks(n, &P->toks[start], P->i - start)) {
      fnode_free(n);
      return NULL;
    }
    return n;
  }
  if (fp_is_kw(P, FK_DEFAULT)) {
    FmtNode *n = fnode_new(FN_DEFAULT);
    if (!n) return NULL;
    fp_next(P);
    if (fp_is_punct(P, ':') ||
        (fp_kind(P) == FT_OP && fp_cur(P)->len == 1 && fp_cur(P)->s[0] == ':'))
      fp_next(P);
    return n;
  }

  if (fp_is_kw(P, FK_IF)) return parse_if(P);
  if (fp_is_kw(P, FK_WHILE)) return parse_while(P);
  if (fp_is_kw(P, FK_FOR)) return parse_for(P);
  if (fp_is_kw(P, FK_DO)) return parse_do(P);
  if (fp_is_kw(P, FK_SWITCH)) return parse_switch(P);
  if (fp_is_kw(P, FK_TRY)) return parse_try(P);
  if (fp_is_kw(P, FK_ASM)) return parse_asm(P);

  return parse_unit_or_stmt(P);
}

static FmtNode *parse_file(FmtParse *P) {
  FmtNode *file = fnode_new(FN_FILE);
  if (!file) return NULL;
  while (fp_kind(P) != FT_EOF) {
    FmtNode *it;
    if (!fp_skip_comments_into(P, file)) {
      fnode_free(file);
      return NULL;
    }
    if (fp_kind(P) == FT_EOF) break;
    it = parse_item(P);
    if (!it) {
      fnode_free(file);
      return NULL;
    }
    if (!fnode_add(file, it)) {
      fnode_free(it);
      fnode_free(file);
      return NULL;
    }
  }
  return file;
}

/* ─── token pretty-print (expression / header interiors) ─── */

static int tok_atom(const FmtTok *t) {
  return t->kind == FT_IDENT || t->kind == FT_KW || t->kind == FT_NUM ||
         t->kind == FT_STR || t->kind == FT_CHAR;
}
static int tok_is(const FmtTok *t, int kind, int aux) {
  return t->kind == kind && (aux < 0 || t->aux == aux);
}

static int tok_is_star(const FmtTok *t) {
  return t && t->kind == FT_OP && t->len == 1 && t->s[0] == '*';
}

/* Pointer star after a type name: Ident/Kw * Ident|*|)  — not binary 0.5*x or )* */
static int tok_ptr_star(FmtTok *toks, int ntoks, int i) {
  FmtTok *t = &toks[i], *prev, *next;
  if (!tok_is_star(t) || i == 0) return 0;
  prev = &toks[i - 1];
  if (!(prev->kind == FT_IDENT || prev->kind == FT_KW)) return 0;
  if (i + 1 >= ntoks) return 1;
  next = &toks[i + 1];
  if (tok_is_star(next) || next->kind == FT_IDENT || next->kind == FT_KW ||
      tok_is(next, FT_PUNCT, ')') || tok_is(next, FT_PUNCT, ',') ||
      tok_is(next, FT_PUNCT, ';') || tok_is(next, FT_PUNCT, '['))
    return 1;
  return 0;
}

static int tok_eq_op(const FmtTok *t, const char *op) {
  int n;
  if (!t || t->kind != FT_OP || !op) return 0;
  n = (int)strlen(op);
  return t->len == n && !memcmp(t->s, op, (size_t)n);
}

/* Member/range glue: a->b, a.b, A::B, 1...3 — no spaces */
static int tok_is_tight_op(const FmtTok *t) {
  if (!t || t->kind != FT_OP) return 0;
  if (t->len == 1 && (t->s[0] == '.' || t->s[0] == '@' || t->s[0] == '`'))
    return 1;
  return tok_eq_op(t, "->") || tok_eq_op(t, "::") || tok_eq_op(t, "...") ||
         tok_eq_op(t, "$$");
}

static int tok_is_incdec(const FmtTok *t) {
  return tok_eq_op(t, "++") || tok_eq_op(t, "--");
}

static int tok_can_unary(const FmtTok *t) {
  if (!t || t->kind != FT_OP) return 0;
  if (tok_is_incdec(t)) return 1;
  if (t->len == 1) {
    char c = t->s[0];
    return c == '+' || c == '-' || c == '!' || c == '~' || c == '*' || c == '&';
  }
  return 0;
}

/* Token that can be the left operand of a binary/postfix op.
 * Keywords (return/case/…) do not count — so `return -x` stays unary. */
static int tok_ends_value(const FmtTok *t) {
  if (!t) return 0;
  if (t->kind == FT_IDENT || t->kind == FT_NUM || t->kind == FT_STR ||
      t->kind == FT_CHAR)
    return 1;
  if (tok_is(t, FT_PUNCT, ')') || tok_is(t, FT_PUNCT, ']')) return 1;
  if (tok_is_incdec(t)) return 1; /* postfix ++/-- */
  return 0;
}

static int tok_is_postfix(FmtTok *toks, int i) {
  if (i <= 0 || !tok_is_incdec(&toks[i])) return 0;
  return tok_ends_value(&toks[i - 1]);
}

/* Prefix unary at i (+ - ! ~ * & ++ --), not decl star / not postfix */
static int tok_unary_prefix(FmtTok *toks, int ntoks, int i) {
  if (!tok_can_unary(&toks[i])) return 0;
  if (tok_ptr_star(toks, ntoks, i)) return 0;
  if (tok_is_postfix(toks, i)) return 0;
  if (i == 0) return 1;
  return !tok_ends_value(&toks[i - 1]);
}

/* Spaced binary / assignment ops (gofmt/C-like), not unary/postfix/tight/decl * */
static int tok_spaced_op(FmtTok *toks, int ntoks, int i) {
  FmtTok *t = &toks[i];
  if (t->kind != FT_OP) return 0;
  if (tok_is_tight_op(t) || tok_ptr_star(toks, ntoks, i) ||
      tok_unary_prefix(toks, ntoks, i) || tok_is_postfix(toks, i))
    return 0;
  return 1;
}

/* `indent` is where a continuation line starts: a `//` comment runs to end of line, so any
 * token after one must go to the NEXT line. Emitting them inline silently commented out live
 * code — `if (x)  // note` + body on the following line came back as
 * `// notedoc->cur_entry = ...;`, i.e. the assignment vanished into the comment. */
static void emit_toks(FmtOut *o, FmtTok *toks, int ntoks, int indent) {
  int i;
  for (i = 0; i < ntoks; i++) {
    FmtTok *t = &toks[i];
    FmtTok *prev = i > 0 ? &toks[i - 1] : NULL;
    int space = 0;

    if (t->kind == FT_COMMENT) {
      int line_comment = t->len >= 2 && t->s[0] == '/' && t->s[1] == '/';
      if (prev) fout_emit(o, ' ');
      fout_emit_n(o, t->s, t->len);
      if (line_comment && i + 1 < ntoks) {
        fout_emit(o, '\n');
        fout_indent(o, indent);
      }
      continue;
    }

    if (prev) {
      if (tok_atom(prev) && tok_atom(t)) space = 1;
      if (tok_atom(prev) && tok_is(t, FT_PUNCT, '{')) space = 1;
      /* return -x / goto L / case 1 / return (x) */
      if (prev->kind == FT_KW &&
          (prev->aux == FK_RETURN || prev->aux == FK_GOTO ||
           prev->aux == FK_CASE || prev->aux == FK_BREAK ||
           prev->aux == FK_CONTINUE) &&
          (tok_atom(t) || t->kind == FT_OP || tok_is(t, FT_PUNCT, '(')))
        space = 1;
      /* I64 (*fp) — space before declarator paren when next is * or ( */
      if (tok_atom(prev) && tok_is(t, FT_PUNCT, '(') && i + 1 < ntoks &&
          (tok_is_star(&toks[i + 1]) || tok_is(&toks[i + 1], FT_PUNCT, '(')))
        space = 1;
      /* space after , and ; (args, decls, for-headers) */
      if (tok_is(prev, FT_PUNCT, ',') || tok_is(prev, FT_PUNCT, ';'))
        space = 1;
      /* spaces around binary ops: a + b, x == y, p = q */
      if (tok_spaced_op(toks, ntoks, i) || tok_spaced_op(toks, ntoks, i - 1))
        space = 1;
      /* CTask *p — not 0.5 * x */
      if (tok_ptr_star(toks, ntoks, i)) space = 1;

      /* unary / decl-star / tight / postfix stay dense */
      if (tok_unary_prefix(toks, ntoks, i - 1) ||
          tok_ptr_star(toks, ntoks, i - 1) || tok_is_tight_op(prev) ||
          tok_is_tight_op(t) || tok_is_postfix(toks, i))
        space = 0;

      /* no space before , ; ) ] */
      if (tok_is(t, FT_PUNCT, ',') || tok_is(t, FT_PUNCT, ';') ||
          tok_is(t, FT_PUNCT, ')') || tok_is(t, FT_PUNCT, ']'))
        space = 0;
      /* no space after ( [ */
      if (tok_is(prev, FT_PUNCT, '(') || tok_is(prev, FT_PUNCT, '['))
        space = 0;
    }

    if (space) fout_emit(o, ' ');
    fout_emit_n(o, t->s, t->len);
  }
}

/* Emit paren group already including '(' ')' with spaced interior + "kw " prefix */
static void emit_kw_parens(FmtOut *o, const char *kw, FmtTok *toks, int ntoks, int indent) {
  fout_emit_s(o, kw);
  fout_emit(o, ' ');
  emit_toks(o, toks, ntoks, indent);
}

/* ─── asm interior re-indent (tabs) ─── */

static void emit_asm_interior(FmtOut *o, const char *text) {
  const char *p = text;
  int depth = 1; /* inside outer asm { */
  while (*p) {
    const char *eol = p;
    const char *content;
    int blank, starts_close;
    while (*eol && *eol != '\n') eol++;
    content = p;
    while (content < eol && fmt_ws((unsigned char)*content)) content++;
    blank = (content == eol);
    starts_close = (!blank && *content == '}');
    if (!blank) {
      int tabs = depth;
      int i;
      if (starts_close && tabs > 0) tabs--;
      for (i = 0; i < tabs; i++) fout_emit(o, '\t');
      /* emit line content, tracking braces outside strings/comments */
      {
        const char *q = content;
        int in_str = 0, in_chr = 0, in_lc = 0, in_bc = 0;
        while (q < eol) {
          int c = (unsigned char)*q;
          int c2 = (q + 1 < eol) ? (unsigned char)q[1] : 0;
          if (in_lc) {
            fout_emit(o, c);
            q++;
            continue;
          }
          if (in_bc) {
            if (c == '*' && c2 == '/') {
              fout_emit(o, '*');
              fout_emit(o, '/');
              q += 2;
              in_bc = 0;
              continue;
            }
            fout_emit(o, c);
            q++;
            continue;
          }
          if (in_str || in_chr) {
            if (c == '\\' && q + 1 < eol) {
              fout_emit(o, c);
              fout_emit(o, (unsigned char)q[1]);
              q += 2;
              continue;
            }
            if ((in_str && c == '"') || (in_chr && c == '\'')) {
              in_str = in_chr = 0;
            }
            fout_emit(o, c);
            q++;
            continue;
          }
          if (c == '/' && c2 == '/') {
            in_lc = 1;
            fout_emit(o, c);
            fout_emit(o, '/');
            q += 2;
            continue;
          }
          if (c == '/' && c2 == '*') {
            in_bc = 1;
            fout_emit(o, c);
            fout_emit(o, '*');
            q += 2;
            continue;
          }
          if (c == '"') {
            in_str = 1;
            fout_emit(o, c);
            q++;
            continue;
          }
          if (c == '\'') {
            in_chr = 1;
            fout_emit(o, c);
            q++;
            continue;
          }
          if (c == '{') depth++;
          if (c == '}') {
            if (depth > 0) depth--;
          }
          fout_emit(o, c);
          q++;
        }
      }
    }
    if (*eol == '\n') {
      fout_emit(o, '\n');
      p = eol + 1;
    } else {
      p = eol;
    }
  }
}

/* ─── AST emit ─── */

static void emit_node(FmtOut *o, FmtNode *n, int indent, int inline_ok);

/* Returns 1 if the last character emitted was '}' of a same-line control block
 * (so caller can attach " else" / " catch" / newline). */
static int emit_body(FmtOut *o, FmtNode *body, int indent) {
  if (!body) return 0;
  if (body->kind == FN_BLOCK) {
    int i;
    fout_emit_s(o, " {");
    fout_emit(o, '\n');
    for (i = 0; i < body->nkids; i++)
      emit_node(o, body->kids[i], indent + 1, 0);
    fout_indent(o, indent);
    fout_emit(o, '}');
    return 1;
  }
  fout_emit(o, '\n');
  emit_node(o, body, indent + 1, 0);
  return 0;
}

/* Attach else / else-if chain; `after_brace` if previous body closed with '}'. */
static void emit_else_chain(FmtOut *o, FmtNode *els, int indent, int after_brace) {
  while (els && els->nkids > 0) {
    FmtNode *body = els->kids[0];
    if (after_brace)
      fout_emit_s(o, " else");
    else {
      fout_indent(o, indent);
      fout_emit_s(o, "else");
    }
    if (body->kind == FN_IF) {
      fout_emit(o, ' ');
      emit_kw_parens(o, "if", body->toks, body->ntoks, indent);
      after_brace =
          body->nkids > 0 ? emit_body(o, body->kids[0], indent) : 0;
      els = body->els;
      continue;
    }
    after_brace = emit_body(o, body, indent);
    break;
  }
  if (after_brace) fout_emit(o, '\n');
}

static void emit_node(FmtOut *o, FmtNode *n, int indent, int inline_ok) {
  int i;
  int braced;
  if (!n || o->err) return;

  switch (n->kind) {
  case FN_FILE:
    for (i = 0; i < n->nkids; i++) {
      emit_node(o, n->kids[i], 0, 0);
      if (i + 1 < n->nkids) {
        FmtKind a = n->kids[i]->kind, b = n->kids[i + 1]->kind;
        if ((a == FN_UNIT || a == FN_ASM) && (b == FN_UNIT || b == FN_ASM))
          fout_emit(o, '\n');
      }
    }
    break;

  case FN_PREPROC:
    fout_emit_s(o, n->text);
    fout_emit(o, '\n');
    break;

  case FN_COMMENT:
    fout_indent(o, indent);
    fout_emit_s(o, n->text);
    fout_emit(o, '\n');
    break;

  case FN_BLANK:
    fout_emit(o, '\n');
    break;

  case FN_ASM:
    fout_indent(o, indent);
    fout_emit_s(o, "asm {");
    fout_emit(o, '\n');
    if (n->text && n->text[0]) {
      emit_asm_interior(o, n->text);
      if (o->len == 0 || o->buf[o->len - 1] != '\n') fout_emit(o, '\n');
    }
    fout_indent(o, indent);
    fout_emit(o, '}');
    fout_emit(o, '\n');
    break;

  case FN_BLOCK:
    if (!inline_ok) fout_indent(o, indent);
    fout_emit(o, '{');
    fout_emit(o, '\n');
    for (i = 0; i < n->nkids; i++) emit_node(o, n->kids[i], indent + 1, 0);
    fout_indent(o, indent);
    fout_emit(o, '}');
    if (!inline_ok) fout_emit(o, '\n');
    break;

  case FN_IF:
    if (!inline_ok) fout_indent(o, indent);
    emit_kw_parens(o, "if", n->toks, n->ntoks, indent);
    braced = n->nkids > 0 ? emit_body(o, n->kids[0], indent) : 0;
    if (n->els)
      emit_else_chain(o, n->els, indent, braced);
    else if (braced)
      fout_emit(o, '\n');
    break;

  case FN_WHILE:
    fout_indent(o, indent);
    emit_kw_parens(o, "while", n->toks, n->ntoks, indent);
    braced = n->nkids > 0 ? emit_body(o, n->kids[0], indent) : 0;
    if (braced) fout_emit(o, '\n');
    break;

  case FN_FOR:
    fout_indent(o, indent);
    emit_kw_parens(o, "for", n->toks, n->ntoks, indent);
    braced = n->nkids > 0 ? emit_body(o, n->kids[0], indent) : 0;
    if (braced) fout_emit(o, '\n');
    break;

  case FN_DO:
    fout_indent(o, indent);
    fout_emit_s(o, "do");
    braced = n->nkids > 0 ? emit_body(o, n->kids[0], indent) : 0;
    if (n->els) {
      if (braced) fout_emit_s(o, " while ");
      else {
        fout_indent(o, indent);
        fout_emit_s(o, "while ");
      }
      emit_toks(o, n->els->toks, n->els->ntoks, indent);
      fout_emit(o, ';');
    }
    fout_emit(o, '\n');
    break;

  case FN_SWITCH:
    fout_indent(o, indent);
    emit_kw_parens(o, "switch", n->toks, n->ntoks, indent);
    braced = n->nkids > 0 ? emit_body(o, n->kids[0], indent) : 0;
    if (braced) fout_emit(o, '\n');
    break;

  case FN_TRY:
    fout_indent(o, indent);
    fout_emit_s(o, "try");
    braced = n->nkids > 0 ? emit_body(o, n->kids[0], indent) : 0;
    if (n->els && n->els->nkids > 0) {
      if (braced) fout_emit_s(o, " catch");
      else {
        fout_indent(o, indent);
        fout_emit_s(o, "catch");
      }
      braced = emit_body(o, n->els->kids[0], indent);
    }
    if (braced) fout_emit(o, '\n');
    break;

  case FN_CASE:
    fout_indent(o, indent);
    emit_toks(o, n->toks, n->ntoks, indent);
    fout_emit(o, '\n');
    break;

  case FN_DEFAULT:
    fout_indent(o, indent);
    fout_emit_s(o, "default:");
    fout_emit(o, '\n');
    break;

  case FN_LABEL:
    fout_indent(o, indent);
    if (n->ntoks > 0) fout_emit_n(o, n->toks[0].s, n->toks[0].len);
    fout_emit(o, ':');
    fout_emit(o, '\n');
    break;

  case FN_UNIT:
    /* Function / class / enum: header then '{' on next line */
    fout_indent(o, indent);
    if (n->ntoks > 0) emit_toks(o, n->toks, n->ntoks, indent);
    fout_emit(o, '\n');
    fout_indent(o, indent);
    fout_emit(o, '{');
    fout_emit(o, '\n');
    if (n->nkids > 0 && n->kids[0]->kind == FN_BLOCK) {
      FmtNode *blk = n->kids[0];
      for (i = 0; i < blk->nkids; i++)
        emit_node(o, blk->kids[i], indent + 1, 0);
    }
    fout_indent(o, indent);
    fout_emit(o, '}');
    if (n->trailing_semi) fout_emit(o, ';');
    fout_emit(o, '\n');
    break;

  case FN_STMT:
    fout_indent(o, indent);
    emit_toks(o, n->toks, n->ntoks, indent);
    fout_emit(o, '\n');
    break;

  case FN_ELSE:
    break;
  }
}

/* ─── public entry ─── */

long long HolyFmtSrc(const char *src, char *out, long long out_cap) {
  FmtLex L;
  FmtParse P;
  FmtNode *ast;
  FmtOut O;
  long long ret;

  if (!src || !out || out_cap < 2) return -1;

  memset(&L, 0, sizeof(L));
  L.src = src;
  if (!flex_tokenize(&L)) {
    free(L.toks);
    return -1;
  }

  P.toks = L.toks;
  P.ntoks = L.ntoks;
  P.i = 0;
  ast = parse_file(&P);
  if (!ast) {
    free(L.toks);
    return -1;
  }

  O.buf = out;
  O.cap = out_cap;
  O.len = 0;
  O.err = 0;
  emit_node(&O, ast, 0, 0);
  fnode_free(ast);
  free(L.toks);

  if (O.err || O.len >= out_cap) return -1;
  out[O.len] = 0;
  ret = O.len;
  return ret;
}
