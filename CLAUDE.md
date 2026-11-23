# Standard Oil: An Oil Tycoon Game

A 2D pixel-art, turn-based oil-drilling strategy game built in **Godot 4 (GDScript)**.
Inspired by the *genre* of 1970s oil-tycoon board games (e.g. King Oil). It is an
**original game**: original name, art, board layout, cards, and text. Do not copy the
original's name, artwork, board, or card wording.

## Engine / display conventions
- Renderer: GL Compatibility (2D only, runs everywhere).
- Base resolution 640x360, window 1280x720, stretch mode `canvas_items`, aspect `keep`,
  fractional scaling so it fills any window/screen (Settings > Scaling can switch to
  pixel-perfect integer scaling). F11 / Alt+Enter toggles fullscreen.
  Layout coordinates are 640x360, but text renders at full window resolution so it stays
  readable. The fonts (`assets/fonts/`) are 8 px pixel fonts.
- Text sizes go through `UiKit.fs()`: call sites pass a size role (8 small, 10 body, 16 title)
  and `UiKit.SIZE_MAPS` sets the rendered size per Text size setting (Normal 8/12/16,
  Large 12/12/16 = default, Extra large 12/16/20). Keep sizes multiples of 4: the 8 px
  pixel fonts render unevenly (and look like a different font) at 10/14/18. Tune it there, not per label. Smooth text
  (antialiased fonts) is a setting. Cards (`CardView`) are built at 2x their 64x88 art (128x176) with fixed 12 px text; the deck icon shows the art at 1x.
- Default texture filter = Nearest; 2D transforms/vertices snap to pixels.
- Texture import: lossless, no mipmaps.

## Layout
- `assets/` — sprites, tilesets, ui, fonts, audio (music/sfx)
- `scenes/` — `main/` (entry), `board/`, `ui/`
- `scripts/` — `autoload/` (singletons), `game/` (rules/logic), `ui/`
- `data/` — game data as `.tres` Resources or JSON (plots, cards, prices)
- `docs/` — design notes (`docs/design-notes.md`): rules, decisions, known sim bugs
- `REFERENCE/KingOilSim/` — the user's earlier Python rules sim (read-only reference;
  ignored by Godot and git). Port its rules, not its bugs; see design notes.
- `tests/run_tests.gd` — headless rules tests + game-length simulation per speed preset
- `tools/generate_placeholders.gd` — makes placeholder PNGs (never overwrites) and
  `asset_requests/*.md` (one description per needed asset)
- `asset_requests/` — what art/audio the user still needs to make

## Code map
- Rules (pure data, headless): `scripts/game/` — `game_state.gd` (all rules, `apply(action)`
  returns events), `board_map.gd` (procedural + Classic layout), `oil_field.gd` (3 strata),
  `deck.gd`, `ai_player.gd`, `cosmetics.gd`, `upgrades.gd`, `match_speed.gd`.
- Autoloads: `Profile` (save, Liquid Gold, upgrades, cosmetics), `Session` (scene routing,
  match config, save game), `Sfx` (plays audio only if files exist), `Net` (lobby + RPC).
- UI is built in code; each `.tscn` is a root node plus a script. `scripts/ui/match.gd` plays
  rule events through an animation queue; `BoardView` keeps a display copy of the state.
- Customize & Store (`scripts/ui/shop_screen.gd`, `Session.open_shop(tab, back_to)`): one screen
  for your name and look and the General Store. Each tab lists every option of one cosmetic
  category (owned ones: Wear/Use; others: buy with Liquid Gold, `Profile.buy_cosmetic`) plus a
  campaign Upgrades tab (`Upgrades.DEFS`). `Session.customize_mode = "create"` is first-time
  character creation before the campaign. Campaign wins still unlock their reward items for free.
- Homestead (presentation only): a house on each player's first property, a small outbuilding on
  every other (`scripts/ui/homestead.gd`, drawn by `BoardView`). Styles and colors are cosmetics
  (`house`, `outbuilding`, `siding`, `roof`); the rules only keep `players[p].land` (purchase order)
  and `GameState.home_plot(p)`.
- Trading: `trade_offer` / `trade_reply` / `trade_cancel` actions in `game_state.gd` (one offer waits
  at a time; cash, plots, and the current player's right to buy land, after which the buyer picks
  a plot or passes: `right_holder`, `buy` / `pass_land`). UI is the
  deal/reply side panel in `match.gd`, opened by clicking a rival's name (`PlayerPanel.clicked`);
  click land on the board to add it. No offer or land limits. AI in `ai_player.gd`.
- Classic Game mode (menu) = original 1974 rules: `settings.rules = "original"`, branches in
  `game_state.gd` via `original_rules()`; see design notes "Classic mode".
- Data: `data/match_speeds/*.tres` (pace tuning), `data/campaign.json` (20 maps, rivals,
  world-map spot positions `pos` and region sign positions `label_pos`, matched to
  `assets/ui/campaign_map.png`; move them if the map art changes).
  Each map also has `background` (640x360 art in `assets/ui/levels/`, shown on the level's title
  card and dimmed behind the match) and `background_desc` (the art brief the generator copies to
  `asset_requests/`).
  Each map also has `board_theme`, which picks its decoration (see Board decoration below).
- Board decoration (presentation only): `scripts/ui/board_decor.gd` builds the board's look from the
  art kit in `data/board_kit.json` (field textures painted freely on a 4 px grid, not tied to properties, road/rail/creek/fence/tree-line
  pieces along borders, props). Saved layouts: `data/boards/<level_XX|classic>.json`; random maps get
  an auto layout from their seed. Edit layouts in the Map Editor (main menu, debug builds only,
  `scripts/ui/board_editor.gd`).
- Edited boards: the Map Editor's Plots/Sites tools reshape properties and move drill sites; the
  result is saved to `data/boards/<level_XX|classic|classic_1974>.board.json` and
  `BoardMap.create(..., board_id)` loads it for every match on that map (campaign passes
  `board_id`, the Classic layouts use their map type). Without that file the board is generated
  from seed + player count, so changing either changes an unedited level's board and invalidates
  its decoration layout.

## Commands (Godot console exe is on PATH as `godot` after a shell restart)
- Tests: `godot --headless --path . --script res://tests/run_tests.gd`
- Placeholders: `godot --headless --path . --script res://tools/generate_placeholders.gd`
- Board layouts (auto-fill missing ones; `-- --force` rebuilds all, losing editor changes):
  `godot --headless --path . --script res://tools/generate_board_layouts.gd`
- Map editor test (screenshots + place/draw/undo, PASS/FAIL): `godot --path . -- --editortest=<dir>`
- Shop test (buys with button presses, restores the profile, PASS/FAIL): `godot --path . -- --shoptest=<dir>`
- Screenshot tour (opens a window): `godot --path . -- --shots=<dir>`
- Bot-play a match: `godot --path . -- --autoplay`
- Real-click test (board purchase, fire, land for sale, a trade + campaign spot, prints PASS/FAIL): `godot --path . -- --clicktest=<dir>`
- Input rule: the board and campaign map read clicks in `_unhandled_input` using the event's
  position (`make_input_local`). Any full-screen or overlapping Control must use
  `MOUSE_FILTER_IGNORE`, or it silently eats those clicks.
- LAN test: run `-- --net-host=<dir>` and `-- --net-join=<dir>` at the same time
- `--script` mode doesn't load autoloads, so UI scripts can only be checked by running the game.
- `addons/godotsteam/` — vendored GodotSteam GDExtension (don't edit; see design notes
  for the Android-strip step on update). `steam_appid.txt` = 480 (Spacewar) for dev.

## Multiplayer
- Host-authoritative over Steam (`SteamMultiplayerPeer`); keep an ENet peer for local
  testing. Clients send actions; only the host runs rules and the seeded RNG.
- Support up to 6 players in all data structures.
- Campaign upgrades never apply outside the campaign.

## Code style
- GDScript, tabs, static typing (`var x: int`), snake_case files and functions,
  PascalCase `class_name`.
- Keep game rules separate from presentation: rules in `scripts/game/` must not
  depend on nodes or scenes so they can be tested headless.
