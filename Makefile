# BootPath build
# CI (ubuntu): nasm + gcc-multilib + qemu-system-x86 -> make all && make boot-test
# local (mac): make compile-check (needs nasm; full build + boot test run in CI)

NAS     ?= nasm
CC      ?= gcc
LD      ?= ld
OBJCOPY ?= objcopy
QEMU    ?= qemu-system-x86_64

MARKERS = BP:1-REAL-MODE BP:1-STAGE2-LOADED BP:2-STAGE2-REAL BP:2-KERNEL-LOADED \
          BP:2-PROTECTED-32 BP:2-LONG-MODE-64 BP:3-C-KERNEL-64 BP:BOOT-COMPLETE

all: os.img

mbr.bin: stages/01-mbr/mbr.S
	$(NAS) -f bin $< -o $@
	@test $$(wc -c < $@) -eq 512 || { echo "mbr.bin must be exactly 512 bytes, got $$(wc -c < $@)"; exit 1; }
	@test "$$(od -A n -t x1 -j 510 -N 2 $@ | tr -d ' \n')" = "55aa" || { echo "mbr.bin: boot signature not at 510"; exit 1; }

stage2.bin: stages/02-stage2/stage2.S
	$(NAS) -f bin $< -o $@

kernel.bin: stages/03-kernel/entry.S stages/03-kernel/kernel.c stages/03-kernel/kernel.ld
	$(NAS) -f elf64 stages/03-kernel/entry.S -o entry64.o
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
	timeout 25 $(QEMU) -cpu max -m 64M -drive format=raw,file=os.img \
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

# Local sanity (no emulator needed): assemble everything.
compile-check:
	$(NAS) -f bin stages/01-mbr/mbr.S -o /dev/null
	$(NAS) -f bin stages/02-stage2/stage2.S -o /dev/null
	$(NAS) -f elf64 stages/03-kernel/entry.S -o /dev/null
	@echo "compile-check done (link + boot in CI)"

clean:
	rm -f *.o *.elf *.bin *.img serial.out qemu.int.log

.PHONY: all boot-test compile-check clean
