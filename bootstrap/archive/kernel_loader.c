/* Minimal kernel loader for HolyC kernel */

typedef void (*kernel_main_t)(void);

// Load the HolyC kernel binary and jump to it
int main(void) {
    // The HolyC kernel binary will be linked at a known address
    extern unsigned char _binary_templeos_kernel_bin_start[];
    
    kernel_main_t kernel = (kernel_main_t)_binary_templeos_kernel_bin_start;
    
    // Jump to HolyC kernel
    kernel();
    
    // Should never return
    while (1) __asm__ volatile ("wfi");
    return 0;
}


