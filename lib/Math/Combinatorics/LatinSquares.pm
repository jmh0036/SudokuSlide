use v5.40;
use feature 'class';
no warnings 'experimental';

class Math::Combinatorics::LatinSquares 0.05;

use Algorithm::DLX;
use List::Util qw(shuffle min);
use Carp       qw(croak);

=head1 NAME

Math::Combinatorics::LatinSquares - Latin squares with simultaneous rectangular
regional constraints

=head1 SYNOPSIS

    use Math::Combinatorics::LatinSquares;

    my $ls = Math::Combinatorics::LatinSquares->new(regions => [[3, 3]]);

    my $grids = $ls->solve;                               # one random solution
    my $grids = $ls->solve(number_of_solutions => 5);     # up to 5 solutions
    my $grids = $ls->solve(number_of_solutions => undef); # all solutions

=head1 DESCRIPTION

A B<latin square> is an NxN grid where each of N symbols appears exactly once
in every row and every column.

This module adds one or more I<rectangular regional> constraints: each region
spec C<[R, C]> tiles the NxN grid with RxC rectangles, each of which must also
contain every symbol exactly once. Multiple specs are enforced simultaneously.

Row and column uniqueness are I<not> assumed; add C<[1, N]> and C<[N, 1]>
explicitly if you want standard sudoku row/column constraints.

=head1 CONSTRUCTOR

=head2 new(regions => \@specs)

C<@specs> is a list of C<[box_rows, box_cols]> pairs. Every pair must have the
same product (= N). N must be at least 2.

=cut

field $regions     :param;
field $_N;
field $_region_maps;

ADJUST {
    croak "regions must be a non-empty arrayref"
        unless ref $regions eq 'ARRAY' && @$regions;

    my ($N, @validated);
    for my $spec (@$regions) {
        croak "each region spec must be an arrayref of two positive integers"
            unless ref $spec eq 'ARRAY' && @$spec == 2
                && $spec->[0] >= 1 && $spec->[1] >= 1;

        my ($br, $bc) = @$spec;
        my $prod = $br * $bc;
        croak "region [$br,$bc]: product $prod must be >= 2" if $prod < 2;

        if (defined $N) {
            croak "region [$br,$bc]: product $prod != $N "
                . "(all regions must have the same product N)"
                unless $prod == $N;
        }
        else {
            $N = $prod;
        }

        croak "grid size $N must be divisible by box_rows $br" if $N % $br;
        croak "grid size $N must be divisible by box_cols $bc" if $N % $bc;
        push @validated, [$br, $bc];
    }

    $_N           = $N;
    $regions      = \@validated;
    $_region_maps = [map { _build_region_map($N, $_->[0], $_->[1]) } @validated];
}

=head1 METHODS

=head2 n

Returns N, the grid side length.

=cut

method n() { $_N }

=head2 regions

Returns the validated arrayref of C<[box_rows, box_cols]> region specs.

=cut

method regions() { $regions }

=head2 region_maps

Returns an arrayref of region maps (one per spec). Each map is a 2D arrayref
where C<$map->[$r][$c]> gives the 0-based box index for cell (r, c).

=cut

method region_maps() { $_region_maps }

=head2 solve(%opts)

Generate solutions using a random pre-fill followed by L<Algorithm::DLX>.

Options:

=over 4

=item C<number_of_solutions> — how many solutions to return (default: 1;
C<undef> = return all solutions, which may be very many)

=item C<prefill_boxes> — number of boxes from the first region to pre-fill
before handing off to DLX (default: floor(N/2); 0 disables pre-filling)

=item C<max_attempts> — how many times to retry if a pre-fill leads to no
DLX solution (default: 200)

=back

Returns an arrayref of 2D grid arrayrefs, where C<$grid->[$r][$c]> is the
value (1..N) at cell (r, c).

Returns an empty arrayref if no solution is found within C<max_attempts>.

=cut

method solve (%opts) {
    my $num_solutions = exists $opts{number_of_solutions}
        ? $opts{number_of_solutions} : 1;
    my $prefill_boxes = exists $opts{prefill_boxes}
        ? $opts{prefill_boxes} : int($_N / 2);
    my $max_attempts  = $opts{max_attempts} // 200;

    # Clamp prefill_boxes to [0, N] to guard against oversized values
    $prefill_boxes = min($prefill_boxes, $_N);
    $prefill_boxes = 0 if $prefill_boxes < 0;

    for my $attempt (1 .. $max_attempts) {
        my %pinned;
        if ($prefill_boxes > 0) {
            my @placements = _prefill($_N, $regions, $_region_maps, $prefill_boxes);
            next unless @placements;
            $pinned{"$_->[0],$_->[1]"} = $_->[2] for @placements;
        }

        my $dlx = Algorithm::DLX->new();
        my %col;

        for my $r (0 .. $_N-1) {
            for my $c (0 .. $_N-1) {
                $col{"cell_${r}_${c}"} = $dlx->add_column("cell_${r}_${c}");
            }
        }
        for my $t (0 .. $#$regions) {
            for my $k (0 .. $_N-1) {
                for my $v (1 .. $_N) {
                    $col{"t${t}_box${k}_v${v}"} = $dlx->add_column("t${t}_box${k}_v${v}");
                }
            }
        }

        # Pinned cells get exactly one candidate (their fixed value) so DLX
        # accepts them at zero search cost; unpinned cells get shuffled candidates
        # to produce different solutions on repeated calls.
        my @candidates;
        for my $r (0 .. $_N-1) {
            for my $c (0 .. $_N-1) {
                if (exists $pinned{"$r,$c"}) {
                    push @candidates, [$r, $c, $pinned{"$r,$c"}];
                }
                else {
                    push @candidates, map { [$r, $c, $_] } shuffle(1 .. $_N);
                }
            }
        }

        for my $p (@candidates) {
            my ($r, $c, $v) = @$p;
            my @cols = ($col{"cell_${r}_${c}"});
            for my $t (0 .. $#$regions) {
                my $k = $_region_maps->[$t][$r][$c];
                push @cols, $col{"t${t}_box${k}_v${v}"};
            }
            $dlx->add_row("${r},${c},${v}", @cols);
        }

        my %dlx_opts;
        $dlx_opts{number_of_solutions} = $num_solutions if defined $num_solutions;
        my $solutions = $dlx->solve(%dlx_opts);
        next unless $solutions && @$solutions;

        return [map {
            my @grid;
            for my $row_label (@$_) {
                my ($r, $c, $v) = split /,/, $row_label;
                $grid[$r][$c] = $v;
            }
            \@grid;
        } @$solutions];
    }

    return [];
}

=head2 print_grid($grid, %opts)

Print a completed grid to a filehandle (default: STDOUT), one row per line,
values space-separated and right-justified.

=cut

method print_grid ($grid, %opts) {
    my $fh = $opts{fh} // \*STDOUT;
    my $w  = length($_N);
    for my $r (0 .. $_N-1) {
        say $fh join(' ', map { sprintf("%${w}d", $grid->[$r][$_]) } 0 .. $_N-1);
    }
}

=head2 print_region_map($t, %opts)

Print the box-assignment map for region index C<$t> to a filehandle (default:
STDOUT). Boxes are labelled A-Z, a-z, 0-9 (up to 62 boxes).

=cut

method print_region_map ($t, %opts) {
    my $fh     = $opts{fh} // \*STDOUT;
    my $map    = $_region_maps->[$t];
    my @labels = ('A'..'Z', 'a'..'z', '0'..'9');
    for my $r (0 .. $_N-1) {
        say $fh join(' ', map { $labels[$map->[$r][$_]] // '?' } 0 .. $_N-1);
    }
}

# ── Private helpers ───────────────────────────────────────────────────────────
#
# All private subs use old-style @_ unpacking (no sub-signature syntax).
# This avoids the `map { BLOCK } @$ref` parser ambiguity that affects Perl
# with `use feature 'signatures'` in scope through at least Perl 5.41.

# Build the box-index map for a single region spec.
# box_index = floor(r/br) * boxes_across + floor(c/bc)
sub _build_region_map {
    my ($N, $br, $bc) = @_;
    my $boxes_across = $N / $bc;
    my @map;
    for my $r (0 .. $N-1) {
        for my $c (0 .. $N-1) {
            $map[$r][$c] = int($r/$br) * $boxes_across + int($c/$bc);
        }
    }
    return \@map;
}

# Randomly pre-fill $num_boxes boxes of the first region with valid values,
# checking all regional constraints simultaneously.
# Returns a list of [$r, $c, $value] triples, or an empty list on failure.
sub _prefill {
    my ($N, $regions, $region_maps, $num_boxes) = @_;

    my $primary_map = $region_maps->[0];
    my @box_cells;
    for my $r (0 .. $N-1) {
        for my $c (0 .. $N-1) {
            push @{ $box_cells[$primary_map->[$r][$c]] }, [$r, $c];
        }
    }

    # num_boxes is already clamped to [0, N] by the caller
    my @box_order = (shuffle 0 .. $N-1)[0 .. $num_boxes-1];

    my (@col_used, @box_used, @all_placements);
    for my $k (@box_order) {
        my @cells    = @{ $box_cells[$k] };
        my @vals     = shuffle 1 .. $N;
        my @assigned;
        return () unless _fill_box(\@cells, \@vals, 0, \@assigned,
                                   \@col_used, \@box_used,
                                   $regions, $region_maps);
        push @all_placements, @assigned;
    }
    return @all_placements;
}

# Recursive backtracker: assign values to cells[idx..end] using values from
# @vals, respecting column-uniqueness and all regional constraints.
sub _fill_box {
    my ($cells, $vals, $idx, $assigned, $col_used, $box_used, $regions, $region_maps) = @_;
    return 1 if $idx == scalar @$cells;

    my ($r, $c) = @{ $cells->[$idx] };

    for my $vi (0 .. $#$vals) {
        my $v = $vals->[$vi];
        next if $col_used->[$c]{$v};
        next if grep { $box_used->[$_][$region_maps->[$_][$r][$c]]{$v} } 0 .. $#$regions;

        $col_used->[$c]{$v} = 1;
        $box_used->[$_][$region_maps->[$_][$r][$c]]{$v} = 1 for 0 .. $#$regions;
        push @$assigned, [$r, $c, $v];

        my @rest = (@{$vals}[0..$vi-1], @{$vals}[$vi+1..$#$vals]);
        if (_fill_box($cells, \@rest, $idx+1, $assigned,
                      $col_used, $box_used, $regions, $region_maps)) {
            return 1;
        }

        pop @$assigned;
        $col_used->[$c]{$v} = 0;
        $box_used->[$_][$region_maps->[$_][$r][$c]]{$v} = 0 for 0 .. $#$regions;
    }
    return 0;
}

1;

__END__

=head1 ALGORITHM

=over 4

=item 1. B<Pre-fill> — a lightweight random backtracker fills C<prefill_boxes>
randomly chosen boxes from the first region, checking all constraints
simultaneously. This seeds the search space cheaply.

=item 2. B<DLX exact cover> — pinned cells (from pre-fill) are given only one
candidate row so Dancing Links accepts them at zero search cost. Unpinned cells
get shuffled value candidates, producing different solutions on repeated calls.

=item 3. B<Retry loop> — if DLX finds no solution for a given pre-fill,
the whole attempt retries (up to C<max_attempts> times). Failure is extremely
rare for well-constrained problems.

=back

=head1 AUTHOR

James Hammer

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
