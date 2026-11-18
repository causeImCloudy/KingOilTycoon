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

## Decisions (2026-11-17)
- **Title:** *Standard Oil: An Oil Tycoon Game*.
- **Player count:** 2–4 players on standard maps (1v1, 3-player and 4-player free-for-all).
  Larger expansion maps support 5–6 players. The procedural generator scales the number of
  plots with player count. The Classic map is 2–4 only, and expansion maps cover 5–6.
- **Style:** mid-1900s Texas oil boom (roughly 1930s–1950s): wooden derricks, gushers,
  scrubland, pump jacks, boomtowns, period signage and typefaces, and a warm, dusty palette.
- **Match length:** chosen before each match, like Civ VI's game speed.

| Preset | Target length | Intended use |
|---|---|---|
| Classic | 3–4 hours | Full board-game pace, the faithful ruleset |
| Online | about 1 hour | Default for online matches |
| Blitz | about 30 min | Quick matches |

  Speed knobs, to be tuned in playtests. The game ends when the bank runs dry, so bank
  size is the main lever.
  - Bank size, e.g. Classic $1M, Online ~$500k, Blitz ~$250k.
  - Starting cash.
  - Income per well (card payout multiplier).
  - Wells you may drill per turn.
  - Pipeline threshold and royalty rate.
  - An optional round cap: when it's reached, the highest net worth wins.
  - Turn timer for online play, e.g. none / 90s / 45s.

  Store each preset as a `.tres` Resource in `data/match_speeds/` so tuning means editing
  data, not code.

## Decisions (2026-11-18)
### Multiplayer
- **Player-hosted:** one player hosts the match and the others join them. There's no
  dedicated server.
- **Transport:** Steam, using **GodotSteam** (GDExtension) and its `SteamMultiplayerPeer`
  for lobbies, invites, and connecting through Steam's relay.
- **Host authority:** the host runs the rules engine. Clients send *actions*, and the host
  validates them and broadcasts the results or state. The seeded RNG lives only on the
  host, so clients can't predict hidden oil.
- **Installed:** GodotSteam GDExtension **4.24** (Steamworks SDK 1.65) in `addons/godotsteam/`,
  from the official Codeberg release (MIT license). The Android binaries were removed and
  their lines dropped from `godotsteam.gdextension`; redo this when updating. The
  editor-plugin updater is left disabled. The extension loads without it.
- **Dev:** `steam_appid.txt` (480) is in the project root. Steam must be running to test
  networking. Leave this file out of exported builds.
- **Dev:** use Steam test App ID 480 until there's a real App ID. Also keep a plain
  ENet/LAN peer for testing without Steam, behind the same interface.
- **5–6 players:** required for the first release, not during early development. Design the
  data structures for up to 6 players from day one (the sim's AI tensor capped this at 4).

### Tycoon features
1. **Campaign:** about 20 hand-designed maps, played as a series against AI.
2. **Progression / level-ups:** the campaign earns resources that permanently upgrade
   derricks and pipelines (for example yield, drilling cost, pipeline royalties, fire
   resistance). Upgrades are data-driven `.tres` trees in `data/upgrades/`.
3. **Customization:** cosmetic choices for the player character (tycoon portrait or
   outfit) and buildings (derrick, tool shed, pipeline skins and colours). Built with
   palette swaps and layered sprites so the user's art can be mixed and matched.

Save data lives in `user://`: campaign progress, upgrade levels, unlocked cosmetics,
and the loadout.

- **Upgrades are campaign-only.** Multiplayer and skirmish matches always use the base
  stats, so online play stays balanced.
- **Cosmetics:** a starter set is available from the start, and more unlock through
  campaign maps, milestones and achievements. Cosmetics work in every mode.
- **Campaign:** a light rise-to-tycoon story across the Texas oil fields, with recurring
  AI rival characters (each with their own personality and AI style).

## Decisions (2026-11-18, part 2)
### Campaign currency: Liquid Gold
- One currency called **Liquid Gold**, earned in the campaign and spent on derrick/pipeline
  upgrades. Its icon is a **pixel-art oil droplet** (black with a gold highlight).
- It's separate from in-match dollars ($), which reset every match.

### Drilling interaction
- A **drill rig sits in a side panel** (a toolbar or rig tray). The player drags it out and
  drops it onto an open drill site on a plot they own.
- While dragging, valid sites highlight and invalid ones are dimmed or red. Dropping it
  anywhere invalid sends it back to the tray. Keyboard and gamepad can pick a site and
  confirm instead of dragging.
- Dropping it plays the drilling animation, then the reveal:
  - **Strike:** a gusher, with the depth shown (shallow/medium/deep). A derrick and well
    cap stay on the site.
  - **Dry hole:** dust and a sputter, and the site is capped as dry.
  - The cost is shown at the reveal ($2k/$4k/$6k by depth).
- The rules engine decides the result *before* the animation plays. The animation only
  shows it. Online, the host sends the result and every client plays the same animation.
- Other players see the same animation for every drill, not just their own.
- **Reveal views (both):**
  - The **cut-away pop-up** for your own drills shows a slice of ground with 3 strata. The
    bit goes down and oil bursts out at the layer where it hits, or it passes through all
    three and comes up dry.
  - The **on-board** version is used for other players' drills (and when animations are
    sped up): the derrick animates on the tile, the gusher height shows the depth, and a
    label pops up.
- **Characters (both):** a full-body animated figure stands in the cut-away pop-up next
  to the rig, and a small animated portrait sits on each player's side panel and reacts
  to every event.
- **Art:** the user draws the droplet icon, rig, gusher, cards and character frames.
  Until then the code uses simple placeholder frames with the same names and frame
  counts, so the final sprite sheets can drop straight in.

### Character animations
- Each player's customizable tycoon character shows up during the drill and reacts:
  anticipation while the drill runs, celebration on a strike, frustration on a dry hole.
- The same reactions are used for other big moments (cards, buying land, bankruptcy).
- Reactions are built in layers (body + outfit + hat, etc.) so customization works with
  every animation.

### Card drawing
- Animated: the card slides off the deck, flips over, the effect plays (e.g. money flies
  to the player, Fire Damage flames on the hit wells), then it goes to the discard pile.
- Players can speed up or skip animations (a global speed setting). Blitz matches default
  to fast animations.

### Animation architecture
- The rules engine (`scripts/game/`) emits an **event log** (e.g. `CardDrawn`, `WellDrilled`,
  `RoyaltyPaid`). The presentation layer plays those events in order through an animation
  queue. This keeps the rules headless and testable, lets online clients replay the
  host's events, and makes skipping animations easy.

## Still open
