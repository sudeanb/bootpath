/* BootPath kernel entry — we arrive here in long mode at 0x10000.
   Sets up a stack shadow and calls the C kernel. */

.intel_syntax noprefix
.code64
.globl _start
.text
_start:
    mov rsp, 0x7000              /* stack below the bootloader area */
    xor rbp, rbp
    call kmain
1:  hlt                          /* kmain never returns; belt and braces */
    jmp 1b
