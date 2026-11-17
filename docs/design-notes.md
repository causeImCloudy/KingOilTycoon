# Design notes

## Reference genre: King Oil (Milton Bradley, 1974)
Collected as background only; our game uses original content.
- 2–4 players compete to be richest / bankrupt opponents.
- Players buy plots of land (~18 properties, roughly $8k–$12k), start with $80k.
- Hidden oil under the board, randomized each game (original used 3 rotating discs).
- Drill wells on owned land — strong luck element (dry hole vs. strike).
- Producing wells earn income; pipelines become available once a property has
  four producing wells.
- Event cards ("Wildcat" cards in the original) add random effects.
- Turn order started with whoever bought the most expensive land.

Sources: toytales.ca/king-oil-from-milton-bradley-1974/, boardgamegeek.com (King Oil)

## Reference implementation: `REFERENCE/KingOilSim` (user's own Python sim, GPL-3)
The user's earlier Python version of the rules, with the start of a reinforcement-learning AI.
Godot (`.gdignore`) and this repo's git (`.gitignore`) both skip the folder.
Use it as the rules spec to port to GDScript in `scripts/game/`:

| Python file | What it does | Godot target |
|---|---|---|
| `src/RandomizationDisk.py` | 3 layered disks (48 spokes x 7 rings); each disk is turned to one of 12 notches, so 12^3 = 1,728 boards | `oil_field.gd` (seeded RNG) |
| `src/Board.py` | Hit positions for each disk; 18 properties with price, neighbours and (spoke, ring) drill sites; `GetOil` returns (hit, depth) | board data in `data/`, logic in `board.gd` |
| `src/Property.py`, `Pipeline.py` | Drill-site state, pipelines at levels 1–3 (need 4/5/6 producing wells) | `property.gd`, `pipeline.gd` |
| `src/Deck.py`, `Card.py` | 32 cards: 25 production, 5 depletion, 2 fire | `deck.gd` + card `.tres` |
| `src/Bank.py`, `Player.py` | $1M bank, $80k starting cash; net worth = cash + land + $25k per pipeline level | `bank.gd`, `player.gd` |
| `src/KingOilGame.py` | Turn loop: pay pipeline royalties → draw card → collect income → drill 1–N → maybe buy land; also an AI state tensor and action IDs (end/buy/burn/pipeline/drill) | `game_state.gd` (pure data, serializable) |

Rules as the sim encodes them:
- Drilling costs $2k/$4k/$6k for shallow/medium/deep; a dry hole costs $6k.
- Pipeline royalties: $1k/$2k/$3k per level × wells, charged every turn.
- The game ends when only one player is solvent (bankruptcy) or the bank is empty (highest net worth wins).

Sim bugs to fix when porting, not copy:
- `IncreaseTurnTracker` takes the turn modulo `PlayerCount - 1`, so one player gets skipped.
- Depth starts at 0, so a shallow drill costs `2000 * 0 = $0`.
- A dry hole is stored as `True` (counts as oil), and `GetMissedHits` checks `True`.
- Pipeline royalties use the payer's total oil instead of the source property's wells.
- `Player` loops over dict keys as if they were objects; `BankruptPlayer` and `GameOver` call methods that don't exist or compare the wrong things.
- Fire Damage always removes 2 wells; the original scales it with how many wells the player owns.
- The Oil Depletion $500 is announced but never paid.
- The deck uses random.SystemRandom and doesn't save state, so games can't be replayed. The port will use a seeded RNG.

The AI agent uses MaskablePPO (sb3-contrib); checkpoints are in `.idea/shelf/`. The Godot AI will
start as rule-based heuristics. A trained model could be added later through an ONNX/GDExtension
bridge if needed.

## Originality
Reuse the rule system freely: mechanics are fine, and the sim is the user's own code. The
shipped game needs its own name, art, board map, and card text. Don't ship the original
board's disk-hole data or its 18-property layout. Generate or design a new field that uses
the same layered-depth idea.

## Decisions (setup Q&A, 2026-11-13)
- Engine: Godot 4.7.2 standard (GDScript), installed via winget.
- Players: local hot-seat, AI opponents, and online multiplayer. Online comes later,
  but rules/state should be serializable and deterministic (seeded RNG) from day one.
- Scope: an expanded tycoon game built on the core loop (land, hidden oil, drilling,
  pipelines, events), adding systems like upgrades, markets, and a campaign.
- Art: 640x360 base resolution. The user makes the pixel art; code uses placeholders
  until it's ready.

- Board modes: (1) a seeded procedural field and (2) a fixed "Classic" map. Classic is an
  original hand-designed radial map in the board-game style (about 18 plots at $8k–$12k,
  3 rotating depth layers, 12 notches each) with new hole data and plot shapes. It is not
  the 1974 board's layout.
- AI: rule-based GDScript opponents (easy/medium/hard) first.
- Rules: port the sim's core loop faithfully (with its bugs fixed) before adding tycoon systems.

## Still open
- Working title
- Setting/era and tone
- Win condition and game length
- Which expanded systems come first
