# Oil Tycoon (working title)

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

## Code style
- GDScript, tabs, static typing (`var x: int`), snake_case files and functions,
  PascalCase `class_name`.
- Keep game rules separate from presentation: rules in `scripts/game/` must not
  depend on nodes or scenes so they can be tested headless.
