# Changelog

## v1.1

A fix for the web player, and documentation updates. The game ROM is the same as v1.

- **Web player:** the "Click to play" overlay now disappears when you click it. Before, it stayed on top of
  the game, because its `display: flex` style overrode the `hidden` attribute.
- **Web player:** pressing a game key (Enter, the arrows, X and so on) while the game screen has keyboard
  focus now starts play too, so the player works without a mouse.
- **Docs:** the README no longer lists pause on Start and level compression as future ideas; both shipped in
  v1. Its next ideas now reflect the space that's left: music, more caves, a co-op spirit marker.

The release assets are the same set as v1: the ROM, booklet, box art, cartridge label and mock-up, pamphlet,
trailer and the release-kit zip.

## v1

The first release of Lantern Moth: a 1-2 player co-op cave arcade game for NES-compatible consoles and
emulators (NROM-256, mapper 0).

**The game**
- 15 caves: 12 cave stages and bosses on 5, 10 and 15 (the Great Owl, the Cave Toad and the Snuffer Queen)
- 6 creatures, each caught a different way: dust bunny, shadow bat, snuffer beetle, mimic stone, wisp and
  moth-eater spider
- 2-player co-op with team loops, spirits and revives
- Power-ups (speed, control, tail, extra life), carry-over time and a time bonus
- Pause on Start, flap on A or B, and a hint on the first stage

**Downloads**

| File | What it is |
|---|---|
| `lantern-moth.nes` | The cartridge image, for any NES emulator or flash cart |
| `manual.pdf` | The 8-page instruction booklet, 5.5 × 8.5 in |
| `box-front.png`, `box-back.png` | Box art, 5.25 × 7.25 in at 300 dpi |
| `label.png`, `cartridge.png` | The cartridge label (3.5 × 3 in, 300 dpi) and a mock-up |
| `pamphlet.pdf` | A letter-size trifold |
| `trailer.mp4` | A one-minute trailer |
| `lantern-moth-release-kit.zip` | All of the print files (PNG and PDF), the logo, sprite and boss art, and screenshots |

Play it in a browser at https://tonym128.github.io/lantern-moth/.
