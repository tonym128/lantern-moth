// Lantern Moth web player: jsnes (vendor/jsnes.min.js) running rom/lantern-moth.nes.
// Keyboard (two players), gamepads, touch buttons, sound. The game runs muted in
// attract mode until the visitor clicks to play.
(function () {
  "use strict";
  const root = document.querySelector("[data-player]");
  if (!root || !window.jsnes) return;
  const canvas = root.querySelector("canvas");
  const ctx = canvas.getContext("2d");
  const overlay = root.querySelector(".player-overlay");
  const status = root.querySelector("[data-status]");
  const btnMute = root.querySelector("[data-mute]");
  const btnPause = root.querySelector("[data-pause]");
  const B = jsnes.Controller;
  const FRAME_MS = 1000 / 60.0988;

  // ---------------------------------------------------------------- video
  const image = ctx.createImageData(256, 240);
  const pixels = new Uint32Array(image.data.buffer);
  function onFrame(fb) {
    for (let i = 0; i < 256 * 240; i++) pixels[i] = 0xff000000 | fb[i];
    ctx.putImageData(image, 0, 0);
  }

  // ---------------------------------------------------------------- audio
  const AC = window.AudioContext || window.webkitAudioContext;
  const audio = AC ? new AC() : null;
  const RING = 8192;
  const ringL = new Float32Array(RING), ringR = new Float32Array(RING);
  let wr = 0, rd = 0, muted = true;
  function onAudioSample(l, r) { ringL[wr] = l; ringR[wr] = r; wr = (wr + 1) % RING; }
  if (audio) {
    const node = audio.createScriptProcessor(1024, 0, 2);
    node.onaudioprocess = (e) => {
      const L = e.outputBuffer.getChannelData(0), R = e.outputBuffer.getChannelData(1);
      for (let i = 0; i < L.length; i++) {
        if (rd !== wr && !muted) { L[i] = ringL[rd]; R[i] = ringR[rd]; rd = (rd + 1) % RING; }
        else { L[i] = R[i] = 0; if (rd !== wr) rd = (rd + 1) % RING; }
      }
    };
    node.connect(audio.destination);
  }

  const nes = new jsnes.NES({ onFrame, onAudioSample, sampleRate: audio ? audio.sampleRate : 44100 });

  // ---------------------------------------------------------------- input
  // [player, button] for each key; both layouts at once, so two people can share a keyboard
  const KEYS = {
    ArrowLeft: [1, B.BUTTON_LEFT], ArrowRight: [1, B.BUTTON_RIGHT], ArrowUp: [1, B.BUTTON_UP], ArrowDown: [1, B.BUTTON_DOWN],
    KeyX: [1, B.BUTTON_A], KeyZ: [1, B.BUTTON_B], Enter: [1, B.BUTTON_START], ShiftRight: [1, B.BUTTON_SELECT], ShiftLeft: [1, B.BUTTON_SELECT],
    KeyA: [2, B.BUTTON_LEFT], KeyD: [2, B.BUTTON_RIGHT], KeyW: [2, B.BUTTON_UP], KeyS: [2, B.BUTTON_DOWN],
    KeyG: [2, B.BUTTON_A], KeyF: [2, B.BUTTON_B], KeyT: [2, B.BUTTON_START],
  };
  const held = [new Set(), new Set(), new Set()];          // [unused, player 1, player 2]
  function press(p, b, down) {
    if (down && !held[p].has(b)) { held[p].add(b); nes.buttonDown(p, b); }
    else if (!down && held[p].has(b)) { held[p].delete(b); nes.buttonUp(p, b); }
  }
  let active = false;                                       // keys go to the game only while it's in use
  function key(e, down) {
    const k = KEYS[e.code];
    if (!k || !active) return;
    if (e.target.closest && e.target.closest("input, textarea, select")) return;
    e.preventDefault();
    press(k[0], k[1], down);
  }
  window.addEventListener("keydown", (e) => {
    if (active && e.code === "KeyP") { togglePause(); e.preventDefault(); return; }
    key(e, true);
  });
  window.addEventListener("keyup", (e) => key(e, false));

  // gamepads: the standard mapping (A = 0, B = 1 or 2, select 8, start 9, d-pad 12-15, left stick)
  const padHeld = [{}, {}];
  function pollPads() {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    let n = 0;
    for (const gp of pads) {
      if (!gp || n > 1) continue;
      const p = n + 1, b = (i) => gp.buttons[i] && gp.buttons[i].pressed, ax = gp.axes || [];
      const state = {
        [B.BUTTON_A]: b(0) || b(3), [B.BUTTON_B]: b(1) || b(2), [B.BUTTON_SELECT]: b(8), [B.BUTTON_START]: b(9),
        [B.BUTTON_UP]: b(12) || ax[1] < -0.5, [B.BUTTON_DOWN]: b(13) || ax[1] > 0.5,
        [B.BUTTON_LEFT]: b(14) || ax[0] < -0.5, [B.BUTTON_RIGHT]: b(15) || ax[0] > 0.5,
      };
      for (const btn in state) {
        if (!!state[btn] !== !!padHeld[n][btn]) { press(p, +btn, !!state[btn]); padHeld[n][btn] = !!state[btn]; }
      }
      if (Object.values(state).some(Boolean) && !active) start();
      n++;
    }
  }

  // touch buttons
  root.querySelectorAll("[data-touch]").forEach((el) => {
    const b = B["BUTTON_" + el.dataset.touch];
    const on = (e) => { e.preventDefault(); if (!active) start(); press(1, b, true); el.classList.add("is-down"); };
    const off = (e) => { e.preventDefault(); press(1, b, false); el.classList.remove("is-down"); };
    el.addEventListener("pointerdown", on);
    el.addEventListener("pointerup", off);
    el.addEventListener("pointercancel", off);
    el.addEventListener("pointerleave", off);
  });

  // ---------------------------------------------------------------- running
  let paused = false, last = 0, acc = 0, loaded = false;
  function loop(t) {
    requestAnimationFrame(loop);
    if (!loaded || paused || document.hidden) { last = t; return; }
    pollPads();
    acc += Math.min(t - last, 100);
    last = t;
    let n = 0;
    while (acc >= FRAME_MS && n < 3) { nes.frame(); acc -= FRAME_MS; n++; }
  }
  function setStatus(s) { if (status) status.textContent = s; }
  function setMuted(m) {
    muted = m;
    if (btnMute) { btnMute.setAttribute("aria-pressed", String(m)); btnMute.querySelector("span").textContent = m ? "Sound off" : "Sound on"; }
  }
  function togglePause() {
    paused = !paused;
    if (btnPause) { btnPause.setAttribute("aria-pressed", String(paused)); btnPause.querySelector("span").textContent = paused ? "Resume" : "Pause"; }
    setStatus(paused ? "Paused" : "Playing");
  }
  function start() {
    active = true;
    overlay.hidden = true;
    root.classList.add("is-active");
    if (audio && audio.state !== "running") audio.resume();
    setMuted(false);
    setStatus("Playing");
    canvas.focus({ preventScroll: true });
  }
  overlay.addEventListener("click", start);
  canvas.addEventListener("click", () => { if (!active) start(); });
  document.addEventListener("pointerdown", (e) => {        // clicking elsewhere hands the keyboard back to the page
    const inside = root.contains(e.target);
    if (active && !inside) { active = false; root.classList.remove("is-active"); setStatus("Click the game to play"); }
    else if (!active && inside && overlay.hidden) { active = true; root.classList.add("is-active"); setStatus("Playing"); }
  });
  if (btnMute) btnMute.addEventListener("click", () => { if (audio && audio.state !== "running") audio.resume(); setMuted(!muted); });
  if (btnPause) btnPause.addEventListener("click", togglePause);
  const btnReset = root.querySelector("[data-reset]");
  if (btnReset) btnReset.addEventListener("click", () => { nes.reloadROM(); canvas.focus({ preventScroll: true }); });
  const btnFull = root.querySelector("[data-fullscreen]");
  if (btnFull) btnFull.addEventListener("click", () => {
    const el = root.querySelector(".player-screen");
    if (document.fullscreenElement) document.exitFullscreen();
    else if (el.requestFullscreen) el.requestFullscreen();
  });

  fetch(root.dataset.rom)
    .then((r) => { if (!r.ok) throw new Error(r.status); return r.arrayBuffer(); })
    .then((buf) => {
      const bytes = new Uint8Array(buf);
      let s = "";
      for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
      nes.loadROM(s);
      loaded = true;
      setStatus("Click the game to play");
    })
    .catch(() => setStatus("The ROM couldn't be loaded. Try the download link below."));
  requestAnimationFrame(loop);
})();
