/* BootPath stage 2 — real mode → protected mode → long mode, all here.
   Linked flat at 0x7E00. Prints BP:2-* markers as it climbs the mode
   ladder, then far-jumps to the pure-64-bit kernel at 0x10000. */

.intel_syntax noprefix
.code16
.globl _start
.text
_start:
    cld
    mov si, msg_real
    call puts16

    /* ---- load the kernel: 32 sectors @ LBA 8 → 1000:0000 (0x10000) ---- */
    mov si, dap
    mov ah, 0x42
    mov dl, 0x80
    int 0x13
    jc disk_fail
    mov si, msg_kernel
    call puts16

    /* ---- GDT: 0x00 null · 0x08 code32 · 0x10 data · 0x18 code64 ---- */
    cli
    lgdt [gdt_desc]

    /* ---- protected mode: set CR0.PE, far jump reloads CS ---- */
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    .att_syntax prefix
    ljmp $0x08, $pm32
    .intel_syntax noprefix

.code32
pm32:
    mov ax, 0x10                 /* data selector */
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x7C00

    mov si, msg_pm
    call puts32

    /* ---- identity-map the first 4 MiB with 2 MiB pages ----
       PML4 @0x9000 → PDPT @0xA000 → PD @0xB000                    */
    mov edi, 0x9000
    xor eax, eax
    mov ecx, 768                 /* clear 3 pages in one 32-bit loop */
clear:
    stosd
    loop clear
    mov dword ptr [0x9000], 0x0000A003   /* PML4[0] → PDPT, P|W */
    mov dword ptr [0xA000], 0x0000B003   /* PDPT[0] → PD,   P|W */
    mov dword ptr [0xB000], 0x00000083   /* PD[0]  → 2 MiB @ 0x000000, P|W|PS */
    mov dword ptr [0xB004], 0x00200083   /* PD[1]  → 2 MiB @ 0x200000, P|W|PS */

    mov eax, 0x9000              /* CR3 = PML4 */
    mov cr3, eax

    mov eax, cr4
    or eax, 0x20                 /* CR4.PAE */
    mov cr4, eax

    mov ecx, 0xC0000080          /* IA32_EFER */
    rdmsr
    or eax, 0x100                /* EFER.LME */
    wrmsr

    mov eax, cr0
    or eax, 0x80000000           /* CR0.PG — paging on → long mode is live */
    mov cr0, eax

    .att_syntax prefix
    ljmp $0x18, $lm64
    .intel_syntax noprefix          /* far jump through the 64-bit code segment */

.intel_syntax noprefix
.code64
lm64:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x7C00

    lea rsi, [rip+msg_lm]
    call puts64

    mov eax, 0x10000             /* hand off to the pure-64-bit kernel */
    jmp rax
1:  hlt
    jmp 1b

/* ---- serial writers, one per mode (same port, different widths) ---- */
.code16
puts16:
    lodsb
    test al, al
    jz 2f
    call putc16
    jmp puts16
2:  ret
putc16:
    push ax
    mov dx, 0x3FD
3:  in al, dx
    test al, 0x20
    jz 3b
    pop ax
    mov dx, 0x3F8
    out dx, al
    ret

.code32
puts32:
    lodsb
    test al, al
    jz 2f
    call putc32
    jmp puts32
2:  ret
putc32:
    push eax
    mov dx, 0x3FD
3:  in al, dx
    test al, 0x20
    jz 3b
    pop eax
    mov dx, 0x3F8
    out dx, al
    ret

.code64
puts64:
    lodsb
    test al, al
    jz 2f
    call putc64
    jmp puts64
2:  ret
putc64:
    push rax
    mov dx, 0x3FD
3:  in al, dx
    test al, 0x20
    jz 3b
    pop rax
    mov dx, 0x3F8
    out dx, al
    ret

.code16
msg_real:    .ascii "BP:2-STAGE2-REAL\r\n"
msg_kernel:  .ascii "BP:2-KERNEL-LOADED\r\n"
msg_diskerr: .ascii "BP:2-DISK-ERROR\r\n"

.align 8
gdt:
    .quad 0                          /* 0x00: null */
    .quad 0x00CF9A000000FFFF         /* 0x08: code32, base 0, limit 4G */
    .quad 0x00CF92000000FFFF         /* 0x10: data,  base 0, limit 4G */
    .quad 0x00209A0000000000         /* 0x18: code64, L=1 */
gdt_desc:
    .word gdt_desc - gdt - 1         /* limit = size - 1 */
    .long gdt                        /* linear base (< 4 GiB, identity-mapped) */

msg_lm: .ascii "BP:2-LONG-MODE-64\r\n"
