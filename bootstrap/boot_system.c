extern unsigned char _binary_system_bin_start[];
int main(void) {
    typedef void (*f_t)(void);
    ((f_t)_binary_system_bin_start)();
    while(1) __asm__("wfi");
}
