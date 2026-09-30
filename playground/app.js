import { STAGES } from './data/stages.js';

/* serial animation — replays the exact marker sequence CI asserts on */
const LINES = [
  'BP:1-REAL-MODE', 'BP:1-STAGE2-LOADED',
  'BP:2-STAGE2-REAL', 'BP:2-KERNEL-LOADED',
  'BP:2-LONG-MODE-64',
  'BP:3-C-KERNEL-64', 'BP:BOOT-COMPLETE',
];
const MARKER_TO_STAGE = [0, 0, 1, 1, 3, 4, 4];

const $ = (id) => document.getElementById(id);
let timer = null;
let current = 0;

function showStage(i) {
  current = i;
  const s = STAGES[i];
  document.querySelectorAll('.step').forEach((el, j) => el.classList.toggle('active', j === i));
  $('stName').textContent = s.name;
  $('stMode').textContent = s.mode;
  $('stCpu').textContent = s.cpu;
  $('stMem').textContent = s.memory;
  $('stReg').textContent = s.registers;
  $('stExpl').textContent = s.explanation;
  $('stCode').textContent = s.excerpt;
}

function boot() {
  clearInterval(timer);
  const pre = $('serial');
  pre.textContent = '';
  let i = 0;
  $('bootState').textContent = 'booting…';
  timer = setInterval(() => {
    if (i >= LINES.length) {
      clearInterval(timer);
      $('bootState').textContent = '✓ 7/7 markers asserted — this is the CI boot-test sequence';
      return;
    }
    pre.textContent += LINES[i] + '\n';
    showStage(MARKER_TO_STAGE[i]);
    i++;
  }, 520);
}

$('stageNav').innerHTML = STAGES.map((s, i) =>
  `<div class="step" data-i="${i}">${s.name}<div class="m">${s.markers.join(' · ')}</div></div>`).join('');
document.querySelectorAll('.step').forEach((el) => el.onclick = () => showStage(Number(el.dataset.i)));

$('boot').onclick = boot;
showStage(0);
boot();
