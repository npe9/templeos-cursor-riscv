/* HolyC source formatter (gofmt-like).
 *
 * Engine: format lexer → FmtAst (CST) → pretty-print.  The host compiler's
 * parser.c emits intermediate code (IC), not a source AST; this module builds
 * its own format tree so emit is structure-driven.
 *
 * Hybrid boundary (honest): statement/block/control/asm/#include/#define nodes
 * are AST-walked.  Expression and declarator interiors are token sequences with
 * canonical spacing (gofmt/C-like ops), not a full expr AST.
 *
 * Rules: 2-space indent; tabs only inside asm{}; #directives at column 0;
 * space after if/while/for/switch/catch before '('; spaces around binary ops
 * and after ','; dense unary (*p, -x, !f) and member glue (-> . ::); control-flow
 * '{' on the same line; function/class '{' on the next line.  Comments and asm
 * interiors are preserved (asm re-indented with tabs).
 */
#ifndef HOLYC_FMT_H
#define HOLYC_FMT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* True if name looks like HolyC source (.hc/.HC/.hh/.HH), including path suffix. */
int HolyFmtIsHcName(const char *name);

/* Format src into out (NUL-terminated). Returns byte length excluding NUL, or -1
 * if args are bad or out_cap is too small. */
long long HolyFmtSrc(const char *src, char *out, long long out_cap);

#ifdef __cplusplus
}
#endif

#endif
