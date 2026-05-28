# SudokuSlide

A self-contained Perl distribution that generates **Polyomino Sudoku puzzles**:
latin-square grids whose cells are partitioned into polyomino-shaped pieces.

---

## What is a SudokuSlide Puzzle?

A SudokuSlide puzzle is an NxN grid with two independent layers of structure:

1. **Latin square constraints** — the grid must be filled with values 1..N such
   that within every specified rectangular region, each value appears exactly
   once. You choose which regions to enforce (rows, columns, boxes, or any
   combination of RxC tilings whose product equals N).

2. **Polyomino tiling** — the same grid is independently partitioned into
   connected polyomino-shaped pieces of specified sizes. The piece shapes and
   their contained values are shown to the solver, but not their positions.

To solve the puzzle, place every piece into the grid (rotating in 90° increments
as needed) so that all latin-square constraints are satisfied simultaneously.
The latin-square constraints together with the piece shapes uniquely determine
the placement.

---

## Requirements

- **Perl v5.40.0 or later** (uses native `class` OO and `use feature 'signatures'`)
- **[Algorithm::DLX](https://metacpan.org/pod/Algorithm::DLX)** from CPAN

Standard Perl modules used (ship with any Perl installation):
`List::Util`, `Scalar::Util`, `Carp`, `Getopt::Long`, `Pod::Usage`

---

## Installation

```bash
cpanm Algorithm::DLX      # install the one CPAN dependency first

cd SudokuSlide
perl Makefile.PL
make
make test
make install              # optional: installs bin/polyomino-sudoku to your PATH
```

Or run directly without installing:

```bash
perl -Ilib bin/polyomino-sudoku [options]
```

---

## Usage

```
polyomino-sudoku --region R C [--region R C ...]
                 (--size K | --pieces S1,S2,... | --must S1,S2 --fill K)
                 [--answer] [--verbose] [--no-random] [--help]
```

### Options

| Flag | Description |
|------|-------------|
| `--region R C` | Add a regional constraint: partition the NxN grid into RxC rectangles, each containing every value 1..N exactly once. Repeat for multiple simultaneous constraints. N = R×C (all regions must agree on N). |
| `--size K` | Tile uniformly with K-ominoes. K must divide N². |
| `--pieces S1,S2,...` | Tile with an exact multiset of piece sizes (must sum to N²). |
| `--must S1,S2 --fill K` | Include at least the listed sizes, then fill the remainder with K-ominoes. |
| `--answer` | Print the completed answer grid after the puzzle, with piece boundaries overlaid on the region borders. |
| `--no-random` | Use the deterministic (first) solution instead of a random one. |
| `--verbose` | Print region box maps and piece count details before the puzzle. |
| `--help` | Show full help and exit. |

---

## Examples

### Classic 9×9 Sudoku, triomino tiling

```bash
polyomino-sudoku --region 1 9 --region 9 1 --region 3 3 --size 3
```

Standard Sudoku constraints (rows + columns + 3×3 boxes), grid tiled with 27
triominoes. The puzzle shows all 27 pieces outside the grid; you fit them back in.

### 6×6 Pair Latin Square, triomino tiling

```bash
polyomino-sudoku --region 1 6 --region 6 1 --region 2 3 --region 3 2 --size 3
```

All four tilings (rows, columns, 2×3 boxes, 3×2 boxes) must each contain every
value 1–6 exactly once. A significantly tighter constraint than standard Sudoku.

### 4×4 full Sudoku, dominoes, show answer

```bash
polyomino-sudoku --region 1 4 --region 4 1 --region 2 2 --size 2 --answer
```

### 9×9, mixed piece sizes

```bash
polyomino-sudoku --region 1 9 --region 9 1 --region 3 3 --must 5,4 --fill 3
```

Includes at least one pentomino and one tetromino; remaining cells filled with
triominoes.

### Box-only 9×9 (no row/column uniqueness)

```bash
polyomino-sudoku --region 3 3 --size 3
```

### 12×12 multi-constraint puzzle with verbose output

```bash
polyomino-sudoku --region 1 12 --region 12 1 \
                 --region 2 6 --region 6 2 --region 3 4 \
                 --size 6 --verbose
```

---

## Output Format

### Puzzle grid

An empty NxN grid with region borders marked by `+`, `-`, and `|`:

```
PUZZLE GRID (fill in the values 1..4 obeying the region constraints;
             each polyomino piece below tells you the values for its cells)

+----+----+----+----+
|         |         |
+    +    +    +    +
|         |         |
+====+====+====+====+
|         |         |
+    +    +    +    +
|         |         |
+----+----+----+----+
```

Region borders use `-` and `|`; heavy borders mark the boundaries between
constraint regions.

### Piece catalogue

Each piece is shown in a randomised order and randomly rotated 0–270°, with
its cell values:

```
PIECES (place each into the grid — rotate in 90° steps as needed;
        the values shown are fixed and must land in the correct cells):

2-omino:
+---+
| 3 |
+   +
| 1 |
+---+

2-omino:
+---+---+
| 4   2 |
+---+---+

...
```

Cells belonging to the same piece share open edges (no border between them).
The piece is displayed in a rotated orientation — you must figure out where it
fits and which rotation restores it to its correct position.

### Answer grid (with `--answer`)

The completed grid with both region borders and piece boundaries overlaid:

- Region borders: `-` and `|` (thin)
- Piece borders: `=` and `!` (thick)
- Corners touching a piece border: `*`

```
ANSWER:

*====*====+----+----*
! 3 ! 1 | 2   4 !
*    *====+====*    *
! 2 | 4 | 1 ! 3 !
+====+----+----*====+
| 4   2 | 3 ! 1 |
+    +    +    *    +
| 1   3 ! 4   2 |
+----+----*----+----+
```

This lets you verify your solution and see how the polyomino pieces tile the
completed grid.

---

## Puzzle Rules

1. Fill every blank cell with a value 1..N.
2. Every regional constraint must be satisfied: within each RxC rectangle of
   every `--region` tiling, each value appears exactly once. The heavy borders
   on the puzzle grid show where all regional boundaries lie.
3. Each polyomino piece fits into exactly one connected group of cells in the
   grid matching its shape (rotating in 90° increments as needed). The values
   shown on the piece are fixed — they must land in the correct cells.
4. The placement of every piece is uniquely determined by constraints 1–3
   together.

---

## Module Structure

```
lib/
  Math/Combinatorics/LatinSquares.pm   — latin square generator with regional constraints
  Polyomino/Tiler.pm                   — polyomino tiling engine (Dancing Links)
  Polyomino/Renderer.pm                — ASCII renderer for tiling solutions
  SudokuSlide/Puzzle.pm                — puzzle assembly and rendering
bin/
  polyomino-sudoku                     — CLI entry point
t/
  Math/Combinatorics/01-basic.t        — LatinSquares tests
  Polyomino/01_polyominoes.t           — polyomino generation tests
  Polyomino/02_solver.t                — tiling solver tests
  Polyomino/03_renderer.t              — renderer tests
  Polyomino/04_mixed.t                 — mixed piece size tests
  Polyomino/TestHelper.pm              — shared test utilities
  SudokuSlide/01-puzzle.t              — full puzzle integration tests
```

---

## How It Works

### Latin square phase

`Math::Combinatorics::LatinSquares` uses a two-phase approach:

1. **Random pre-fill** — a lightweight backtracker fills approximately half the
   boxes of the first region with valid values, checking all constraints
   simultaneously. This seeds the search cheaply and produces diverse solutions.

2. **Dancing Links (DLX)** — the pre-filled cells are given to
   `Algorithm::DLX` as fixed constraints (single-candidate rows); the remaining
   cells get shuffled candidates. DLX then completes the grid.

3. **Retry loop** — if a pre-fill leads to no DLX solution, the whole attempt
   retries (default: up to 200 times). Failure is rare for well-constrained
   problems.

All `--region` constraints are enforced simultaneously throughout.

### Tiling phase

`Polyomino::Tiler` independently tiles the NxN grid with the specified
polyomino pieces using Dancing Links:

1. All free polyominoes of each required size are generated (up to rotation
   and reflection, OEIS A000105).
2. Every valid placement of every orientation at every grid position is
   enumerated.
3. DLX finds a placement that covers every cell exactly once with the correct
   multiset of piece sizes.

The two phases are fully independent — the latin-square values do not influence
the tiling, and the tiling does not influence the values. This independence is
what makes the puzzle well-defined: the piece shapes carry no information about
the values, and vice versa.

### Puzzle assembly

`SudokuSlide::Puzzle` combines both results:

- The **puzzle grid** shows the empty latin-square grid with region borders.
- The **piece catalogue** shows each piece in a randomised order and random
  rotation, with its cell values but without its grid position.
- The **answer grid** (optional) shows the completed grid with both region
  borders and piece borders rendered in distinct characters.

---

## License

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

## Author

James Hammer
