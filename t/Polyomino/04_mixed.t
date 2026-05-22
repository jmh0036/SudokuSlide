use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib", "$Bin";

use Polyomino::Tiler;
use TestHelper qw(validate_solution);

# ── suggest_pieces ────────────────────────────────────────────────────────
{
    my $pieces = Polyomino::Tiler->suggest_pieces(
        n    => 4,
        m    => 4,
        must => [ 3, 5 ],
        fill => 4,
    );
    my $sum = 0;
    $sum += $_ for @$pieces;
    is( $sum,            16, 'suggest_pieces: result sums to n*m' );
    is( scalar @$pieces, 4,  'suggest_pieces: correct piece count' );
    ok( ( grep { $_ == 3 } @$pieces ),
        'suggest_pieces: includes must piece of size 3' );
    ok( ( grep { $_ == 5 } @$pieces ),
        'suggest_pieces: includes must piece of size 5' );
}

{
    eval { Polyomino::Tiler->suggest_pieces( n => 3, must => [4], fill => 2 ); };
    like(
        $@,
        qr/not divisible/,
        'suggest_pieces: dies when remainder not divisible by fill'
    );
}

{
    eval {
        Polyomino::Tiler->suggest_pieces(
            n    => 2,
            m    => 2,
            must => [ 3, 5 ],
            fill => 1
        );
    };
    like( $@, qr/exceed/, 'suggest_pieces: dies when must pieces exceed area' );
}

# ── Mixed piece tiling ────────────────────────────────────────────────────
{
    my $tiler = Polyomino::Tiler->new( n => 2, m => 3, pieces => [ 3, 3 ] );
    my @sol   = $tiler->solve();
    ok( @sol > 0, '2x3 [3,3]: has solutions' );
    for my $s (@sol) {
        my ( $ok, $reason ) = validate_solution( $s, 2, 3, [ 3, 3 ] );
        ok( $ok, "2x3 [3,3]: solution valid ($reason)" );
    }
}

{
    my $tiler = Polyomino::Tiler->new( n => 2, m => 3, pieces => [ 2, 4 ] );
    my @sol   = $tiler->solve();
    ok( @sol > 0, '2x3 [2,4]: has solutions' );
    for my $s (@sol) {
        my ( $ok, $reason ) = validate_solution( $s, 2, 3, [ 2, 4 ] );
        ok( $ok, "2x3 [2,4]: solution valid ($reason)" );
    }
}

{
    # [2,4] and [4,2] describe the same tiling problem; should give same count
    my $t24 = Polyomino::Tiler->new( n => 2, m => 3, pieces => [ 2, 4 ] );
    my $t42 = Polyomino::Tiler->new( n => 2, m => 3, pieces => [ 4, 2 ] );
    my @s24 = $t24->solve();
    my @s42 = $t42->solve();
    is( scalar @s24, scalar @s42,
        '[2,4] and [4,2] give same number of solutions' );
}

{
    # 3x3 with [4,5] — valid sizes summing to 9, check solver runs cleanly
    my $tiler = Polyomino::Tiler->new( n => 3, m => 3, pieces => [ 4, 5 ] );
    my @sol   = $tiler->solve();
    for my $s (@sol) {
        my ( $ok, $reason ) = validate_solution( $s, 3, 3, [ 4, 5 ] );
        ok( $ok, "3x3 [4,5]: solution valid ($reason)" );
    }
    pass("3x3 [4,5]: solver ran without error");
}

{
    my $tiler = Polyomino::Tiler->new( n => 2, m => 3, pieces => [ 3, 3 ] );
    my @sols  = $tiler->solve_random();
    ok( @sols, 'solve_random with mixed pieces returns a solution' );
    my ( $ok, $reason ) = validate_solution( $sols[0], 2, 3, [ 3, 3 ] );
    ok( $ok, "solve_random mixed solution valid ($reason)" );
}

# ── Rectangular grid ──────────────────────────────────────────────────────
{
    my $tiler = Polyomino::Tiler->new( n => 3, m => 4, k => 3 );
    my @sol   = $tiler->solve();
    ok( @sol > 0, '3x4/k=3: has solutions' );
    for my $s (@sol) {
        my ( $ok, $reason ) = validate_solution( $s, 3, 4, $tiler->pieces );
        ok( $ok, "3x4/k=3: solution valid ($reason)" );
    }
}

{
    # 1x6 with three dominoes: only one distinct tiling
    my $tiler = Polyomino::Tiler->new( n => 1, m => 6, pieces => [ 2, 2, 2 ] );
    my @sol   = $tiler->solve();
    is( scalar @sol, 1, '1x6 [2,2,2]: exactly 1 solution' );
}

# ── No duplicate solutions ────────────────────────────────────────────────
{
    my $tiler = Polyomino::Tiler->new( n => 2, m => 3, pieces => [ 3, 3 ] );
    my @sol   = $tiler->solve();
    my %seen;
    for my $s (@sol) {
        my $key = join(
            '|',
            sort map {
                join( ',',
                    map    { "$_->[0]:$_->[1]" }
                      sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @$_ )
            } @$s
        );
        $seen{$key}++;
    }
    my $dupes = grep { $_ > 1 } values %seen;
    is( $dupes, 0, '2x3 [3,3]: no duplicate solutions' );
}

done_testing();
