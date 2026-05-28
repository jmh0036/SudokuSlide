use v5.40;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../../lib";

use SudokuSlide::Puzzle;

# ── Constructor validation ────────────────────────────────────────────────

eval { SudokuSlide::Puzzle->new(pieces => [3,3]) };
like($@, qr/regions/, 'dies without regions');

eval { SudokuSlide::Puzzle->new(regions => [[2,2]]) };
like($@, qr/polyomino_size|pieces/, 'dies without piece spec');

eval { SudokuSlide::Puzzle->new(regions => [[2,2]], polyomino_size => 2, pieces => [2,2]) };
like($@, qr/both/, 'dies when both polyomino_size and pieces given');

eval { SudokuSlide::Puzzle->new(regions => [[2,2]], pieces => [2,2], givens_ratio => 99) };
like($@, qr/givens_ratio/, 'dies with out-of-range givens_ratio');

# ── 4x4 puzzle with dominoes ─────────────────────────────────────────────

my $p4 = SudokuSlide::Puzzle->new(
    regions        => [[1,4],[4,1],[2,2]],
    polyomino_size => 2,
    random         => 0,
);
ok($p4, '4x4 object constructed');

my $r4 = $p4->generate;
ok($r4, 'generate returned a result');

# Grid structure
my $grid = $r4->{grid};
is(scalar @$grid,        4, 'grid has 4 rows');
is(scalar @{$grid->[0]}, 4, 'grid row has 4 cols');

# Every row has all values 1..4
for my $row (0..3) {
    my %v;
    $v{$_}++ for map { $grid->[$row][$_] } 0..3;
    is_deeply([sort{$a<=>$b} keys %v], [1,2,3,4], "row $row has all values");
}

# Tiling covers all 16 cells exactly once
my %cells_seen;
for my $piece (@{$r4->{tiling}}) {
    for my $cell (@$piece) {
        my $key = "$cell->[0],$cell->[1]";
        ok(!$cells_seen{$key}, "cell $key not double-covered");
        $cells_seen{$key} = 1;
    }
}
is(scalar keys %cells_seen, 16, 'tiling covers exactly 16 cells');

# Each piece is a domino
my $pids = $r4->{pieces_by_id};
ok(scalar keys %$pids > 0, 'pieces_by_id non-empty');
is(scalar @{$pids->{$_}}, 2, "piece $_ is a domino") for keys %$pids;

# Output text sanity
like($r4->{puzzle_text}, qr/PUZZLE/,   'puzzle_text has PUZZLE header');
like($r4->{puzzle_text}, qr/PIECES/,   'puzzle_text has PIECES section');
like($r4->{answer_text}, qr/ANSWER/,   'answer_text has ANSWER header');

# Piece labels must NOT appear — they give away position
unlike($r4->{puzzle_text}, qr/Piece \d+/, 'puzzle_text has no "Piece N" labels');

# Size-omino labels should be present
like($r4->{puzzle_text}, qr/\d+-omino/, 'puzzle_text has N-omino size labels');

# answer_text should contain piece borders (= for horizontal)
like($r4->{answer_text}, qr/=/, 'answer_text contains piece border chars (=)');

# ── 9x9 Sudoku with triominoes ────────────────────────────────────────────

my $p9 = SudokuSlide::Puzzle->new(
    regions        => [[1,9],[9,1],[3,3]],
    polyomino_size => 3,
    random         => 1,
);
my $r9 = $p9->generate;
ok($r9, '9x9 puzzle generated');

my $g9 = $r9->{grid};

# Row uniqueness
for my $row (0..8) {
    my %v;
    $v{$_}++ for map { $g9->[$row][$_] } 0..8;
    is_deeply([sort{$a<=>$b} keys %v], [1..9], "9x9 row $row ok");
}

# Column uniqueness
for my $col (0..8) {
    my %v;
    $v{$_}++ for map { $g9->[$_][$col] } 0..8;
    is_deeply([sort{$a<=>$b} keys %v], [1..9], "9x9 col $col ok");
}

# 3x3 box uniqueness
for my $br (0..2) {
    for my $bc (0..2) {
        my %v;
        for my $r ($br*3 .. $br*3+2) {
            $v{$g9->[$r][$_]}++ for $bc*3 .. $bc*3+2;
        }
        is_deeply([sort{$a<=>$b} keys %v], [1..9], "9x9 box ($br,$bc) ok");
    }
}

# Tiling covers all 81 cells
my %cells9;
for my $piece (@{$r9->{tiling}}) {
    $cells9{"$_->[0],$_->[1]"}++ for @$piece;
}
is(scalar keys %cells9, 81, '9x9 tiling covers 81 cells');

done_testing;
