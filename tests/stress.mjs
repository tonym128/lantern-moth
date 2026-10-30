import fs from "fs";
import { boot, B } from "./harness.mjs";
const COUNT = JSON.parse(fs.readFileSync(new URL("../gen/stages.json", import.meta.url), "utf8")).stages.length;
for (const st of (process.env.ST ? process.env.ST.split(",").map(Number) : [...Array(COUNT).keys()])) {
  const g = boot(process.argv[2]);
  g.step(30); g.tap(0, B.BUTTON_DOWN); g.tap(0, B.BUTTON_START);
  g.set("stage", st); g.set("phase", 2); g.set("phase_timer", 1); g.set("phase_timer", 0, 1); g.step(3);
  while (g.get("phase") !== 1) g.step(1);
  const c0 = g.costs.length; let t = 0;
  g.step(900, () => { t++; const a = t / 40;
    g.putp(0, Math.round(120 + 90 * Math.sin(a)), Math.round(120 + 70 * Math.sin(a * 0.7)));
    g.putp(1, Math.round(120 + 80 * Math.cos(a * 0.9)), Math.round(110 + 60 * Math.cos(a * 1.3)));
    g.set("p_invuln", 5, 0); g.set("p_invuln", 5, 1); g.set("time_sec", 60); });
  const w = Math.max(...g.costs.slice(c0));
  console.log(`stage ${st + 1}: worst ${w} cycles, lag ${g.get("lag_frames")}, loops ${g.get("captures")} (team ${g.get("team_caps")}), heavy ${g.heavy.length}, vq dropped ${g.get("vq_dropped")}`);
  for (const [c, p] of [...g.heavy].sort((a, b) => b[0] - a[0]).slice(0, 2)) console.log("   ", c, p.map(([k, v]) => k + ":" + v).join(" "));
}
