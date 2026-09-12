I64 Five() { return 5; }
I64 (*g_f[1])() = {&Five};
I64 main() { return (*g_f[0])(); }
