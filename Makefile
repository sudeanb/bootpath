# BootPath build
# CI (ubuntu): gcc-multilib + qemu-system-x86 → make all && make boot-test
# local (mac): make compile-check (clang syntax-only, objects to /dev/null)

AS      ?= gcc
CC      ?= gcc
LD      ?= ld
OBJCOPY ?= objcopy
QEMU    ?= qemu-system-i386

MARKERS = BP:1-REAL-MODE BP:1-STAGE2-LOADED BP:2-STAGE2-REAL BP:2-KERNEL-LOADED \
          BP:2-PROTECTED-32 BP:2-LONG-MODE-64 BP:3-C-KERNEL-64 BP:BOOT-COMPLETE

all: os.img

mbr.bin: stages/01-mbr/mbr.S stages/01-mbr/mbr.ld
	$(AS) --32 -c stages/01-mbr/mbr.S -o mbr.o
	$(LD) -m elf_i386 -T stages/01-mbr/mbr.ld -o mbr.elf mbr.o
	$(OBJCOPY) -O binary mbr.elf $@
	@test $$(wc -c < $@) -le 512 || { echo "mbr.bin is $$(wc -c < $@) bytes (> 512)"; exit 1; }

stage2.bin: stages/02-stage2/stage2.S stages/02-stage2/stage2.ld
	$(AS) --32 -c stages/02-stage2/stage2.S -o stage2.o
	$(LD) -m elf_i386 -T stages/02-stage2/stage2.ld -o stage2.elf stage2.o
	$(OBJCOPY) -O binary stage2.elf $@

kernel.bin: stages/03-kernel/entry.S stages/03-kernel/kernel.c stages/03-kernel/kernel.ld
	$(AS) --64 -c stages/03-kernel/entry.S -o entry64.o
	$(CC) -m64 -ffreestanding -fno-pic -fno-pie -fno-stack-protector -mno-red-zone \
	      -O2 -Wall -Wextra -c stages/03-kernel/kernel.c -o kernel64.o
	$(LD) -m elf_x86_64 -T stages/03-kernel/kernel.ld -o kernel.elf entry64.o kernel64.o
	$(OBJCOPY) -O binary kernel.elf $@

os.img: mbr.bin stage2.bin kernel.bin
	dd if=/dev/zero of=$@ bs=512 count=64 2>/dev/null
	dd if=mbr.bin    of=$@ bs=512 seek=0 conv=notrunc
	dd if=stage2.bin of=$@ bs=512 seek=1 conv=notrunc
	dd if=kernel.bin of=$@ bs=512 seek=8 conv=notrunc
	@echo "os.img ready"

# Hard boot assertion: every stage marker must appear on serial.
boot-test: os.img
	timeout 25 $(QEMU) -m 64M -drive format=raw,file=os.img \
	  -display none -no-reboot -no-shutdown \
	  -serial file:serial.out \
	  -d int,cpu_reset -D qemu.int.log || true
	@echo "=== serial output ($$(wc -c < serial.out) bytes) ==="; cat serial.out
	@echo "=== qemu exceptions/resets (last 15) ==="; \
	grep -E "v=" qemu.int.log 2>/dev/null | tail -15 || true; \
	grep -E "Triple|RESET" qemu.int.log 2>/dev/null | tail -3 || true
	@missing=0; for m in $(MARKERS); do \
	  grep -q "$$m" serial.out || { echo "MISSING MARKER: $$m"; missing=1; }; done; \
	exit $$missing

# Local sanity (no linker/emulator needed): assemble + compile checks only.
compile-check:
	clang --target=i386-pc-none -c stages/01-mbr/mbr.S -o /dev/null
	clang --target=i386-pc-none -c stages/02-stage2/stage2.S -o /dev/null
	clang --target=x86_64-pc-none -c stages/03-kernel/entry.S -o /dev/null
	clang --target=x86_64-pc-none -ffreestanding -fno-pic -mno-red-zone -O2 -Wall -Wextra -c stages/03-kernel/kernel.c -o /dev/null
	@echo "compile-check done (link + boot in CI)"

clean:
	rm -f *.o *.elf *.bin *.img serial.out

.PHONY: all boot-test compile-check clean
