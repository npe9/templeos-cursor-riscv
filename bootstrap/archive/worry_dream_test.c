#include <stdint.h>
extern unsigned char _binary_worry_dream_runtime_bin_start[];
int main(void) {
    typedef int64_t (*f_t)(void);
    // Find Main() - it's the last function
    int64_t result = ((f_t)(_binary_worry_dream_runtime_bin_start + 0x1850))();
    while (1) __asm__ volatile ("wfi");
}
