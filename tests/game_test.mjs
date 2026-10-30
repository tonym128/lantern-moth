// Lantern Moth gameplay tests: node game_test.mjs ../lantern.nes ../levels
// Moths are moved by writing their positions (scripted paths ignore physics), so
// these test the game's rules, not how it feels.
import fs from "fs";
import { boot, B } from "./harness.mjs";
const [rom, LV] = process.argv.slice(2);
const OUT = process.env.OUT || ".";
let fails = 0;
const check = (name, ok, info = "") => { console.log(`${ok ? "PASS" : "FAIL"}  ${name} ${info}`); if (!ok) fails++; };
const PH = ["intro", "play", "dead", "timeup", "clear", "over", "end"];
const T = ["bunny", "bat", "beetle", "wisp", "mimic", "spider", "orb", "bubble", "feather"];
const FILES = JSON.parse(fs.readFileSync(new URL("../gen/stages.json", import.meta.url), "utf8")).stages;   // (from make_assets.py)
const CHARS = "baeosk";

// level geometry from the text maps (enemy order = slot order: by row, then column)
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
const boxRect = (x, y, m = 22) => [[x - m, y - m], [x + m, y - m], [x + m, y + m], [x - m, y + m], [x - m, y - m], [x - m + 24, y - m]];

function startGame(players) {
  const g = boot(rom);
  g.step(30);
  if (players === 2) g.tap(0, B.BUTTON_DOWN);
  g.tap(0, B.BUTTON_START);
  return g;
}
function jumpStage(g, n) {   // (test shortcut) restart into stage n
  g.set("stage", n); g.set("phase", 2); g.set("phase_timer", 1); g.set("phase_timer", 0, 1);
  g.step(3);
  while (PH[g.get("phase")] !== "play") g.step(1, () => g.set("p_invuln", 5));
}
// smooth scripted flight; `each` runs every frame (pinning, invulnerability)
function fly(g, p, pts, sp = 1.6, each) {
  for (const [tx, ty] of pts) for (;;) {
    const c = g.plr(p); const dx = tx - c.x, dy = ty - c.y, d = Math.hypot(dx, dy);
    if (d < 1) break;
    const k = Math.min(1, sp / d);
    g.putp(p, Math.round(c.x + dx * k), Math.round(c.y + dy * k));
    if (each) each(); g.step(1);
  }
}
const closeTrail = (g, p) => { for (let i = 0; i < 64; i++) g.set("trail_cy", g.get("trail_cy", p * 64 + i) & 0x7F, p * 64 + i); };   // (bit 7 = open)
const transit = (g, p, x, y, each) => { const c = g.plr(p); fly(g, p, [[c.x, 24], [x, 24], [x, y]], 3, () => { g.set("p_invuln", 5, p); if (each) each(); }); closeTrail(g, p); };
const wait = (g, n, each) => g.step(n, () => { g.set("p_invuln", 5); g.set("p_invuln", 5, 1); if (each) each(); });
const pin = (g, i, x, y) => () => { g.set("en_x", x, i); g.set("en_y", y, i); };
function chase(g, p, i) {
  for (let t = 0; t < 420 && g.en(i).st !== "none"; t++) {
    const e = g.en(i);
    if (e.st === "firefly") { const c = g.plr(p); const dx = e.x - 4 - c.x, dy = e.y - 4 - c.y, d = Math.hypot(dx, dy) || 1, k = Math.min(1, 2 / d); g.putp(p, Math.round(c.x + dx * k), Math.round(c.y + dy * k)); }
    g.set("p_invuln", 5, p); g.step(1);
  }
}
// circle (ox, oy) at radius r, starting on the side the moth is already on
function circle(g, ox, oy, r, speed = 2.4) {
  // approach without flying over the target: out to the side, level with it, in
  const c = g.plr(0), side = c.x < ox ? -1 : 1, a0 = side < 0 ? Math.PI : 0;
  const outX = Math.max(14, Math.min(226, ox + side * (r + 24)));
  fly(g, 0, [[outX, c.y], [outX, oy], [Math.round(ox + r * Math.cos(a0)), oy]], 3, () => g.set("p_invuln", 5));
  closeTrail(g, 0);
  for (let a = 0; a < 2 * Math.PI + 0.9; a += speed / r) {
    g.putp(0, Math.round(ox + r * Math.cos(a0 + a)), Math.round(oy - r * Math.sin(a0 + a)));
    g.set("p_invuln", 5); g.step(1);
  }
}
// wait (up to n frames) for enemy i to pause in a way it can be looped
function waitFor(g, ok, n = 900) { for (let t = 0; t < n && !ok(); t++) wait(g, 1); return ok(); }
// loop around enemy slot i and collect its firefly. No pinning: ledge walkers
// are looped around their ledge, the others while they pause.
function catchEnemy(g, i, info) {
  const type = info.type;
  if (info.ledge) {
    const pts = ledgeRect(info);
    transit(g, 0, pts[0][0], pts[0][1]);
    fly(g, 0, pts, 1.6, () => g.set("p_invuln", 5));
  } else if (type === "bat") {          // while it dozes, out of startle range
    waitFor(g, () => g.get("en_hop", i) > 170, 1500);
    circle(g, g.en(i).x, g.en(i).y, 26);
  } else if (type === "wisp") {         // while it hovers
    waitFor(g, () => g.get("en_timer", i) > 140);
    circle(g, g.get("en_vx", i), g.get("en_vy", i), 26);
  } else if (type === "spider") {       // while it hangs at the bottom of its thread
    waitFor(g, () => g.get("en_vy", i) === 2 && g.get("en_yf", i) > 140);
    circle(g, g.en(i).x, g.en(i).y, 26);
  }
  wait(g, 10);
  const st = g.en(i).st;
  if (process.env.DBG) console.log("  after loop:", type, st, g.en(i), "moth", g.plr(0));
  wait(g, 50);
  chase(g, 0, i);
  return st;
}

// ============================================================ 1. title -> 1P, all 10 stages
{
  const g = startGame(1);
  check("start: play mode, stage 1 intro", g.get("game_mode") === 1 && g.get("stage") === 0 && PH[g.get("phase")] === "intro");
  wait(g, 125);
  const START = +(process.env.START || 1) - 1;    // (debugging) begin at a later stage
  if (START > 0) jumpStage(g, START);
  const banners = [];
  for (let st = START; st < FILES.length; st++) {
    banners.push(String.fromCharCode(...[...Array(10).keys()].map(i => g.get("banner_buf", i))).replace(/\0.*/, ""));
    while (PH[g.get("phase")] !== "play") wait(g, 1);
    const L = level(st);
    const t0 = g.get("time_sec");
    if (!L.boss) {
      const caught = [];
      for (let i = 0; i < L.en.length; i++) {
        check(`stage ${st + 1}: slot ${i} is a ${L.en[i].type}`, T[g.get("en_type", i)] === L.en[i].type, T[g.get("en_type", i)]);
        caught.push(`${L.en[i].type}:${catchEnemy(g, i, L.en[i])}`);
      }
      wait(g, 3);
      check(`stage ${st + 1}: every enemy looped and collected -> clear`, PH[g.get("phase")] === "clear", `${caught.join(" ")} phase=${PH[g.get("phase")]} left=${g.get("en_left")}`);
    } else {
      const BT = { owl: [1, 4, "orb"], toad: [2, 6, "bubble"], queen: [3, 8, "orb"] }[L.boss];
      const want = BT[2], hp0 = g.get("boss_hp");
      check(`stage ${st + 1}: the ${L.boss} is here (${hp0} hp)`, g.get("boss_type") === BT[0] && hp0 === BT[1]);
      let hits = 0, shook = false;
      // no pinning: wait for the weak point to hover, then circle the spot
      for (let tries = 0; tries < 30 && g.get("boss_hp") > 0; tries++) {
        let slot = -1;
        for (let t = 0; t < 700 && slot < 0; t++) {
          wait(g, 1);
          slot = [0, 1, 2, 3].find(i => g.en(i).st === "walk" && T[g.get("en_type", i)] === want &&
            (want === "orb" ? g.get("en_timer", i) > 120 : g.en(i).y === g.get("en_vy", i) && g.get("en_timer", i) > 130)) ?? -1;
        }
        if (slot < 0) break;
        const ox = want === "orb" ? g.en(slot).x : g.get("en_by", slot), oy = g.en(slot).y;
        const hp = g.get("boss_hp");
        fly(g, 0, [[ox + 26, oy]], 3, () => g.set("p_invuln", 5)); closeTrail(g, 0);
        let a = 0;
        for (let t = 0; t < 120 && a < 7 && g.get("boss_hp") === hp; t++) {
          a += 0.08; g.putp(0, Math.round(ox + 26 * Math.cos(a)), Math.round(oy - 26 * Math.sin(a)));
          g.set("p_invuln", 5); g.step(1);
          if (g.get("scroll_x") !== 0) shook = true;
        }
        wait(g, 10, () => { if (g.get("scroll_x") !== 0) shook = true; });
        if (g.get("boss_hp") < hp) hits++;
      }
      check(`stage ${st + 1}: looping the ${want} hurts the ${L.boss} until it's beaten`, g.get("boss_hp") === 0 && hits >= 1, `${hits} loops (one loop can catch two bubbles) hp ${g.get("boss_hp")}`);
      check(`stage ${st + 1}: hits shake the screen`, shook);
      if (st === 4) g.shot(`${OUT}/owl_beaten.rgb`);
      wait(g, 160);
      check(`stage ${st + 1}: beating the boss clears the stage`, PH[g.get("phase")] === "clear", PH[g.get("phase")]);
    }
    while (PH[g.get("phase")] === "clear") wait(g, 1);
    if (st < FILES.length - 1) check(`stage ${st + 2} starts`, g.get("stage") === st + 1);
  }
  check("every stage's intro banner shows its number", banners.every((b, i) => b === `STAGE ${START + i + 1}`), banners.join(","));
  check("after the last stage: THE END", PH[g.get("phase")] === "end");
  g.step(410);
  check("back to the title with a hi score", g.get("game_mode") === 0 && !/HI 000000/.test(g.hud()), JSON.stringify(g.hud()));
  check("no deaths in the clear run (all scripted moves were invulnerable)", g.get("deaths") === 0, `deaths=${g.get("deaths")}`);
  check("no lag frames in the full run", g.get("lag_frames") === 0, `lag=${g.get("lag_frames")}`);
  check("no tile writes lost to a full vblank queue", g.get("vq_dropped") === 0, `dropped=${g.get("vq_dropped")}`);
  console.log(`   worst logic frame ${g.worst()} cycles (budget ~27000), NMI PPU work ${g.nmiMax()} cycles (vblank ~2270)`);
}

// ============================================================ 2. the new enemies
{ // bat flees
  const g = startGame(1); jumpStage(g, 1); wait(g, 100);
  const i = [0, 1, 2, 3].find(k => T[g.get("en_type", k)] === "bat"), b = g.en(i);
  g.putp(0, b.x + 24, b.y); const d0 = 24;
  wait(g, 40, () => g.putp(0, g.plr(0).x, g.plr(0).y));
  const b2 = g.en(i), d1 = Math.hypot(b2.x - g.plr(0).x, b2.y - g.plr(0).y);
  check("bat: bolts away from a nearby moth", d1 > d0 + 20, `distance ${d0} -> ${d1.toFixed(0)}`);
  g.set("p_invuln", 0); g.putp(0, b2.x, b2.y); g.step(1, () => { g.set("en_x", b2.x, i); g.set("en_y", b2.y, i); });
  check("bat: touching it is deadly", g.plr(0).st === 2);
}
{ // beetle eats trail and breaks it
  const g = startGame(1); jumpStage(g, 2); wait(g, 100);
  const i = [0, 1, 2, 3].find(k => T[g.get("en_type", k)] === "beetle"), b = g.en(i);
  const y = b.y - 10, x0 = b.x - 40;   // a trail line right over its back
  transit(g, 0, x0, y);
  const hold = () => { g.set("en_x", b.x, i); };
  fly(g, 0, [[b.x + 40, y], [b.x + 60, y]], 1.5, () => { g.set("p_invuln", 5); hold(); });
  wait(g, 40, () => { hold(); g.putp(0, b.x + 60, y); });   // it eats a cell every few frames
  const cells = [];
  for (let k = 0; k < 64; k++) if (g.get("trail_age", k) !== 255) cells.push([g.get("trail_cx", k), g.get("trail_cy", k) & 0x7F, g.get("trail_cy", k) >> 7]);
  const bx = b.x >> 3, by = b.y >> 3;
  const near = cells.filter(([cx, cy]) => cx >= bx - 1 && cx <= bx + 2 && cy >= by - 1 && cy <= by + 2);
  const firstOpen = cells.filter(c => c[2]).map(c => c[0]);
  check("beetle: eats the trail dots it touches", near.length === 0, `${near.length} dots left over it`);
  check("beetle: the trail before the bite can't close a loop any more", firstOpen.every(cx => cx > bx), `open dots at columns ${[...new Set(firstOpen)].join(",")} (beetle at ${bx})`);
}
{ // mimic: rock until lit, then deadly
  const g = startGame(1); jumpStage(g, 3); wait(g, 100);
  const i = [0, 1, 2, 3].find(k => T[g.get("en_type", k)] === "mimic"), m = g.en(i);
  wait(g, 30, () => g.putp(0, 232, 200));
  check("mimic: asleep (a rock) while unlit", g.get("en_hop", i) === 0 && m.y === g.en(i).y);
  wait(g, 20, () => g.putp(0, m.x + 18, m.y - 6));
  check("mimic: wakes when a moth's light reaches it", g.get("en_hop", i) > 0, `awake timer ${g.get("en_hop", i)}`);
  g.set("p_invuln", 0); const e = g.en(i); g.putp(0, e.x, e.y); g.step(2);
  check("mimic: awake, it's deadly", g.plr(0).st === 2);
}
{ // mimic asleep is harmless
  const g = startGame(1); jumpStage(g, 3); wait(g, 100);
  const i = [0, 1, 2, 3].find(k => T[g.get("en_type", k)] === "mimic"), m = g.en(i);
  g.set("en_hop", 0, i); g.set("p_invuln", 0); g.putp(0, m.x, m.y + 2); g.set("en_hop", 0, i); g.step(1);
  g.set("en_hop", 0, i);
  check("mimic: asleep, touching it doesn't hurt", g.plr(0).st === 1 || g.get("en_hop", i) > 0);
}
{ // wisp steals light, doesn't kill
  const g = startGame(1); jumpStage(g, 2); wait(g, 100);
  const i = [0, 1, 2, 3].find(k => T[g.get("en_type", k)] === "wisp");
  g.set("p_invuln", 0);
  for (let t = 0; t < 30 && g.get("p_dim") === 0; t++) { const w = g.en(i); g.putp(0, w.x, w.y); g.step(1); }
  check("wisp: touching it steals your light", g.get("p_dim") > 0, `dim ${g.get("p_dim")}`);
  check("wisp: ...but it doesn't kill", g.plr(0).st === 1 && g.get("deaths") === 0);
  const mx = (g.plr(0).x + 8) >> 4;
  g.step(2);
  check("wisp: your light is smaller while dimmed", g.get("cclass", mx) >= 1, `own block class ${g.get("cclass", mx)}`);
}
{ // spider: webs slow you, touching kills
  const g = startGame(1); jumpStage(g, 3); wait(g, 100);
  const i = [0, 1, 2, 3].find(k => T[g.get("en_type", k)] === "spider"), s = g.en(i);
  let fired = false;
  for (let t = 0; t < 320 && g.get("p_slow") === 0; t++) { g.putp(0, s.x, s.y + 50); g.set("p_invuln", 5); g.step(1); if (g.get("web_t")) fired = true; }
  check("spider: spits webs at a moth below it", fired);
  check("spider: a web hit slows the moth", g.get("p_slow") > 0, `slow ${g.get("p_slow")}`);
  g.putp(0, 160, 136); g.hold(0, [B.BUTTON_RIGHT]); let vmax = 0;   // (open air)
  g.step(30, () => { const v = g.m[g.L.plr + 4] | g.m[g.L.plr + 5] << 8; vmax = Math.max(vmax, v > 32767 ? 0 : v); g.set("p_invuln", 5); });
  g.hold(0, []);
  check("spider: webbed moths fly at half speed", vmax <= 0xC0 && vmax > 0, `max vx ${(vmax / 256).toFixed(2)}`);
  g.set("p_invuln", 0); const e = g.en(i); g.putp(0, e.x, e.y); g.step(1);
  check("spider: touching it is deadly", g.plr(0).st === 2);
}

// ============================================================ 3. boss hazards
{ // owl feathers
  const g = startGame(1); jumpStage(g, 4);
  let f = -1;
  for (let t = 0; t < 600 && f < 0; t++) { g.putp(0, 20, 200); g.set("p_invuln", 5); g.step(1); f = [1, 2, 3].find(k => g.en(k).st === "walk" && T[g.get("en_type", k)] === "feather") ?? -1; }
  check("owl: drops feathers while its orb is out", f > 0 && g.en(0).st === "walk" && T[g.get("en_type", 0)] === "orb");
  g.shot(`${OUT}/owl.rgb`);
  g.set("p_invuln", 0); const e = g.en(f); g.putp(0, e.x - 4, e.y - 4); g.step(2);
  check("owl: feathers are deadly", g.plr(0).st === 2);
}
{ // toad tongue
  const g = startGame(1); jumpStage(g, 9);
  let max = 0;
  // hover over its mouth, within reach of the tongue (it reaches 96px up)
  const hover = () => g.putp(0, g.get("mouth_x") - 8, g.get("mouth_y") - 80);
  for (let t = 0; t < 400 && max < 60; t++) { hover(); g.set("p_invuln", 5); g.step(1); max = Math.max(max, g.get("tongue_len")); }
  check("toad: lashes its tongue at a moth overhead", max >= 60, `tongue ${max}px`);
  g.shot(`${OUT}/toad.rgb`);
  g.set("p_invuln", 0); g.step(6, hover);
  check("toad: the tongue is deadly", g.plr(0).st === 2);
}

// ============================================================ 4. earlier rules still hold
{ // 1P death and restart
  const g = startGame(1); wait(g, 130); g.step(100);
  const b = g.en(0); g.putp(0, b.x, b.y); g.step(2);
  check("1P: touching a bunny kills, lives 3 -> 2", g.plr(0).st === 2 && g.plr(0).lives === 2);
  g.step(125);
  check("1P: no moth alive -> stage restarts", PH[g.get("phase")] === "intro" && g.plr(0).st === 1);
}
{ // 2P spirit, revive
  const g = startGame(2); g.step(232);
  const b = g.en(0); g.putp(0, b.x - 6, b.by); g.step(2);
  check("2P: P1 dies and becomes a spirit; play goes on", g.plr(0).st === 2 && PH[g.get("phase")] === "play");
  g.step(60);
  const sp = g.plr(0), bb = g.en(0);
  check("2P: the spirit drifts away from its killer", Math.hypot(sp.x - bb.x, sp.y - bb.y) >= 36);
  transit(g, 1, sp.x, sp.y); g.step(2);
  check("2P: P2 revives P1", g.plr(0).st === 1 && g.plr(0).inv > 100);
}
{ // time up
  const g = startGame(2); g.step(130); g.set("time_sec", 2); g.step(130);
  check("time up: everyone loses a life", PH[g.get("phase")] === "timeup" && g.plr(0).lives === 2 && g.plr(1).lives === 2);
  g.step(160);
  check("time up: restart with 60s", g.get("time_sec") === 60);
}
{ // power-ups
  const g = startGame(1); g.step(130);
  for (let t = 0; t < 900 && g.get("pw_state") !== 2; t++) { g.set("p_invuln", 5); g.step(1); }
  check("power-up appears during the stage", g.get("pw_state") === 2);
  for (let type = 0; type < 4; type++) {
    g.set("pw_type", type); g.set("pw_state", 2); g.set("pw_timer", 40);
    const before = g.plr(0), sc = g.score(0);
    transit(g, 0, g.get("pw_x") - 4, g.get("pw_y") - 4); g.step(2);
    const p = g.plr(0);
    check(`power-up ${["speed", "control", "tail", "life"][type]} applied (+500)`, (type < 3 ? (p.power & (1 << type)) !== 0 : p.lives === before.lives + 1) && g.score(0) === sc + 500);
  }
}
{ // team loop
  const g = startGame(2); g.step(130);
  const b = level(0).en[0], [tl, tr, br, bl] = ledgeRect(b);
  transit(g, 0, tl[0], tl[1], () => g.putp(1, g.plr(1).x, g.plr(1).y));
  const p1 = g.plr(1);
  transit(g, 1, br[0], br[1] + 6, () => { g.putp(0, tl[0], tl[1]); g.set("p_invuln", 5, 0); });
  closeTrail(g, 0);
  const A = [tr, [br[0], br[1] - 2]], Bp = [[bl[0], br[1] + 6], [tl[0], tl[1] + 8]];
  const toward = (p, t) => { const c = g.plr(p); const dx = t[0] - c.x, dy = t[1] - c.y, d = Math.hypot(dx, dy); if (d < 1) return true; const k = Math.min(1, 1.6 / d); g.putp(p, Math.round(c.x + dx * k), Math.round(c.y + dy * k)); return false; };
  let ia = 0, ib = 0;
  for (let t = 0; t < 400 && (ia < 2 || ib < 2); t++) {
    if (ia < 2) { if (toward(0, A[ia])) ia++; } else toward(0, A[1]);
    if (ib < 2) { if (toward(1, Bp[ib])) ib++; } else toward(1, Bp[1]);
    g.set("p_invuln", 5, 0); g.set("p_invuln", 5, 1); g.step(1);
  }
  for (let k = 0; k < 20; k++) { toward(0, A[1]); toward(1, Bp[1]); g.step(1); }
  check("team loop: closed together, bunny cocooned at double value, team power-up", g.get("team_caps") === 1 && g.get("en_value") === 2 && g.get("pw_state") === 2);
}
// ============================================================ 7b. packed maps
{ // every stage unpacks to its text map: rock where '#', back wall (or boss art) where '.'
  const wrong = [];
  for (let st = 0; st < FILES.length; st++) {
    const g = startGame(1);
    g.set("stage", st); g.set("phase", 2); g.set("phase_timer", 1); g.set("phase_timer", 0, 1); g.step(3);
    while (PH[g.get("phase")] !== "intro") g.step(1);
    const { rows } = level(st), v = g.nes.ppu.vramMem;
    for (let y = 2; y < 30; y++) for (let x = 0; x < 32; x++) {
      const t = v[0x2000 + y * 32 + x], ch = rows[y][x];
      if ((ch === "#" && t !== 1 && t !== 2) || (ch === "." && t !== 0 && t !== 5 && !g.m[g.L.solid_tab + t])) wrong.push(`${FILES[st]} ${x},${y}=${t}`);
    }
  }
  check("packed maps: every stage unpacks to its text map", wrong.length === 0, wrong.slice(0, 5).join(" "));
}

{ // the snuffer queen
  const st = FILES.indexOf("boss3");
  const g = startGame(1); jumpStage(g, st);
  const slots = () => [0, 1, 2, 3].map(i => ({ st: g.en(i).st, type: T[g.get("en_type", i)] }));
  let larva = false, open = false;
  for (let t = 0; t < 900 && !larva; t++) {
    wait(g, 1, () => g.putp(0, 120, 200));
    if (g.get("boss_eye") === 1) open = true;
    larva = slots().some((e, i) => (i === 1 || i === 2) && e.st === "walk" && e.type === "beetle");
  }
  check("queen: wakes (her eyes open)", open);
  check("queen: lays snuffer larvae on the ledges", larva, JSON.stringify(slots()));
  for (let i = 0; i < 4; i++) g.set("en_state", 0, i);
  g.set("boss_hp", 4); g.set("boss_state", 0); g.set("boss_timer", 1); g.set("boss_timer", 0, 1);
  let embers = 0;
  for (let t = 0; t < 200 && embers < 2; t++) { wait(g, 1, () => g.putp(0, 120, 200)); embers = slots().filter(e => e.st === "walk" && e.type === "orb").length; }
  check("queen: two embers at once at half health", embers === 2, JSON.stringify(slots()));
}

// ============================================================ 8. quality of life
{ // stage 1 tells you what to do
  const g = startGame(1); g.step(10);
  const line2 = String.fromCharCode(...[...Array(10).keys()].map(i => g.get("banner_buf", 10 + i))).replace(/\0.*/, "");
  check("stage 1 intro: the banner says what to do", line2 === "LOOP ALL!", JSON.stringify(line2));
}
{ // pause
  const g = startGame(1); g.step(130);
  check("pause: game is in play", PH[g.get("phase")] === "play");
  const t0 = g.get("time_sec"), e0 = JSON.stringify([0, 1, 2, 3].map(i => g.en(i))), p0 = g.plr(0);
  g.tap(0, B.BUTTON_START); g.step(120);
  check("pause: Start pauses, the picture goes grey", g.get("paused") === 1 && (g.get("mask_val") & 1) === 1);
  check("pause: nothing moves and the clock stops", g.get("time_sec") === t0 && JSON.stringify([0, 1, 2, 3].map(i => g.en(i))) === e0 && g.plr(0).y === p0.y);
  g.tap(1, B.BUTTON_START); g.step(130);
  check("pause: Start on either pad resumes", g.get("paused") === 0 && (g.get("mask_val") & 1) === 0 && g.get("time_sec") < t0, `time ${t0} -> ${g.get("time_sec")}`);
}
{ // B flaps as well as A
  const g = startGame(1); g.step(130);
  const y0 = g.plr(0).y;
  g.hold(0, [B.BUTTON_B]); g.step(25, () => g.set("p_invuln", 5)); g.hold(0, []);
  check("B flaps too", g.plr(0).y < y0 - 8, `y ${y0} -> ${g.plr(0).y}`);
}
{ // low time: the HUD digits blink
  const g = startGame(1); g.step(130); g.set("time_sec", 8);
  const seen = new Set();
  g.step(130, () => { g.set("p_invuln", 5); seen.add(g.hud().slice(15, 17)); });
  check("low time: the clock digits blink", seen.has("  ") && [...seen].some(t => /\d\d/.test(t)), JSON.stringify([...seen]));
}
{ // every game is seeded differently
  const seeds = [30, 31, 47].map(n => { const g = boot(rom); g.step(n); g.tap(0, B.BUTTON_START); return g.get("seed") + 256 * g.get("seed", 1); });
  check("random seed depends on when Start was pressed", new Set(seeds).size === 3, seeds.join(" "));
}
console.log(fails ? `${fails} FAILED` : "ALL PASSED");
