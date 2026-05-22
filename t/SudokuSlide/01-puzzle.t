#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";

use SudokuSlide::Puzzle;

# ── 1. Constructor validation ───────────────────────────────────────────────

eval { SudokuSlide::Puzzle->new(pieces => [3,3]) };
like($@, qr/regions/, 'dies without regions');

eval { SudokuSlide::Puzzle->new(regions => [[2,2]]) };
like($@, qr/polyomino_size|pieces/, 'dies without piece spec');

# ── 2. Small 4x4 puzzle with uniform dominoes ───────────────────────────────

my $p4 = SudokuSlide::Puzzle->new(
    regions => [[1,4],[4,1],[2,2]],   # rows + cols + 2x2 boxes (full 4x4 Sudoku)
    polyomino_size => 2,
    random => 0,
);
ok($p4, '4x4 object created');

my $r4 = $p4->generate;
ok($r4, 'generate returned a result');

# Grid structure
my $grid = $r4->{grid};
is(scalar @$grid, 4, 'grid has 4 rows');
is(scalar @{$grid->[0]}, 4, 'grid row has 4 cols');

# Every value in 1..4 appears in every row (enforced by --region 1 4)
for my $row (0..3) {
    my %vals;
    $vals{$_}++ for map { $grid->[$row][$_] } 0..3;
    is_deeply([sort { $a<=>$b } keys %vals], [1,2,3,4], "row $row has all values");
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

# pieces_by_id is populated
my $pids = $r4->{pieces_by_id};
ok(scalar keys %$pids > 0, 'pieces_by_id is non-empty');

# Each piece is exactly 2 cells (dominoes)
for my $id (keys %$pids) {
    is(scalar @{$pids->{$id}}, 2, "piece $id is a domino");
}

# Puzzle text and solution text are non-empty strings
like($r4->{puzzle_text},   qr/PUZZLE/, 'puzzle_text contains header');
like($r4->{solution_text}, qr/SOLUTION/, 'solution_text contains header');

# ── 3. 9x9 Sudoku-style with triominoes ─────────────────────────────────────

my $p9 = SudokuSlide::Puzzle->new(
    regions => [[1,9],[9,1],[3,3]],
    polyomino_size => 3,
    random => 1,
);
my $r9 = $p9->generate;
ok($r9, '9x9 puzzle generated');

# Verify row uniqueness for the 9x9
my $g9 = $r9->{grid};
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
            for my $c ($bc*3 .. $bc*3+2) {
                $v{$g9->[$r][$c]}++;
            }
        }
        is_deeply([sort{$a<=>$b} keys %v], [1..9], "9x9 box ($br,$bc) ok");
    }
}

# Tiling covers all 81 cells
my %cells9;
for my $piece (@{$r9->{tiling}}) {
    for my $cell (@$piece) {
        $cells9{"$cell->[0],$cell->[1]"}++;
    }
}
is(scalar keys %cells9, 81, '9x9 tiling covers 81 cells');

done_testing;
