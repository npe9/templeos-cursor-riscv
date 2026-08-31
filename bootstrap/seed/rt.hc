// rt.hc -- intentionally empty of Man `// Name --` blocks.
//
// holy_rt.h symbols (GetRAX, InU8, Yield, RV*, Hash*, …) are for the AOT/exec harness
// import table, NOT the UART REPL. The REPL does zero RuntimeRegister; callable math/bits
// live in math.hc (HolyC). Do not re-add Man pages here that imply callability.
