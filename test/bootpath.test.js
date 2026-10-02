import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const { STAGES, ALL_MARKERS } = await import('../playground/data/stages.js');

const read = (p) => readFileSync(join(root, p), 'utf8');

test('every stage file referenced by the walkthrough exists', () => {
  for (const s of STAGES) assert.ok(readFileSync(join(root, s.file)), s.file);
});

test('every code excerpt is a verbatim substring of its real source', () => {
  for (const s of STAGES) {
    const src = read(s.file);
    assert.ok(src.includes(s.excerpt), `excerpt of ${s.file} drifted:\n---page---\n${s.excerpt}\n---source has no such block---`);
  }
});

test('every marker is emitted by the real stage code', () => {
  const sources = Object.fromEntries([...new Set(STAGES.map((s) => s.file))].map((f) => [f, read(f)]));
  for (const s of STAGES) {
    for (const marker of s.markers) {
      assert.ok(sources[s.file].includes(marker),
        `marker ${marker} claimed by the page but absent from ${s.file}`);
    }
  }
});

test('mbr has the boot signature and loads stage 2 from sector 2', () => {
  const mbr = read('stages/01-mbr/mbr.S');
  assert.match(mbr, /dw 0xAA55/);                     // signature emitted at 510
  assert.match(mbr, /times 510-\(\$-\$\$\) db 0/);    // pad+sig must total 512 — no double counting
  assert.match(mbr, /mov \[boot_drive\], dl/);        // DL saved before serial init clobbers DX
  assert.match(mbr, /mov ah, 0x02/);                  // CHS read — works on every BIOS
  assert.match(mbr, /mov cl, 2/);                     // sector 2 -> linear 0x7E00
  assert.match(mbr, /jmp 0x0000:0x7E00/);             // handoff
});

test('stage 2 contains the full mode ladder', () => {
  const s2 = read('stages/02-stage2/stage2.S');
  assert.match(s2, /lgdt/);
  assert.match(s2, /or eax, 1\b/);                    // CR0.PE
  assert.match(s2, /0xC0000080/);                     // IA32_EFER
  assert.match(s2, /or eax, 0x100/);                  // EFER.LME
  assert.match(s2, /or eax, 0x80000000/);             // CR0.PG
  assert.match(s2, /mov cr3, eax/);
  assert.match(s2, /0x00209A0000000000/);             // code64 descriptor, L=1
  assert.match(s2, /jmp 0x18:lm64/);                  // the far jump into 64-bit
});

test('kernel emits the final C markers', () => {
  const k = read('stages/03-kernel/kernel.c');
  for (const m of ['BP:3-C-KERNEL-64', 'BP:BOOT-COMPLETE']) assert.ok(k.includes(m));
});

test('Makefile boot-test asserts every walkthrough marker (hard gate)', () => {
  const mk = read('Makefile');
  assert.match(mk, /boot-test:/);
  for (const m of ALL_MARKERS) assert.ok(mk.includes(m), `Makefile must grep ${m}`);
  assert.match(mk, /exit \$\$missing/);
});

test('the walkthrough covers the full marker set the Makefile asserts', () => {
  const mk = read('Makefile');
  const m = mk.match(/MARKERS = ((?:[^\n\\]|\\\n)+)/);
  assert.ok(m, 'MARKERS defined in Makefile');
  const inMakefile = m[1].replace(/\\\n/g, ' ').trim().split(/\s+/);
  assert.deepEqual([...new Set(ALL_MARKERS)].sort(), [...new Set(inMakefile)].sort());
});
