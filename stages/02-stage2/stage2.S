; BootPath stage 2 — real mode -> protected mode -> long mode, all here.
; Assembled flat at 0x7E00. Prints BP:2-* markers as it climbs the mode
; ladder, then far-jumps to the pure-64-bit kernel at 0x10000.

org 0x7E00
bits 16

_start:
    cld
    mov si, msg_real
    call puts16

    ; ---- load the kernel: 32 sectors @ LBA 8 -> 1000:0000 (0x10000) ----
    mov ax, 0x1000
    mov es, ax                  ; ES:BX = 1000:0000 = 0x10000
    mov bx, 0x0000
    mov al, 32                  ; 32 sectors
    mov ch, 0                   ; cylinder 0
    mov cl, 9                   ; sector 9 (LBA 8)
    mov dh, 0                   ; head 0
    mov dl, 0x80
    mov ah, 0x02                ; CHS read — works on every BIOS
    int 0x13
    jc disk_fail
    cmp al, 32
    jne disk_fail
    mov si, msg_kernel
    call puts16

    ; ---- GDT: 0x00 null / 0x08 code32 / 0x10 data / 0x18 code64 ----
    cli
    lgdt [gdt_desc]

    ; ---- protected mode: set CR0.PE, far jump reloads CS ----
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:pm32

bits 32
pm32:
    mov ax, 0x10                ; data selector
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x7C00

    mov si, msg_pm              ; flat SI works here: base-0 data segment
    call puts32

    ; ---- identity-map the first 4 MiB with 2 MiB pages ----
    ; PML4 @0x9000 -> PDPT @0xA000 -> PD @0xB000
    ; NOTE: entries are stored through EDI, not as disp32 absolutes —
    ; QEMU's TCG mis-walks the walk when the tables are written with
    ; C7 /5 absolute stores (reproduced on 6.2 and 8.2); register-
    ; indexed stores page-walk correctly on both.
    mov edi, 0x9000
    xor eax, eax
    mov ecx, 3072               ; clear 3 pages = 12 KiB in one 32-bit loop
.clear:
    stosd
    loop .clear
    mov edi, 0x9000
    mov dword [edi], 0x0000A003      ; PML4[0] -> PDPT, P|W
    add edi, 0x1000
    mov dword [edi], 0x0000B003      ; PDPT[0] -> PD,   P|W
    add edi, 0x1000
    mov dword [edi], 0x00000083      ; PD[0]  -> 2 MiB @ 0x000000, P|W|PS
    add edi, 8
    mov dword [edi], 0x00200083      ; PD[1]  -> 2 MiB @ 0x200000, P|W|PS

    mov eax, 0x9000             ; CR3 = PML4
    mov cr3, eax

    mov eax, cr4
    or eax, 0x20                ; CR4.PAE
    mov cr4, eax

    mov ecx, 0xC0000080         ; IA32_EFER
    rdmsr
    or eax, 0x100               ; EFER.LME
    wrmsr

    mov eax, cr0
    or eax, 0x80000000          ; CR0.PG — paging on -> long mode is live
    mov cr0, eax

    jmp 0x18:lm64               ; far jump through the 64-bit code segment

bits 64
lm64:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x7C00

    mov rsi, msg_lm
    call puts64

    mov eax, 0x10000            ; hand off to the pure-64-bit kernel
    jmp rax
.halt:
    hlt
    jmp .halt

; ---- serial writers, one per mode (same port, different widths) ----
bits 16
puts16:
    lodsb
    test al, al
    jz .done
    call putc16
    jmp puts16
.done:
    ret
putc16:
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

bits 32
puts32:
    lodsb
    test al, al
    jz .done
    call putc32
    jmp puts32
.done:
    ret
putc32:
    push eax
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    pop eax
    mov dx, 0x3F8
    out dx, al
    ret

bits 64
puts64:
    lodsb
    test al, al
    jz .done
    call putc64
    jmp puts64
.done:
    ret
putc64:
    push rax
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    pop rax
    mov dx, 0x3F8
    out dx, al
    ret

msg_real:    db "BP:2-STAGE2-REAL", 13, 10, 0
msg_kernel:  db "BP:2-KERNEL-LOADED", 13, 10, 0
msg_pm:      db "BP:2-PROTECTED-32", 13, 10, 0
msg_diskerr: db "BP:2-DISK-ERROR", 13, 10, 0
msg_lm:      db "BP:2-LONG-MODE-64", 13, 10, 0

disk_fail:                      ; still in real mode here
    mov si, msg_diskerr
    call puts16
.halt:
    hlt
    jmp .halt

; the kernel is read via CHS int 13h AH=02 (C0/H0/S9, 32 sectors -> 0x10000)

align 8
gdt:
    dq 0                          ; 0x00: null
    dq 0x00CF9A000000FFFF         ; 0x08: code32, base 0, limit 4G
    dq 0x00CF92000000FFFF         ; 0x10: data,  base 0, limit 4G
    dq 0x00209A0000000000         ; 0x18: code64, L=1
gdt_desc:
    dw gdt_desc - gdt - 1         ; limit = size - 1
    dq gdt                        ; linear base (< 4 GiB, identity-mapped)
