/* BootPath stage 1 — MBR (512 bytes, 16-bit real mode).
   Prints BP:1-REAL-MODE over COM1, loads stage 2 (sectors 2-5) to 0x7E00,
   jumps to it. BP: prefix = BootPath marker, grepped by CI. */

.intel_syntax noprefix
.code16
.globl _start
.text
_start:
    jmp setup
    nop
    .ascii "BOOTPATH"          /* 8 bytes OEM-style filler in the BPB area */
    .space 40                   /* BPB area stays zero — we don't need it */

setup:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    cld                          /* BIOS may leave DF set — lodsb must go forward */

    /* ---- init COM1: 115200 8N1, FIFO ---- */
    mov dx, 0x3F9               /* IER: disable serial interrupts */
    xor al, al
    out dx, al
    mov dx, 0x3FB               /* LCR: DLAB on */
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8               /* DLL: divisor 3 → 38400 baud */
    mov al, 3
    out dx, al
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB               /* LCR: 8N1, DLAB off */
    mov al, 0x03
    out dx, al
    mov dx, 0x3FA               /* FCR: enable+clear FIFOs */
    mov al, 0xC7
    out dx, al
    mov dx, 0x3FC               /* MCR: DTR|RTS|OUT2 */
    mov al, 0x0B
    out dx, al

    /* ---- print BP:1-REAL-MODE ---- */
    mov si, offset msg_real
1:  lodsb
    test al, al
    jz 1f
    call putc
    jmp 1b
1:
    /* ---- load stage 2: sectors 2-5 (CHS 0/0/2, 4 sectors) → 0000:7E00 ---- */
    mov si, offset dap
    mov ah, 0x42                /* extended read (LBA) — deterministic, no CHS math */
    mov dl, 0x80                /* BIOS passes the boot drive in DL */
    int 0x13
    jc disk_fail
    mov si, offset msg_loaded
2:  lodsb
    test al, al
    jz 3f
    call putc
    jmp 2b
3:
    ljmp 0x0000, 0x7E00           /* hand off to stage 2 */

disk_fail:
    mov si, offset msg_diskerr
4:  lodsb
    test al, al
    jz 5f
    call putc
    jmp 4b
5:  hlt
    jmp 5b

putc:                           /* AL = char, waits for THR empty (LSR bit 5) */
    push ax
    mov dx, 0x3FD
6:  in al, dx
    test al, 0x20
    jz 6b
    pop ax
    mov dx, 0x3F8
    out dx, al
    ret

msg_real:    .ascii "BP:1-REAL-MODE\r\n"
msg_loaded:  .ascii "BP:1-STAGE2-LOADED\r\n"
msg_diskerr: .ascii "BP:1-DISK-ERROR\r\n"

dap:                            /* disk address packet: read 4 sectors @ LBA 1 → 0000:7E00 */
    .byte 0x10, 0
    .word 4                     /* sector count */
    .word 0x00E0                /* offset 0x7E00 */
    .word 0x0000                /* segment */
    .quad 1                     /* starting LBA */

    .space 510 - (. - _start) - 2
    .word 0xAA55                /* boot signature — BIOS requires it */
