# Boot stages — CPU and memory state at every step

The chain: `stages/01-mbr` (BIOS handoff) → `stages/02-stage2` (real →
protected → long) → `stages/03-kernel` (C, 64-bit). One serial port
(COM1, 115200 8N1) narrates the whole journey; CI boots the image in
QEMU and asserts every `BP:` marker.

## Stage 1 — MBR (real mode, 512 bytes)

| at entry | value |
|---|---|
| CS:IP | `0000:7C00` (BIOS jump target) |
| DL | boot drive (`0x80` = first HDD) |
| state | A20 typically on in QEMU; real hardware would check/enable it |

What it does:

1. zero the segment registers, stack to `0x7C00` (grows down, away from code)
2. init COM1: IER=0, LCR DLAB → divisor 3 (38400), 8N1, FIFO on, MCR DTR|RTS|OUT2
3. print `BP:1-REAL-MODE`
4. int 13h AH=42h (extended read, LBA DAP): 4 sectors from LBA 1 → `0000:7E00`
5. print `BP:1-STAGE2-LOADED`, `ljmp 0x0000, 0x7E00`

Byte 510–511 must be `55 AA` or BIOS refuses the sector.

## Stage 2 — the mode ladder (still one asm file)

**2a. real mode.** Same CPU, no more 510-byte limit. Loads the kernel:
32 sectors from LBA 8 → `1000:0000` (= physical 0x10000). Prints
`BP:2-STAGE2-REAL`, `BP:2-KERNEL-LOADED`. `cli` from here on — no BIOS
calls survive the mode switch.

**2b. protected mode.**

| step | instruction | effect |
|---|---|---|
| GDT | `lgdt [gdt_desc]` | 0x00 null · 0x08 code32 (base 0, limit 4G) · 0x10 data · 0x18 code64 (L=1) |
| PE | `mov cr0` / `or eax, 1` | protection enabled — segments are now selectors |
| reload CS | `ljmp 0x08, pm32` | the mode switch happens IN the jump; after it: DS=ES=SS=0x10, ESP=0x7C00 |

Prints `BP:2-STAGE2-REAL` was before the switch; after it the 32-bit
writer prints nothing new — the next marker comes from deeper.

**2c. long mode.** Paging is mandatory, so build a minimal identity map
first:

```
PML4 @0x9000 : [0] = 0xA000|P|W          → PDPT
PDPT @0xA000 : [0] = 0xB000|P|W          → PD
PD   @0xB000 : [0] = 0x0000000|P|W|PS    → 2 MiB page @ 0x000000
               [1] = 0x2000000|P|W|PS    → 2 MiB page @ 0x200000
```

(768 `stosd`s clear all three pages in one loop.) Then:

| step | register | value |
|---|---|---|
| CR3 | page-table root | 0x9000 |
| CR4.PAE | physical address extension | bit 5 |
| IA32_EFER.LME | `rdmsr/wrmsr` ECX=0xC0000080 | bit 8 |
| CR0.PG | paging on → **long mode active** | bit 31 |
| far jump | `ljmp 0x18, …` through the L=1 segment | executing 64-bit code |

Prints `BP:2-LONG-MODE-64`, then `jmp 0x10000`.

## Stage 3 — C kernel (64-bit)

`entry.S` (linked at 0x10000): `RSP = 0x7000`, call `kmain`.
`kernel.c` — compiled `-m64 -ffreestanding -fno-pic -fno-stack-protector
-mno-red-zone` — talks to the same COM1 port (the `inb/outb` semantics
survived every mode change) and prints `BP:3-C-KERNEL-64` and
`BP:BOOT-COMPLETE`, then parks in a `hlt` loop.

## Serial protocol

Every marker is `BP:<stage>-<event>`. CI greps all seven and fails the
build if any is missing — the web walkthrough's marker list is
generated from the same list, and the structural tests keep page and
code locked together (every excerpt on the page must be a verbatim
substring of the real source file).

## What this deliberately skips

- A20 line handling (QEMU enables it; real hardware needs the port 0x92
  dance — noted, not shipped)
- moving the stack above 1 MiB, ELF loading, memory detection
- interrupts: `cli` after stage 1 begins and never undone — this is a
  one-shot boot narrative, not a kernel
