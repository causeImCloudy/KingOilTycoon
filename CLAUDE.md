# Standard Oil: An Oil Tycoon Game

A 2D pixel-art, turn-based oil-drilling strategy game built in **Godot 4 (GDScript)**.
Inspired by the *genre* of 1970s oil-tycoon board games (e.g. King Oil). It is an
**original game**: original name, art, board layout, cards, and text. Do not copy the
original's name, artwork, board, or card wording.

## Engine / display conventions
- Renderer: GL Compatibility (2D only, runs everywhere).
- Base resolution 640x360, window 1280x720, stretch mode `viewport`, integer scaling.
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
- `tests/` — tests (GUT addon goes in `addons/` if adopted)
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
