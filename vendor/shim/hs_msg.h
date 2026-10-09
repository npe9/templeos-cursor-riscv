/* UPSTREAM BUG WORKAROUND -- see docs/CFS_UPSTREAM_NOTES.md #22.
 *
 * NASA's vendor/HS/config/default_hs_msg.h opens with
 *
 *     #ifndef DEFAULT_HK_MSG_H
 *     #define DEFAULT_HK_MSG_H
 *
 * -- **HK's include guard, not HS's**, copy-pasted from vendor/HK/config/default_hk_msg.h, which
 * uses the same name. It is the only header in either repository with the wrong guard.
 *
 * SO WHICHEVER OF THE TWO IS INCLUDED SECOND IS SILENTLY SKIPPED. In NASA's build HK and HS are
 * separate CMake targets and no translation unit sees both, so it never surfaces. This port
 * compiles every app into ONE translation unit, which is exactly the configuration that exposes
 * it: with hk_msg.h first, HS_BITS_PER_APPMON_ENABLE is never defined and HS_AppData_t's
 * AppMonEnables array has no bound.
 *
 * The two headers are DISJOINT -- HK's only re-includes three HK headers, HS's defines one
 * constant and includes three HS headers -- so clearing the guard here is exact rather than a
 * compromise. HK's three sub-headers carry their own guards, so a later hk_msg.h that gets
 * skipped loses nothing.
 *
 * This file is the right place for it: vendor/shim stands in for the headers CMake would
 * generate, so the accommodation lives beside the other build-system substitutions and NASA's
 * source is untouched.
 */
#undef DEFAULT_HK_MSG_H
#include "default_hs_msg.h"
