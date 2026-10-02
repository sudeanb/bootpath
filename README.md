# ⏻ BootPath

**The x86 boot ladder as real, booting code: BIOS → MBR → stage 2 →
protected mode → long mode → a C kernel — every stage announcing itself
over serial, every marker asserted in QEMU on every push.**

[![CI](https://github.com/sudeanb/bootpath/actions/workflows/ci.yml/badge.svg)](https://github.com/sudeanb/bootpath/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

```text
BP:1-REAL-MODE          ← MBR (512 bytes), COM1 up, stage 2 loaded via int 13h
BP:1-STAGE2-LOADED
BP:2-STAGE2-REAL        ← kernel pulled from disk (32 sectors → 0x10000)
BP:2-KERNEL-LOADED
BP:2-LONG-MODE-64       ← GDT → CR0.PE → paging → EFER.LME → CR0.PG
BP:3-C-KERNEL-64        ← first C code, linked flat at 0x10000
BP:BOOT-COMPLETE
```

**[Web walkthrough →](https://sudeanb.github.io/bootpath/)**
(step through the ladder; every code excerpt is test-verified to be a
verbatim substring of the real source)

## What it is

Not a slideshow — a chain of stages that boots. `make boot-test` runs the
image in headless QEMU and **fails the build if any of the seven stage
markers is missing from the serial log**; the same image boots the
playground's narration. Each stage lives in its own folder:

| folder | contents | leaves the CPU in |
|---|---|---|
| `stages/01-mbr/` | 512-byte MBR: serial init, int 13h extended read, `55 AA` | 16-bit real @ `0x7C00` |
| `stages/02-stage2/` | kernel load, GDT, CR0.PE, page tables, CR4.PAE, EFER.LME, CR0.PG | 64-bit long, jumps to `0x10000` |
| `stages/03-kernel/` | 64-bit entry + `kmain()` C | parked in `hlt` |

## Quick start

```bash
git clone https://github.com/sudeanb/bootpath.git
cd bootpath
make compile-check      # local sanity: clang assembles/compiles every stage (no link)
make all                # needs gcc-multilib + ld + objcopy (Linux)
make boot-test          # needs qemu-system-i386 — hard marker assertions
node --test             # structural tests: page/code drift guard
```

CI does all four on every push; the boot test is the real proof.

## How it works

`docs/STAGES.md` narrates the ladder with the exact CPU/memory state at
each border: segment zeroing, the COM1 init sequence, the CHS disk
read (and why the boot drive is saved before any serial output), the
GDT layout (code32 / data / code64 with L=1), the
`CR0.PE` far-jump trick, the three-page identity map (2 MiB pages,
PML4→PDPT→PD at 0x9000/0xA000/0xB000), and the IA32_EFER dance that
turns 32-bit protected into 64-bit long mode.

The educational core is that **the far jump is the mode switch**: CS is
only reloaded by a jump, so each mode change is a jump through a
selector built for the next world. Paging must already be on before the
last of those jumps, which is why the page tables come first.

The web walkthrough (`playground/`) replays the serial log and pairs
each marker with the CPU state and the real source excerpt. The drift
guard test makes that pairing honest: if someone edits a stage file
without updating the page (or vice versa), `node --test` fails.

## Testing

Two layers:

1. **QEMU (CI, hard gate)** — boots `os.img` headless, greps all seven
   `BP:` markers from the serial log, exits non-zero on any miss.
2. **Structural (everywhere)** — every walkthrough excerpt is a
   substring of its source file, every claimed marker is emitted by the
   code it claims, the Makefile asserts exactly the walkthrough's marker
   set, the MBR carries `55 AA` within an exactly-512-byte image, loads stage 2
   with a CHS int 13h read, and stage 2 contains
   the whole ladder (lgdt, CR0.PE, IA32_EFER, CR0.PG, the L=1 GDT
   entry).

## Limitations

- no A20 handling, no ELF loading, no interrupts after `cli` — a boot
  narrative, not a kernel (see the last section of docs/STAGES.md)
- QEMU-only: real hardware would need the A20/PS2 dance and maybe
  different disk geometry
- serial only: no VGA text writer (keeps every stage under its size budget)

## License

[MIT](LICENSE)
