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

## Build status (first playable, 2026-11-18)
Working and tested:
- **Rules engine** (`scripts/game/game_state.gd`): land draft (most expensive start goes
  first), card draw with royalties paid first, production/depletion/fire cards, drilling with
  depth-based costs, land purchase, pipelines (L1-3 at 4/5/6 wells), forced land sale,
  bankruptcy, and game end (last standing / bank empty / round cap). It's deterministic per
  seed, saves to a dict, and has a public snapshot without secrets. 1,459 headless checks pass.
- **Maps:** seeded procedural (18 plots; 24 plots on a 36x24 field for 5-6 players) and an
  original hand-laid Classic map (18 plots, 3 strata slid to 12 notches each).
- **AI:** easy/medium/hard heuristics that only read public state.
- **Match screen:** board, player panels with animated portraits, drag-the-rig drilling
  (or click the rig, then a site), cut-away reveal for local drills, on-board
  gusher/dust for others, animated card draw, fire, pipeline and royalty effects, a turn
  banner, Space/click to speed up, pause menu, autosave plus Continue, and a results screen.
- **Menus:** main menu, skirmish/hot-seat setup (2-6 seats, any mix of human/AI), campaign
  (20 maps, 5 chapters, 5 recurring rivals), Liquid Gold upgrade shop, customization
  (skin, outfit, hat, hat color, derrick paint; unlocks from campaign wins), settings, lobby.
- **Multiplayer:** host-authoritative. ENet LAN was tested with two local instances and their
  states matched. Steam lobby code (`host_with_lobby` / `connect_to_lobby`, invites) is
  written but **not yet tested with the Steam client running**. If a client disconnects
  mid-game, the host turns that seat into an AI. The online turn timer is enforced by the host.

Rule choices made while building (easy to change):
- **Bankruptcy (rule change, 2026-11-19):** if you can't pay a pipeline royalty, you're
  bankrupt and **the pipeline owner takes all your assets**: remaining cash, every plot with its
  wells, and your pipelines. There is no forced sale to the bank (removed). A player with no land
  left is eliminated. In a 1v1 game, bankrupting your rival ends the game.
- **Blowout Fire**: the player **chooses** which wells to cap (1 per 5 owned, rounded up). A new
  `fire` phase waits for `cap` actions; End Turn is blocked until it's done. The AI caps the
  wells whose loss hurts least (not ones feeding pipelines or sitting on a pipeline threshold).
  Fire Crews can save a chosen well. Online, the turn timer picks for you.
- **Drilling** requires enough cash to cover a dry hole, so drilling can't bankrupt you.
- **Pipelines** cost $10k/level (Classic) and pay `level x rate x derricks on the plot piped
  INTO` every turn (was source wells until 2026-11-20; see "Pipeline royalties per derrick"). They must run into a rival's adjacent plot.
- **Drills:** you drill up to exactly the number on the card (no pace bonus).
- **Pace tuning** (`data/match_speeds/`, retuned after the bankruptcy change): Classic bank $4M,
  royalty $300/well/level, cap ~420 turns; Online $900k, $500, cap ~120, 75 s timer;
  Blitz $340k, $700, cap ~72, 40 s timer, cheaper drilling. AIs now keep a cash cushion of
  1-3 turns of royalties. AI-only medians: Classic 4p ~170 turns, Online 4p ~67, Blitz 4p ~43;
  1v1 games are shorter because one bankruptcy ends them. Real time still needs playtests.
- Upgrades are data in `scripts/game/upgrades.gd` (not `.tres` yet).

Known gaps / next steps:
- Steam: test on two machines with Steam running, then get a real App ID.
- Audio files don't exist yet, so the game is silent. `Sfx` plays them once added.
- Pixel font: the default font with antialiasing off is a stand-in (see asset_requests).
- Hot-seat players other than seat 1 get a random look; there's no per-seat customization.
- Gamepad support for picking drill sites isn't done (mouse and keyboard only).
- The AI could use more personality per rival (all rivals share the 3 difficulty levels).

## Campaign world map and readability pass (2026-11-19)
- The campaign select screen is now a **world map**: the player's tycoon stands on a spot
  and walks a dashed trail spot to spot (arrow keys/A-D or click a spot; click the current
  spot or press Enter to play). Spots are numbered: gold with a pennant = won, cream with a
  glowing ring = open, grey with a padlock = locked. Regions run bottom to top (Boomtown,
  East Texas, Permian, Gulf Coast, Big Board). The briefing panel on the right shows the map
  story, pace, reward, rivals and unlocks. Your position is saved in the profile.
- Art: `assets/ui/campaign_map.png` is a generated placeholder; see
  `asset_requests/assets__ui__campaign_map.md`.
- Readability: switched the window stretch mode to `canvas_items` so text renders at full
  resolution. Text sizes went up (small 10, body 12, title 16) with extra line spacing. The
  match screen was re-laid out for the bigger text (two-line player cards, taller status bar).
- Follow-up readability pass: the campaign map has a dim layer over the art, dark sign
  boards for region names and hover titles, bigger spots (r=11), and a solid trail. The
  briefing panel uses larger story text and a big Play button.
- Cards: fixed a bug where the flip animation reset the card's width to 1x while its height
  stayed 2x (tall, skinny cards). Cards are now built at 2x with 12 px text, and the deck
  icon shows the card back at its true 64x88 size.
- Character creation: the first time the player opens the campaign (no `character_created`
  flag and no campaign progress), they go to **Create Your Tycoon** (the Customize screen in
  "create" mode). It has a welcome line, name and look options, Randomize and
  "Start the Campaign". The normal Customize screen is still in the main menu.
- Padding: `UiKit.PAD_X` (6 px) adds left/right padding to panels, buttons, fields, tooltips,
  dropdowns, signs and player cards, because the pixel fonts have no side bearing.
- Match side column widened (the board only uses 360 px), so Draw Card and End Turn sit side
  by side and the card summary is a short form ("$2,000 a well / Land for sale").
- Land for sale is now hard to miss: a "LAND FOR SALE!" banner after the card, pulsing gold
  outlines and gold price tags on every buyable plot, a LAND FOR SALE hint line, and the left
  action button turns into **Buy Land** (it points at the plots).

## Classic mode: original rules (2026-11-20)
- **Main menu "Classic Game" replaces Skirmish / Hot-Seat** (local hot-seat is gone; LAN/Steam
  play is still in Multiplayer). You vs 3 AI rivals on the 18-property Classic map,
  `settings.rules = "original"`, pace preset `data/match_speeds/original.tres`.
- The user has permission from Hasbro. Classic mode copies the 1974 rules booklet's rules and
  numbers, but keeps this game's own board art, plot shapes, names and card wording.
- Numbers from the booklet: $80,000 each; $825,000 total money supply (the box's money pack:
  50 each of $500/$1,000/$5,000/$10,000); property prices $12k,8k,9k,11k,9k,9k,8k,8k,10k,10k,
  9k,8k,8k,10k,8k,8k,12k,12k ($1,000 per hole); drilling $2k shallow, $4k medium, $6k deep or
  dry; pipelines $25,000, need 4/5/6 producing wells on the source property, max 3 (all into one target since 2026-11-20) out of one
  property, no pipe straight back into the property it came from; royalties $1,000/$3,000/
  $5,000 per derrick on the TARGET property for 1/2/3 pipelines from one owner; fire removes
  pipelines the source's wells no longer support; must drill at least one well a turn
  (except Fire); no empty holes = $10,000 penalty; may drill with under $6,000 (can't pay =
  bankrupt); bankrupt land is auctioned by the bank in $500 steps (sold with wells and
  pipelines; unsold land is closed for the game); bank empty = net worth: cash + land +
  $4,000 per producing well + $25,000 per pipeline + whatever the bank owed you.
- Auctions are sealed maximum bids settled like an open auction (winner pays $500 over the
  second bid). Every remaining player bids; the `bid` action is the only one not limited to
  the current player.
- Fire card (from the original card, confirmed by the user): 1-5 wells = cap 1, 6-10 = cap 2,
  11 or more = cap 3. Other modes keep 1 per 5 owned, rounded up, with no maximum.
- Not from the booklet / open questions: players selling
  property to each other by agreement isn't included. The draft tie rule ("next highest goes
  first") is ambiguous; ties go to the earlier pick.
- The "Classic" pace (3-4 h house rules) is now displayed as "Long" to avoid two "Classics".
- AI-only Classic games (4 players): median ~42 turns, nearly always ending by bankruptcy.

## Board decoration kit (2026-11-20)
- Replaces the earlier painted board-art idea (one 360x240 picture per map), which was removed. The
  board is now assembled from a kit of small pieces the user draws, listed in `data/board_kit.json`:
  20 field textures (32x32 seamless), 7 line types (straight 16x8, corner 8x8, crossing 8x8; the game
  rotates them) and 77 props in fixed sizes (multiples of 4, bottom-center anchor, with a ground
  footprint). Requests: `asset_requests/board_kit/` (one file per piece + README with the rules).
- Draw order: field textures, owner tints, lines, flat props, standing props (sorted by y), then
  borders, drill holes, derricks, pipelines. Decoration never covers the game pieces.
- Lines live on cell corners and run along property borders, 8 px wide, so they miss drill sites
  (site centers are 5-6 px from a border). All lines of one kind merge into a graph; corners and
  crossings get their own pieces.
- Props keep drill sites (with a 3 px margin) out of their footprint; big flat props (ponds,
  arenas) may cover a few (footprint area / 300). Footprints stay inside one property, off lines,
  and the whole sprite stays on the board.
- 21 themes (fields, line counts, building groups, scattered props). Each campaign level has a
  `board_theme`; Classic and random maps use `farm`. Saved layouts in `data/boards/`; random maps
  are auto-filled from their seed at runtime (same on host and clients).
- Map Editor (debug builds, main menu): pick a map, paint fields, place/move/flip/delete props,
  draw lines on cell corners, Auto-fill by theme, undo, save. Warns (red ghost) when a prop covers
  a drill site, crosses a border, sits on a line or sticks out of the board.

## General Store (2026-11-20)
- One shop screen replaces the old Upgrades screen. Tabs: Upgrades (campaign-only, same costs as
  before), Outfits, Hats, Hat Colors, Rig Paint. Opened from the main menu ("General Store") and the
  campaign map ("Shop", opens on Upgrades). Picking an item tries it on in the preview; "Buy & Wear"
  pays and equips it; owned items have "Wear".
- Every non-starter cosmetic has a Liquid Gold price (25-150). Campaign rewards stay free with the
  win, and the shop shows which map gives them; items with no campaign source are "Only sold here".
- New shop items: outfits Desert Sand, Mustard Gold, Charcoal, Pinstripe Navy; hats Flat Cap,
  Ten-Gallon, Top Hat (new art layers requested: hat_<style>.png + portrait_hat_<style>.png);
  hat colors Brown, Rodeo Red, Navy, Silver Belly; rig paints Patina Green, Navy Blue, Candy Red,
  Chrome.
- Price guide: the 20 campaign maps pay about 1,900 Liquid Gold in total; all upgrades cost about
  3,400 and all cosmetics about 1,800, so players have to choose.

## Map editor: properties and drill sites (2026-11-20)
- New editor tools (Board row): **Plots** paints cells into a property (drag to paint, "+ New
  property", "Erase (no land)", right-click picks) and **Sites** toggles drill sites per cell.
  Price is always $1,000 per drill site. Property numbers and names are kept; properties left with
  no land are dropped (and renumbered) when saving.
- Saved as `data/boards/<map>.board.json` (width, height, cells, site cells, names, label cells);
  `BoardMap.from_cells()` rebuilds plots, sites, prices and adjacency from it. Matches load it via
  `BoardMap.create(map_type, seed, players, board_id)`; the board is part of the match state, so
  saved games and online clients get the edited board too.
- Save refuses an unplayable board: a property with no drill sites, or fewer properties than the
  map's players. "Check board" also reports properties split into pieces and props that now
  cover drill sites. "Reset board" goes back to the generated board (saving then deletes the
  edited file). Undo covers board edits.

## Rule change: running dry isn't bankruptcy (2026-11-20, user)
- Classic mode (original rules): drilling a hole you can't fully afford takes what you have and
  leaves you at $0, still in the game. The $10,000 no-empty-holes fine works the same way.
- At $0 you can't drill, so the must-drill-a-well rule doesn't apply while you're broke (this also
  stops free drilling at $0). The fine only applies when you truly have no empty holes.
- The only way to go bankrupt is a pipeline royalty you can't pay, collected at the start of your
  next turn (then the bank auctions your land, as before). Other modes already required enough
  cash to drill, so they're unchanged.
- AI-only Classic games went from about 42 to about 82 turns (median, 4 players).

## Homestead: a house on your first property (2026-11-20, user)
- Each player's first property gets their **house**; every property after that gets a small
  **outbuilding** (a shed). Both are cosmetics: Customize has a Homestead page and the General
  Store has a second tab row (Houses, Sheds, Siding, Roofs). Siding and roof colors tint both
  buildings so a player's buildings match. Free starters: Farmhouse, Log Cabin, Tool Shed, Barn,
  three sidings and three roofs; the rest cost 30-200 Liquid Gold.
- Rules side: `players[p].land` lists plots in the order the player got them (bought, won at
  auction, or taken from a bankrupt debtor). `GameState.home_plot(p)` = the first one still owned,
  so if the home plot is lost the house moves to the next oldest plot. Old saves without the list
  fall back to the lowest-numbered plot. Nothing in the rules reads it.
- Board: `scripts/ui/homestead.gd` picks a spot per plot (inside the plot, off drill sites and
  the derricks above them, off the plot's center where pipelines end and Classic lot numbers sit,
  off roads), draws the three art layers, and adds a pennant in the owner's color so player
  buildings stand out from the decoration houses. Decoration props under a building are hidden.
  Buildings rise out of the ground when land is bought.
- Campaign rivals' looks predate the homestead: `Cosmetics.complete_look` fills the missing keys
  from a seed per rival, so each rival always gets the same buildings.
- Art: `assets/sprites/homestead/house_<style>.png` (3 frames of 20x20) and
  `outbuilding_<style>.png` (3 frames of 12x12): walls (greyscale, siding tint), roof (greyscale,
  roof tint), details (full color). Briefs in `asset_requests/assets__sprites__homestead__*.md`.

## Map editor: fields painted freely (2026-11-20, user)
- Field textures are no longer one per property. A layout's `field_grid` stores one field per
  4x4 board pixels (90x60 cells over the 360x240 board) as row strings (`A` = `ids[0]`), so the
  ground can be painted in any shape across property lines.
- Editor Fields tool: square brush S/M/L/XL (4/8/16/32 px, click or drag), Bucket (fills the
  connected patch of one field), Shift+click fills a whole property, right-click picks a field.
- Old layouts (`fields` per property) convert on load; `generate_board_layouts.gd` upgraded all
  22 saved layouts in place, keeping their look. Auto-fill still starts with one field per
  property, then it's all repaintable. Board cells with no land are still drawn as water on top.

## Trading between players (2026-11-20, user)
User asked for trades of money, properties, and the ability to purchase property.
- On your turn (before or after drawing), click a rival's name in the player list to open the
  deal panel over the side column (no Trade button). It has a "Trade with" row, then a YOU GIVE
  and a THEY GIVE section (cash stepper, land, and the land right). Click land on the board: your
  plot = give it (red), theirs = ask for it (green), a for-sale plot = sell this turn's right to
  buy it (gold). Clicking a third player's plot switches the partner. The reply panel mirrors it
  (YOU GET / YOU GIVE, cash after, Accept / Decline).
- "The ability to purchase property" = the land-for-sale right from a production card. It's sold
  for one named plot: the buyer pays the bank the land price on accept, and your right is used up.
  Only the current player holds that right, so only they can sell it.
- Rules (`GameState`): `trade_offer` (current player only), `trade_reply` (only the player
  offered), `trade_cancel` (proposer). One offer waits at a time and play pauses until it's
  answered. No limits (user, 2026-11-20): any number of offers, and any plots, even all of a
  player's land; whoever is left with none is out (the panels warn first). The only checks are
  that you own what you give and can pay. Everything is re-checked on accept. Wells go with the land; pipelines running OUT of a
  traded plot go to the new owner; a pipeline that ends up between one owner's plots is torn out.
- AI (`AIPlayer.trade_reply`/`trade_offer`): values land by price + wells + open sites +
  outgoing pipelines − royalties owed into it; wants a margin that grows with level (hard also
  wants more from whoever is ahead); keeps a royalty cushion; never gives up its last plot. On its turn it makes at most one
  offer: sell a land right it won't use, or (medium/hard, rarely) cash for a neighbor's plot.
- Online: the host validates replies come from the player offered. With a turn timer, an
  unanswered offer counts as declined when the clock runs out.
- Allowed in every mode, Classic included (the 1974 rules don't cover trading).

## Pipeline rules (2026-11-20, user)
- A pipeline needs 4 derricks (producing wells) on the source property. Level 2 needs 5, level 3
  needs 6 (unchanged numbers). The check happens when you build; a later fire doesn't remove
  pipelines in the normal rules (Classic still trims them).
- New: **one pipeline per property.** A property pipes into a single neighboring rival
  property; more pipe from it can only upgrade that same line (`GameState.piped_into`). This
  applies to Classic too (its 2nd/3rd pipelines from a property now go into the same target,
  with the same 4/5/6 thresholds and $1k/$3k/$5k royalties).
- No piping straight back (2026-11-23, user): if a property already pipes into yours, you can't
  pipe from yours back into it. Was Classic-only; now both modes.
- Effect on the sim: Classic pace, 4 players, median game went from 79 to 158 turns (fewer
  pipelines = fewer royalty bankruptcies; more games end on an empty bank). Online and Blitz
  barely moved.

## Pipeline royalties per derrick (2026-11-20, user)
- Normal rules now charge royalties per derrick (producing well) on the property the pipeline
  runs INTO: `level x royalty_per_well x derricks there x owner's royalty mod`. Before, it counted
  the source's wells. Classic already worked this way ($1k/$3k/$5k per derrick on the target).
- Since the source has 4-6 derricks but targets often have 1-3, royalties fell and games ran
  long. User chose to double only Blitz: `royalty_per_well` Long 300, Online 500 (unchanged),
  Blitz 700 -> 1400. Sim medians (2/4/6 players): Long 161/287/336 turns (cap 420), Online
  65/94/107 (cap 120), Blitz 36/40/52. Most games now end when the bank runs dry.
- AI: aims a new pipeline at the neighbor with the most derricks; in a fire it would rather cap
  wells on land a rival pipes into (cuts what it pays).

## Customize & Store merged (2026-11-23, user)
- The General Store and Customize Tycoon are one screen, "Customize & Store" on the main menu
  (`shop_screen.gd`; the old `customize_screen.gd`/`customize.tscn` are gone).
- Tabs: Tycoon row (Character, Skin, Outfits, Hats, Hat Colors, Rig Paint); Homestead row
  (Houses, Sheds, Siding, Roofs) and Campaign: Upgrades. Owned items: Wear/Use; others: Buy.
- The preview column has your name and a Random button (random look from what you own).
- First-time campaign visit opens it as "Create Your Tycoon": a short welcome in the item text
  and a "Start Campaign >" button in the header (in place of the Liquid Gold balance).
- Dropped from the old Customize screen: the animation test buttons and the
  "Unlocked N / M" count.

## Trade panel: partner header and an open land right (2026-11-23, user)
- The partner toggle button is gone: the panel title says "Trading with <name>" (color chip);
  the reply says "Offer from <name>". To trade with someone else, Cancel and click their name
  (or click one of their plots on the board).
- The land right is no longer tied to a plot. The offer has `land_right: true` (a Sell / Remove
  switch on the Right row). On accept the seller's `can_buy` ends and the buyer becomes
  `GameState.right_holder`: play waits while they pick any plot for sale (`buy`, paying the bank)
  or pass (`pass_land`). The pick UI highlights affordable plots with a "Skip, buy nothing"
  button; the turn timer passes for them. AI buyers take the best plot they can afford with a
  cushion, or pass; AI sellers price the right from the best plot's value over its price.

## Draw by clicking the deck (2026-11-23, user)
- No "Draw Card" button: on your turn, before drawing, the deck in the action panel glows and
  is clicked to draw (Space still works). The left button only appears as "Buy Land" when the
  card put land up for sale; otherwise End Turn fills the row.

## Campaign bankruptcy ends the match; plainer main menu (2026-11-23, user)
- Campaign: as soon as the player (every human seat) is out, bankrupt or landless, the match
  ends (`end_reason = "player_out"`, results say "You went bankrupt"); it's a loss with the
  consolation Liquid Gold. Even mid-auction. Other modes play on to the last tycoon.
- The main menu no longer shows the player's tycoon or Liquid Gold balance (the balance is on
  Customize & Store and the campaign map).

## Campaign: fresh oil and cards every attempt (2026-11-23, user)
- Each level's `seed` in `data/campaign.json` used to drive everything, so replays had the same
  oil, deck order, draft order and AI choices. Now `Session.campaign_config` passes it as
  `board_seed` (board layout only: the level's saved decoration fits that board) and `seed: 0`,
  so oil, deck, draft order and AI are random each attempt. `GameState.new_match` uses
  `board_seed` for `BoardMap.create` and falls back to `seed` when it's missing. A saved game
  still resumes exactly (the save keeps the RNG state).

## Pipeline levels pay 1x/3x/5x (2026-11-23, user)
- Normal-mode royalty = `PIPELINE_LEVEL_MULT[level]` (1/3/5) x `royalty_per_well` x derricks on
  the property piped into x owner's royalty mod. Was level x (1/2/3). Example, Online pace,
  8 derricks: L1 $4k, L2 $12k, L3 $20k a round (was $4k/$8k/$12k). Same curve as Classic.
- Sim medians (2/4/6 players): Long 72/233/275, Online 61/87/100 (6p round-cap endings 8 -> 3
  of 12), Blitz 31/40/53.
