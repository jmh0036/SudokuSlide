use v5.40;
use feature 'class';
no warnings 'experimental';

class SudokuSlide::Puzzle 0.05;

use List::Util   qw(shuffle min max);
use Carp         qw(croak);
use Scalar::Util qw(looks_like_number);

use Math::Combinatorics::LatinSquares;
use Polyomino::Tiler;

=head1 NAME

SudokuSlide::Puzzle - Generate polyomino-tiled Quasi Factor Pair latin-square puzzles

=head1 SYNOPSIS

    use SudokuSlide::Puzzle;

    my $puzzle = SudokuSlide::Puzzle->new(
        regions        => [[1,9],[9,1],[3,3]],
        polyomino_size => 3,
    );

    my $result = $puzzle->generate;

    print $result->{puzzle_text};    # empty grid + piece catalogue
    print $result->{answer_text};    # completed grid with piece borders shown

=head1 DESCRIPTION

Combines a Quasi Factor Pair Latin Square with a polyomino tiling to produce
a puzzle. The solver sees an empty grid and a set of polyomino pieces shown in
randomised order and orientation; they must place each piece into the grid
satisfying all latin-square constraints.

=head1 CONSTRUCTOR

=head2 new(%params)

    SudokuSlide::Puzzle->new(
        regions        => [[1,9],[9,1],[3,3]],   # required
        polyomino_size => 3,                     # uniform k-omino tiling
        # -- OR --
        pieces         => [3,3,3,...],           # explicit piece list
        random         => 1,                     # default: 1 (random)
        givens_ratio   => 0.0,                   # fraction of cells pre-revealed
    );

Exactly one of C<polyomino_size> or C<pieces> must be provided.

=cut

field $regions        :param;
field $polyomino_size :param = undef;
field $pieces         :param = undef;
field $random         :param = 1;
field $givens_ratio   :param = 0.0;
field $N;

ADJUST {
    croak "regions must be a non-empty arrayref"
        unless ref $regions eq 'ARRAY' && @$regions;

    croak "specify exactly one of 'polyomino_size' or 'pieces'"
        unless defined $polyomino_size || defined $pieces;

    croak "specify exactly one of 'polyomino_size' or 'pieces', not both"
        if defined $polyomino_size && defined $pieces;

    if (defined $polyomino_size) {
        croak "'polyomino_size' must be a positive integer"
            unless looks_like_number($polyomino_size)
                && $polyomino_size >= 1
                && int($polyomino_size) == $polyomino_size;
    }

    if (defined $pieces) {
        croak "'pieces' must be a non-empty arrayref"
            unless ref $pieces eq 'ARRAY' && @$pieces;
    }

    croak "givens_ratio must be between 0 and 1"
        if defined $givens_ratio && ($givens_ratio < 0 || $givens_ratio > 1);

    my ($br0, $bc0) = @{ $regions->[0] };
    $N = $br0 * $bc0;

    croak "N (=$N) must be >= 1" unless $N >= 1;
}

=head1 METHODS

=head2 generate

Solve the latin square, tile the grid, and return a hashref with keys:

=over 4

=item C<grid>          — 2D arrayref of latin-square values (1..N)

=item C<tiling>        — arrayref of pieces; each piece is an arrayref of [r,c] pairs

=item C<pieces_by_id>  — hashref: piece_id (1-based) => [[r,c],...]

=item C<cell_piece>    — 2D arrayref: cell_piece->[r][c] = piece_id

=item C<h_wall>        — horizontal region-border wall map (between columns)

=item C<v_wall>        — vertical region-border wall map (between rows)

=item C<N>             — grid side length

=item C<puzzle_text>   — formatted string: empty grid + piece catalogue

=item C<answer_text>   — formatted string: completed grid with piece + region borders

=back

=cut

method generate() {

    # ── Step 1: Latin square ──────────────────────────────────────────────────
    my $ls    = Math::Combinatorics::LatinSquares->new(regions => $regions);
    my $grids = $ls->solve(number_of_solutions => 1);
    croak "Latin square solver found no solution" unless $grids && @$grids;
    my $grid = $grids->[0];

    # ── Step 2: Polyomino tiling ──────────────────────────────────────────────
    my $tiler = defined $pieces
        ? Polyomino::Tiler->new(n => $N, m => $N, pieces => $pieces)
        : Polyomino::Tiler->new(n => $N, m => $N, k      => $polyomino_size);

    my @sols = $random ? $tiler->solve_random(1) : $tiler->solve(1);
    croak "Polyomino tiler found no solution" unless @sols;
    my $tiling = $sols[0];

    # ── Step 3: Index structures ──────────────────────────────────────────────
    my %pieces_by_id;
    my $pid = 1;
    $pieces_by_id{$pid++} = $_ for @$tiling;

    my @cell_piece;
    for my $id (sort { $a <=> $b } keys %pieces_by_id) {
        for my $cell (@{ $pieces_by_id{$id} }) {
            $cell_piece[$cell->[0]][$cell->[1]] = $id;
        }
    }

    # ── Step 4: Region-border wall maps ──────────────────────────────────────
    # Only use non-trivial regions (not pure row/column strips) for the visible
    # grid borders; fall back to all regions if every spec is a strip.
    my $region_specs = $ls->regions;
    my $region_maps  = $ls->region_maps;

    my @display_t = grep {
        $region_specs->[$_][0] != 1 && $region_specs->[$_][1] != 1
    } 0 .. $#$region_specs;
    @display_t = (0 .. $#$region_specs) unless @display_t;

    my (@h_wall, @v_wall);
    for my $r (0 .. $N-1) {
        for my $c (0 .. $N-2) {
            $h_wall[$r][$c] = 1
                if grep { $region_maps->[$_][$r][$c] != $region_maps->[$_][$r][$c+1] }
                   @display_t;
        }
    }
    for my $r (0 .. $N-2) {
        for my $c (0 .. $N-1) {
            $v_wall[$r][$c] = 1
                if grep { $region_maps->[$_][$r][$c] != $region_maps->[$_][$r+1][$c] }
                   @display_t;
        }
    }

    # ── Step 5: Render ────────────────────────────────────────────────────────
    my $puzzle_text = _render_puzzle(
        $grid, \%pieces_by_id, \@h_wall, \@v_wall, $N, $givens_ratio, $random,
    );
    my $answer_text = _render_answer(
        $grid, \@cell_piece, \@h_wall, \@v_wall, $N,
    );

    return {
        grid         => $grid,
        tiling       => $tiling,
        pieces_by_id => \%pieces_by_id,
        cell_piece   => \@cell_piece,
        h_wall       => \@h_wall,
        v_wall       => \@v_wall,
        N            => $N,
        puzzle_text  => $puzzle_text,
        answer_text  => $answer_text,
    };
}

# ── Private rendering helpers ─────────────────────────────────────────────────
#
# All private subs use old-style @_ unpacking (no sub-signature syntax).
# This avoids the `map { BLOCK } @$ref` parser ambiguity that affects all Perl
# versions with `use feature 'signatures'` in scope through at least 5.41.
# (Fixed in 5.42, but we target v5.40 as the minimum.)

# ---------------------------------------------------------------------------
# _render_grid(\@show, \@h_wall, \@v_wall, $N, $W)
#
# Render the NxN latin-square grid with region borders only.
# $show->[$r][$c] = value to display (undef = blank cell).
# $h_wall->[$r][$c] = 1 means a region border to the RIGHT of cell (r,c).
# $v_wall->[$r][$c] = 1 means a region border BELOW cell (r,c).
# $W = minimum field width for values.
# ---------------------------------------------------------------------------
sub _render_grid {
    my ($show, $h_wall, $v_wall, $N, $W) = @_;
    my $dash  = '-' x ($W + 2);
    my $blank = ' ' x ($W + 2);
    my $out   = '';

    for my $r (0 .. $N-1) {
        # Top border of row r
        $out .= '+';
        for my $c (0 .. $N-1) {
            $out .= (($r == 0 || $v_wall->[$r-1][$c]) ? $dash : $blank) . '+';
        }
        $out .= "\n|";
        # Data row — outer left wall is always present (full grid, all cells exist)
        for my $c (0 .. $N-1) {
            $out .= defined $show->[$r][$c]
                ? sprintf(' %*d ', $W, $show->[$r][$c])
                : $blank;
            $out .= $c < $N-1
                ? ($h_wall->[$r][$c] ? '|' : ' ')
                : '|';
        }
        $out .= "\n";
    }
    # Final bottom border
    $out .= '+' . (($dash . '+') x $N) . "\n";
    return $out;
}

# ---------------------------------------------------------------------------
# _render_answer(\@grid, \@cell_piece, \@h_wall, \@v_wall, $N)
#
# Render the completed NxN grid overlaying BOTH region borders and piece
# borders, using distinct characters for each:
#
#   Region borders  : -  |      (thin)
#   Piece borders   : =  !      (thick)
#   Corner markers  : +  (region-only corners)
#                     *  (corners touching at least one piece border)
#
# When both a region border and a piece border coincide on the same edge,
# the piece border character wins (it carries more specific information).
# ---------------------------------------------------------------------------
sub _render_answer {
    my ($grid, $cell_piece, $h_wall, $v_wall, $N) = @_;
    my $W     = length("$N");
    my $rdash = '-' x ($W + 2);   # region horizontal segment
    my $pdash = '=' x ($W + 2);   # piece  horizontal segment
    my $blank = ' ' x ($W + 2);

    my $out = "ANSWER:\n\n";

    for my $r (0 .. $N) {          # N+1 border rows

        # --- Horizontal border row ---
        for my $c (0 .. $N) {      # N+1 corner positions
            # Corner: use '*' if any adjacent segment is a piece border
            my $corner_has_piece = 0;

            # Horizontal segment to the LEFT of this corner (above row r, col c-1)
            if ($c > 0 && $r > 0 && $r <= $N) {
                my $above = $cell_piece->[$r-1][$c-1] // 0;
                my $below = $r < $N ? ($cell_piece->[$r  ][$c-1] // 0) : 0;
                $corner_has_piece = 1 if $above != $below;
            }
            # Horizontal segment to the RIGHT of this corner (above row r, col c)
            if (!$corner_has_piece && $c < $N && $r > 0 && $r <= $N) {
                my $above = $cell_piece->[$r-1][$c] // 0;
                my $below = $r < $N ? ($cell_piece->[$r  ][$c] // 0) : 0;
                $corner_has_piece = 1 if $above != $below;
            }
            # Vertical segment ABOVE this corner (between rows r-1 and r, col c-1)
            if (!$corner_has_piece && $r > 0 && $c > 0 && $c < $N) {
                my $left  = $cell_piece->[$r-1][$c-1] // 0;
                my $right = $cell_piece->[$r-1][$c  ] // 0;
                $corner_has_piece = 1 if $left != $right;
            }
            # Vertical segment BELOW this corner (between rows r and r+1, col c-1)
            if (!$corner_has_piece && $r < $N && $c > 0 && $c < $N) {
                my $left  = $cell_piece->[$r][$c-1] // 0;
                my $right = $cell_piece->[$r][$c  ] // 0;
                $corner_has_piece = 1 if $left != $right;
            }

            $out .= $corner_has_piece ? '*' : '+';
            last if $c == $N;

            # Horizontal segment spanning column c (between rows r-1 and r)
            my $above = ($r > 0) ? ($cell_piece->[$r-1][$c] // 0) : 0;
            my $below = ($r < $N) ? ($cell_piece->[$r  ][$c] // 0) : 0;

            if ($above != $below) {
                $out .= $pdash;     # piece border wins
            }
            elsif ($r > 0 && $v_wall->[$r-1][$c]) {
                $out .= $rdash;     # region border
            }
            else {
                $out .= $blank;
            }
        }
        $out .= "\n";
        last if $r == $N;

        # --- Data row ---
        for my $c (0 .. $N) {      # N+1 vertical wall positions
            # Vertical wall between col c-1 (left) and col c (right)
            my $left  = ($c > 0)  ? ($cell_piece->[$r][$c-1] // 0) : 0;
            my $right = ($c < $N) ? ($cell_piece->[$r][$c  ] // 0) : 0;

            if ($left != $right) {
                $out .= '!';        # piece border
            }
            elsif ($c == 0 || $c == $N) {
                $out .= '|';        # grid boundary
            }
            elsif ($h_wall->[$r][$c-1]) {
                $out .= '|';        # region border
            }
            else {
                $out .= ' ';
            }

            last if $c == $N;
            $out .= sprintf(' %*d ', $W, $grid->[$r][$c]);
        }
        $out .= "\n";
    }

    return $out;
}

# ---------------------------------------------------------------------------
# _rotate_cw(\@cells)
#
# Rotate a list of [r,c] cells 90 degrees clockwise, renormalized to 0-origin.
# ---------------------------------------------------------------------------
sub _rotate_cw {
    my ($cells) = @_;
    my @r = map { [$_->[1], -$_->[0]] } @$cells;
    my $min_r = min(map { $_->[0] } @r);
    my $min_c = min(map { $_->[1] } @r);
    return [map { [$_->[0]-$min_r, $_->[1]-$min_c] } @r];
}

# ---------------------------------------------------------------------------
# _rotate(\@cells, $steps)
#
# Rotate cells by $steps * 90 degrees clockwise (0..3).
# ---------------------------------------------------------------------------
sub _rotate {
    my ($cells, $steps) = @_;
    $cells = _rotate_cw($cells) for 1 .. ($steps % 4);
    return $cells;
}

# ---------------------------------------------------------------------------
# _render_piece(\@display_cells, \%val_map, $size, $W)
#
# Render a single piece showing its shape and cell values.
# $display_cells: arrayref of [r,c] pairs in normalized (possibly rotated) coords.
# $val_map: "r,c" => value for each cell in display coords.
# $size: number of cells (used for the header label).
# $W: minimum field width for values.
#
# Border rules (correct for non-rectangular pieces):
#   Horizontal segment between rows r-1 and r at col c: draw if exactly one of
#     (above-cell, below-cell) is occupied.
#   Vertical wall between cols c-1 and c at row r: draw if exactly one of
#     (left-cell, right-cell) is occupied.
# ---------------------------------------------------------------------------
sub _render_piece {
    my ($display_cells, $val_map, $size, $W) = @_;

    my @rows  = map { $_->[0] } @$display_cells;
    my @cols  = map { $_->[1] } @$display_cells;
    my $min_r = min(@rows); my $max_r = max(@rows);
    my $min_c = min(@cols); my $max_c = max(@cols);

    my %occ;
    for my $cell (@$display_cells) {
        $occ{"$cell->[0],$cell->[1]"} = $val_map->{"$cell->[0],$cell->[1]"};
    }

    my $dash  = '-' x ($W + 2);
    my $blank = ' ' x ($W + 2);
    my $out   = "$size-omino:\n";

    for my $r ($min_r .. $max_r + 1) {
        # Horizontal border row: draw '-' where exactly one of (above, below) is occupied
        $out .= '+';
        for my $c ($min_c .. $max_c) {
            my $above = ($r > $min_r)  && exists $occ{($r-1) . ",$c"};
            my $below = ($r <= $max_r) && exists $occ{"$r,$c"};
            $out .= (($above != $below) ? $dash : $blank) . '+';
        }
        $out .= "\n";
        last if $r > $max_r;

        # Data row: draw '|' where exactly one of (left, right) is occupied
        for my $c ($min_c .. $max_c + 1) {
            my $left  = ($c > $min_c)  && exists $occ{"$r," . ($c-1)};
            my $right = ($c <= $max_c) && exists $occ{"$r,$c"};
            $out .= ($left != $right) ? '|' : ' ';
            last if $c > $max_c;
            $out .= exists $occ{"$r,$c"}
                ? sprintf(' %*d ', $W, $occ{"$r,$c"})
                : $blank;
        }
        $out .= "\n";
    }

    return $out;
}

# ---------------------------------------------------------------------------
# _render_puzzle(\@grid, \%pieces_by_id, \@h_wall, \@v_wall, $N,
#                $givens_ratio, $random)
#
# Render the puzzle: an empty grid (with optional pre-revealed givens) followed
# by the piece catalogue. Pieces are displayed in randomised order (when
# $random is true) and each is randomly rotated 0-3 * 90 degrees.
# ---------------------------------------------------------------------------
sub _render_puzzle {
    my ($grid, $pieces_by_id, $h_wall, $v_wall, $N, $givens_ratio, $random) = @_;
    my $W = length("$N");

    # Optionally reveal a fraction of cells as givens
    my @show;
    if ($givens_ratio > 0) {
        my $num_givens = int($givens_ratio * $N * $N);
        if ($num_givens > 0) {
            my @all = map { my $r=$_; map { [$r,$_] } 0..$N-1 } 0..$N-1;
            my @revealed = $random
                ? (shuffle @all)[0 .. $num_givens - 1]
                : @all[0 .. $num_givens - 1];
            $show[$_->[0]][$_->[1]] = $grid->[$_->[0]][$_->[1]] for @revealed;
        }
    }

    my $out = "PUZZLE GRID (fill in the values 1..$N obeying the region constraints;\n"
            . "             each polyomino piece below tells you the values for its cells)\n\n"
            . _render_grid(\@show, $h_wall, $v_wall, $N, $W)
            . "\nPIECES (place each into the grid \x{2014} rotate in 90\x{00B0} steps as needed;\n"
            . "        the values shown are fixed and must land in the correct cells):\n\n";

    # Shuffle display order so sequential piece IDs don't reveal position
    my @ids = $random
        ? shuffle(keys %$pieces_by_id)
        : sort { $a <=> $b } keys %$pieces_by_id;

    for my $id (@ids) {
        my $orig = $pieces_by_id->{$id};
        my $size = scalar @$orig;

        # Normalize to 0-origin
        my $min_r = min(map { $_->[0] } @$orig);
        my $min_c = min(map { $_->[1] } @$orig);
        my @norm  = map { [$_->[0]-$min_r, $_->[1]-$min_c] } @$orig;

        # Build value map at normalized coords
        my %val_map;
        for my $i (0 .. $#norm) {
            $val_map{"$norm[$i][0],$norm[$i][1]"} = $grid->[$orig->[$i][0]][$orig->[$i][1]];
        }

        # Apply random rotation; remap values by index (rotation is index-preserving)
        my $steps   = $random ? int(rand 4) : 0;
        my $rotated = _rotate(\@norm, $steps);

        my %rot_map;
        for my $i (0 .. $#norm) {
            $rot_map{"$rotated->[$i][0],$rotated->[$i][1]"}
                = $val_map{"$norm[$i][0],$norm[$i][1]"};
        }

        $out .= _render_piece($rotated, \%rot_map, $size, $W) . "\n";
    }

    return $out;
}

1;

__END__

=head1 PUZZLE RULES

=over 4

=item 1. Fill every blank cell with a value 1..N.

=item 2. Every regional constraint must be satisfied: within each RxC rectangle,
every value appears exactly once. Heavy borders on the grid show where regional
boundaries lie.

=item 3. Place each polyomino piece into the grid (rotating in 90-degree
increments as needed) so its values land on a connected group of cells exactly
matching its shape.

=item 4. The placement is uniquely determined by constraints 1-3 together.

=back

=head1 AUTHOR

James Hammer

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
