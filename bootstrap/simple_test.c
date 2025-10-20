void uart_putc(char c) { *(volatile char*)0x10000000 = c; }
void puts(const char *s) { while(*s) { if(*s=='\n') uart_putc('\r'); uart_putc(*s++); } }

int main() {
    puts("Test!\n");
    return 0;
}
