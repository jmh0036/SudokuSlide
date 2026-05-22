use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";

use Polyomino::Tiler;

# ── Polyomino counts (OEIS A000105) ───────────────────────────────────────
my %expected_counts = ( 1 => 1, 2 => 1, 3 => 2, 4 => 5, 5 => 12 );

for my $k ( sort keys %expected_counts ) {
    my $tiler = Polyomino::Tiler->new( n => $k, m => $k, k => $k );
    my $polys = $tiler->free_polyominoes_of($k);
    is( scalar @$polys,
        $expected_counts{$k},
        "k=$k: correct free polyomino count ($expected_counts{$k})" );
}

# ── Canonical form: all coords >= 0 ───────────────────────────────────────
for my $k ( 1 .. 4 ) {
    my $tiler = Polyomino::Tiler->new( n => $k * 2, m => $k * 2, k => $k );
    for my $poly ( @{ $tiler->free_polyominoes_of($k) } ) {
        for my $cell (@$poly) {
            ok( $cell->[0] >= 0, "k=$k: row coord non-negative" );
            ok( $cell->[1] >= 0, "k=$k: col coord non-negative" );
        }
    }
}

# ── Cell count ────────────────────────────────────────────────────────────
for my $k ( 1 .. 5 ) {
    my $tiler = Polyomino::Tiler->new( n => $k * 2, m => $k * 2, k => $k );
    for my $poly ( @{ $tiler->free_polyominoes_of($k) } ) {
        is( scalar @$poly, $k, "k=$k: polyomino has exactly $k cells" );
    }
}

# ── Connectivity ──────────────────────────────────────────────────────────
sub is_connected {
    my ($poly) = @_;
    return 1 if @$poly == 1;
    my %cells;
    for my $cell (@$poly) { $cells{"$cell->[0],$cell->[1]"} = 1 }
    my @queue   = ( $poly->[0] );
    my %visited = ( "$poly->[0][0],$poly->[0][1]" => 1 );
    while (@queue) {
        my $cur = shift @queue;
        for my $d ( [ -1, 0 ], [ 1, 0 ], [ 0, -1 ], [ 0, 1 ] ) {
            my $nr  = $cur->[0] + $d->[0];
            my $nc  = $cur->[1] + $d->[1];
            my $key = "$nr,$nc";
            next unless $cells{$key} && !$visited{$key}++;
            push @queue, [ $nr, $nc ];
        }
    }
    return scalar keys %visited == scalar @$poly;
}

for my $k ( 1 .. 5 ) {
    my $tiler = Polyomino::Tiler->new( n => $k * 2, m => $k * 2, k => $k );
    for my $poly ( @{ $tiler->free_polyominoes_of($k) } ) {
        ok( is_connected($poly), "k=$k: polyomino is connected" );
    }
}

# ── Memoization: same ref returned for same k ─────────────────────────────
{
    my $tiler = Polyomino::Tiler->new( n => 4, m => 4, k => 2 );
    my $p1    = $tiler->free_polyominoes_of(2);
    my $p2    = $tiler->free_polyominoes_of(2);
    is( $p1, $p2, 'free_polyominoes_of: memoized (same ref returned)' );
}

# ── Constructor validation ─────────────────────────────────────────────────
eval { Polyomino::Tiler->new( n => 'abc', m => 4, k => 2 ) };
like( $@, qr/positive integer/, 'dies on non-integer n' );

eval { Polyomino::Tiler->new( n => 3, m => 3, k => 4 ) };
like( $@, qr/must divide/, 'dies when k does not divide n*m' );

eval { Polyomino::Tiler->new( n => 2, m => 2, k => 5 ) };
like( $@, qr/cannot exceed/, 'dies when k exceeds n*m' );

eval { Polyomino::Tiler->new( n => 4, m => 4 ) };
like( $@, qr/required/, 'dies when neither k nor pieces given' );

eval { Polyomino::Tiler->new( n => 4, m => 4, pieces => [ 3, 4 ] ) };
like( $@, qr/sum/, 'dies when pieces do not sum to n*m' );

done_testing();
