/* Shim for the header a stock cFS build GENERATES.
 *
 * modules/resourceid/mission_build.cmake:11-24 picks one of option_inc/*.h -- EDS if
 * CFE_EDS_ENABLED, else STRICT if MISSION_RESOURCEID_MODE is "STRICT", else SIMPLE -- and
 * generate_config_includefile writes a one-line wrapper under this name that #includes it.
 * In cmake/sample_defs the mode is derived from the OMIT_DEPRECATED environment variable
 * (global_build_options.cmake:19-27), so a stock non-EDS build is SIMPLE unless that is set.
 * cFE's own CI runs both ways. SIMPLE is what we take, matching the stock default.
 *
 * ONE DIFFERENCE FROM STOCK, so nobody has to rediscover it: the generated wrapper uses the
 * option header's ABSOLUTE path, because option_inc is never on the include path in a stock
 * build (modules/resourceid/CMakeLists.txt:17 adds only fsw/inc). This unqualified include
 * works only because our gate puts option_inc on the include path itself. To mirror stock, or
 * to switch to STRICT, the sanctioned route is a <MISSION_DEFS>/config/cfe_resourceid_typedef.h
 * override rather than editing this file.
 */
#include "cfe_resourceid_simple.h"
