use v5.40;
use feature 'class';
no warnings 'experimental';

class Polyomino::Tiler 0.05;

use List::Util   qw(shuffle min);
use Scalar::Util qw(looks_like_number);
use Algorithm::DLX;

=head1 NAME

Polyomino::Tiler - Partition an NxM grid into polyominoes using Dancing Links

=head1 SYNOPSIS

    use Polyomino::Tiler;

    # Uniform: 6x6 grid tiled entirely with triominoes
    my $tiler = Polyomino::Tiler->new(n => 6, m => 6, k => 3);

    # Explicit piece list
    my $tiler = Polyomino::Tiler->new(n => 4, m => 5, pieces => [3,3,4,4,2]);

    my @solutions = $tiler->solve();          # all solutions
    my @solutions = $tiler->solve(10);        # up to 10 solutions
    my @solutions = $tiler->solve_random();   # one random solution
    my @solutions = $tiler->solve_random(5);  # up to 5 random solutions

=head1 DESCRIPTION

Tiles an NxM rectangular grid with a prescribed multiset of free polyominoes
using Knuth's Algorithm X / Dancing Links via L<Algorithm::DLX>.

Each solution is an arrayref of pieces, where each piece is an arrayref of
C<[$row, $col]> pairs (0-indexed).

=cut

field $n        :param;
field $m        :param = undef;
field $_pieces  :param(pieces) = undef;
field $k        :param = undef;
field $_area;
field $_piece_list;

ADJUST {
    croak_tiler("n is required") unless defined $n;
    croak_tiler("n must be a positive integer")
        unless looks_like_number($n) && $n >= 1 && int($n) == $n;

    $m //= $n;
    croak_tiler("m must be a positive integer")
        unless looks_like_number($m) && $m >= 1 && int($m) == $m;

    $_area = $n * $m;

    if (defined $k && defined $_pieces) {
        croak_tiler("specify exactly one of 'k' or 'pieces', not both");
    }
    elsif (defined $k) {
        croak_tiler("k must be a positive integer")
            unless looks_like_number($k) && $k >= 1 && int($k) == $k;
        croak_tiler("k ($k) cannot exceed n*m ($_area)") if $k > $_area;
        croak_tiler("k ($k) must divide n*m ($_area)")   if $_area % $k != 0;
        $_piece_list = [($k) x ($_area / $k)];
    }
    elsif (defined $_pieces) {
        croak_tiler("pieces must be a non-empty arrayref")
            unless ref $_pieces eq 'ARRAY' && @$_pieces;
        for my $sz (@$_pieces) {
            croak_tiler("each piece size must be a positive integer")
                unless looks_like_number($sz) && $sz >= 1 && int($sz) == $sz;
            croak_tiler("piece size $sz cannot exceed n*m ($_area)") if $sz > $_area;
        }
        my $total = 0;
        $total += $_ for @$_pieces;
        if ($total != $_area) {
            croak_tiler(sprintf(
                "piece sizes sum to %d but n*m = %d (off by %+d). %s",
                $total, $_area, $_area - $total, _suggest_fill($_pieces, $_area)
            ));
        }
        $_piece_list = [@$_pieces];
    }
    else {
        croak_tiler("either 'k' or 'pieces' is required");
    }
}

# Consistent error prefix for all constructor failures
sub croak_tiler {
    require Carp;
    Carp::croak("Polyomino::Tiler: $_[0]");
}

=head1 METHODS

=head2 n, m, pieces

Read-only accessors.

=cut

method n()      { $n }
method m()      { $m }
method pieces() { $_piece_list }

=head2 suggest_pieces(n => $n, m => $m, must => \@sizes, fill => $fill_k)

Class method. Returns an arrayref of piece sizes that exactly fills the NxM
grid: the C<must> sizes come first, then as many C<fill>-sized pieces as needed
to cover the remainder.

Dies if the remainder is not divisible by C<fill>, or if the C<must> pieces
already exceed the grid area.

=cut

sub suggest_pieces {
    my ($class, %args) = @_;
    my $n    = $args{n}    // croak_tiler("suggest_pieces: n is required");
    my $m    = $args{m}    // $n;
    my $must = $args{must} // [];
    my $fill = $args{fill} // croak_tiler("suggest_pieces: fill is required");

    croak_tiler("fill must be a positive integer")
        unless looks_like_number($fill) && $fill >= 1 && int($fill) == $fill;

    my $area  = $n * $m;
    my $taken = 0;
    $taken += $_ for @$must;

    my $remainder = $area - $taken;
    croak_tiler("the 'must' pieces already exceed the grid area ($taken > $area)")
        if $remainder < 0;
    croak_tiler(
        "remainder ($remainder cells) is not divisible by fill size $fill. "
        . _suggest_fill($must, $area)
    ) if $remainder % $fill != 0;

    return [@$must, ($fill) x ($remainder / $fill)];
}

=head2 solve( [$limit] )

Return distinct tilings as a list. With no argument, returns all tilings.
With C<$limit>, stops after at most C<$limit> solutions (genuine early exit
via Dancing Links).

B<Warning:> the number of tilings grows very fast. Without a limit this is
practical only for small grids or highly constrained piece sets. Use
C<solve_random()> for large grids.

=cut

method solve ($limit = undef) {
    if (defined $limit) {
        croak_tiler("solve: limit must be a positive integer")
            unless looks_like_number($limit) && $limit >= 1 && int($limit) == $limit;
    }
    return $self->_run_dlx($self->_all_placements(), $limit);
}

=head2 solve_random( [$count] )

Shuffle placement candidates before solving and return up to C<$count>
tilings (default 1). Produces a uniformly random-looking result.

=cut

method solve_random ($count = 1) {
    croak_tiler("solve_random: count must be a positive integer")
        unless looks_like_number($count) && $count >= 1 && int($count) == $count;
    return $self->_run_dlx($self->_all_placements(shuffle => 1), $count);
}

=head2 free_polyominoes_of($k)

Return an arrayref of all distinct free k-ominoes (up to rotation and
reflection), in canonical form. Results are memoized across calls within the
same process.

Counts match OEIS A000105: 1, 1, 2, 5, 12, 35, ...

=cut

my %_poly_cache;

method free_polyominoes_of ($k) {
    $_poly_cache{$k} //= _generate_polyominoes($k);
    return $_poly_cache{$k};
}

# ── Private helpers ───────────────────────────────────────────────────────────
#
# All private subs use old-style @_ unpacking (no sub-signature syntax).
# This avoids the `map { BLOCK } @$ref` parser ambiguity that affects Perl
# with `use feature 'signatures'` in scope through at least Perl 5.41.

sub _suggest_fill {
    my ($pieces, $area) = @_;
    my $total = 0;
    $total += $_ for @$pieces;
    my $diff = $area - $total;
    if ($diff > 0) {
        my @opts = grep { $diff % $_ == 0 } 1 .. $diff;
        return "The grid has $diff unfilled cells. "
             . "Add: " . join('; or ', map { ($diff/$_) . " piece(s) of size $_" } @opts) . ".";
    }
    return "The pieces overflow the grid by " . abs($diff) . " cells.";
}

# Recursively generate all free polyominoes of size $size.
# Uses a canonical-form + symmetry-group deduplication approach.
sub _generate_polyominoes {
    my ($size) = @_;
    return [[[0, 0]]] if $size == 1;

    my @prev = @{ _generate_polyominoes($size - 1) };
    my (%seen, @result);

    for my $poly (@prev) {
        my %in;
        for my $cell (@$poly) { $in{"$cell->[0],$cell->[1]"} = 1 }

        # Candidate expansions: all cells adjacent to the current piece
        my %cands;
        for my $cell (@$poly) {
            for my $d ([-1,0],[1,0],[0,-1],[0,1]) {
                my ($nr, $nc) = ($cell->[0]+$d->[0], $cell->[1]+$d->[1]);
                $cands{"$nr,$nc"} = [$nr, $nc] unless $in{"$nr,$nc"};
            }
        }

        for my $cand (values %cands) {
            my $np       = _canonicalize(@$poly, $cand);
            # Canonical key under all 8 symmetries (4 rotations x 2 reflections)
            my $free_key = (sort map { _poly_key(_apply_transform($np, $_)) } _transforms())[0];
            push @result, $np unless $seen{$free_key}++;
        }
    }
    return \@result;
}

# The 8 symmetry transforms of the dihedral group D4
sub _transforms {
    return (
        sub { [ $_[0],  $_[1]] }, sub { [-$_[1],  $_[0]] },
        sub { [-$_[0], -$_[1]] }, sub { [ $_[1], -$_[0]] },
        sub { [-$_[0],  $_[1]] }, sub { [ $_[1],  $_[0]] },
        sub { [ $_[0], -$_[1]] }, sub { [-$_[1], -$_[0]] },
    );
}

# Normalize a list of [r,c] cells to 0-origin, sorted
sub _canonicalize {
    my @cells = @_;
    my ($min_r, $min_c) = ($cells[0][0], $cells[0][1]);
    for my $cell (@cells) {
        $min_r = $cell->[0] if $cell->[0] < $min_r;
        $min_c = $cell->[1] if $cell->[1] < $min_c;
    }
    return [
        sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] }
        map  { [$_->[0]-$min_r, $_->[1]-$min_c] } @cells
    ];
}

sub _poly_key {
    my ($poly) = @_;
    return join ',', map { "$_->[0]:$_->[1]" } @$poly;
}

sub _apply_transform {
    my ($poly, $t) = @_;
    return _canonicalize(map { $t->($_->[0], $_->[1]) } @$poly);
}

# All distinct orientations of a polyomino (up to 8, deduped for symmetric shapes)
sub _orientations {
    my ($poly) = @_;
    my %seen;
    return grep { !$seen{_poly_key($_)}++ }
           map  { _apply_transform($poly, $_) } _transforms();
}

# Build the full placement list: every (polyomino shape, orientation, position)
# triple that fits within the n*m grid.
method _all_placements (%opts) {
    my %needed;
    $needed{$_}++ for @$_piece_list;

    my @placements;
    for my $sz (keys %needed) {
        for my $poly (@{ $self->free_polyominoes_of($sz) }) {
            for my $ori (_orientations($poly)) {
                my ($max_r, $max_c) = (0, 0);
                for my $cell (@$ori) {
                    $max_r = $cell->[0] if $cell->[0] > $max_r;
                    $max_c = $cell->[1] if $cell->[1] > $max_c;
                }
                for my $dr (0 .. $n-1-$max_r) {
                    for my $dc (0 .. $m-1-$max_c) {
                        push @placements, {
                            size  => $sz,
                            cells => [map { [$_->[0]+$dr, $_->[1]+$dc] } @$ori],
                        };
                    }
                }
            }
        }
    }

    @placements = shuffle @placements if $opts{shuffle};
    return \@placements;
}

# Run Dancing Links on the placement list and collect valid solutions.
#
# DLX enforces "every cell covered exactly once" via the cell columns, but does
# NOT enforce piece-count constraints — those are handled by the post-filter
# below. The piece-count filter is necessary because DLX may select placements
# that collectively cover all cells but use the wrong multiset of piece sizes
# (e.g. two triominoes instead of one domino + one tetromino).
method _run_dlx ($placements, $limit) {
    my %required;
    $required{$_}++ for @$_piece_list;

    my $dlx = Algorithm::DLX->new();
    my %cell_col;
    for my $r (0 .. $n-1) {
        for my $c (0 .. $m-1) {
            $cell_col{"$r,$c"} = $dlx->add_column("$r,$c");
        }
    }
    for my $id (0 .. $#$placements) {
        $dlx->add_row("r$id",
            map { $cell_col{"$_->[0],$_->[1]"} } @{ $placements->[$id]{cells} });
    }

    my $raw = defined $limit
        ? $dlx->solve(number_of_solutions => $limit)
        : $dlx->solve();

    my (%seen, @solutions);
    for my $raw_sol (@$raw) {
        my (@pieces, %got);
        for my $label (@$raw_sol) {
            (my $id = $label) =~ s/^r//;
            my $p = $placements->[$id];
            $got{$p->{size}}++;
            push @pieces, $p->{cells};
        }

        # Reject if the multiset of piece sizes doesn't match the request
        next if grep { ($got{$_} // 0) != $required{$_} } keys %required;

        # Deduplicate (DLX can return the same tiling labelled in different row orders)
        my $key = join '|',
            sort map {
                join ',', map { "$_->[0]:$_->[1]" }
                sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @$_
            } @pieces;
        next if $seen{$key}++;

        push @solutions,
            [sort { $a->[0][0] <=> $b->[0][0] || $a->[0][1] <=> $b->[0][1] } @pieces];
        last if defined $limit && @solutions >= $limit;
    }
    return @solutions;
}

1;

=head1 AUTHOR

James Hammer

=head1 LICENSE

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
