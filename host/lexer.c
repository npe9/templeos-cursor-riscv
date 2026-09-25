/* HolyC Lexer - Tokenizes HolyC source code */

#include "holyc_compiler.h"
#include <ctype.h>

#define IS_ALPHA_CHAR(c) (((c) >= 'a' && (c) <= 'z') || ((c) >= 'A' && (c) <= 'Z'))
#define IS_DIGIT_CHAR(c) ((c) >= '0' && (c) <= '9')
#define IS_ALNUM_CHAR(c) (IS_ALPHA_CHAR(c) || IS_DIGIT_CHAR(c) || (c) == '_')
// A #define/#ifdef/#undef NAME is scanned by the preprocessor, and an identifier TOKEN is scanned
// by LexIdentifier, whose IS_IDENT_CHAR accepts every byte >= 128 (the TempleOS charset). The two
// have to agree or a name that contains one splits: `#define SA_SET_\xE9 3` registered `SA_SET_`
// with the body "\xE9 3", and `case SA_SET_\xE9:` then failed with "Expected integer constant in
// case" — Demo/Games/FlatTops.HC and three other demos.
#define IS_IDENT_BYTE(c) (IS_ALNUM_CHAR(c) || (unsigned char)(c) >= 128)

#define MAX_INCLUDE_PATH 1024

static bool EndsWith(const char *str, const char *suffix) {
  if (!str || !suffix) return false;
  size_t str_len = strlen(str);
  size_t suffix_len = strlen(suffix);
  if (suffix_len > str_len) return false;
  return strcmp(str + str_len - suffix_len, suffix) == 0;
}

static bool ReadEntireFile(const char *path, char **out_src, size_t *out_size) {
  if (!path || !out_src) return false;

  FILE *f = fopen(path, "rb");
  if (!f) return false;

  if (fseek(f, 0, SEEK_END) != 0) {
    fclose(f);
    return false;
  }
  long fsize = ftell(f);
  if (fsize < 0) {
    fclose(f);
    return false;
  }
  if (fseek(f, 0, SEEK_SET) != 0) {
    fclose(f);
    return false;
  }

  char *buffer = malloc((size_t)fsize + 1);
  if (!buffer) {
    fclose(f);
    return false;
  }

  size_t read = fread(buffer, 1, (size_t)fsize, f);
  fclose(f);
  if (read != (size_t)fsize) {
    free(buffer);
    return false;
  }

  buffer[fsize] = '\0';
  *out_src = buffer;
  if (out_size) *out_size = (size_t)fsize;
  return true;
}

static void ExtractDirectory(const char *path, char *out_dir, size_t out_size) {
  if (!out_dir || out_size == 0) return;
  out_dir[0] = '\0';
  if (!path || !path[0] || path[0] == '<') return;

  const char *last_forward = strrchr(path, '/');
  const char *last_back = strrchr(path, '\\');
  const char *slash = last_forward;
  if (last_back && (!slash || last_back > slash)) {
    slash = last_back;
  }
  if (!slash) return;

  size_t dir_len = (size_t)(slash - path);
  if (dir_len >= out_size) {
    dir_len = out_size - 1;
  }
  memcpy(out_dir, path, dir_len);
  out_dir[dir_len] = '\0';
}

/* Resolve lex->filename past "<macro expansion>" frames to the real include path. */
static const char *LexRealFilename(Lexer *lex) {
  if (!lex) return "";
  if (lex->filename && lex->filename[0] && lex->filename[0] != '<')
    return lex->filename;
  for (IncludeFile *inc = lex->include_stack; inc; inc = inc->next) {
    if (inc->filename && inc->filename[0] && inc->filename[0] != '<')
      return inc->filename;
  }
  return lex->filename ? lex->filename : "";
}

/* TempleOS drive / boot prefixes: `::/x` → `/x`, `A:/x` → `/x`, `:/x` → `/x`. */
static const char *StripTempleOSPathPrefix(const char *filename) {
  if (!filename || !filename[0]) return filename;
  if (filename[0] == ':' && filename[1] == ':')
    return filename + 2; /* `::/Adam` → `/Adam`; bare `::` → "" */
  if (filename[0] == ':' && (filename[1] == '/' || filename[1] == '\\'))
    return filename + 1; /* `:/Demo` → `/Demo` */
  if (((filename[0] >= 'A' && filename[0] <= 'Z') ||
       (filename[0] >= 'a' && filename[0] <= 'z')) &&
      filename[1] == ':')
    return filename + 2; /* `A:/Kernel` → `/Kernel` */
  return filename;
}

static void PathSlashNormalize(char *s) {
  for (; s && *s; s++) {
    if (*s == '\\') *s = '/';
  }
}

/* Host path → boot-root `::/…` under HOLYC_INCLUDE_ROOT (StreamDir shape).
 * Maps the repo ISO tree `tos/X` → `::/X`, mirroring the `#include "::/Apps/…"`
 * → `$ROOT/tos/Apps/…` adapter. Soft Cd (DskDirB.HC: no cur_dv → strip `X:`,
 * record cur_dir) makes pre-mount AOT `Cd(__DIR__)` safe without keeping `/tos/`.
 * Relative paths are treated as already under the include root. See docs/PATHS.md. */
static void TempleosPathFromHost(const char *host_path, char *out, size_t out_size) {
  if (!out || out_size == 0) return;
  out[0] = '\0';
  if (!host_path || !host_path[0] || host_path[0] == '<') {
    StrPrintF(out, out_size, "%s", host_path ? host_path : "");
    return;
  }
#ifndef BARE_METAL
  const char *root = getenv("HOLYC_INCLUDE_ROOT");
  if (root && *root) {
    size_t root_len = strlen(root);
    const char *rest = NULL;
    while (root_len > 1 && (root[root_len - 1] == '/' || root[root_len - 1] == '\\'))
      root_len--;
    if (strncmp(host_path, root, root_len) == 0 &&
        (host_path[root_len] == '/' || host_path[root_len] == '\\' ||
         host_path[root_len] == '\0')) {
      rest = host_path + root_len;
    } else if (host_path[0] != '/' && host_path[0] != '\\' &&
               !(((host_path[0] >= 'A' && host_path[0] <= 'Z') ||
                  (host_path[0] >= 'a' && host_path[0] <= 'z')) &&
                 host_path[1] == ':') &&
               !strstr(host_path, "..")) {
      rest = host_path;
    }
    if (rest) {
      while (*rest == '/' || *rest == '\\') rest++;
      /* Repo ISO tree: `tos/Apps/Span` → `::/Apps/Span`; bare `tos` → `::/`. */
      if (strncmp(rest, "tos", 3) == 0) {
        if (rest[3] == '/' || rest[3] == '\\') {
          rest += 4;
          while (*rest == '/' || *rest == '\\') rest++;
        } else if (rest[3] == '\0') {
          rest += 3;
        }
      }
      if (*rest)
        StrPrintF(out, out_size, "::/%s", rest);
      else
        StrPrintF(out, out_size, "::/");
      PathSlashNormalize(out);
      return;
    }
  }
#endif
  StrPrintF(out, out_size, "%s", host_path);
  PathSlashNormalize(out);
}

/* KernelA `#define __DIR__ #exe{StreamDir;}` — host skips #exe, so expand builtins here. */
static int LexExeBuiltin(Compiler *cc, const char *name) {
  Lexer *lex = &cc->lex;
  char injected[MAX_INCLUDE_PATH + 16];
  const char *fn = LexRealFilename(lex);
  int line = lex->line;
  /* Prefer include-stack line when expanding through a macro frame. */
  if (lex->filename && lex->filename[0] == '<' && lex->include_stack)
    line = lex->include_stack->line;

  if (!strcmp(name, "__LINE__")) {
    StrPrintF(injected, sizeof(injected), "%d", line);
  } else if (!strcmp(name, "__FILE__")) {
    char path[MAX_INCLUDE_PATH];
    TempleosPathFromHost(fn, path, sizeof(path));
    StrPrintF(injected, sizeof(injected), "\"%s\"", path);
  } else if (!strcmp(name, "__DIR__")) {
    char host_dir[MAX_INCLUDE_PATH];
    char path[MAX_INCLUDE_PATH];
    ExtractDirectory(fn, host_dir, sizeof(host_dir));
    TempleosPathFromHost(host_dir[0] ? host_dir : fn, path, sizeof(path));
    if (!path[0])
      StrPrintF(path, sizeof(path), "/");
    StrPrintF(injected, sizeof(injected), "\"%s\"", path);
  } else {
    return 0;
  }

  IncludeFile *inc = calloc(1, sizeof(IncludeFile));
  if (!inc) return 0;
  inc->src = lex->src;
  inc->src_size = lex->src_size;
  inc->ptr = lex->ptr;
  inc->filename = lex->filename;
  inc->line = lex->line;
  inc->col = lex->col;
  inc->next = lex->include_stack;
  lex->include_stack = inc;
  lex->src = strdup(injected);
  lex->src_size = lex->src ? strlen(lex->src) : 0;
  lex->ptr = lex->src;
  lex->filename = strdup("<exe builtin>");
  lex->line = 1;
  lex->col = 1;
  LexNext(cc);
  return cc->lex.token;
}

static bool NeedsSeparator(const char *dir) {
  if (!dir || !dir[0]) return false;
  size_t len = strlen(dir);
  char last = dir[len - 1];
  return !(last == '/' || last == '\\');
}

static bool TryIncludeInDirectory(const char *dir,
                                  const char *filename,
                                  char *resolved,
                                  size_t resolved_size,
                                  char **out_src,
                                  size_t *out_size) {
  if (!filename || !resolved || !out_src) return false;

  char candidate[MAX_INCLUDE_PATH];
  int written;
  if (dir && dir[0]) {
    written = StrPrintF(candidate,
                       sizeof(candidate),
                       NeedsSeparator(dir) ? "%s/%s" : "%s%s",
                       dir,
                       filename);
  } else {
    written = StrPrintF(candidate, sizeof(candidate), "%s", filename);
  }

  if (written < 0 || written >= (int)sizeof(candidate)) {
    return false;
  }

  if (ReadEntireFile(candidate, out_src, out_size)) {
    StrPrintF(resolved, resolved_size, "%s", candidate);
    return true;
  }

  if (!EndsWith(filename, ".HC")) {
    if (dir && dir[0]) {
      written = StrPrintF(candidate,
                         sizeof(candidate),
                         NeedsSeparator(dir) ? "%s/%s.HC" : "%s%s.HC",
                         dir,
                         filename);
    } else {
      written = StrPrintF(candidate, sizeof(candidate), "%s.HC", filename);
    }

    if (written < 0 || written >= (int)sizeof(candidate)) {
      return false;
    }

    if (ReadEntireFile(candidate, out_src, out_size)) {
      StrPrintF(resolved, resolved_size, "%s", candidate);
      return true;
    }
  }

  return false;
}

static bool IsAbsolutePath(const char *path) {
  if (!path || !path[0]) return false;
#ifdef _WIN32
  if (path[0] == '/' || path[0] == '\\') return true;
  if (strlen(path) > 1 && path[1] == ':') return true;
  return false;
#else
  return path[0] == '/';
#endif
}

static bool LoadIncludeFile(Compiler *cc,
                            const char *filename,
                            char **out_src,
                            size_t *out_size,
                            char *resolved_path,
                            size_t resolved_size) {
  if (!filename || !out_src || !resolved_path) return false;

  /* `::/Adam/…`, `A:/Kernel/…`, `:/Demo/…` → distribution-rooted absolute. */
  filename = StripTempleOSPathPrefix(filename);

  /* `~/HomeLocalize` is the CURRENT USER'S Home directory — where a TempleOS account keeps the
   * files it overrides (see docs/ACCT_EXAMPLE.md). On the host there is no logged-in account, so
   * HOLYC_HOME_ROOT names one; it defaults to the distribution's `/Home`, which is `tos/` in this
   * repo and holds the shipped templates. Without this, Demo/AcctExample/MakeHome.HC could not be
   * read at all. */
  if (filename[0] == '~' && (filename[1] == '/' || filename[1] == '\\')) {
#ifndef BARE_METAL
    const char *home = getenv("HOLYC_HOME_ROOT");
#else
    const char *home = NULL;
#endif
    /* MakeHome.HC: "If these are not present in /Home, it uses the version in the root dir." */
    const char *roots[2] = { (home && *home) ? home : "/Home", "" };
    for (int r = 0; r < 2; r++) {
      char home_buf[MAX_INCLUDE_PATH];
      int wh = StrPrintF(home_buf, sizeof(home_buf), "%s%s", roots[r], filename + 1);
      if (wh > 0 && wh < (int)sizeof(home_buf) &&
          LoadIncludeFile(cc, home_buf, out_src, out_size, resolved_path, resolved_size))
        return true;
    }
    return false;
  }

  if (IsAbsolutePath(filename)) {
    // TempleOS paths are rooted at the distribution ("/Kernel/KernelA.HH"): HOLYC_INCLUDE_ROOT
    // names that directory on the host (the exec scripts point it at the repo root).
#ifndef BARE_METAL
    const char *root = getenv("HOLYC_INCLUDE_ROOT");
    if (root && *root) {
      char rooted[MAX_INCLUDE_PATH];
      char tos_rooted[MAX_INCLUDE_PATH];
      int w = StrPrintF(rooted, sizeof(rooted), "%s%s", root, filename);
      if (w > 0 && w < (int)sizeof(rooted)) {
        if (TryIncludeInDirectory(NULL, rooted, resolved_path, resolved_size, out_src, out_size)) return true;
        if (!EndsWith(filename, ".HC") && !EndsWith(filename, ".HH")) {
          char tmp2[MAX_INCLUDE_PATH];
          int w2 = StrPrintF(tmp2, sizeof(tmp2), "%s.HC", rooted);
          if (w2 > 0 && w2 < (int)sizeof(tmp2) && TryIncludeInDirectory(NULL, tmp2, resolved_path, resolved_size, out_src, out_size)) return true;
        }
      }
      /* ISO trees live under tos/ on the host (`::/Apps` → $ROOT/tos/Apps). */
      w = StrPrintF(tos_rooted, sizeof(tos_rooted), "%s/tos%s", root, filename);
      if (w > 0 && w < (int)sizeof(tos_rooted)) {
        if (TryIncludeInDirectory(NULL, tos_rooted, resolved_path, resolved_size, out_src, out_size)) return true;
        if (!EndsWith(filename, ".HC") && !EndsWith(filename, ".HH")) {
          char tmp2[MAX_INCLUDE_PATH];
          int w2 = StrPrintF(tmp2, sizeof(tmp2), "%s.HC", tos_rooted);
          if (w2 > 0 && w2 < (int)sizeof(tmp2) && TryIncludeInDirectory(NULL, tmp2, resolved_path, resolved_size, out_src, out_size)) return true;
        }
      }
    }
#endif
    if (TryIncludeInDirectory(NULL, filename, resolved_path, resolved_size, out_src, out_size)) {
      return true;
    }
    if (!EndsWith(filename, ".HC")) {
      char tmp[MAX_INCLUDE_PATH];
      int written = StrPrintF(tmp, sizeof(tmp), "%s.HC", filename);
      if (written >= 0 && written < (int)sizeof(tmp)) {
        if (TryIncludeInDirectory(NULL, tmp, resolved_path, resolved_size, out_src, out_size)) {
          return true;
        }
      }
    }
    return false;
  }

  char current_dir[MAX_INCLUDE_PATH];
  ExtractDirectory(cc->lex.filename, current_dir, sizeof(current_dir));

  if (current_dir[0]) {
    if (TryIncludeInDirectory(current_dir, filename, resolved_path, resolved_size, out_src, out_size)) {
      return true;
    }
    if (!EndsWith(filename, ".HC") && !EndsWith(filename, ".HH")) {   // `#include "KStart16"` → KStart16.HC
      char tmp[MAX_INCLUDE_PATH];
      int written = StrPrintF(tmp, sizeof(tmp), "%s.HC", filename);
      if (written > 0 && written < (int)sizeof(tmp) &&
          TryIncludeInDirectory(current_dir, tmp, resolved_path, resolved_size, out_src, out_size)) return true;
    }
  }

  if (TryIncludeInDirectory(NULL, filename, resolved_path, resolved_size, out_src, out_size)) {
    return true;
  }

  return false;
}

static const struct {
  const char *name;
  int token;
} keywords[] = {
  {"if", KW_IF},
  {"else", KW_ELSE},
  {"while", KW_WHILE},
  {"for", KW_FOR},
  {"return", KW_RETURN},
  {"break", KW_BREAK},
  {"class", KW_CLASS},
  {"enum", KW_ENUM},
  {"public", KW_PUBLIC},
  {"I0", KW_I0},
  {"U0", KW_U0},
  {"I8", KW_I8},
  {"U8", KW_U8},
  {"I16", KW_I16},
  {"U16", KW_U16},
  {"I32", KW_I32},
  {"U32", KW_U32},
  {"I64", KW_I64},
  {"U64", KW_U64},
  {"F64", KW_F64},
  // The kernel's actual fixed-width primitives are the `*i`-suffixed names; U8/U16/... are
  // scalar-typed unions overlaying them (KernelA.HH: `U16i union U16 {…}`). Alias each to the
  // same keyword so `U16i union U16` records U16i as the union's scalar base type.
  {"I0i", KW_I0}, {"U0i", KW_U0},
  {"I8i", KW_I8}, {"U8i", KW_U8},
  {"I16i", KW_I16}, {"U16i", KW_U16},
  {"I32i", KW_I32}, {"U32i", KW_U32},
  {"I64i", KW_I64}, {"U64i", KW_U64},
  {"F64i", KW_F64},
  {NULL, 0}
};

static void FreeDefine(CHashDefine *def) {
  if (!def) return;
  if (def->data) free(def->data);
  if (def->param_names) {
    for (int i = 0; i < def->param_count; i++) {
      if (def->param_names[i]) free(def->param_names[i]);
    }
    free(def->param_names);
  }
  if (def->str) free(def->str);
  free(def);
}

static void SkipWhitespace(Lexer *lex) {
  while (*lex->ptr && (*lex->ptr == ' ' || *lex->ptr == '\t' || *lex->ptr == '\n' || *lex->ptr == '\r')) {
    if (*lex->ptr == '\n') {
      lex->line++;
      lex->col = 1;
    } else {
      lex->col++;
    }
    lex->ptr++;
  }
}

static void SkipComment(Lexer *lex) {
  if (lex->ptr[0] == '/' && lex->ptr[1] == '/') {
    // Line comment
    while (*lex->ptr && *lex->ptr != '\n') {
      lex->ptr++;
    }
  } else if (lex->ptr[0] == '/' && lex->ptr[1] == '*') {
    // Block comment
    lex->ptr += 2;
    while (*lex->ptr) {
      if (lex->ptr[0] == '*' && lex->ptr[1] == '/') {
        lex->ptr += 2;
        break;
      }
      if (*lex->ptr == '\n') {
        lex->line++;
        lex->col = 1;
      }
      lex->ptr++;
    }
  }
}

static void SkipDolDoc(Lexer *lex) {
  // Skip a DolDoc command in source text: `$XX,...$` (single dollars on disk; `$$` inside
  // is an escaped '$'). Called with ptr at the opening '$'.
  lex->ptr++;
  lex->col++;
  while (*lex->ptr) {
    if (lex->ptr[0] == '$') {
      if (lex->ptr[1] == '$') { lex->ptr += 2; lex->col += 2; continue; }   // escaped
      lex->ptr++; lex->col++;                                               // closing
      return;
    }
    if (*lex->ptr == '\n') { lex->line++; lex->col = 1; } else lex->col++;
    lex->ptr++;
  }
}

/* TempleOS DocSave on-disk CDocBin header: U32 num,flags,size,use_cnt (after text NUL). */
#define CDOC_BIN_HDR_SIZE 16

static int DocBinParseBI(const char *cmd, size_t cmd_len, U32 *out_bi) {
  /* Find BI=<digits> inside `$IB…$` / `$IS…$` body (cmd points past opening '$'). */
  const char *p = cmd;
  const char *end = cmd + cmd_len;
  while (p + 3 < end) {
    if ((p[0] == 'B' || p[0] == 'b') && (p[1] == 'I' || p[1] == 'i') && p[2] == '=') {
      p += 3;
      U32 n = 0;
      int any = 0;
      while (p < end && *p >= '0' && *p <= '9') {
        n = n * 10u + (U32)(*p - '0');
        p++;
        any = 1;
      }
      if (any) {
        *out_bi = n;
        return 1;
      }
      return 0;
    }
    p++;
  }
  return 0;
}

static int DocBinFindInSrc(const char *src, size_t src_size, U32 bin_num,
                          const U8 **out_data, U32 *out_size) {
  size_t text_len, rem;
  const U8 *p;
  if (!src || src_size == 0 || bin_num == 0 || !out_data || !out_size) return 0;
  text_len = 0;
  while (text_len < src_size && src[text_len]) text_len++;
  if (text_len + 1 >= src_size) return 0;
  p = (const U8 *)src + text_len + 1;
  rem = src_size - (text_len + 1);
  while (rem >= CDOC_BIN_HDR_SIZE) {
    U32 num, flags, size, use_cnt;
    memcpy(&num, p, 4);
    memcpy(&flags, p + 4, 4);
    memcpy(&size, p + 8, 4);
    memcpy(&use_cnt, p + 12, 4);
    (void)flags;
    (void)use_cnt;
    p += CDOC_BIN_HDR_SIZE;
    rem -= CDOC_BIN_HDR_SIZE;
    if (size > rem) return 0;
    if (num == bin_num) {
      *out_data = p;
      *out_size = size;
      return 1;
    }
    p += size;
    rem -= size;
  }
  return 0;
}

static void LexEmitDocBin(Compiler *cc, int want_size) {
  /* `$IB` → TK_STR (bin bytes); `$IS` → TK_I64 (bin size). TempleOS Lex DOCT_INS_BIN*. */
  Lexer *lex = &cc->lex;
  const char *cmd = lex->ptr + 1; /* past '$' */
  const char *scan = cmd;
  size_t cmd_len = 0;
  U32 bi = 0;
  const U8 *data = NULL;
  U32 size = 0;

  while (*scan) {
    if (scan[0] == '$') {
      if (scan[1] == '$') { scan += 2; continue; }
      break;
    }
    scan++;
  }
  cmd_len = (size_t)(scan - cmd);
  DocBinParseBI(cmd, cmd_len, &bi);
  SkipDolDoc(lex);

  if (bi && DocBinFindInSrc(lex->src, lex->src_size, bi, &data, &size)) {
    if (want_size) {
      lex->token = TK_I64;
      lex->token_i64 = (I64)size;
      lex->token_is_char = false;
      if (lex->token_str) { free(lex->token_str); lex->token_str = NULL; }
      lex->token_str_len = 0;
      return;
    }
    lex->token = TK_STR;
    lex->token_is_char = false;
    if (lex->token_str) free(lex->token_str);
    lex->token_str = malloc((size_t)size + 1);
    if (lex->token_str) {
      if (size) memcpy(lex->token_str, data, size);
      lex->token_str[size] = '\0';
      lex->token_str_len = (int)size;
    } else {
      lex->token_str_len = 0;
    }
    return;
  }

  /* Missing bin: TempleOS still yields empty/zero; keep prior NULL-ish behavior. */
  if (want_size) {
    lex->token = TK_I64;
    lex->token_i64 = 0;
    lex->token_is_char = false;
    if (lex->token_str) { free(lex->token_str); lex->token_str = NULL; }
    lex->token_str_len = 0;
  } else {
    lex->token = TK_I64;
    lex->token_i64 = 0;
    lex->token_is_char = false;
    if (lex->token_str) free(lex->token_str);
    lex->token_str = strdup("");
    lex->token_str_len = 0;
    cc->asm_blocks_skipped++;
  }
}

static void HandlePreprocessor(Compiler *cc) {
  Lexer *lex = &cc->lex;
  
  // Skip preprocessor directive (starts with #)
  if (*lex->ptr != '#') return;
  
  lex->ptr++;  // Skip '#'
  lex->col++;
  
  // Skip whitespace
  while (*lex->ptr == ' ' || *lex->ptr == '\t') {
    lex->ptr++;
    lex->col++;
  }
  
  // Get directive name
  char directive[64];
  int i = 0;
  while (IS_ALPHA_CHAR(*lex->ptr) && i < 63) {
    directive[i++] = *lex->ptr++;
    lex->col++;
  }
  directive[i] = '\0';
  
  // While skipping a false conditional block, only the conditional directives manage the skip/nesting
  // state; every other directive (#define, #include, #undef, …) must be ignored, not executed. (Fixes
  // `#ifndef X` guards: the guarded #define was being run even when X was already defined.)
  if (cc->preprocessor_skip &&
      strcmp(directive, "ifdef") && strcmp(directive, "ifndef") && strcmp(directive, "if") &&
      strcmp(directive, "ifjit") && strcmp(directive, "ifaot") && strcmp(directive, "else") &&
      strcmp(directive, "elif") && strcmp(directive, "endif")) {
    goto skip_line;
  }
  
  if (strcmp(directive, "define") == 0) {
    // Parse #define NAME VALUE or #define NAME(params) VALUE

    // Skip whitespace
    while (*lex->ptr == ' ' || *lex->ptr == '\t') {
      lex->ptr++;
      lex->col++;
    }

    // Get macro name
    char name[256];
    i = 0;
    while ((IS_IDENT_BYTE(*lex->ptr)) && i < 255) {
      name[i++] = *lex->ptr++;
      lex->col++;
    }
    name[i] = '\0';

    // Parse parameter list if present immediately after the name
    char *param_names_buf[16];
    int param_count = 0;

    if (*lex->ptr == '(') {
      lex->ptr++;
      lex->col++;

      while (*lex->ptr && *lex->ptr != ')') {
        while (*lex->ptr == ' ' || *lex->ptr == '\t') {
          lex->ptr++;
          lex->col++;
        }

        if (*lex->ptr == ')') break;  // Allow trailing whitespace before ')'

        char param[256];
        int pj = 0;
        while ((IS_ALNUM_CHAR(*lex->ptr)) && pj < 255) {
          param[pj++] = *lex->ptr++;
          lex->col++;
        }
        param[pj] = '\0';

        if (pj == 0) {
          // Unsupported token (like variadic); treat as empty and break
          break;
        }

        if (param_count < 16) {
          param_names_buf[param_count++] = strdup(param);
        }

        while (*lex->ptr == ' ' || *lex->ptr == '\t') {
          lex->ptr++;
          lex->col++;
        }

        if (*lex->ptr == ',') {
          lex->ptr++;
          lex->col++;
          continue;
        }
        break;
      }

      if (*lex->ptr == ')') {
        lex->ptr++;
        lex->col++;
      }

      // Skip whitespace between parameter list and replacement
      while (*lex->ptr == ' ' || *lex->ptr == '\t') {
        lex->ptr++;
        lex->col++;
      }
    } else {
      // No parameters: skip whitespace before replacement
      while (*lex->ptr == ' ' || *lex->ptr == '\t') {
        lex->ptr++;
        lex->col++;
      }
    }

    // Get replacement text (rest of line)
    char value[8192];
    i = 0;
    while (*lex->ptr && *lex->ptr != '\n' && i < (int)sizeof(value) - 1) {
      if (*lex->ptr == '\\' && (lex->ptr[1] == '\n' || (lex->ptr[1] == '\r' && lex->ptr[2] == '\n'))) {
        // backslash-newline: the definition continues on the next line
        lex->ptr += (lex->ptr[1] == '\r') ? 3 : 2;
        lex->line++;
        lex->col = 1;
        value[i++] = ' ';
        continue;
      }
      value[i++] = *lex->ptr++;
      lex->col++;
    }
    value[i] = '\0';
    
    // Trim trailing whitespace
    while (i > 0 && (value[i-1] == ' ' || value[i-1] == '\t')) {
      value[--i] = '\0';
    }
    
    // Add to define table
    CHashEntry *existing = HashRemove(cc->define_table, name, HTT_DEFINE_STR);
    if (existing && (existing->type & HTT_DEFINE_STR)) {
      FreeDefine((CHashDefine*)existing);
    }

    CHashDefine *def = calloc(1, sizeof(CHashDefine));
    def->str = strdup(name);
    def->type = HTT_DEFINE_STR;
    def->data = strdup(value);
    if (param_count > 0) {
      def->param_count = param_count;
      def->param_names = calloc(param_count, sizeof(char*));
      for (int idx = 0; idx < param_count; idx++) {
        def->param_names[idx] = param_names_buf[idx];
      }
    } else {
      def->param_count = 0;
      def->param_names = NULL;
    }
    HashAdd((CHashEntry*)def, cc->define_table);
  } else if (strcmp(directive, "include") == 0) {
    // Parse #include "filename"
    
    // Skip whitespace
    while (*lex->ptr == ' ' || *lex->ptr == '\t') {
      lex->ptr++;
      lex->col++;
    }
    
    // Expect quote
    if (*lex->ptr != '"') {
      // Skip to end of line
      goto skip_line;
    }
    lex->ptr++;  // Skip opening quote
    lex->col++;
    
    // Get filename
    char filename[512];
    i = 0;
    while (*lex->ptr && *lex->ptr != '"' && *lex->ptr != '\n' && i < 511) {
      filename[i++] = *lex->ptr++;
      lex->col++;
    }
    filename[i] = '\0';
    
    if (*lex->ptr == '"') {
      lex->ptr++;  // Skip closing quote
      lex->col++;
    }
    
    char resolved_path[MAX_INCLUDE_PATH];
    char *include_src = NULL;
    size_t include_size = 0;
    if (!LoadIncludeFile(cc, filename, &include_src, &include_size, resolved_path, sizeof(resolved_path))) {
      char err_msg[256];
      StrPrintF(err_msg, sizeof(err_msg), "Unable to open include file '%s'", filename);
      Error(cc, err_msg);
      goto skip_line;
    }

    IncludeFile *inc = calloc(1, sizeof(IncludeFile));
    inc->src = lex->src;
    inc->src_size = lex->src_size;
    inc->ptr = lex->ptr;
    inc->filename = lex->filename;
    inc->line = lex->line;
    inc->col = lex->col;
    inc->next = lex->include_stack;
    lex->include_stack = inc;

    lex->src = include_src;
    lex->src_size = include_size;
    lex->ptr = include_src;
    lex->filename = strdup(resolved_path);
    lex->line = 1;
    lex->col = 1;
    HolyProgress("  %s", HolyProgressRel(resolved_path));
#ifndef BARE_METAL
    AOTDepAdd(cc, resolved_path);
#endif

    return;  // Don't skip to next line
  } else if (strcmp(directive, "ifdef") == 0 || strcmp(directive, "ifndef") == 0 ||
             strcmp(directive, "ifjit") == 0 || strcmp(directive, "ifaot") == 0 ||
             strcmp(directive, "if") == 0) {
    // Push a conditional frame. Nesting must save/restore skip: a false inner
    // #ifdef must not leave skip stuck through later siblings in a true outer block.
    bool cond_true = false;
    if (strcmp(directive, "ifdef") == 0 || strcmp(directive, "ifndef") == 0) {
      bool is_ifndef = (strcmp(directive, "ifndef") == 0);
      while (*lex->ptr == ' ' || *lex->ptr == '\t') { lex->ptr++; lex->col++; }
      char name[256];
      i = 0;
      while ((IS_IDENT_BYTE(*lex->ptr)) && i < 255) {
        name[i++] = *lex->ptr++;
        lex->col++;
      }
      name[i] = '\0';
      bool is_defined = (HashFind(name, cc->define_table, HTT_DEFINE_STR) != NULL);
      cond_true = is_ifndef ? !is_defined : is_defined;
    } else if (strcmp(directive, "ifjit") == 0) {
      cond_true = false;  // this compiler is always AOT
    } else if (strcmp(directive, "ifaot") == 0) {
      cond_true = true;
    } else {
      // #if — only literal 0 / non-zero
      while (*lex->ptr == ' ' || *lex->ptr == '\t') { lex->ptr++; lex->col++; }
      if (*lex->ptr == '0') { cond_true = false; lex->ptr++; }
      else if (*lex->ptr) { cond_true = true; if (*lex->ptr != '\n') { lex->ptr++; } }
    }
    if (cc->ifdef_depth < (int)(sizeof(cc->pp_stack) / sizeof(cc->pp_stack[0]))) {
      cc->pp_stack[cc->ifdef_depth].skip_before = cc->preprocessor_skip;
      bool then_active = !cc->preprocessor_skip && cond_true;
      cc->pp_stack[cc->ifdef_depth].taken = then_active;
      cc->preprocessor_skip = !then_active;
      cc->ifdef_depth++;
    }
  } else if (strcmp(directive, "exe") == 0) {
    // #exe { … } runs code at compile time in TempleOS; nothing to run here — skip the block
    // (it may span lines), then the rest of the line.
    while (*lex->ptr == ' ' || *lex->ptr == '\t') { lex->ptr++; lex->col++; }
    if (*lex->ptr == '{') {
      int depth = 0;
      do {
        if (*lex->ptr == '{') depth++;
        else if (*lex->ptr == '}') depth--;
        else if (*lex->ptr == '\n') { lex->line++; lex->col = 0; }
        lex->ptr++; lex->col++;
      } while (*lex->ptr && depth > 0);
    }
    while (*lex->ptr && *lex->ptr != '\n') { lex->ptr++; lex->col++; }
  } else if (strcmp(directive, "elif") == 0) {
    // #elif — only if parent is live and no prior branch of this frame was taken
    if (cc->ifdef_depth > 0) {
      int fi = cc->ifdef_depth - 1;
      bool parent_skip = cc->pp_stack[fi].skip_before;
      while (*lex->ptr == ' ' || *lex->ptr == '\t') { lex->ptr++; lex->col++; }
      bool cond_true = (*lex->ptr == '1');
      if (*lex->ptr == '0' || *lex->ptr == '1') lex->ptr++;
      if (parent_skip || cc->pp_stack[fi].taken) {
        cc->preprocessor_skip = true;
      } else if (cond_true) {
        cc->preprocessor_skip = false;
        cc->pp_stack[fi].taken = true;
      } else {
        cc->preprocessor_skip = true;
      }
    }
  } else if (strcmp(directive, "else") == 0) {
    if (cc->ifdef_depth > 0) {
      int fi = cc->ifdef_depth - 1;
      // else is active only when the parent is live and the then-branch was not
      cc->preprocessor_skip = cc->pp_stack[fi].skip_before || cc->pp_stack[fi].taken;
      if (!cc->pp_stack[fi].skip_before) cc->pp_stack[fi].taken = true;
    }
  } else if (strcmp(directive, "endif") == 0) {
    if (cc->ifdef_depth > 0) {
      cc->ifdef_depth--;
      cc->preprocessor_skip = cc->pp_stack[cc->ifdef_depth].skip_before;
    }
  } else if (strcmp(directive, "undef") == 0) {
    // #undef - undefine a macro
    while (*lex->ptr == ' ' || *lex->ptr == '\t') {
      lex->ptr++;
      lex->col++;
    }
    
    // Get macro name
    char name[256];
    i = 0;
  while ((IS_IDENT_BYTE(*lex->ptr)) && i < 255) {
      name[i++] = *lex->ptr++;
      lex->col++;
    }
    name[i] = '\0';
    
    // Remove from define table
    CHashEntry *removed = HashRemove(cc->define_table, name, HTT_DEFINE_STR);
    if (removed && (removed->type & HTT_DEFINE_STR)) {
      FreeDefine((CHashDefine*)removed);
    }
  }

skip_line:
  
  // Skip to end of line for all directives (a backslash continues the line: `#help_index "…"\`)
  while (*lex->ptr) {
    if (lex->ptr[0] == '\\' && lex->ptr[1] == '\n') { lex->ptr += 2; lex->line++; continue; }
    if (lex->ptr[0] == '\\' && lex->ptr[1] == '\r' && lex->ptr[2] == '\n') { lex->ptr += 3; lex->line++; continue; }
    if (*lex->ptr == '\n') break;
    lex->ptr++;
  }
  if (*lex->ptr == '\n') {
    lex->ptr++;
    lex->line++;
    lex->col = 1;
  }
}

static int LexIdentifier(Compiler *cc) {
  Lexer *lex = &cc->lex;
  char buf[256];
  int len = 0;
  
  // Check if character is alphanumeric or underscore or extended ASCII
  #define IS_IDENT_CHAR(c) ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || (unsigned char)c >= 128)
  
  while (IS_IDENT_CHAR(*lex->ptr)) {
    if (len < 255) {
      buf[len++] = *lex->ptr;
    }
    lex->ptr++;
    lex->col++;
  }
  buf[len] = '\0';
  
  #undef IS_IDENT_CHAR
  
  if (lex->token_str) free(lex->token_str);
  lex->token_str = strdup(buf);

  /* TempleOS KernelA builtins: intercept before `#define __DIR__ #exe{…}` expands to a skip. */
  if (!strcmp(buf, "__DIR__") || !strcmp(buf, "__FILE__") || !strcmp(buf, "__LINE__")) {
    int tok = LexExeBuiltin(cc, buf);
    if (tok) return tok;
  }
  
  // Check if it's a #define macro first
  CHashEntry *def_entry = HashFind(buf, cc->define_table, HTT_DEFINE_STR);
  if (def_entry && (def_entry->type & HTT_DEFINE_STR)) {
    CHashDefine *def = (CHashDefine*)def_entry;
    
    // Check if it's a parameterized macro
    if (def->param_count > 0) {
      // Need to check if followed by '('
      // Save current position
      char *saved_ptr = lex->ptr;
      int saved_col = lex->col;
      
      // Skip whitespace to check for '('
      while (*lex->ptr && (*lex->ptr == ' ' || *lex->ptr == '\t')) {
        lex->ptr++;
        lex->col++;
      }
      
      if (*lex->ptr == '(') {
        // It's a macro call - parse arguments
        lex->ptr++;  // Skip '('
        lex->col++;
        
        char *args[16];
        int arg_count = 0;
        
        // Parse arguments
        while (arg_count < 16 && *lex->ptr && *lex->ptr != ')') {
          // Skip whitespace
          while (*lex->ptr && (*lex->ptr == ' ' || *lex->ptr == '\t')) {
            lex->ptr++;
            lex->col++;
          }
          
          // Collect argument text
          char arg_buf[256];
          int arg_len = 0;
          int paren_depth = 0;
          
          while (*lex->ptr && arg_len < 255) {
            if (*lex->ptr == '(') {
              paren_depth++;
              arg_buf[arg_len++] = *lex->ptr++;
              lex->col++;
            } else if (*lex->ptr == ')') {
              if (paren_depth == 0) break;
              paren_depth--;
              arg_buf[arg_len++] = *lex->ptr++;
              lex->col++;
            } else if (*lex->ptr == ',' && paren_depth == 0) {
              break;
            } else {
              arg_buf[arg_len++] = *lex->ptr++;
              lex->col++;
            }
          }
          
          arg_buf[arg_len] = '\0';
          
          // Trim trailing whitespace
          while (arg_len > 0 && (arg_buf[arg_len-1] == ' ' || arg_buf[arg_len-1] == '\t')) {
            arg_buf[--arg_len] = '\0';
          }
          
          args[arg_count++] = strdup(arg_buf);
          
          // Skip comma if present
          if (*lex->ptr == ',') {
            lex->ptr++;
            lex->col++;
          }
        }
        
        if (*lex->ptr == ')') {
          lex->ptr++;  // Skip ')'
          lex->col++;
        }
        
        // Expand macro: substitute parameters in macro body
        char expanded[1024];
        int exp_len = 0;
        char *body = def->data;
        
        while (*body && exp_len < 1023) {
          // Check for # (stringification)
          if (*body == '#' && (IS_ALPHA_CHAR(body[1]) || body[1] == '_')) {
            body++;  // Skip '#'
            
            // Get parameter name
            char param_name[64];
            int pn_len = 0;
            while ((IS_ALNUM_CHAR(*body) || *body == '_') && pn_len < 63) {
              param_name[pn_len++] = *body++;
            }
            param_name[pn_len] = '\0';
            
            // Find matching parameter and stringify it
            bool found = false;
            for (int i = 0; i < def->param_count && i < arg_count; i++) {
              if (def->param_names[i] && strcmp(param_name, def->param_names[i]) == 0) {
                // Stringify: add quotes around argument
                if (exp_len < 1022) {
                  expanded[exp_len++] = '"';
                  int arg_len = strlen(args[i]);
                  if (exp_len + arg_len < 1022) {
                    strcpy(&expanded[exp_len], args[i]);
                    exp_len += arg_len;
                  }
                  expanded[exp_len++] = '"';
                }
                found = true;
                break;
              }
            }
            
            if (!found) {
              // Not a parameter, keep the # and name
              expanded[exp_len++] = '#';
              if (exp_len + pn_len < 1023) {
                strcpy(&expanded[exp_len], param_name);
                exp_len += pn_len;
              }
            }
            continue;
          }
          
          // Check for ## (token pasting)
          if (*body == '#' && body[1] == '#') {
            body += 2;  // Skip '##'
            // Skip whitespace after ##
            while (*body == ' ' || *body == '\t') body++;
            // Token pasting: just continue without adding anything
            // The tokens on either side will be concatenated
            continue;
          }
          
          // Check if this is a parameter name
          bool found_param = false;
          
          if (IS_ALPHA_CHAR(*body) || *body == '_') {
            // Possible parameter name
            char param_name[64];
            int pn_len = 0;
            char *temp = body;
            
            while ((IS_ALNUM_CHAR(*temp) || *temp == '_') && pn_len < 63) {
              param_name[pn_len++] = *temp++;
            }
            param_name[pn_len] = '\0';
            
            // Check if it matches a parameter
            for (int i = 0; i < def->param_count && i < arg_count; i++) {
              if (def->param_names[i] && strcmp(param_name, def->param_names[i]) == 0) {
                // Substitute with argument
                int arg_len = strlen(args[i]);
                if (exp_len + arg_len < 1023) {
                  strcpy(&expanded[exp_len], args[i]);
                  exp_len += arg_len;
                }
                body = temp;
                found_param = true;
                break;
              }
            }
          }
          
          if (!found_param) {
            expanded[exp_len++] = *body++;
          }
        }
        expanded[exp_len] = '\0';
        
        // Free arguments
        for (int i = 0; i < arg_count; i++) {
          free(args[i]);
        }
        
        // Re-lex the expanded text by pushing it onto the include stack
        IncludeFile *inc = calloc(1, sizeof(IncludeFile));
        inc->src = lex->src;
        inc->src_size = lex->src_size;
        inc->ptr = lex->ptr;
        inc->filename = lex->filename;
        inc->line = lex->line;
        inc->col = lex->col;
        inc->next = lex->include_stack;
        lex->include_stack = inc;
        
        // Replace with expanded macro text
        lex->src = strdup(expanded);
        lex->src_size = lex->src ? strlen(lex->src) : 0;
        lex->ptr = lex->src;
        lex->filename = strdup("<macro expansion>");
        lex->line = 1;
        lex->col = 1;
        
        // Recurse to lex first token from expanded text
        LexNext(cc);
        return cc->lex.token;
      } else {
        // Not followed by '(' - restore position and treat as identifier
        lex->ptr = saved_ptr;
        lex->col = saved_col;
      }
    } else {
      // Simple (non-parameterized) macro
      IncludeFile *inc = calloc(1, sizeof(IncludeFile));
      inc->src = lex->src;
      inc->src_size = lex->src_size;
      inc->ptr = lex->ptr;
      inc->filename = lex->filename;
      inc->line = lex->line;
      inc->col = lex->col;
      inc->next = lex->include_stack;
      lex->include_stack = inc;

      const char *replacement = def->data ? def->data : "";
      lex->src = strdup(replacement);
      lex->src_size = lex->src ? strlen(lex->src) : 0;
      lex->ptr = lex->src;
      lex->filename = strdup("<macro expansion>");
      lex->line = 1;
      lex->col = 1;

      LexNext(cc);
      return cc->lex.token;
    }
  }
  
  // Look up in hash table (like original Lex.HC)
  lex->hash_entry = HashFind(buf, cc->hash_table, 0xFFFFFFFF);
  
  if (lex->hash_entry) {
    // Prefer KEYWORD when INTERNAL_TYPE (or another entry) shadows it in the bucket.
    // `U32i` is both KW_U32 and an internal type; without this, `U32i union U32` lexes as
    // TK_IDENT and the `_extern SYMBOL` skipper eats the scalar base (U32 stayed RT_I64).
    if (!(lex->hash_entry->type & HTT_KEYWORD)) {
      CHashEntry *kw_e = HashFind(buf, cc->hash_table, HTT_KEYWORD);
      if (kw_e) lex->hash_entry = kw_e;
    }
    // Check if it's a keyword
    if (lex->hash_entry->type & HTT_KEYWORD) {
      CHashKeyword *kw = (CHashKeyword*)lex->hash_entry;
      return kw->keyword_code;
    }
    // Type/class/function - return as identifier
    return TK_IDENT;
  }
  
  // Not in hash table yet
  return TK_IDENT;
}

static int LexNumber(Lexer *lex) {
  I64 value = 0;
  
  // Check for 0x prefix
  if (lex->ptr[0] == '0' && (lex->ptr[1] == 'x' || lex->ptr[1] == 'X')) {
    lex->ptr += 2; // Skip '0x'
    lex->col += 2;
    
    // Parse hex digits manually
    while (*lex->ptr) {
      char c = *lex->ptr;
      if (c >= '0' && c <= '9') {
        value = value * 16 + (c - '0');
      } else if (c >= 'a' && c <= 'f') {
        value = value * 16 + (c - 'a' + 10);
      } else if (c >= 'A' && c <= 'F') {
        value = value * 16 + (c - 'A' + 10);
      } else {
        break;
      }
      lex->ptr++;
      lex->col++;
    }
  } else if (lex->ptr[0] == '0' && (lex->ptr[1] == 'b' || lex->ptr[1] == 'B') &&
             (lex->ptr[2] == '0' || lex->ptr[2] == '1')) {
    // 0b binary (HolyC LexGetNumber)
    lex->ptr += 2;
    lex->col += 2;
    while (*lex->ptr == '0' || *lex->ptr == '1') {
      value = value * 2 + (*lex->ptr - '0');
      lex->ptr++;
      lex->col++;
    }
  } else if (lex->ptr[0] == '0' && (lex->ptr[1] == 'd' || lex->ptr[1] == 'D') &&
             (lex->ptr[2] >= '0' && lex->ptr[2] <= '9')) {
    // 0d decimal
    lex->ptr += 2;
    lex->col += 2;
    while (*lex->ptr >= '0' && *lex->ptr <= '9') {
      value = value * 10 + (*lex->ptr - '0');
      lex->ptr++;
      lex->col++;
    }
  } else if (lex->ptr[0] == '0' && (lex->ptr[1] == 'o' || lex->ptr[1] == 'O') &&
             (lex->ptr[2] >= '0' && lex->ptr[2] <= '7')) {
    // 0o octal
    lex->ptr += 2;
    lex->col += 2;
    while (*lex->ptr >= '0' && *lex->ptr <= '7') {
      value = value * 8 + (*lex->ptr - '0');
      lex->ptr++;
      lex->col++;
    }
  } else {
    // Parse decimal digits manually (no atoll in bare metal)
    while (*lex->ptr >= '0' && *lex->ptr <= '9') {
      value = value * 10 + (*lex->ptr - '0');
      lex->ptr++;
      lex->col++;
    }
  }
  
  // Floating literal: digits ['.' digits] [e[+-]digits]  (decimal only; 0x... never gets here)
  bool exp_follows = (*lex->ptr == 'e' || *lex->ptr == 'E') &&
                     ((lex->ptr[1] >= '0' && lex->ptr[1] <= '9') ||
                      ((lex->ptr[1] == '+' || lex->ptr[1] == '-') && lex->ptr[2] >= '0' && lex->ptr[2] <= '9'));
  if ((*lex->ptr == '.' && lex->ptr[1] >= '0' && lex->ptr[1] <= '9') || exp_follows) {
    F64 f = (F64)value, scale = 0.1;
    if (*lex->ptr == '.') {
      lex->ptr++; lex->col++;
      while (*lex->ptr >= '0' && *lex->ptr <= '9') {
        f += (F64)(*lex->ptr - '0') * scale;
        scale /= 10.0;
        lex->ptr++; lex->col++;
      }
    }
    if ((*lex->ptr == 'e' || *lex->ptr == 'E') &&
        ((lex->ptr[1] >= '0' && lex->ptr[1] <= '9') ||
         ((lex->ptr[1] == '+' || lex->ptr[1] == '-') && lex->ptr[2] >= '0' && lex->ptr[2] <= '9'))) {
      lex->ptr++; lex->col++;
      int neg = 0, e = 0;
      if (*lex->ptr == '+' || *lex->ptr == '-') { neg = (*lex->ptr == '-'); lex->ptr++; lex->col++; }
      while (*lex->ptr >= '0' && *lex->ptr <= '9') { e = e * 10 + (*lex->ptr - '0'); lex->ptr++; lex->col++; }
      // Scale by 10^e with exact powers up to 1e22 and as few roundings as possible.
      static const double p10[] = { 1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
                                    1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22 };
      double scale10 = 1.0;
      int ee = e;
      while (ee > 22) { scale10 *= 1e22; ee -= 22; }
      scale10 *= p10[ee];
      f = neg ? f / scale10 : f * scale10;
    }
    lex->token_f64 = f;
    return TK_F64;
  }
  lex->token_i64 = value;
  return TK_I64;
}

static int LexString(Lexer *lex) {
  static char buf[65536];   // TempleOS strings (DolDoc text) run long; static: not on the stack
  int len = 0;
  char quote = *lex->ptr++;
  lex->col++;
  
  for (;;) {
  while (*lex->ptr && *lex->ptr != quote) {
    if (*lex->ptr == '\\') {
      lex->ptr++;
      lex->col++;
      switch (*lex->ptr) {
        case 'n': buf[len++] = '\n'; lex->ptr++; lex->col++; break;
        case 't': buf[len++] = '\t'; lex->ptr++; lex->col++; break;
        case 'r': buf[len++] = '\r'; lex->ptr++; lex->col++; break;
        /* Host extension: C-style \b = BS (0x08). TempleOS Lex.HC omits it;
         * without this, "\b \b" / '\b' become literal 'b' and UART rubout echo breaks. */
        case 'b': buf[len++] = '\b'; lex->ptr++; lex->col++; break;
        case '\\': buf[len++] = '\\'; lex->ptr++; lex->col++; break;
        case '"': buf[len++] = '"'; lex->ptr++; lex->col++; break;
        case '\'': buf[len++] = '\''; lex->ptr++; lex->col++; break;
        case 'd': // \d = '$' (DolDoc escape)
          buf[len++] = '$';
          lex->ptr++; lex->col++;
          break;
        default:
          // Octal escapes (\0, \012, …): DefineLstLoad lists are NUL-separated and
          // require a trailing empty entry (double NUL). Treating \0 as the character
          // '0' left a single terminator and DefineLstLoad walked off the string.
          if (*lex->ptr >= '0' && *lex->ptr <= '7') {
            int v = 0, nd = 0;
            while (nd < 3 && *lex->ptr >= '0' && *lex->ptr <= '7') {
              v = (v << 3) + (*lex->ptr - '0');
              lex->ptr++; lex->col++; nd++;
            }
            buf[len++] = (char)(v & 0xff);
          } else {
            buf[len++] = *lex->ptr;
            lex->ptr++; lex->col++;
          }
          break;
      }
    } else if (*lex->ptr == '$' && lex->ptr[1] >= 'A' && lex->ptr[1] <= 'Z') {
      // A DolDoc command inside a string (`$TX,"512Meg",D="…"$`): quotes inside it do not end
      // the literal. Copied verbatim; the UART runtime shows it as-is.
      buf[len++] = *lex->ptr++; lex->col++;
      while (*lex->ptr) {
        if (lex->ptr[0] == '$') {
          if (lex->ptr[1] == '$') { buf[len++] = '$'; lex->ptr += 2; lex->col += 2; continue; }
          buf[len++] = *lex->ptr++; lex->col++;
          break;
        }
        if (*lex->ptr == '\n') { lex->line++; lex->col = 1; } else lex->col++;
        buf[len++] = *lex->ptr++;
      }
    } else if (*lex->ptr == '$' && lex->ptr[1] == '$') {
      // `$$` is a literal '$' in HolyC source (DolDoc escape); "$$FG,RED$$" carries a DolDoc
      // command to the console, which the UART runtime strips at print time.
      buf[len++] = '$';
      lex->ptr += 2;
      lex->col += 2;
    } else {
      buf[len++] = *lex->ptr++;
      lex->col++;
    }
  }
  
  if (*lex->ptr == quote) {
    lex->ptr++;
    lex->col++;
  }
  if (quote == '"') {
    // Adjacent literals concatenate ("a" "b", also across lines and comments).
    char *p = lex->ptr; int line = lex->line, col = lex->col;
    for (;;) {
      while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') { if (*p == '\n') { line++; col = 1; } else col++; p++; }
      if (p[0] == '/' && p[1] == '/') { while (*p && *p != '\n') p++; continue; }
      if (p[0] == '/' && p[1] == '*') { p += 2; while (*p && !(p[0] == '*' && p[1] == '/')) { if (*p == '\n') line++; p++; } if (*p) p += 2; continue; }
      break;
    }
    if (*p == '"') { lex->ptr = p + 1; lex->line = line; lex->col = col + 1; continue; }
  }
  break;
  }
  
  buf[len] = '\0';
  if (lex->token_str) free(lex->token_str);
  lex->token_str = malloc(len + 1);
  memcpy(lex->token_str, buf, len + 1);
  lex->token_str_len = len;
  if (quote == '\'') {
    // HolyC char literal: up to 8 chars packed little-endian into an I64 ('AB' == 0x4241).
    lex->token_i64 = 0;
    for (int i = 0; i < len && i < 8; i++) lex->token_i64 |= (I64)(U8)buf[i] << (8 * i);
    lex->token_is_char = true;
    return TK_I64;
  }
  return TK_STR;
}

static void LexNextInner(Compiler *cc);

// ── Newline as a statement separator (the BCPL rule) ─────────────────────────────────────────
//
// BCPL let a newline end a statement when the statement had plainly ended, and required a
// semicolon only when it had not. That is what this does. It is decided from the token just
// read and the character about to be read, without lexing ahead: the next token is not needed,
// only the shape of what starts the line.
//
// A newline ends the statement when ALL of these hold:
//   * the previous token could end one — a name, a number, a string, `)`, `]`, `++`, `--`.
//     NOT `}` (a function body is followed by the next declaration, not by an empty statement),
//     not a keyword (`return` on its own line must not become `return;`), not an operator.
//   * no bracket is open. Inside ( ) or [ ] a newline is continuation, which is what makes a
//     wrapped argument list work.
//   * the line does not begin with something that CONTINUES the statement: an operator, `,`
//     `.` `?` `:` `)` `]` `}`, an opening `{` (a function header is followed by its body, not
//     by a prototype), or the words `else` and `while`.
//   * the `)` just read did not close an `if`/`while`/`for`/`switch` header, or the body would
//     become an empty statement — the classic dangling-if of every language that does this.
//   * we are not inside an asm{} block, where newlines already separate instructions and belong
//     to the assembler.
//
// Existing source is unaffected: a line ending in `;` has `;` as its previous token, which is
// not a terminator, so nothing is inserted.
static bool NewlineStarterContinues(Compiler *cc, const char *p) {
  char c = p[0];
  if (!c) return true;
  if (strchr("+-*/%&|^<>=!?:,.)]}{~", c)) return true;
  // A line that starts with a string continues the one before it ONLY when the one before it
  // was itself a string, or the word `format` — those are the two shapes of HolyC's adjacent-
  // literal concatenation (a class field's format spec is the common one, KernelA.HH:3910).
  // After anything else a leading string is a new statement, which is how a print reads.
  if (c == '"') {
    if (cc->lex.token == TK_STR) return true;
    if (cc->lex.token == TK_IDENT && cc->lex.token_str && !strcmp(cc->lex.token_str, "format"))
      return true;
    return false;
  }
  if (c == 'e' && !strncmp(p, "else", 4) && !isalnum((unsigned char)p[4]) && p[4] != '_') return true;
  // `while` continues the statement only when it is a do..while's own while. Suppressing it
  // always would cost the far commoner case — a loop following an ordinary statement.
  if (cc->lex.nl_do_brace && c == 'w' && !strncmp(p, "while", 5) &&
      !isalnum((unsigned char)p[5]) && p[5] != '_')
    return true;
  return false;
}

static bool NewlineEndsStatement(Compiler *cc, int prev, bool after_ctl) {
  Lexer *lex = &cc->lex;
  // ON by default now. It was opt-in while the rule learned HolyC's line-spanning shapes —
  // adjacent string literals, `_extern` declarations, `while` after a `do`, and a type name on
  // a line of its own — and the gate for turning it on was that the whole kernel image compiles
  // BYTE-IDENTICAL with it, which it does. HOLYC_NL_SEMI=0 turns it off if that ever stops
  // being true.
  //
  // A file static rather than lexer state: the answer is the same for every file in a run, and
  // the lexer struct is memset to zero in places where -1 could not survive as "not yet read".
#ifdef BARE_METAL
  return false;
#else
  static int nl_on = -1;
  if (nl_on < 0) {
    const char *e = getenv("HOLYC_NL_SEMI");
    nl_on = (e && *e && *e == '0') ? 0 : 1;
  }
  if (!nl_on) return false;
#endif
  if (lex->paren_depth > 0) return false;
  if (lex->nl_asm_depth) return false;
  if (lex->nl_decl) return false;
  // a public/_extern/import declaration runs to its own semicolon, across as many lines as it
  // likes — see KernelB.HH's extern tables
  if (after_ctl) return false;
  if (!(prev == TK_IDENT || prev == TK_I64 || prev == TK_F64 || prev == TK_STR ||
        prev == ')' || prev == ']' || prev == TK_PLUS_PLUS || prev == TK_MINUS_MINUS))
    return false;
  // A TYPE NAME cannot end a statement. HolyC writes wide declarations with the class on its
  // own line and the declarator under it:
  //     U32
  //       char_bmp_alpha[16]= {...};
  // and there are pages of those in Kernel/StrA.HC. The lexer already resolved the identifier,
  // so ask what it was rather than guessing from the spelling.
  if (prev == TK_IDENT && lex->hash_entry && (lex->hash_entry->type & HTT_CLASS))
    return false;
  // `lock` takes a STATEMENT, and stock writes that statement on the NEXT line:
  //     for (i=0;i<CNT;i++)
  //         lock  //Can be used without {}
  //           glbl++;
  // Ending the statement at the newline makes the lock bracket NOTHING and moves `glbl++` out of
  // the loop, where it runs once. Demo/MultiCore/Lock.HC printed `Actual Cnt:2` instead of
  // `2000000` for exactly that reason. `lock` is an unknown identifier here (host/parser.c turns
  // it into IC_LOCK_ENTER/IC_LOCK_LEAVE), so it has no hash entry to ask — compare the spelling.
  // CLI/STI/PUSHFD/POPFD/PAUSE are complete statements and must keep ending at a newline.
  if (prev == TK_IDENT && !lex->hash_entry && lex->token_str && !strcmp(lex->token_str, "lock"))
    return false;
  if (NewlineStarterContinues(cc, lex->ptr)) return false;
  return true;
}
// Read `text` as the next tokens, holding the current token back until the text is exhausted
// (default arguments are expressions evaluated at each call site).
void LexPushStringPending(Compiler *cc, const char *text) {
  Lexer *lex = &cc->lex;
  IncludeFile *inc = calloc(1, sizeof(IncludeFile));
  inc->src = lex->src; inc->src_size = lex->src_size;
  inc->ptr = lex->ptr; inc->filename = lex->filename; inc->line = lex->line; inc->col = lex->col;
  inc->has_pending = true;
  // The default-argument text is a complete expression; its brackets belong to it, not to the
  // file that called it. Saved here and put back when the string is exhausted.
  inc->has_nl_state = true;
  inc->s_brace_depth = lex->brace_depth; inc->s_paren_depth = lex->paren_depth;
  inc->s_nl_asm_depth = lex->nl_asm_depth; inc->s_nl_ctl_paren = lex->nl_ctl_paren;
  inc->s_nl_do_brace = lex->nl_do_brace; inc->s_nl_decl = lex->nl_decl;
  inc->s_nl_after_ctl = lex->nl_after_ctl;
  inc->p_token = lex->token; inc->p_i64 = lex->token_i64; inc->p_f64 = lex->token_f64;
  inc->p_is_char = lex->token_is_char; inc->p_str_len = lex->token_str_len; inc->p_hash = lex->hash_entry;
  inc->p_str = lex->token_str; lex->token_str = NULL;
  inc->next = lex->include_stack;
  lex->include_stack = inc;
  lex->src = strdup(text);
  lex->src_size = lex->src ? strlen(lex->src) : 0;
  lex->ptr = lex->src;
  lex->filename = strdup("<default argument>");
  lex->line = 1; lex->col = 1;
  LexNext(cc);
}
// Drop a pushed default-argument string after a parse error inside it, so the next item
// resumes at the token that was held back.
void LexAbandonPendingString(Compiler *cc) {
  Lexer *lex = &cc->lex;
  while (lex->include_stack) {
    IncludeFile *inc = lex->include_stack;
    bool pend = inc->has_pending;
    lex->include_stack = inc->next;
    lex->src = inc->src; lex->src_size = inc->src_size;
    lex->ptr = inc->ptr; lex->filename = inc->filename; lex->line = inc->line; lex->col = inc->col;
    if (pend) {
      if (inc->has_nl_state) {
        lex->brace_depth = inc->s_brace_depth; lex->paren_depth = inc->s_paren_depth;
        lex->nl_asm_depth = inc->s_nl_asm_depth; lex->nl_ctl_paren = inc->s_nl_ctl_paren;
        lex->nl_do_brace = inc->s_nl_do_brace; lex->nl_decl = inc->s_nl_decl;
        lex->nl_after_ctl = inc->s_nl_after_ctl;
      }
      lex->token = inc->p_token; lex->token_i64 = inc->p_i64; lex->token_f64 = inc->p_f64;
      lex->token_is_char = inc->p_is_char; lex->token_str_len = inc->p_str_len; lex->hash_entry = inc->p_hash;
      if (lex->token_str) free(lex->token_str);
      lex->token_str = inc->p_str; inc->p_str = NULL;
      free(inc);
      return;
    }
    free(inc);
  }
}
void LexNext(Compiler *cc) {
  LexNextInner(cc);
#ifndef BARE_METAL
  {
    static const char *tf = NULL; static int inited = 0;
    if (!inited) { tf = getenv("HOLYC_TOKTRACE"); inited = 1; }
    if (tf && cc->lex.filename && strstr(cc->lex.filename, tf))
      fprintf(stderr, "[tok] %s:%d tok=%d '%s' depth=%d\n", cc->lex.filename, cc->lex.line, cc->lex.token,
              (cc->lex.token == TK_IDENT || cc->lex.token == TK_STR) && cc->lex.token_str ? cc->lex.token_str : "", cc->lex.brace_depth);
  }
#endif
}
static void LexNextInner(Compiler *cc) {
  Lexer *lex = &cc->lex;
  int prev_token = lex->token;
  int line_before = lex->line;
  bool after_ctl = lex->nl_after_ctl;
  lex->nl_after_ctl = false;
  // one-shot: it describes the token just read, not the rest of the file
  lex->token_is_char = false;
  
  // Skip whitespace, comments, DolDoc, and preprocessor directives
  while (true) {
    SkipWhitespace(lex);
    if (lex->ptr[0] == '/' && (lex->ptr[1] == '/' || lex->ptr[1] == '*')) {
      SkipComment(lex);
    } else if (lex->ptr[0] == '$' && lex->ptr[1] == '$') {
      // `$$` in code: the current address (`Fs->rip=$$;`) or, in a class body, the offset.
      lex->ptr += 2; lex->col += 2; lex->token = TK_DOLLAR; return;
    } else if (lex->ptr[0] == '$' && lex->ptr[1] >= 'A' && lex->ptr[1] <= 'Z') {
      // DolDoc in code. `$IB`/`$IS` insert bin ptr/size from trailing CDocBin (TempleOS).
      // `$SP…$` (sprite defs) and other cmds vanish from the token stream.
      bool is_ib = (lex->ptr[1] == 'I' && lex->ptr[2] == 'B');
      bool is_is = (lex->ptr[1] == 'I' && lex->ptr[2] == 'S');
      if (is_ib || is_is) {
        LexEmitDocBin(cc, is_is ? 1 : 0);
        return;
      }
      SkipDolDoc(lex);
    } else if (*lex->ptr == '#') {
      HandlePreprocessor(cc);
    } else {
      break;
    }
  }
  
  // A newline crossed between the last token and this one may itself be the statement's end.
  if (lex->line > line_before && !cc->preprocessor_skip &&
      NewlineEndsStatement(cc, prev_token, after_ctl)) {
    lex->token = ';';
    return;
  }

  // If preprocessor says skip, consume tokens until #else or #endif
  if (cc->preprocessor_skip && *lex->ptr != '#') {
    // Skip lines until we hit a preprocessor directive
    while (*lex->ptr && *lex->ptr != '#') {
      if (*lex->ptr == '\n') {
        lex->line++;
        lex->col = 1;
      } else {
        lex->col++;
      }
      lex->ptr++;
    }
    if (*lex->ptr == '#') {
      // Process the directive (might be #endif or #else)
      HandlePreprocessor(cc);
      // Recurse to get next real token
      return LexNext(cc);
    }
  }
  
  // End of file - check if we need to pop include stack
  if (!*lex->ptr) {
    if (lex->include_stack) {
      // Pop back to previous file
      IncludeFile *inc = lex->include_stack;
      lex->include_stack = inc->next;
      
      // The finished buffer is intentionally not freed: a LexPush taken inside it may still
      // be restored after the lookahead ran past its end.
      
      // Restore previous file
      lex->src = inc->src;
      lex->src_size = inc->src_size;
      lex->ptr = inc->ptr;
      lex->filename = inc->filename;
      lex->line = inc->line;
      lex->col = inc->col;
      if (inc->has_pending) {   // a pushed string ended: resume with the token held back
        if (inc->has_nl_state) {
          lex->brace_depth = inc->s_brace_depth; lex->paren_depth = inc->s_paren_depth;
          lex->nl_asm_depth = inc->s_nl_asm_depth; lex->nl_ctl_paren = inc->s_nl_ctl_paren;
          lex->nl_do_brace = inc->s_nl_do_brace; lex->nl_decl = inc->s_nl_decl;
          lex->nl_after_ctl = inc->s_nl_after_ctl;
        }
        lex->token = inc->p_token; lex->token_i64 = inc->p_i64; lex->token_f64 = inc->p_f64;
        lex->token_is_char = inc->p_is_char; lex->token_str_len = inc->p_str_len; lex->hash_entry = inc->p_hash;
        if (lex->token_str) free(lex->token_str);
        lex->token_str = inc->p_str; inc->p_str = NULL; inc->has_pending = false;
        if (!lex->stack) free(inc);
        return;
      }
      // Keep the frame while a lookahead is pending: LexPopRestore re-links it if the
      // LexPush was taken inside this buffer (a macro's last token, `_intern IC_BT Bool …`).
#ifndef BARE_METAL
      if (getenv("HOLYC_TRACE") && lex->stack) fprintf(stderr, "[trace] frame pop with pending lookahead: back to %s:%d\n", lex->filename ? lex->filename : "?", lex->line);
#endif
      if (!lex->stack) free(inc);
      
      // Continue lexing from restored position
      return LexNext(cc);
    }
    
    // Really at EOF
    lex->token = TK_EOF;
    return;
  }
  
  // Identifier or keyword
  if ((*lex->ptr >= 'a' && *lex->ptr <= 'z') || (*lex->ptr >= 'A' && *lex->ptr <= 'Z') || *lex->ptr == '_' ||
      ((unsigned char)*lex->ptr >= 128 && (unsigned char)*lex->ptr != 0xEC && (unsigned char)*lex->ptr != 0xE3 &&
       !((unsigned char)lex->ptr[0] == 0xE2 && (unsigned char)lex->ptr[1] == 0x88) &&
       !((unsigned char)lex->ptr[0] == 0xCF && (unsigned char)lex->ptr[1] == 0x80))) {   // `µs`: TempleOS charset
    lex->token = LexIdentifier(cc);
    // A control header's parentheses are not an expression's: the newline after the one that
    // closes them must not end the statement, or `if (x)` on its own line becomes `if (x);`.
    if (lex->token == KW_IF || lex->token == KW_WHILE || lex->token == KW_FOR ||
        lex->token == KW_SWITCH)
      lex->nl_ctl_paren = lex->paren_depth + 1;
    if (lex->token == KW_PUBLIC || lex->token == KW_EXTERN || lex->token == KW__EXTERN ||
        lex->token == KW_IMPORT)
      lex->nl_decl = true;
    if (lex->token == KW_DO)
      lex->nl_do_brace = lex->brace_depth + 1;
    else if (lex->token == KW_WHILE && lex->nl_do_brace &&
             lex->brace_depth + 1 <= lex->nl_do_brace)
      lex->nl_do_brace = 0;
    // ...that was the do's own while; an inner one sits at a deeper brace depth
    else if (lex->token == KW_ASM)
      lex->nl_asm_depth = lex->brace_depth + 1;
    // inside asm{} the newlines are the assembler's, and it already uses them
    return;
  }
  
  // Number
  if ((*lex->ptr >= '0' && *lex->ptr <= '9') || (*lex->ptr == '.' && lex->ptr[1] >= '0' && lex->ptr[1] <= '9')) {
    lex->token = LexNumber(lex);
    return;
  }
  
  // String
  if (*lex->ptr == '"' || *lex->ptr == '\'') {
    lex->token = LexString(lex);
    return;
  }
  
  // Two-character operators
  if (lex->ptr[0] == '=' && lex->ptr[1] == '=') {
    lex->token = TK_EQU_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '!' && lex->ptr[1] == '=') {
    lex->token = TK_NOT_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '<' && lex->ptr[1] == '=') {
    lex->token = TK_LESS_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '>' && lex->ptr[1] == '=') {
    lex->token = TK_GREATER_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '<' && lex->ptr[1] == '<' && lex->ptr[2] == '=') {
    lex->token = TK_SHL_EQU;
    lex->ptr += 3;
    lex->col += 3;
    return;
  }
  if (lex->ptr[0] == '>' && lex->ptr[1] == '>' && lex->ptr[2] == '=') {
    lex->token = TK_SHR_EQU;
    lex->ptr += 3;
    lex->col += 3;
    return;
  }
  if (lex->ptr[0] == '%' && lex->ptr[1] == '=') {
    lex->token = TK_MOD_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '<' && lex->ptr[1] == '<') {
    lex->token = TK_SHL;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '>' && lex->ptr[1] == '>') {
    lex->token = TK_SHR;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '&' && lex->ptr[1] == '&') {
    lex->token = TK_AND_AND;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '|' && lex->ptr[1] == '|') {
    lex->token = TK_OR_OR;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '^' && lex->ptr[1] == '^') {
    lex->token = TK_XOR_XOR;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '+' && lex->ptr[1] == '+') {
    lex->token = TK_ADD_ADD;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '+' && lex->ptr[1] == '=') {
    lex->token = TK_ADD_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '-' && lex->ptr[1] == '-') {
    lex->token = TK_SUB_SUB;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '-' && lex->ptr[1] == '=') {
    lex->token = TK_SUB_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '-' && lex->ptr[1] == '>') {
    lex->token = TK_ARROW;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '*' && lex->ptr[1] == '=') {
    lex->token = TK_MUL_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '/' && lex->ptr[1] == '=') {
    lex->token = TK_DIV_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '&' && lex->ptr[1] == '=') {
    lex->token = TK_AND_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '|' && lex->ptr[1] == '=') {
    lex->token = TK_OR_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '^' && lex->ptr[1] == '=') {
    lex->token = TK_XOR_EQU;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == ':' && lex->ptr[1] == ':') {
    lex->token = TK_DBL_COLON;
    lex->ptr += 2;
    lex->col += 2;
    return;
  }
  if (lex->ptr[0] == '.' && lex->ptr[1] == '.' && lex->ptr[2] == '.') {
    lex->token = TK_ELLIPSIS;
    lex->ptr += 3;
    lex->col += 3;
    return;
  }
  
  // `π` (TempleOS char 0xE3, or UTF-8 CF 80): F64 pi literal
  if ((unsigned char)lex->ptr[0] == 0xE3 ||
      ((unsigned char)lex->ptr[0] == 0xCF && (unsigned char)lex->ptr[1] == 0x80)) {
    lex->ptr += ((unsigned char)lex->ptr[0] == 0xE3) ? 1 : 2;
    lex->col++;
    lex->token = TK_F64;
    lex->token_f64 = 3.141592653589793;
    return;
  }
  // `∞` (TempleOS char 0xEC, or UTF-8 on the host): F64 infinity literal
  if ((unsigned char)lex->ptr[0] == 0xEC ||
      ((unsigned char)lex->ptr[0] == 0xE2 && (unsigned char)lex->ptr[1] == 0x88 && (unsigned char)lex->ptr[2] == 0x9E)) {
    lex->ptr += ((unsigned char)lex->ptr[0] == 0xEC) ? 1 : 3;
    lex->col++;
    lex->token = TK_F64;
    lex->token_f64 = __builtin_inf();
    return;
  }
  // Single character
  lex->token = *lex->ptr++;
  lex->col++;
  if (lex->token == ';' || lex->token == '{') lex->nl_decl = false;
  if (lex->token == '{') {
    lex->brace_depth++;
  } else if (lex->token == '}') {
    lex->brace_depth--;
    if (lex->nl_asm_depth && lex->brace_depth < lex->nl_asm_depth) lex->nl_asm_depth = 0;
  } else if (lex->token == '(' || lex->token == '[') {
    lex->paren_depth++;
  } else if (lex->token == ')' || lex->token == ']') {
    if (lex->paren_depth > 0) lex->paren_depth--;
    // Closing an if/while/for/switch header: the next newline must NOT end the statement, or
    // the body becomes an empty one.
    if (lex->nl_ctl_paren && lex->paren_depth < lex->nl_ctl_paren) {
      lex->nl_ctl_paren = 0;
      lex->nl_after_ctl = true;
    }
  }
}

bool LexExpect(Compiler *cc, int token) {
  if (cc->lex.token != token) {
    // Error: token mismatch (no stdio like HolyC)
    return false;
  }
  LexNext(cc);
  return true;
}

bool IsKeyword(const char *str) {
  for (int i = 0; keywords[i].name; i++) {
    if (strcmp(str, keywords[i].name) == 0) {
      return true;
    }
  }
  return false;
}

void Error(Compiler *cc, const char *msg) {
  if (!cc->error) {
    cc->error = strdup(msg);
    cc->error_line = cc->lex.line;
    cc->error_col = cc->lex.col;
    cc->error_file = cc->lex.filename;
  }
  // No fprintf - HolyC doesn't use stdio
}

// ═══════════════════════════════════════════════════════════════
// LEXER STATE STACK (LexPush/LexPop)
// ═══════════════════════════════════════════════════════════════

void LexPush(Compiler *cc) {
  
  // Save current lexer state onto stack
  LexerStack *saved = calloc(1, sizeof(LexerStack));
  
  
  if (!saved) {
    // Allocation failed - can't save state
    // This will break lookahead, but prevents crash
    return;
  }
  
  
  // Check cc validity
  if (!cc) {
    free(saved);
    return;
  }
  
  
  saved->ptr = cc->lex.ptr;
  
  saved->line = cc->lex.line;
  saved->col = cc->lex.col;
  saved->token = cc->lex.token;
  saved->token_i64 = cc->lex.token_i64;
  saved->token_f64 = cc->lex.token_f64;
  
  
  if (cc->lex.token_str) {
    size_t n = (cc->lex.token == TK_STR) ? (size_t)cc->lex.token_str_len : strlen(cc->lex.token_str);
    saved->token_str = malloc(n + 1);
    memcpy(saved->token_str, cc->lex.token_str, n + 1);
  } else saved->token_str = NULL;
  saved->token_str_len = cc->lex.token_str_len;
  saved->brace_depth = cc->lex.brace_depth;
  saved->paren_depth = cc->lex.paren_depth;
  saved->nl_asm_depth = cc->lex.nl_asm_depth;
  saved->nl_ctl_paren = cc->lex.nl_ctl_paren;
  saved->nl_do_brace = cc->lex.nl_do_brace;
  saved->nl_decl = cc->lex.nl_decl;
  saved->nl_after_ctl = cc->lex.nl_after_ctl;
  
  
  saved->hash_entry = cc->lex.hash_entry;
  saved->src = cc->lex.src;
  saved->src_size = cc->lex.src_size;
  saved->filename = cc->lex.filename;
  saved->include_stack = cc->lex.include_stack;
  
  
  // Push onto stack
  saved->next = cc->lex.stack;
  cc->lex.stack = saved;
  
}

void LexPopRestore(Compiler *cc) {
  // Restore lexer state from stack
  if (!cc->lex.stack) return;  // Nothing to restore
  
  LexerStack *saved = cc->lex.stack;
  
  // Unwind any #include / macro-expansion frames entered during the lookahead, so that
  // src/ptr describe the same buffer again (a macro used inside parentheses hits this).
  IncludeFile *f = cc->lex.include_stack;
  while (f && f != saved->include_stack) f = f->next;
  if (f == saved->include_stack) {
    while (cc->lex.include_stack != saved->include_stack) {
      IncludeFile *inc = cc->lex.include_stack;
      cc->lex.include_stack = inc->next;
      cc->lex.src = inc->src;
      cc->lex.src_size = inc->src_size;
      cc->lex.filename = inc->filename;
      free(inc);
    }
    cc->lex.src = saved->src;
    cc->lex.src_size = saved->src_size;
    cc->lex.filename = saved->filename;
  } else {
    // Frames finished during the lookahead were popped (kept alive above): re-link them so
    // the saved buffer resumes and then returns to the outer file where it left off.
    cc->lex.include_stack = saved->include_stack;
    cc->lex.src = saved->src;
    cc->lex.src_size = saved->src_size;
    cc->lex.filename = saved->filename;
  }
  // Restore state
  cc->lex.ptr = saved->ptr;
  cc->lex.line = saved->line;
  cc->lex.col = saved->col;
  cc->lex.token = saved->token;
  cc->lex.token_i64 = saved->token_i64;
  cc->lex.token_f64 = saved->token_f64;
  
  // Free old token_str and restore saved one
  if (cc->lex.token_str) free(cc->lex.token_str);
  cc->lex.token_str = saved->token_str;  // Transfer ownership
  cc->lex.token_str_len = saved->token_str_len;
  cc->lex.brace_depth = saved->brace_depth;
  cc->lex.paren_depth = saved->paren_depth;
  cc->lex.nl_asm_depth = saved->nl_asm_depth;
  cc->lex.nl_ctl_paren = saved->nl_ctl_paren;
  cc->lex.nl_do_brace = saved->nl_do_brace;
  cc->lex.nl_decl = saved->nl_decl;
  cc->lex.nl_after_ctl = saved->nl_after_ctl;
  
  cc->lex.hash_entry = saved->hash_entry;
  
  // Pop from stack
  cc->lex.stack = saved->next;
  free(saved);
}

void LexPopNoRestore(Compiler *cc) {
  // Discard saved state without restoring
  if (!cc->lex.stack) return;
  
  LexerStack *saved = cc->lex.stack;
  
  // Free the saved token_str
  if (saved->token_str) free(saved->token_str);
  
  // Pop from stack
  cc->lex.stack = saved->next;
  free(saved);
}

