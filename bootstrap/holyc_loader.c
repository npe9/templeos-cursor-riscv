/* Loader for HolyC binary */

extern unsigned char _binary_mini_compiler_bin_start[];
extern unsigned char _binary_mini_compiler_bin_end[];

int main(void) {
    // The HolyC binary contains a Main() function at the start
    // Just jump to it
    typedef void (*main_func_t)(void);
    main_func_t holyc_main = (main_func_t)_binary_mini_compiler_bin_start;
    
    holyc_main();
    
    while (1) __asm__ volatile ("wfi");
    return 0;
}

