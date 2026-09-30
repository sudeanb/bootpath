/* Stage narration data — the web walkthrough's source of truth.
   EVERY excerpt here must be a substring of the real stage file; the
   test suite (test/bootpath.test.js) fails the build if code and page
   drift apart. Markers are grepped from the sources AND asserted on the
   QEMU serial output in CI. */

export const STAGES = [
  {
    id: 's1',
    file: 'stages/01-mbr/mbr.S',
    name: '1 · MBR — real mode',
    mode: '16-bit real',
    cpu: 'BIOS handed over: CS:IP = 0000:7C00, DL = boot drive (0x80)',
    memory: 'stage 1 lives at 0x7C00; stage 2 is loaded to 0x7E00 (sectors 2-5, LBA via int 13h AH=42h)',
    registers: 'DS=ES=SS=0000, SP=0x7C00 — segments are flat zeros, stack right below the code',
    explanation: 'BIOS loads the first sector and jumps to it if the 0xAA55 signature is present. We bring up COM1 (115200 8N1), announce real mode, load stage 2 through the BIOS disk API and far-jump to it.',
    markers: ['BP:1-REAL-MODE', 'BP:1-STAGE2-LOADED'],
    excerpt: 'ljmp 0x0000, 0x7E00           /* hand off to stage 2 */',
  },
  {
    id: 's2',
    file: 'stages/02-stage2/stage2.S',
    name: '2 · stage 2 — loading the kernel',
    mode: '16-bit real',
    cpu: 'same CPU, more room: stage 2 is not bound by 510 bytes',
    memory: 'kernel (32 sectors) loaded to 0000:0000 ← ES:BX = 1000h:0000 = 0x10000',
    registers: 'DL still the boot drive; SI walks the message strings (cld guarantees forward lodsb)',
    explanation: 'Stage 2 pulls the future kernel from disk, still through BIOS services. From here on there is no going back to BIOS — once paging is on, interrupt and disk services are ours to build.',
    markers: ['BP:2-STAGE2-REAL', 'BP:2-KERNEL-LOADED'],
    excerpt: 'mov si, offset dap\n    mov ah, 0x42\n    mov dl, 0x80\n    int 0x13',
  },
  {
    id: 's3',
    file: 'stages/02-stage2/stage2.S',
    name: '3 · protected mode (32-bit)',
    mode: '32-bit protected',
    cpu: 'CR0.PE = 1 after `lgdt`; the far jump into selector 0x08 reloads CS and IS the mode switch',
    memory: 'GDT: 0x00 null · 0x08 code32 (base 0, limit 4G) · 0x10 data · 0x18 code64 (L=1, for later)',
    registers: 'DS=ES=SS=0x10, ESP=0x7C00; EAX holds CR0 mid-update',
    explanation: 'Segments become selectors into the GDT instead of real-mode paragraphs. paging is still off; addresses are linear and, with base-0 segments, identical to physical.',
    markers: ['BP:2-STAGE2-REAL', 'BP:2-PROTECTED-32'],
    excerpt: 'mov eax, cr0\n    or eax, 1\n    mov cr0, eax',
  },
  {
    id: 's4',
    file: 'stages/02-stage2/stage2.S',
    name: '4 · paging tables + long mode',
    mode: '32-bit protected → 64-bit long',
    cpu: 'CR4.PAE → CR3 = PML4 → IA32_EFER.LME → CR0.PG; the far jump through the L=1 segment lands in 64-bit',
    memory: 'identity map of the first 4 MiB with 2 MiB pages: PML4 @0x9000 → PDPT @0xA000 → PD @0xB000 (PD[0..1], P|W|PS)',
    registers: 'ECX=0xC0000080 (IA32_EFER) for rdmsr/wrmsr; CR3 = 0x9000',
    explanation: 'Long mode requires paging, so we build a minimal identity map covering the bootloader, stack and kernel, enable PAE, flip EFER.LME and finally CR0.PG. The far jump through the 64-bit code segment is the point of no return.',
    markers: ['BP:2-LONG-MODE-64'],
    excerpt: 'mov ecx, 0xC0000080          /* IA32_EFER */\n    rdmsr\n    or eax, 0x100                /* EFER.LME */\n    wrmsr',
  },
  {
    id: 's5',
    file: 'stages/03-kernel/kernel.c',
    name: '5 · C kernel — long mode',
    mode: '64-bit long',
    cpu: 'C code compiled -m64 -ffreestanding -mno-red-zone; entry.S sets RSP=0x7000 and calls kmain',
    memory: 'kernel linked flat at 0x10000, identity-mapped; stack below the bootloader area',
    registers: 'all 64-bit; noInterrupts forever — `hlt` loop after the banner',
    explanation: 'The first C of the journey. It prints the final markers over the same COM1 port — proof that port I/O semantics survived the whole mode ladder — and parks with hlt.',
    markers: ['BP:3-C-KERNEL-64', 'BP:BOOT-COMPLETE'],
    excerpt: 'void kmain(void) {\n    puts("BP:3-C-KERNEL-64\\r\\n");\n    puts("BP:BOOT-COMPLETE\\r\\n");',
  },
];

export const ALL_MARKERS = STAGES.flatMap((s) => s.markers);
