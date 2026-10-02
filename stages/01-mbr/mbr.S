; BootPath stage 1 — MBR (512 bytes, 16-bit real mode).
; Loads stage 2 (sectors 2-5) to 0x7E00 via int 13h, printing progress
; over COM1. Order matters: the boot drive in DL is saved BEFORE any
; serial output, because putc clobbers DX.

org 0x7C00
bits 16

_start:
    jmp setup
    db "BOOTPATH"
    times 40 db 0

setup:
    mov [boot_drive], dl        ; FIRST: BIOS passes the drive in DL — the
                                ; COM1 init below clobbers DX (a clobbered
                                ; drive number makes int 13h fail)
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    cld                         ; BIOS may leave DF set — lodsb must go forward

    ; ---- init COM1: 38400 8N1, FIFO ----
    mov dx, 0x3F9               ; IER: disable serial interrupts
    xor al, al
    out dx, al
    mov dx, 0x3FB               ; LCR: DLAB on
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8               ; DLL: divisor 3
    mov al, 3
    out dx, al
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB               ; LCR: 8N1, DLAB off
    mov al, 0x03
    out dx, al
    mov dx, 0x3FA               ; FCR: enable+clear FIFOs
    mov al, 0xC7
    out dx, al
    mov dx, 0x3FC               ; MCR: DTR|RTS|OUT2
    mov al, 0x0B
    out dx, al

    ; ---- load stage 2 FIRST (serial prints would trash DL) ----
    mov bx, 0x7E00              ; ES:BX = 0000:7E00
    mov al, 4                   ; 4 sectors
    mov ch, 0                   ; cylinder 0
    mov cl, 2                   ; sector 2
    mov dh, 0                   ; head 0
    mov dl, [boot_drive]
    mov ah, 0x02                ; CHS read — works on every BIOS
    int 0x13
    jc disk_fail
    cmp al, 4
    jne disk_fail

    mov si, msg_real
    call puts16
    mov si, msg_loaded
    call puts16

    jmp 0x0000:0x7E00           ; hand off to stage 2

disk_fail:
    mov si, msg_diskerr
    call puts16
    cli
.halt:
    hlt
    jmp .halt

puts16:
    lodsb
    test al, al
    jz .done
    call putc
    jmp puts16
.done:
    ret
putc:                           ; AL = char, waits for THR empty (LSR bit 5)
    push ax
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    pop ax
    mov dx, 0x3F8
    out dx, al
    ret

msg_real:    db "BP:1-REAL-MODE", 13, 10, 0
msg_loaded:  db "BP:1-STAGE2-LOADED", 13, 10, 0
msg_diskerr: db "BP:1-DISK-ERROR", 13, 10, 0

boot_drive: db 0

; stage 2 is read via CHS int 13h AH=02 (C0/H0/S2, 4 sectors -> 0000:7E00).
; The padding below MUST total exactly 512 with the signature: BIOS checks
; bytes 510-511 for 55 AA and refuses the sector (silently) otherwise.

times 510-($-$$) db 0
dw 0xAA55                   ; boot signature — BIOS requires it
