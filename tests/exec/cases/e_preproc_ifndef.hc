// A #ifndef / #ifdef guard must SKIP its body (including any #define) when the condition is false —
// directives inside a skipped conditional block were being executed, so `#ifndef X` re-#defined X.
#define A 5
#ifndef A
#define A 99
#endif
#ifdef A
#define B 7
#endif
#ifdef NOT_DEFINED
#define C 1000
#else
#define C 40
#endif
#ifndef ALSO_NOT_DEFINED
#define D 300
#endif
I64 main(){ return A*1 + B*10 + C*100 + D*1000; }   // 5 + 70 + 4000 + 300000 = 304075 = 0x4A40B
