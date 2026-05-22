package Math::Combinatorics::LatinSquares;

use strict;
use warnings;
use Algorithm::DLX;
use List::Util qw(shuffle);
use Carp       qw(croak);

our $VERSION = '0.03';

=head1 NAME

Math::Combinatorics::LatinSquares - Generate random latin squares with simultaneous
rectangular regional constraints

=head1 VERSION

Version 0.03

=head1 SYNOPSIS

    use Math::Combinatorics::LatinSquares;

    my $ls = Math::Combinatorics::LatinSquares->new(regions => [[3, 3]]);

    # One random solution (default)
    my $grids = $ls->solve;
    $ls->print_grid($grids->[0]);

    # All solutions
    my $grids = $ls->solve(number_of_solutions => undef);

    # Exactly 5 solutions
    my $grids = $ls->solve(number_of_solutions => 5);

=head1 DESCRIPTION

A B<latin square> is an NxN grid in which each of N symbols appears exactly
once in every row and every column.

A B<sudoku pair latin square> adds one or more I<regional> constraints: the NxN
grid is partitioned into N non-overlapping regions of N cells each, and each
region must also contain every symbol exactly once.

This module focuses on B<rectangular regional tilings>: each region specification
C<[R, C]> describes a uniform tiling of the NxN grid by RxC rectangles.  Multiple
region specifications can be enforced I<simultaneously>.

Rows and columns are I<not> assumed; specify C<[1, N]> and C<[N, 1]> explicitly
if you want them.

Solving uses a two-phase approach: a fast random pre-filler places values in
some boxes before invoking L<Algorithm::DLX>, which dramatically reduces the
DLX search space.

=head1 METHODS

=head2 new(%args)

    my $ls = Math::Combinatorics::LatinSquares->new(regions => [[2, 3], [3, 2]]);

Constructs a new solver object.  Arguments:

=over 4

=item regions

Required.  An arrayref of C<[box_rows, box_cols]> pairs.  All pairs must have
the same product R*C, which becomes N (the grid side length and symbol count).

=back

=cut

sub new {
    my ($class, %args) = @_;

    croak "regions is required" unless exists $args{regions};
    my $region_specs = $args{regions};
    croak "regions must be a non-empty arrayref"
        unless ref $region_specs eq 'ARRAY' && @$region_specs;

    my $N;
    my @regions;
    for my $spec (@$region_specs) {
        croak "each region spec must be an arrayref of two positive integers"
            unless ref $spec eq 'ARRAY' && @$spec == 2
                && $spec->[0] >= 1 && $spec->[1] >= 1;
        my ($br, $bc) = @$spec;
        my $prod = $br * $bc;
        croak "region [$br, $bc]: product must be >= 2" if $prod < 2;
        if (defined $N) {
            croak "region [$br, $bc]: product $prod differs from $N "
                . "(all regions must have the same product)"
                unless $prod == $N;
        } else {
            $N = $prod;
        }
        croak "grid size $N must be divisible by box_rows $br" if $N % $br;
        croak "grid size $N must be divisible by box_cols $bc" if $N % $bc;
        push @regions, [$br, $bc];
    }

    my @region_maps = map { _build_region_map($N, $_->[0], $_->[1]) } @regions;

    return bless {
        N           => $N,
        regions     => \@regions,
        region_maps => \@region_maps,
    }, $class;
}

=head2 n

Returns N, the grid side length (and number of symbols).

=cut

sub n { $_[0]->{N} }

=head2 regions

Returns the arrayref of C<[box_rows, box_cols]> region specs.

=cut

sub regions { $_[0]->{regions} }

=head2 region_maps

Returns an arrayref of region maps (one per region spec).  Each map is a 2D
arrayref C<$map->[$r][$c]> giving the box index (0..N-1) for cell (r, c).

=cut

sub region_maps { $_[0]->{region_maps} }

=head2 solve(%opts)

    my $grids = $ls->solve;                               # one random solution (default)
    my $grids = $ls->solve(number_of_solutions => 5);     # up to 5 solutions
    my $grids = $ls->solve(number_of_solutions => undef); # all solutions

Uses a fast random pre-filler to seed the grid, then invokes
L<Algorithm::DLX> to complete it.  Pre-filled cells are injected into the
DLX matrix as the only candidate for that cell, so DLX is forced to accept
them without any search on those cells, reducing the search space greatly.

A pre-filled partial assignment that is individually consistent may still
leave no completable solution (the randomly chosen boxes can paint DLX into
a corner).  In that case the whole attempt — pre-fill and DLX — is retried
with a fresh random assignment up to C<max_attempts> times.

Options:

=over 4

=item number_of_solutions

How many solutions to return.  Defaults to C<1>.  Pass C<undef> for all.

=item prefill_boxes

How many boxes (of the first region) to pre-fill before invoking DLX.
Defaults to half of N (rounded down).  Set to 0 to disable pre-filling.

=item max_attempts

Maximum number of full solve attempts (prefill + DLX) before giving up and
returning an empty arrayref.  Defaults to 200.

=back

Returns an arrayref of grids (each a 2D arrayref where C<$grid->[$r][$c]> is
a value 1..N), or an empty arrayref if no solution was found within
C<max_attempts> tries.

=cut

sub solve {
    my ($self, %opts) = @_;

    my $num_solutions = exists $opts{number_of_solutions}
        ? $opts{number_of_solutions}
        : 1;

    my $N           = $self->{N};
    my @regions     = @{ $self->{regions} };
    my @region_maps = @{ $self->{region_maps} };

    my $prefill_boxes = exists $opts{prefill_boxes}
        ? $opts{prefill_boxes}
        : int($N / 2);
    my $max_attempts  = $opts{max_attempts} // 200;

    for my $attempt (1 .. $max_attempts) {

        # --- Phase 1: random pre-fill ---
        # Try to place values in $prefill_boxes random boxes of region 0,
        # obeying all constraints.  Returns () if it gets stuck — just retry
        # the whole attempt with a fresh shuffle.
        my %pinned;
        if ($prefill_boxes > 0) {
            my @placements = _prefill($N, \@regions, \@region_maps, $prefill_boxes);
            next unless @placements;   # stuck — try a completely fresh attempt
            $pinned{"$_->[0],$_->[1]"} = $_->[2] for @placements;
        }

        # --- Phase 2: build and run DLX ---
        # Pinned cells get only their one forced row; unpinned cells get all
        # N candidates in shuffled order.  DLX trivially selects pinned cells
        # at zero search cost and only needs to search the remaining cells.
        my $dlx = Algorithm::DLX->new();
        my %col;

        for my $r (0 .. $N-1) {
            for my $c (0 .. $N-1) {
                $col{"cell_${r}_${c}"} = $dlx->add_column("cell_${r}_${c}");
            }
        }

        for my $t (0 .. $#regions) {
            for my $k (0 .. $N-1) {
                for my $v (1 .. $N) {
                    $col{"t${t}_box${k}_v${v}"} = $dlx->add_column("t${t}_box${k}_v${v}");
                }
            }
        }

        # Build candidate list.  Pinned cells get only their forced value;
        # unpinned cells get all values in shuffled order.
        my @candidates;
        for my $r (0 .. $N-1) {
            for my $c (0 .. $N-1) {
                my $key = "$r,$c";
                if (exists $pinned{$key}) {
                    push @candidates, [$r, $c, $pinned{$key}];
                } else {
                    push @candidates, map { [$r, $c, $_] } shuffle(1 .. $N);
                }
            }
        }

        for my $p (@candidates) {
            my ($r, $c, $v) = @$p;
            my @cols = ( $col{"cell_${r}_${c}"} );
            for my $t (0 .. $#regions) {
                my $k = $region_maps[$t][$r][$c];
                push @cols, $col{"t${t}_box${k}_v${v}"};
            }
            $dlx->add_row("${r},${c},${v}", @cols);
        }

        my %dlx_opts;
        $dlx_opts{number_of_solutions} = $num_solutions if defined $num_solutions;
        my $solutions = $dlx->solve(%dlx_opts);

        # DLX found nothing for this prefill — try a fresh random assignment
        next unless $solutions && @$solutions;

        my @grids;
        for my $sol (@$solutions) {
            my @grid;
            for my $row_name (@$sol) {
                my ($r, $c, $v) = split /,/, $row_name;
                $grid[$r][$c] = $v;
            }
            push @grids, \@grid;
        }
        return \@grids;
    }

    return [];  # exhausted all attempts
}

=head2 print_grid($grid, %opts)

    $ls->print_grid($grid);
    $ls->print_grid($grid, fh => \*STDERR);

Prints the solution grid to a filehandle (default: STDOUT).

=cut

sub print_grid {
    my ($self, $grid, %opts) = @_;
    my $fh = $opts{fh} // \*STDOUT;
    my $N  = $self->{N};
    my $w  = length($N);
    for my $r (0 .. $N-1) {
        print $fh join(' ', map { sprintf("%${w}d", $grid->[$r][$_]) } 0 .. $N-1), "\n";
    }
}

=head2 print_region_map($tiling_index, %opts)

    $ls->print_region_map(0);
    $ls->print_region_map(1, fh => \*STDERR);

Prints the box map for the given tiling index using letter labels.

=cut

sub print_region_map {
    my ($self, $t, %opts) = @_;
    my $fh  = $opts{fh} // \*STDOUT;
    my $N   = $self->{N};
    my $map = $self->{region_maps}[$t];
    my @labels = ('A'..'Z', 'a'..'z', '0'..'9');
    for my $r (0 .. $N-1) {
        print $fh join(' ', map { $labels[$map->[$r][$_]] // '?' } 0 .. $N-1), "\n";
    }
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Attempt to pre-fill $num_boxes boxes of region 0, obeying all constraints.
# Returns a list of [r, c, v] triples on success, or empty list on failure.
sub _prefill {
    my ($N, $regions, $region_maps, $num_boxes) = @_;

    my $primary_map = $region_maps->[0];

    # Gather cells per box of the primary region
    my @box_cells;
    for my $r (0 .. $N-1) {
        for my $c (0 .. $N-1) {
            push @{ $box_cells[ $primary_map->[$r][$c] ] }, [$r, $c];
        }
    }

    # Pick $num_boxes boxes at random to fill
    my @box_order = (shuffle 0 .. $N-1)[ 0 .. $num_boxes-1 ];

    # Shared constraint tracking across boxes:
    #   $col_used[$c]{$v}         — value $v already placed in column $c
    #   $box_used[$t][$k]{$v}     — value $v already placed in tiling $t, box $k
    my @col_used;
    my @box_used;
    my @all_placements;

    for my $k (@box_order) {
        my @cells = @{ $box_cells[$k] };
        my @vals  = shuffle 1 .. $N;
        my @assigned;

        my $ok = _fill_box(\@cells, \@vals, 0, \@assigned,
                           \@col_used, \@box_used,
                           $regions, $region_maps);
        return () unless $ok;   # signal failure; caller will retry

        push @all_placements, @assigned;
    }

    return @all_placements;
}

# Recursive backtracker for a single box.
sub _fill_box {
    my ($cells, $vals, $idx, $assigned,
        $col_used, $box_used,
        $regions, $region_maps) = @_;

    return 1 if $idx == scalar @$cells;

    my ($r, $c) = @{ $cells->[$idx] };

    for my $vi (0 .. $#$vals) {
        my $v = $vals->[$vi];

        next if $col_used->[$c]{$v};

        my $conflict = 0;
        for my $t (0 .. $#$regions) {
            if ($box_used->[$t][ $region_maps->[$t][$r][$c] ]{$v}) {
                $conflict = 1;
                last;
            }
        }
        next if $conflict;

        # Place
        $col_used->[$c]{$v} = 1;
        $box_used->[$_][ $region_maps->[$_][$r][$c] ]{$v} = 1 for 0 .. $#$regions;
        push @$assigned, [$r, $c, $v];

        my @rest = (@{$vals}[0..$vi-1], @{$vals}[$vi+1..$#$vals]);
        if (_fill_box($cells, \@rest, $idx+1, $assigned,
                      $col_used, $box_used, $regions, $region_maps)) {
            return 1;
        }

        # Undo
        pop @$assigned;
        $col_used->[$c]{$v} = 0;
        $box_used->[$_][ $region_maps->[$_][$r][$c] ]{$v} = 0 for 0 .. $#$regions;
    }

    return 0;
}

sub _build_region_map {
    my ($N, $br, $bc) = @_;
    my $boxes_across = $N / $bc;
    my @map;
    for my $r (0 .. $N-1) {
        for my $c (0 .. $N-1) {
            $map[$r][$c] = int($r / $br) * $boxes_across + int($c / $bc);
        }
    }
    return \@map;
}

1;

__END__

=head1 REGION SPECIFICATIONS

Each region spec C<[R, C]> describes a uniform tiling of the NxN grid by RxC
rectangles.  N must equal R*C.

Rows and columns are just special cases:

  [1, N]  — each row is a single 1xN strip (row latin constraint)
  [N, 1]  — each column is a single Nx1 strip (column latin constraint)

=head1 ALGORITHM

Solving is a two-phase process:

=over 4

=item 1. B<Pre-fill>

A lightweight random backtracker fills C<prefill_boxes> random boxes of the
first region (default: N/2), checking all regional constraints simultaneously.
If it gets stuck (a box has no valid placement given the earlier choices) it
signals failure and the whole attempt is retried from scratch.

=item 2. B<DLX exact cover>

Pinned cells are injected into the DLX matrix with only one candidate row
(their forced value), so DLX trivially selects them at zero search cost.
Unpinned cells get the usual shuffled set of N candidates.  DLX then only
needs to search the remaining free cells.

=item 3. B<Retry loop>

If DLX finds no solution for the given prefill (the randomly chosen boxes
were individually consistent but globally unsatisfiable), the whole attempt —
prefill and DLX — is retried with a fresh random assignment.  Up to
C<max_attempts> tries are made (default: 200) before giving up.

=back

=head1 DEPENDENCIES

L<Algorithm::DLX>, L<List::Util>

=head1 AUTHOR

James Hammer

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
