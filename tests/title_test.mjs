import { boot, B } from "./harness.mjs";
const S = process.argv[3];
const g = boot(process.argv[2]);
g.step(10);
console.log("mode", g.get("game_mode"), "fps", g.get("fps"), "hud:", JSON.stringify(g.hud()));
console.log("row21:", g.ntRow(21)); console.log("row23:", g.ntRow(23)); console.log("row24:", g.ntRow(24));
for (const f of [60, 300, 600, 900, 1200, 1500, 2400, 3600]) {
  g.step(f - g.f);
  const p = g.plr(0);
  console.log(`f${f} moth ${p.x},${p.y} wp ${g.get("ai_wp")} logo_lit ${g.get("logo_lit")} caps ${g.get("captures")} lag ${g.get("lag_frames")}`);
  g.shot(`${S}/t${f}.rgb`);
}
console.log("worst cycles", g.worst());
console.log("heavy frames:", g.heavy.length);
for (const [c, p] of g.heavy.slice(0, 4)) console.log(c, p.map(([k, v]) => k + ":" + v).join(" "));
const sorted = [...g.costs].sort((a, b) => a - b); console.log("median", sorted[sorted.length >> 1]);
