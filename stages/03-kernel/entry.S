; BootPath kernel entry — we arrive here in long mode at 0x10000.
; Sets up a stack shadow and calls the C kernel.

bits 64
global _start
extern kmain
section .text
_start:
    mov rsp, 0x7000              ; stack below the bootloader area
    xor ebp, ebp
    call kmain
.halt:
    hlt                          ; kmain never returns; belt and braces
    jmp .halt
