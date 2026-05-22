package Polyomino::Tiler;

use strict;
use warnings;
use List::Util qw(shuffle);
use Algorithm::DLX;

our $VERSION = '0.03';

=head1 NAME

Polyomino::Tiler - Partition an N×M grid into polyominoes using Dancing Links

=head1 SYNOPSIS

    use Polyomino::Tiler;

    # Uniform: 6×6 grid tiled entirely with triominoes
    my $tiler = Polyomino::Tiler->new(n => 6, m => 6, pieces => [3,3,3,3,3,3]);

    # Shorthand for uniform tiling (k divides n*m)
    my $tiler = Polyomino::Tiler->new(n => 6, m => 6, k => 3);

    # Mixed: 4×5 grid with two triominoes and two tetrominoes and one domino
    my $tiler = Polyomino::Tiler->new(n => 4, m => 5, pieces => [3,3,4,4,2]);

    # Suggest a valid piece list (fills remainder with a given size)
    my $pieces = Polyomino::Tiler->suggest_pieces(
        n    => 4, m => 5,
        must => [3, 5],   # must include one of each of these
        fill => 4,        # pad remainder with 4-ominoes if possible
    );

    my @solutions = $tiler->solve();          # all solutions
    my @solutions = $tiler->solve(10);        # up to 10 solutions (stops early)
    my @solutions = $tiler->solve_random();   # one random solution
    my @solutions = $tiler->solve_random(5);  # up to 5 random solutions

=head1 DESCRIPTION

Tiles an n×m rectangular grid with a prescribed multiset of free polyominoes
using Knuth's Algorithm X / Dancing Links via L<Algorithm::DLX>.

Each solution is returned as an arrayref of pieces, where each piece is an
arrayref of C<[$row, $col]> pairs (0-indexed).

=cut

# ── Constructor ────────────────────────────────────────────────────────────

=head1 METHODS

=head2 new(n => $n, m => $m, pieces => \@sizes)

=head2 new(n => $n, m => $m, k => $k)

Construct a tiler. C<pieces> is an arrayref of piece sizes (e.g. C<[3,3,4]>)
whose sum must equal C<n*m>. C<k> is a shorthand: it fills the grid uniformly
with pieces of size C<k> (equivalent to passing C<[(k) x (n*m/k)]>).

Dies with an informative message on invalid input.

=cut

sub new {
    my ( $class, %args ) = @_;

    my $n = $args{n} // die "n is required\n";
    my $m = $args{m} // $n;                     # default to square if m omitted

    die "n must be a positive integer\n" unless $n =~ /^\d+$/ && $n >= 1;
    die "m must be a positive integer\n" unless $m =~ /^\d+$/ && $m >= 1;

    my $area = $n * $m;
    my @pieces;

    if ( exists $args{k} ) {
        my $k = $args{k};
        die "k must be a positive integer\n" unless $k =~ /^\d+$/ && $k >= 1;
        die "k ($k) cannot exceed n*m ($area)\n" if $k > $area;
        die "k ($k) must divide n*m ($area)\n"   if $area % $k != 0;
        @pieces = ($k) x ( $area / $k );
    }
    elsif ( exists $args{pieces} ) {
        @pieces = @{ $args{pieces} };
        die "pieces must be a non-empty arrayref\n" unless @pieces;
        for my $k (@pieces) {
            die "each piece size must be a positive integer\n"
              unless $k =~ /^\d+$/ && $k >= 1;
            die "piece size $k cannot exceed n*m ($area)\n" if $k > $area;
        }
        my $total = 0;
        $total += $_ for @pieces;
        if ( $total != $area ) {
            my $diff       = $area - $total;
            my $suggestion = _suggest_fill( \@pieces, $area );
            die
              sprintf( "piece sizes sum to %d but n*m = %d (off by %+d).\n%s\n",
                $total, $area, $diff, $suggestion );
        }
    }
    else {
        die "either 'k' or 'pieces' is required\n";
    }

    my $self = bless { n => $n, m => $m, pieces => \@pieces }, $class;
    return $self;
}

# Build a human-readable suggestion string when the pieces don't sum to area.
sub _suggest_fill {
    my ( $pieces, $area ) = @_;
    my $total = 0;
    $total += $_ for @$pieces;
    my $diff = $area - $total;

    my @suggestions;

    if ( $diff > 0 ) {
        push @suggestions, "The grid has $diff unfilled cells.";

        # Suggest fill sizes that divide the remainder
        my @divs = grep { $diff % $_ == 0 } ( 1 .. $diff );
        if (@divs) {
            my @opts;
            for my $d (@divs) {
                my $count = $diff / $d;
                push @opts, "$count piece(s) of size $d";
            }
            push @suggestions,
              "To fill exactly, add one of: " . join( '; or ', @opts ) . ".";
        }
    }
    elsif ( $diff < 0 ) {
        push @suggestions,
          "The pieces overflow the grid by " . abs($diff) . " cells.";
        push @suggestions,
            "Remove pieces totalling "
          . abs($diff)
          . " cells, or use a larger grid.";
    }

    return join( "\n", @suggestions );
}

=head2 suggest_pieces(n => $n, m => $m, must => \@sizes, fill => $fill_k)

Class method. Given a grid and a list of required piece sizes (C<must>),
returns an arrayref of piece sizes that exactly fills the grid by appending
as many C<fill>-sized pieces as needed.

Dies if the remainder is not divisible by C<fill>, with alternatives suggested.

=cut

sub suggest_pieces {
    my ( $class, %args ) = @_;
    my $n    = $args{n}    // die "n is required\n";
    my $m    = $args{m}    // $n;
    my $must = $args{must} // [];
    my $fill = $args{fill} // die "fill is required\n";

    die "fill must be a positive integer\n"
      unless $fill =~ /^\d+$/ && $fill >= 1;

    my $area  = $n * $m;
    my $taken = 0;
    $taken += $_ for @$must;

    my $remainder = $area - $taken;
    if ( $remainder < 0 ) {
        die
          "The 'must' pieces already exceed the grid area ($taken > $area).\n";
    }
    if ( $remainder % $fill != 0 ) {
        my $suggestion = _suggest_fill( $must, $area );
        die
"Remainder ($remainder cells) is not divisible by fill size $fill.\n$suggestion\n";
    }

    my @result = ( @$must, ($fill) x ( $remainder / $fill ) );
    return \@result;
}

=head2 n, m, pieces

Accessors.

=cut

sub n      { $_[0]->{n} }
sub m      { $_[0]->{m} }
sub pieces { $_[0]->{pieces} }

# ── Public solve methods ───────────────────────────────────────────────────

=head2 solve( [$limit] )

Return distinct tilings as a list of solutions. Each solution is an
arrayref of pieces; each piece is an arrayref of C<[$row, $col]> pairs.

With no argument, returns all solutions. With a positive integer C<$limit>,
DLX stops as soon as it has found C<$limit> solutions — genuinely faster
than finding everything when the total count is much larger than C<$limit>.

B<Warning>: the number of tilings grows extremely fast with grid size and
small piece sizes. Without a limit this is practical only for small grids
(roughly up to 6×6 with triominoes, or where you expect at most a few
thousand solutions). For large grids use C<solve_random()> or pass a limit.

=cut

sub solve {
    my ( $self, $limit ) = @_;
    if ( defined $limit ) {
        die "solve limit must be a positive integer\n"
          unless $limit =~ /^\d+$/ && $limit >= 1;
    }
    my $placements = $self->_all_placements();
    return $self->_run_dlx( $placements, $limit );
}

=head2 solve_random( [$count] )

Shuffle the placement candidates and return up to C<$count> tilings (default
1). Because DLX stops as soon as it has enough solutions, this is fast even
for large grids. Always returns a (possibly empty) list.

For mixed-piece problems the DLX result is filtered by piece-size multiset
after solving. In the rare case that none of the returned raw solutions pass
that filter (which can happen when C<number_of_solutions> caps the search
before a valid multiset arrangement is found), the caller should retry.
C<solve_random> itself does not retry so that callers retain control over
timeout and attempt budgets.

=cut

sub solve_random {
    my ( $self, $count ) = @_;
    $count //= 1;
    die "solve_random count must be a positive integer\n"
      unless $count =~ /^\d+$/ && $count >= 1;

    my $placements = $self->_all_placements( shuffle => 1 );
    return $self->_run_dlx( $placements, $count );
}

# ── Polyomino generation ───────────────────────────────────────────────────

=head2 free_polyominoes_of($k)

Return an arrayref of all free k-ominoes (up to rotation and reflection).
Results are memoized across calls.

=cut

{
    my %_cache;

    sub free_polyominoes_of {
        my ( $self_or_class, $k ) = @_;
        $_cache{$k} //= _generate_polyominoes($k);
        return $_cache{$k};
    }
}

# Recursively build all free polyominoes of a given size.
sub _generate_polyominoes {
    my ($size) = @_;
    return [ [ [ 0, 0 ] ] ] if $size == 1;

    my @prev = @{ _generate_polyominoes( $size - 1 ) };
    my %seen;
    my @result;

    for my $poly (@prev) {
        my %in_poly;
        for my $cell (@$poly) {
            $in_poly{"$cell->[0],$cell->[1]"} = 1;
        }
        my %candidates;
        for my $cell (@$poly) {
            for my $d ( [ -1, 0 ], [ 1, 0 ], [ 0, -1 ], [ 0, 1 ] ) {
                my $nr = $cell->[0] + $d->[0];
                my $nc = $cell->[1] + $d->[1];
                next if $in_poly{"$nr,$nc"};
                $candidates{"$nr,$nc"} = [ $nr, $nc ];
            }
        }
        for my $cand ( values %candidates ) {
            my $new_poly = _canonicalize( @$poly, $cand );
            my @ori_keys;
            for my $ori ( _orientations($new_poly) ) {
                push @ori_keys, _poly_key($ori);
            }
            my $free_key = ( sort @ori_keys )[0];
            unless ( $seen{$free_key}++ ) {
                push @result, $new_poly;
            }
        }
    }
    return \@result;
}

# ── Orientation / canonicalization helpers ─────────────────────────────────

sub _canonicalize {
    my @cells = @_;
    my ( $min_r, $min_c ) = ( $cells[0][0], $cells[0][1] );
    for my $cell (@cells) {
        $min_r = $cell->[0] if $cell->[0] < $min_r;
        $min_c = $cell->[1] if $cell->[1] < $min_c;
    }
    my @shifted;
    for my $cell (@cells) {
        push @shifted, [ $cell->[0] - $min_r, $cell->[1] - $min_c ];
    }
    my @sorted = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @shifted;
    return \@sorted;
}

sub _poly_key {
    my ($poly) = @_;
    my @parts;
    for my $cell (@$poly) {
        push @parts, "$cell->[0]:$cell->[1]";
    }
    return join( ',', @parts );
}

sub _apply_transform {
    my ( $poly, $t ) = @_;
    my @transformed;
    for my $cell (@$poly) {
        push @transformed, $t->( $cell->[0], $cell->[1] );
    }
    return _canonicalize(@transformed);
}

sub _orientations {
    my ($poly) = @_;
    my @transforms = (
        sub { [ $_[0],  $_[1] ] },
        sub { [ -$_[1], $_[0] ] },
        sub { [ -$_[0], -$_[1] ] },
        sub { [ $_[1],  -$_[0] ] },
        sub { [ -$_[0], $_[1] ] },
        sub { [ $_[1],  $_[0] ] },
        sub { [ $_[0],  -$_[1] ] },
        sub { [ -$_[1], -$_[0] ] },
    );
    my %seen;
    my @results;
    for my $t (@transforms) {
        my $canon = _apply_transform( $poly, $t );
        my $key   = _poly_key($canon);
        unless ( $seen{$key}++ ) {
            push @results, $canon;
        }
    }
    return @results;
}

# ── Placement enumeration ──────────────────────────────────────────────────

# Returns a flat list of placements, each a hashref {size=>$k, cells=>\@cells}.
# We enumerate placements for every distinct piece size in the multiset.
# Only one entry per distinct size is needed — DLX will pick the right count.
sub _all_placements {
    my ( $self, %opts ) = @_;
    my $n = $self->{n};
    my $m = $self->{m};

    # Collect the distinct sizes we need placements for
    my %needed_sizes;
    $needed_sizes{$_}++ for @{ $self->{pieces} };

    my @placements;
    for my $k ( keys %needed_sizes ) {
        for my $poly ( @{ $self->free_polyominoes_of($k) } ) {
            for my $ori ( _orientations($poly) ) {
                my ( $max_r, $max_c ) = ( 0, 0 );
                for my $cell (@$ori) {
                    $max_r = $cell->[0] if $cell->[0] > $max_r;
                    $max_c = $cell->[1] if $cell->[1] > $max_c;
                }
                for my $dr ( 0 .. $n - 1 - $max_r ) {
                    for my $dc ( 0 .. $m - 1 - $max_c ) {
                        my @placed;
                        for my $cell (@$ori) {
                            push @placed,
                              [ $cell->[0] + $dr, $cell->[1] + $dc ];
                        }
                        push @placements, { size => $k, cells => \@placed };
                    }
                }
            }
        }
    }

    @placements = shuffle @placements if $opts{shuffle};
    return \@placements;
}

# ── DLX solve ─────────────────────────────────────────────────────────────

# Model: columns = grid cells only. Each row covers k cell-columns.
# A solution from DLX is a set of placements covering every cell once.
# We then check that the multiset of piece sizes matches what was requested,
# discarding solutions that don't match (e.g. wrong counts of each size).
# Finally we deduplicate: two solutions that partition the grid identically
# (same set of cell-groups, regardless of piece ordering) are the same tiling.
#
# $limit: maximum number of solutions to return, or undef for all.
# DLX is told to stop at $limit (when defined), so this is a true early exit,
# not a post-hoc slice.
sub _run_dlx {
    my ( $self, $placements, $limit ) = @_;
    my $n = $self->{n};
    my $m = $self->{m};

    # Build the required size multiset for validation
    my %required;
    $required{$_}++ for @{ $self->{pieces} };

    my $dlx = Algorithm::DLX->new();

    my %cell_col;
    for my $r ( 0 .. $n - 1 ) {
        for my $c ( 0 .. $m - 1 ) {
            $cell_col{"$r,$c"} = $dlx->add_column("$r,$c");
        }
    }

    for my $id ( 0 .. $#$placements ) {
        my @cols;
        for my $cell ( @{ $placements->[$id]{cells} } ) {
            push @cols, $cell_col{"$cell->[0],$cell->[1]"};
        }
        $dlx->add_row( "r$id", @cols );
    }

    # When $limit is defined, tell DLX to stop early. For the unlimited case
    # we omit the parameter entirely so DLX uses its own default (all).
    my $raw_solutions =
      defined $limit
      ? $dlx->solve( number_of_solutions => $limit )
      : $dlx->solve();

    # Decode, validate multiset, deduplicate
    my %seen;
    my @solutions;

    for my $raw_sol (@$raw_solutions) {
        my @pieces;
        my %got;
        for my $label (@$raw_sol) {
            ( my $id = $label ) =~ s/^r//;
            my $p = $placements->[$id];
            $got{ $p->{size} }++;
            push @pieces, $p->{cells};
        }

        # Check size multiset matches requested
        my $match = 1;
        for my $k ( keys %required ) {
            $match = 0, last if ( $got{$k} // 0 ) != $required{$k};
        }
        next unless $match;

        # Deduplicate: canonical key = sorted list of sorted cell-lists
        my $key = join(
            '|',
            sort map {
                my @sorted_cells =
                  sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @$_;
                join( ',', map { "$_->[0]:$_->[1]" } @sorted_cells )
            } @pieces
        );
        next if $seen{$key}++;

        # Return pieces sorted by top-left cell for stable output
        my @sorted_pieces =
          sort { $a->[0][0] <=> $b->[0][0] || $a->[0][1] <=> $b->[0][1] }
          @pieces;
        push @solutions, \@sorted_pieces;

        # Stop once we have enough (guards against DLX returning more than
        # $limit after deduplication expands or collapses the raw count)
        last if defined $limit && @solutions >= $limit;
    }

    return @solutions;
}

1;

=head1 AUTHOR

James Hammer <DERHAMMER>

=head1 LICENSE

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
