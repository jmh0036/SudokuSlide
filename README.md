# PolyominoSudoku

A self-contained Perl distribution that combines two puzzle-generation tools
into a single CLI command:

1. **`Math::Combinatorics::LatinSquares`** — generates a completed NxN
   Quasi Factor Pair latin square satisfying arbitrary rectangular regional
   constraints (like Sudoku boxes, rows, columns, or any RxC tiling).

2. **`Polyomino::Tiler`** — independently tiles the same NxN grid with
   polyominoes (pieces of specified sizes).

The result is a **Polyomino Sudoku puzzle**: the numbered grid is shown
empty, with each polyomino piece displayed outside the grid. The solver
must place every piece back into the grid while obeying all latin-square
rules. Pieces may be rotated in **90° increments** before placement.

---

## Installation

This distribution is self-contained — `Algorithm::DLX` is vendored inside
`lib/` so no CPAN install is required beyond the core Perl modules.

```bash
cd PolyominoSudoku
perl Makefile.PL
make
make test        # 67 tests, all green
make install     # optional: installs bin/polyomino-sudoku to your PATH
```

Or run directly without installing:

```bash
perl -Ilib bin/polyomino-sudoku [options]
```

**Requirements:** Perl 5.10+, `List::Util`, `Getopt::Long`, `Pod::Usage`
(all ship with standard Perl).

---

## Usage

```
polyomino-sudoku --region R C [--region R C ...]
                 (--size K | --pieces S1,S2,... | --must S1,S2 --fill K)
                 [--solution] [--verbose] [--no-random] [--help]
```

### Options

| Flag | Description |
|------|-------------|
| `--region R C` | Add a regional constraint: the NxN grid is partitioned into RxC rectangles, each containing every value exactly once. Repeat for multiple constraints. N = R×C (all regions must agree). |
| `--size K` | Tile uniformly with K-ominoes (K must divide N²). |
| `--pieces S1,S2,...` | Tile with an exact multiset of piece sizes (must sum to N²). |
| `--must S1,S2 --fill K` | Include at least one of each size in `--must`, pad remainder with K-ominoes. |
| `--solution` | Also print the completed solution grid after the puzzle. |
| `--verbose` | Print region box maps and extra information. |
| `--no-random` | Use deterministic (first) solutions instead of random. |
| `--help` | Show full help with examples. |

---

## Examples

### Classic 9×9 Sudoku regions, tiled with triominoes

```bash
polyomino-sudoku --region 1 9 --region 9 1 --region 3 3 --size 3
```

This generates a standard 9×9 Sudoku (rows + columns + 3×3 boxes) and
independently tiles the grid with 27 triominoes. The puzzle shows all 27
numbered pieces outside the grid; you fit them back in.

### 6×6 Pair Latin Square, uniform triominoes

```bash
polyomino-sudoku --region 1 6 --region 6 1 --region 2 3 --region 3 2 --size 3
```

All four tilings (rows, columns, 2×3 boxes, 3×2 boxes) must each contain
every value 1–6 exactly once — a much tighter constraint than standard Sudoku.

### 4×4 full Sudoku, dominoes, show solution

```bash
polyomino-sudoku --region 1 4 --region 4 1 --region 2 2 --size 2 --solution
```

### 9×9, mixed pieces (at least one pentomino and tetromino, fill with triominoes)

```bash
polyomino-sudoku --region 1 9 --region 9 1 --region 3 3 \
                 --must 5,4 --fill 3
```

### Box-only 9×9 constraint (no row/column uniqueness required)

```bash
polyomino-sudoku --region 3 3 --size 3
```

### Deterministic output (useful for testing or reproducibility)

```bash
polyomino-sudoku --region 3 3 --size 3 --no-random
```

---

## Puzzle Rules

1. The NxN grid must be filled with values **1 through N**.
2. Every **regional constraint** must be satisfied: within each RxC
   rectangle of every `--region` tiling, each value appears exactly once.
3. Each **numbered polyomino piece** fits exactly into the cells of the
   grid labelled with that number. Pieces may be **rotated in 90° steps**
   before placement (reflections are not required — only rotations).

---

## Output Format

**Puzzle grid** — shows which piece number occupies each cell:

```
+----+----+----+----+----+----+
|  1 |  1 |  1 |  2 |  3 |  3 |
+----+----+----+----+----+----+
|  4 |  4 |  4 |  2 |  3 |  5 |
...
```

**Piece catalogue** — each piece rendered in its bounding box:

```
Piece 3 (3-omino):
+---+---+
| 3 | 3 |
+---+---+
| 3 |   |
+---+---+
```

**Solution** (with `--solution`) — filled values with piece borders as thin walls:

```
+---+---+---+---+---+---+
| 6   2   1 | 3 | 5   4 |
+---+---+---+   +   +---+
| 5   3   4 | 6 | 2 | 1 |
...
```

Cells belonging to the **same piece** share an open edge (no `|` or `-`
between them); cells from **different pieces** are separated by a border.

---

## Module Structure

```
lib/
  Algorithm/DLX.pm                        # vendored Dancing Links solver
  Math/Combinatorics/LatinSquares.pm      # latin square generator
  Polyomino/Tiler.pm                      # polyomino tiling engine
  Polyomino/Renderer.pm                   # ASCII grid renderer
  Polyomino/Sudoku/Puzzle.pm              # combined puzzle logic (new)
bin/
  polyomino-sudoku                        # CLI entry point (new)
t/
  01-puzzle.t                             # 67-test suite
```

---

## How It Works

1. **Latin square phase** — `Math::Combinatorics::LatinSquares` uses a
   two-phase approach: random pre-filling of half the boxes, then
   Knuth's Algorithm X / Dancing Links to complete the grid. All
   `--region` constraints are enforced simultaneously.

2. **Tiling phase** — `Polyomino::Tiler` independently uses Dancing Links
   to tile the same NxN grid with free polyominoes. All 8 orientations
   (4 rotations × 2 reflections) of each piece are considered during
   solving; the catalogue display normalises each piece to its 0-origin
   rotation as placed.

3. **Puzzle assembly** — `SudokuSlide::Puzzle` combines both results:
   the grid cell values come from step 1; the numbered regions come from
   step 2. The two steps are fully independent — neither influences the
   other — which ensures the piece shapes give no information about the
   values.

---

## Authors

James Hammer — original `Math::Combinatorics::LatinSquares` and
`Polyomino::Tiler` / `Polyomino::Renderer` modules.

Combined into `Polyomino::Sudoku` by James Hammer.

## License

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
