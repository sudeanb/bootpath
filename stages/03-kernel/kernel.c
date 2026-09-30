/* BootPath kernel — the first C code of the journey, now in long mode. */

static inline void outb(unsigned short port, unsigned char val) {
    __asm__ volatile("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline unsigned char inb(unsigned short port) {
    unsigned char v;
    __asm__ volatile("inb %1, %0" : "=a"(v) : "Nd"(port));
    return v;
}

static void putc(char c) {
    while (!(inb(0x3FD) & 0x20)) { /* wait for THR empty */ }
    outb(0x3F8, (unsigned char)c);
}

static void puts(const char *s) {
    while (*s) putc(*s++);
}

void kmain(void) {
    puts("BP:3-C-KERNEL-64\r\n");
    puts("BP:BOOT-COMPLETE\r\n");
    for (;;) __asm__ volatile("hlt");
}
