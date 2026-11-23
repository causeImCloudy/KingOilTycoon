# Font fixes: letters to redraw

**Files:** `assets/fonts/main_font.ttf` (Lease Office) and `assets/fonts/title_font.ttf` (Spindletop Slab)
**Status:** both fonts work, but some letters are hard to read in game. Redraw the letters
below, then save over the same files. No code changes are needed.

`font_current_glyphs.png` (in this folder) shows the main font's current letters at 3x.

## Why these letters fail

Both fonts are drawn on a pixel grid:

- 8 px em; capitals are **7 px tall**, lowercase x-height is **5 px**, descenders are 2 px.
- Letters are **5 px wide** with 1 px spacing.

At that width there's only room for **1-pixel gaps**. Where a letter fills a gap with a
solid block (to suggest a diagonal or a middle stroke), the letter turns into a blob. That
gets worse when the game scales text to non-whole sizes (e.g. 2.5x on a 1600x900 window).
In game, "Animations" reads as "Aninations", "Music" as "Husic" and "F11" as "Fii".

**Rule of thumb:** every stroke in these letters should be 1 px wide, with at least
1 px of empty space between strokes. No 2x2 filled blocks inside a letter.

## Letters to redraw

Grids are drawn top to bottom. `#` = ink, `.` = empty. The suggested shapes are clear, common
pixel-font forms; adjust the style to taste, but keep the gaps.

### Must fix (unreadable now)

**m** (lowercase, 5 wide x 5 tall). Now: the top is a solid block with no counters, so it
reads as a blob or an "n".
```
####.
#.#.#
#.#.#
#.#.#
#.#.#
```

**M** (capital, 5 x 7). Now: an "H" with a filled block in the middle.
```
#...#
##.##
#.#.#
#.#.#
#...#
#...#
#...#
```

**W** (capital, 5 x 7). Now: a "U" with a filled bottom middle.
```
#...#
#...#
#...#
#.#.#
#.#.#
##.##
#...#
```

**w** (lowercase, 5 x 5). Now: same blob as W.
```
#...#
#...#
#.#.#
#.#.#
.#.#.
```

**1** (5 x 7). Now: a 1 px flag and a narrow foot, so it reads as "i" or "l". Give it a clear
flag and a full-width foot:
```
..#..
.##..
#.#..
..#..
..#..
..#..
#####
```

### Should fix (heavy, but readable)

**v** (lowercase, 5 x 5). Now: a 2x2 block at the bottom point.
```
#...#
#...#
#...#
.#.#.
..#..
```

**V** (capital, 5 x 7)
```
#...#
#...#
#...#
#...#
.#.#.
.#.#.
..#..
```

**N** (capital, 5 x 7). Now: a thick blob on the diagonal near the top.
```
#...#
##..#
##..#
#.#.#
#..##
#..##
#...#
```

**r** (lowercase, 5 x 5). Now: the join is a solid block.
```
#.##.
##..#
#....
#....
#....
```

### Worth checking

- **Q**, **4**, **x / X**: the solid centers work at 2x and above, but get muddy at 2.5x. If
  you redraw anything else, open these up the same way.
- **i / l / 1 / I**: make sure all four look different: i has a dot, l has a foot or curl,
  1 has a flag and a full foot, I has top and bottom bars.

## Title font (Spindletop Slab)

It has the **same shapes** for m, M, W, w, v, V, N and r, so the same fixes apply. It can keep
its slab serifs, as long as the gaps inside each letter stay open.

## Checking your fix

1. Save over `assets/fonts/main_font.ttf` / `title_font.ttf` (same file names).
2. Open Godot once so it re-imports the fonts (keep Antialiasing = None in the import settings).
3. Run the game and check Settings ("Animations", "Music", "F11") and the campaign briefing.
   Try both Text size "Large" and "Extra large", and windowed as well as fullscreen.
