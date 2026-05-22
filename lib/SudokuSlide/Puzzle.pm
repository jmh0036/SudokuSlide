package SudokuSlide::Puzzle;

use strict;
use warnings;
use List::Util qw(shuffle);
use Carp       qw(croak);

use Math::Combinatorics::LatinSquares;
use Polyomino::Tiler;

our $VERSION = '0.02';

=head1 NAME

SudokuSlide::Puzzle - Generate polyomino-tiled Quasi Factor Pair latin-square puzzles

=head1 SYNOPSIS

    use SudokuSlide::Puzzle;

    my $puzzle = SudokuSlide::Puzzle->new(
        regions        => [[1,9],[9,1],[3,3]],
        polyomino_size => 3,
    );

    my $result = $puzzle->generate;

    print $result->{puzzle_text};    # sudoku grid (with givens) + pieces outside
    print $result->{solution_text};  # completed grid

=head1 DESCRIPTION

Combines a Quasi Factor Pair Latin Square with a polyomino tiling to produce
a puzzle:

=over 4

=item 1. A completed NxN latin square is generated satisfying all regional
constraints.

=item 2. The NxN grid is independently tiled with polyominoes.

=item 3. The B<puzzle grid> shows the latin square with the union of all
regional constraint borders overlaid (just like a Sudoku grid shows box
borders). Some cells are revealed as givens; the rest are blank.

=item 4. The B<pieces> are shown outside the grid. Each piece shows its shape
and the values it contains — but NOT its position. The solver must place each
piece into the grid (rotating in 90° increments as needed) so that all
latin-square constraints are satisfied.

=back

=cut

sub new {
    my ($class, %args) = @_;

    croak "regions is required and must be a non-empty arrayref"
        unless ref $args{regions} eq 'ARRAY' && @{$args{regions}};

    croak "specify exactly one of 'polyomino_size' or 'pieces'"
        unless defined $args{polyomino_size} || defined $args{pieces};

    my $random = exists $args{random} ? $args{random} : 1;

    # givens_ratio: fraction of cells to reveal as givens (0=none, 1=all)
    my $givens_ratio = exists $args{givens_ratio} ? $args{givens_ratio} : 0.0;

    my ($br0, $bc0) = @{$args{regions}[0]};
    my $N = $br0 * $bc0;

    return bless {
        regions        => $args{regions},
        polyomino_size => $args{polyomino_size},
        pieces         => $args{pieces},
        random         => $random,
        givens_ratio   => $givens_ratio,
        N              => $N,
    }, $class;
}

sub generate {
    my ($self, %opts) = @_;

    my $N      = $self->{N};
    my $random = $self->{random};

    # ── Step 1: Latin square ────────────────────────────────────────────────
    my $ls = Math::Combinatorics::LatinSquares->new(regions => $self->{regions});
    my $grids = $ls->solve(number_of_solutions => 1);
    croak "Latin square solver found no solution" unless $grids && @$grids;
    my $grid = $grids->[0];

    # ── Step 2: Polyomino tiling ────────────────────────────────────────────
    my $tiler;
    if (defined $self->{pieces}) {
        $tiler = Polyomino::Tiler->new(n => $N, m => $N, pieces => $self->{pieces});
    } else {
        $tiler = Polyomino::Tiler->new(n => $N, m => $N, k => $self->{polyomino_size});
    }

    my @tiling_solutions;
    if ($random) {
        @tiling_solutions = $tiler->solve_random(1);
    } else {
        @tiling_solutions = $tiler->solve(1);
    }
    croak "Polyomino tiler found no solution" unless @tiling_solutions;
    my $tiling = $tiling_solutions[0];

    # ── Step 3: Index structures ────────────────────────────────────────────

    # pieces_by_id: id -> [ [r,c], ... ]  (actual grid coordinates)
    my %pieces_by_id;
    my $pid = 1;
    for my $piece (@$tiling) {
        $pieces_by_id{$pid++} = $piece;
    }

    # cell_piece[r][c] = piece id
    my @cell_piece;
    for my $id (sort { $a <=> $b } keys %pieces_by_id) {
        for my $cell (@{$pieces_by_id{$id}}) {
            $cell_piece[$cell->[0]][$cell->[1]] = $id;
        }
    }

    # ── Step 4: Compute region-border wall maps ──────────────────────────────
    # Use only "non-trivial" regions for border display: skip pure 1xN (row)
    # and Nx1 (col) regions since every internal edge would become a wall and
    # the grid would look like a fully-separated lattice, obscuring box structure.
    # h_wall[r][c] = 1 if there is a wall between (r,c) and (r,c+1)
    # v_wall[r][c] = 1 if there is a wall between (r,c) and (r+1,c)
    my $region_specs = $ls->regions;
    my $region_maps  = $ls->region_maps;
    my (@h_wall, @v_wall);
    my @display_t;
    for my $t (0 .. $#$region_specs) {
        my ($br, $bc) = @{$region_specs->[$t]};
        next if $br == 1 || $bc == 1;   # skip trivial row/col strips
        push @display_t, $t;
    }
    @display_t = (0 .. $#$region_specs) unless @display_t;  # fallback

    for my $r (0 .. $N-1) {
        for my $c (0 .. $N-2) {
            my $wall = 0;
            for my $t (@display_t) {
                $wall = 1 if $region_maps->[$t][$r][$c] != $region_maps->[$t][$r][$c+1];
            }
            $h_wall[$r][$c] = $wall;
        }
    }
    for my $r (0 .. $N-2) {
        for my $c (0 .. $N-1) {
            my $wall = 0;
            for my $t (@display_t) {
                $wall = 1 if $region_maps->[$t][$r][$c] != $region_maps->[$t][$r+1][$c];
            }
            $v_wall[$r][$c] = $wall;
        }
    }

    # ── Step 5: Render ──────────────────────────────────────────────────────
    my $puzzle_text   = _render_puzzle(
        $grid, \%pieces_by_id, \@cell_piece,
        \@h_wall, \@v_wall, $N,
        $self->{givens_ratio}, $random,
    );
    my $solution_text = _render_solution($grid, \@h_wall, \@v_wall, $N);

    return {
        grid          => $grid,
        tiling        => $tiling,
        pieces_by_id  => \%pieces_by_id,
        cell_piece    => \@cell_piece,
        h_wall        => \@h_wall,
        v_wall        => \@v_wall,
        puzzle_text   => $puzzle_text,
        solution_text => $solution_text,
        N             => $N,
    };
}

# ── Rendering ───────────────────────────────────────────────────────────────

# Draw the NxN sudoku-style grid with region borders.
# $show[r][c] = value to display, or undef for blank.
sub _render_grid {
    my ($show, $h_wall, $v_wall, $N, $W) = @_;

    my $dash  = '-' x ($W + 2);
    my $blank = ' ' x ($W + 2);
    my $out   = '';

    for my $r (0 .. $N - 1) {
        # Top border of row r: solid at top edge of grid, or wherever v_wall is set
        $out .= '+';
        for my $c (0 .. $N - 1) {
            my $wall = ($r == 0) || $v_wall->[$r-1][$c];
            $out .= ($wall ? $dash : $blank) . '+';
        }
        $out .= "\n";

        # Data row
        $out .= '|';
        for my $c (0 .. $N - 1) {
            if (defined $show->[$r][$c]) {
                $out .= sprintf(" %*d ", $W, $show->[$r][$c]);
            } else {
                $out .= $blank;
            }
            if ($c < $N - 1) {
                $out .= $h_wall->[$r][$c] ? '|' : ' ';
            } else {
                $out .= '|';
            }
        }
        $out .= "\n";
    }
    # Bottom border
    $out .= '+' . (($dash . '+') x $N) . "\n";
    return $out;
}

# Render a single piece showing its shape and VALUES (not its position).
# Cells are normalized to 0-origin. Connected cells share open edges;
# empty bounding-box cells are blank.
sub _render_piece {
    my ($id, $cells, $grid, $W) = @_;

    # Normalize to 0-origin
    my @rows = map { $_->[0] } @$cells;
    my @cols = map { $_->[1] } @$cells;
    my $min_r = (sort { $a <=> $b } @rows)[0];
    my $max_r = (sort { $b <=> $a } @rows)[0];
    my $min_c = (sort { $a <=> $b } @cols)[0];
    my $max_c = (sort { $b <=> $a } @cols)[0];

    my %occ;  # "r,c" -> latin value  (in original grid coords)
    $occ{"$_->[0],$_->[1]"} = $grid->[$_->[0]][$_->[1]] for @$cells;

    my $dash  = '-' x ($W + 2);
    my $blank = ' ' x ($W + 2);

    my $out = "Piece $id (" . scalar(@$cells) . "-omino):\n";

    for my $r ($min_r .. $max_r) {
        # Top border: draw segment above (r,c) if exactly one of {here, above} is in the piece
        $out .= '+';
        for my $c ($min_c .. $max_c) {
            my $here  = exists $occ{"$r,$c"} ? 1 : 0;
            my $above = ($r > $min_r && exists $occ{($r-1).",$c"}) ? 1 : 0;
            my $draw  = ($r == $min_r) ? $here : ($here != $above);
            $out .= ($draw ? $dash : $blank) . '+';
        }
        $out .= "\n";

        # Data row
        $out .= '|';
        for my $c ($min_c .. $max_c) {
            my $here  = exists $occ{"$r,$c"} ? 1 : 0;
            my $right = ($c < $max_c && exists $occ{"$r,".($c+1)}) ? 1 : 0;

            if ($here) {
                $out .= sprintf(" %*d ", $W, $occ{"$r,$c"});
            } else {
                $out .= $blank;
            }

            if ($c < $max_c) {
                $out .= ($here != $right) ? '|' : ' ';
            } else {
                $out .= $here ? '|' : ' ';
            }
        }
        $out .= "\n";
    }

    # Bottom border
    $out .= '+';
    for my $c ($min_c .. $max_c) {
        my $here = exists $occ{"$max_r,$c"} ? 1 : 0;
        $out .= ($here ? $dash : $blank) . '+';
    }
    $out .= "\n";
    return $out;
}

# Build the full puzzle output:
#   - The sudoku grid (region borders, some cells blank = to be filled,
#     optionally some given cells revealed)
#   - The polyomino pieces outside, each showing its shape + values
#     but NOT its position in the grid
sub _render_puzzle {
    my ($grid, $pieces_by_id, $cell_piece,
        $h_wall, $v_wall, $N,
        $givens_ratio, $random) = @_;

    my $W = length("$N");

    # Decide which cells to reveal as givens (all cells are "given" via pieces,
    # but we can additionally pre-reveal some in the grid itself if givens_ratio > 0)
    my @show;  # show[r][c] = value or undef
    if ($givens_ratio > 0) {
        my @all_cells = map { my $r=$_; map { [$r,$_] } 0..$N-1 } 0..$N-1;
        my @revealed = $random
            ? (shuffle @all_cells)[0 .. int($givens_ratio * $N * $N) - 1]
            : @all_cells[0 .. int($givens_ratio * $N * $N) - 1];
        $show[$_->[0]][$_->[1]] = $grid->[$_->[0]][$_->[1]] for @revealed;
    }
    # (all other cells remain undef = blank)

    my $num_pieces = scalar keys %$pieces_by_id;

    my $out  = "PUZZLE GRID (fill in the values 1..$N obeying the region constraints;\n";
    $out    .= "             each polyomino piece below tells you the values for its cells)\n\n";
    $out    .= _render_grid(\@show, $h_wall, $v_wall, $N, $W);

    $out .= "\nPIECES (place each into the grid — rotate in 90\xc2\xb0 steps as needed;\n";
    $out .= "        the values shown are fixed and must land in the correct cells):\n\n";

    for my $id (keys %$pieces_by_id) {
        $out .= _render_piece($id, $pieces_by_id->{$id}, $grid, $W) . "\n";
    }

    return $out;
}

# Solution: the completed grid with region borders.
sub _render_solution {
    my ($grid, $h_wall, $v_wall, $N) = @_;
    my $W = length("$N");
    return "SOLUTION:\n\n" . _render_grid($grid, $h_wall, $v_wall, $N, $W);
}

1;

__END__

=head1 PUZZLE RULES

=over 4

=item 1. Fill every blank cell in the NxN grid with a value 1..N.

=item 2. Every regional constraint (each C<--region> tiling) must be satisfied:
within each RxC rectangle of that tiling, every value appears exactly once.
The heavy borders on the grid show where ALL regional boundaries lie.

=item 3. The polyomino pieces shown below the grid each contain a set of values.
Place each piece into the grid (rotating in 90-degree increments) so that its
values land on a connected group of cells that exactly matches its shape.

=item 4. The piece placements are uniquely determined by satisfying rules 1-3
simultaneously.

=back

=head1 AUTHOR

James Hammer

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
