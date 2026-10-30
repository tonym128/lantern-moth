// Test harness for Lantern Moth
import fs from "fs";
import { NES, Controller } from "jsnes";
export const B = Controller;

const HEAVY = +(process.env.HEAVY || 26000);   // frames above this many cycles get a profile

export function boot(rom) {
  const bytes = fs.readFileSync(rom);
  const L = Object.fromEntries(fs.readFileSync(rom.replace(/\.nes$/, ".lbl"), "utf8").trim().split("\n")
    .map(l => { const [, a, n] = l.split(" "); return [n.slice(1), parseInt(a, 16)]; }));
  let last = null;
  const nes = new NES({ onFrame: (fb) => { last = fb; }, onAudioSample: () => {} });
  nes.loadROM(bytes.toString("binary"));
  const m = nes.cpu.mem;
  // cycle profiler: main_loop entry -> wait_frame entry
  const cpu = nes.cpu; let total = 0, start = -1; const costs = [];
  const orig = cpu.emulate.bind(cpu);
  let nmiStart = -1, nmiMax = 0;
  const wf = L.wait_frame, ml = L.main_loop, nmi = L.nmi, skip = L["nmi"];
  const labs = Object.entries(L).filter(([n, a]) => a >= 0x8000).sort((a, b) => a[1] - b[1]);
  const routineOf = (pc) => { let lo = 0, hi = labs.length - 1, r = "?"; while (lo <= hi) { const mid = (lo + hi) >> 1; if (labs[mid][1] <= pc) { r = labs[mid][0]; lo = mid + 1; } else hi = mid - 1; } return r; };
  let prof = {}, f0 = 0; const heavy = [];
  cpu.emulate = () => {
    const pc = cpu.REG_PC + 1;
    if (pc === ml) { start = total; prof = {}; f0 = m[L.frame]; }
    // (an iteration that spans an NMI turned the screen off to load a level)
    if (pc === wf && start >= 0 && m[L.frame] !== f0) start = -1;
    if (pc === wf && start >= 0) { const c = total - start; costs.push(c); if (c > HEAVY) heavy.push([c, Object.entries(prof).sort((a, b) => b[1] - a[1]).slice(0, 8)]); start = -1; }
    if (pc === L.nmi) nmiStart = total;
    if (pc === L.nmi_ppu_end && nmiStart >= 0) { nmiMax = Math.max(nmiMax, total - nmiStart); nmiStart = -1; }
    const c = orig(); total += c; if (start >= 0) { const r = routineOf(pc); prof[r] = (prof[r] || 0) + c; } return c;
  };
  const held = [new Set(), new Set()];
  const g = {
    nes, m, L, f: 0, costs, heavy,
    get: (n, i = 0) => m[L[n] + i],
    set: (n, v, i = 0) => { m[L[n] + i] = v; },
    plr: (p) => ({ x: m[L.plr + p * 16 + 1], y: m[L.plr + p * 16 + 3], st: m[L.p_state + p], lives: m[L.p_lives + p],
                   power: m[L.p_power + p], inv: m[L.p_invuln + p] }),
    putp(p, x, y) { const b = L.plr + p * 16; m[b + 1] = x; m[b + 3] = y; for (const o of [0, 2, 4, 5, 6, 7]) m[b + o] = 0; },
    en: (i) => ({ st: ["none", "walk", "wake", "cocoon", "firefly"][m[L.en_state + i]], x: m[L.en_x + i], y: m[L.en_y + i], by: m[L.en_by + i], t: m[L.en_timer + i] }),
    score: (p) => +[...Array(6).keys()].map(i => m[L.p_score + p * 6 + i]).join(""),
    hud: () => { const v = nes.ppu.vramMem; let s = ""; for (let i = 0; i < 32; i++) s += String.fromCharCode(v[0x2020 + i]); return s; },
    ntRow: (r) => { const v = nes.ppu.vramMem; let s = ""; for (let i = 0; i < 32; i++) { const t = v[0x2000 + r * 32 + i]; s += t >= 0x20 && t < 0x60 ? String.fromCharCode(t) : "."; } return s; },
    hold(p, btns) {
      for (const b of [B.BUTTON_A, B.BUTTON_B, B.BUTTON_SELECT, B.BUTTON_START, B.BUTTON_UP, B.BUTTON_DOWN, B.BUTTON_LEFT, B.BUTTON_RIGHT]) {
        if (btns.includes(b) && !held[p].has(b)) { nes.buttonDown(p + 1, b); held[p].add(b); }
        else if (!btns.includes(b) && held[p].has(b)) { nes.buttonUp(p + 1, b); held[p].delete(b); }
      }
    },
    tap(p, b, n = 2) { g.hold(p, [b]); g.step(n); g.hold(p, []); g.step(2); },
    step(n = 1, fn) { for (let i = 0; i < n; i++) { if (fn) fn(g.f); nes.frame(); g.f++; } },
    frameRGB() { const buf = Buffer.alloc(256 * 240 * 3); for (let i = 0; i < 256 * 240; i++) { const v = last[i]; buf[i*3] = v & 255; buf[i*3+1] = (v >> 8) & 255; buf[i*3+2] = (v >> 16) & 255; } return buf; },
    shot(path) { fs.writeFileSync(path, g.frameRGB()); },
    worst: () => Math.max(...costs.slice(5)),
    nmiMax: () => nmiMax,
  };
  return g;
}
