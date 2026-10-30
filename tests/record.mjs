// Records a whole game, title to THE END, as a video with sound:
//   node record.mjs ../lantern.nes ../levels <1|2> out.mp4
// The moths are flown by script (as in game_test.mjs) and can't die: kill_player
// is patched to return at once, so nothing flickers from invulnerability.
// Needs ffmpeg. SNAP=frame,frame,... saves those frames as PNGs into SNAPDIR
// (default .) as well; OUT "-" skips the video.
import fs from "fs";
import os from "os";
import path from "path";
import zlib from "zlib";
import { spawn, execFileSync } from "child_process";
import { boot, B } from "./harness.mjs";

const [rom, LV, PLAYERS, OUT] = process.argv.slice(2);
const players = +PLAYERS;
const FILES = JSON.parse(fs.readFileSync(new URL("../gen/stages.json", import.meta.url), "utf8")).stages;
const T = ["bunny", "bat", "beetle", "wisp", "mimic", "spider", "orb", "bubble", "feather"];
const PH = ["intro", "play", "dead", "timeup", "clear", "over", "end"];
const CHARS = "baeosk";
const FPS = 60.0988, RATE = 48000, SCALE = 3;
const SNAP = new Set((process.env.SNAP || "").split(",").filter(Boolean).map(Number)), SNAPDIR = process.env.SNAPDIR || ".";
const VIDEO = OUT !== "-";

// png: 256x240 RGB frame -> PNG file
function png(rgb, file) {
  const raw = Buffer.alloc((256 * 3 + 1) * 240);
  for (let y = 0; y < 240; y++) rgb.copy(raw, y * (256 * 3 + 1) + 1, y * 256 * 3, (y + 1) * 256 * 3);
  const crcT = [...Array(256).keys()].map(n => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = (b) => { let c = 0xFFFFFFFF; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4), c = Buffer.alloc(4), td = Buffer.concat([Buffer.from(t), d]); l.writeUInt32BE(d.length); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(256, 0); ih.writeUInt32BE(240, 4); ih[8] = 8; ih[9] = 2;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ih), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}

// ------------------------------------------------------------------ capture
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "lantern-video-"));
const fifo = path.join(tmp, "video.fifo"), silent = path.join(tmp, "silent.mkv"), wav = path.join(tmp, "audio.f32");
if (VIDEO) execFileSync("mkfifo", [fifo]);
const enc = VIDEO && spawn("ffmpeg", ["-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "256x240", "-r", String(FPS),
  "-i", fifo, "-vf", `scale=${256 * SCALE}:${240 * SCALE}:flags=neighbor`, "-c:v", "libx264", "-preset", "medium", "-crf", "16",
  "-pix_fmt", "yuv420p", silent], { stdio: "inherit" });
const vfd = VIDEO ? fs.openSync(fifo, "w") : -1;
const audio = [];
const g = boot(rom, { onAudio: (l, r) => audio.push((l + r) / 2) });
g.m[g.L.kill_player] = 0x60;                       // RTS: the scripted moths can't die
const set0 = g.set;
g.set = (n, v, i) => { if (n !== "p_invuln") set0(n, v, i); };   // (no invulnerability flicker)
let frames = 0;
g.step = (n = 1, fn) => {
  for (let k = 0; k < n; k++) { if (fn) fn(g.f); g.nes.frame(); g.f++;
    const rgb = g.frameRGB();
    if (VIDEO) fs.writeSync(vfd, rgb);
    if (SNAP.has(frames)) png(rgb, path.join(SNAPDIR, `frame${frames}.png`));
    frames++;
  }
};

// ------------------------------------------------------------------ flying (from game_test.mjs, for either moth)
function level(n) {
  const rows = fs.readFileSync(`${LV}/${FILES[n]}.txt`, "utf8").trim().split("\n");
  const solid = (x, y) => "#L".includes(rows[y][x]);
  const en = [];
  rows.forEach((r, y) => [...r].forEach((c, x) => { if (CHARS.includes(c)) en.push({ x, y, type: T[CHARS.indexOf(c)] }); }));
  en.sort((a, b) => a.y - b.y || a.x - b.x);
  for (const e of en) if ("bes".includes(CHARS[T.indexOf(e.type)])) {
    const ly = e.y + 2; let s = e.x; while (solid(s - 1, ly)) s--; let t = e.x + 1; while (solid(t + 1, ly)) t++;
    Object.assign(e, { s, e: t, ledge: true });
  }
  const boss = rows.some(r => r.includes("O")) ? "owl" : rows.some(r => r.includes("T")) ? "toad" : rows.some(r => r.includes("Q")) ? "queen" : null;
  return { rows, en, boss };
}
const ledgeRect = (b) => { const top = b.y * 8 - 24, bot = b.y * 8 + 22, left = b.s * 8 - 18, right = b.e * 8 + 10;
  return [[left, top], [right, top], [right, bot], [left, bot], [left, top], [left + 24, top]]; };
function fly(p, pts, sp = 1.6, each) {
  for (const [tx, ty] of pts) for (let t = 0; t < 2000; t++) {
    const c = g.plr(p); const dx = tx - c.x, dy = ty - c.y, d = Math.hypot(dx, dy);
    if (d < 1) break;
    const k = Math.min(1, sp / d);
    g.putp(p, Math.round(c.x + dx * k), Math.round(c.y + dy * k));
    if (each) each();
    g.step(1);
  }
}
const closeTrail = (p) => { for (let i = 0; i < 64; i++) g.set("trail_cy", g.get("trail_cy", p * 64 + i) & 0x7F, p * 64 + i); };
const transit = (p, x, y, each) => { const c = g.plr(p); fly(p, [[c.x, 24], [x, 24], [x, y]], 3, each); closeTrail(p); };
function chase(p, i) {
  for (let t = 0; t < 420 && g.en(i).st !== "none"; t++) {
    const e = g.en(i);
    if (e.st === "firefly") { const c = g.plr(p); const dx = e.x - 4 - c.x, dy = e.y - 4 - c.y, d = Math.hypot(dx, dy) || 1, k = Math.min(1, 2 / d); g.putp(p, Math.round(c.x + dx * k), Math.round(c.y + dy * k)); }
    g.step(1);
  }
}
function circle(p, ox, oy, r, speed = 2.4) {
  const c = g.plr(p), side = c.x < ox ? -1 : 1, a0 = side < 0 ? Math.PI : 0;
  const outX = Math.max(14, Math.min(226, ox + side * (r + 24)));
  fly(p, [[outX, c.y], [outX, oy], [Math.round(ox + r * Math.cos(a0)), oy]], 3);
  closeTrail(p);
  for (let a = 0; a < 2 * Math.PI + 0.9; a += speed / r) {
    g.putp(p, Math.round(ox + r * Math.cos(a0 + a)), Math.round(oy - r * Math.sin(a0 + a)));
    g.step(1);
  }
}
function waitFor(ok, n = 900) { for (let t = 0; t < n && !ok(); t++) g.step(1); return ok(); }
function catchEnemy(p, i, info) {
  if (info.ledge) {
    const pts = ledgeRect(info);
    transit(p, pts[0][0], pts[0][1]);
    fly(p, pts, 1.6);
  } else if (info.type === "bat") {
    waitFor(() => g.get("en_hop", i) > 170, 1500);
    circle(p, g.en(i).x, g.en(i).y, 26);
  } else if (info.type === "wisp") {
    waitFor(() => g.get("en_timer", i) > 140);
    circle(p, g.get("en_vx", i), g.get("en_vy", i), 26);
  } else if (info.type === "spider") {
    waitFor(() => g.get("en_vy", i) === 2 && g.get("en_yf", i) > 140);
    circle(p, g.en(i).x, g.en(i).y, 26);
  }
  g.step(60);
  chase(p, i);
}
// both moths close one loop round the first bunny's ledge together
function teamLoop(b) {
  const [tl, tr, br, bl] = ledgeRect(b);
  const p1 = g.plr(1);
  transit(0, tl[0], tl[1], () => g.putp(1, p1.x, p1.y));      // the other moth waits where it is
  transit(1, br[0], br[1] + 6, () => g.putp(0, tl[0], tl[1]));
  closeTrail(0);
  const A = [tr, [br[0], br[1] - 2]], Bp = [[bl[0], br[1] + 6], [tl[0], tl[1] + 8]];
  const toward = (p, t) => { const c = g.plr(p); const dx = t[0] - c.x, dy = t[1] - c.y, d = Math.hypot(dx, dy); if (d < 1) return true; const k = Math.min(1, 1.6 / d); g.putp(p, Math.round(c.x + dx * k), Math.round(c.y + dy * k)); return false; };
  let ia = 0, ib = 0;
  for (let t = 0; t < 400 && (ia < 2 || ib < 2); t++) {
    if (ia < 2) { if (toward(0, A[ia])) ia++; } else toward(0, A[1]);
    if (ib < 2) { if (toward(1, Bp[ib])) ib++; } else toward(1, Bp[1]);
    g.step(1);
  }
  for (let k = 0; k < 20; k++) { toward(0, A[1]); toward(1, Bp[1]); g.step(1); }
  g.step(60);
  chase(0, 0);
}

// ------------------------------------------------------------------ the game
g.step(240);                                       // the title's attract mode
if (players === 2) g.tap(0, B.BUTTON_DOWN);
g.step(30);
g.tap(0, B.BUTTON_START);
for (let st = 0; st < FILES.length; st++) {
  waitFor(() => PH[g.get("phase")] === "play", 600);
  const L = level(st);
  if (!L.boss) {
    for (let i = 0; i < L.en.length; i++) {
      if (g.en(i).st === "none") continue;          // (already caught by a team loop)
      if (players === 2 && st === 0 && i === 0 && L.en[0].type === "bunny") { teamLoop(L.en[0]); continue; }
      catchEnemy(players === 2 ? i % 2 : 0, i, L.en[i]);
    }
  } else {
    const want = L.boss === "toad" ? "bubble" : "orb";
    for (let tries = 0; tries < 40 && g.get("boss_hp") > 0; tries++) {
      const p = players === 2 ? tries % 2 : 0;
      let slot = -1;
      for (let t = 0; t < 700 && slot < 0; t++) {
        g.step(1);
        slot = [0, 1, 2, 3].find(i => g.en(i).st === "walk" && T[g.get("en_type", i)] === want &&
          (want === "orb" ? g.get("en_timer", i) > 120 : g.en(i).y === g.get("en_vy", i) && g.get("en_timer", i) > 130)) ?? -1;
      }
      if (slot < 0) break;
      const ox = want === "orb" ? g.en(slot).x : g.get("en_by", slot), oy = g.en(slot).y, hp = g.get("boss_hp");
      fly(p, [[ox + 26, oy]], 3); closeTrail(p);
      let a = 0;
      for (let t = 0; t < 120 && a < 7 && g.get("boss_hp") === hp; t++) {
        a += 0.08; g.putp(p, Math.round(ox + 26 * Math.cos(a)), Math.round(oy - 26 * Math.sin(a))); g.step(1);
      }
      g.step(10);
    }
  }
  waitFor(() => PH[g.get("phase")] === "clear", 400);
  console.log(`stage ${st + 1}: ${PH[g.get("phase")]} at ${(frames / FPS / 60).toFixed(1)} min`);
  if (PH[g.get("phase")] !== "clear") { console.error(`stage ${st + 1} wasn't cleared: stopping`); process.exit(1); }
  waitFor(() => PH[g.get("phase")] !== "clear", 1200);
}
waitFor(() => g.get("game_mode") === 0, 600);      // THE END, back to the title
g.step(240);

// ------------------------------------------------------------------ encode
if (!VIDEO) { fs.rmSync(tmp, { recursive: true }); console.log(`${frames} frames, ${SNAP.size} snapshots`); process.exit(0); }
fs.closeSync(vfd);
await new Promise(res => enc.on("exit", res));
fs.writeFileSync(wav, Buffer.from(new Float32Array(audio).buffer));
execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-i", silent, "-f", "f32le", "-ar", String(RATE), "-ac", "1", "-i", wav,
  "-c:v", "copy", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", OUT]);
fs.rmSync(tmp, { recursive: true });
console.log(`${OUT}: ${frames} frames, ${(frames / FPS / 60).toFixed(1)} min, score ${g.score(0)}${players === 2 ? " / " + g.score(1) : ""}`);
