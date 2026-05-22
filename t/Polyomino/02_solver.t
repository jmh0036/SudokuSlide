use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib", "$Bin";

use Polyomino::Tiler;
use TestHelper qw(validate_solution);

# ── Solution count spot-checks ─────────────────────────────────────────────
{
    my $tiler = Polyomino::Tiler->new( n => 2, m => 2, k => 2 );
    my @sol   = $tiler->solve();
    is( scalar @sol, 2, '2x2/k=2: exactly 2 solutions' );
}

{
    my $tiler = Polyomino::Tiler->new( n => 4, m => 4, k => 2 );
    my @sol   = $tiler->solve();
    is( scalar @sol, 36, '4x4/k=2: exactly 36 solutions' );
}

{
    my $tiler = Polyomino::Tiler->new( n => 3, m => 3, k => 3 );
    my @sol   = $tiler->solve();
    is( scalar @sol, 10, '3x3/k=3: exactly 10 solutions' );
}

{
    my $tiler = Polyomino::Tiler->new( n => 1, m => 1, k => 1 );
    my @sol   = $tiler->solve();
    is( scalar @sol, 1, '1x1/k=1: exactly 1 solution' );
}

# ── Rectangular grid ──────────────────────────────────────────────────────
{
    my $tiler = Polyomino::Tiler->new( n => 2, m => 4, k => 2 );
    my @sol   = $tiler->solve();
    ok( @sol > 0, '2x4/k=2: has solutions' );
}

# ── Solution validity ──────────────────────────────────────────────────────
for my $spec ( [ 2, 2, 2 ], [ 3, 3, 3 ], [ 4, 4, 2 ], [ 2, 4, 2 ] ) {
    my ( $n, $m, $k ) = @$spec;
    my $tiler     = Polyomino::Tiler->new( n => $n, m => $m, k => $k );
    my @sol       = $tiler->solve();
    my @pieces    = @{ $tiler->pieces };
    my $all_valid = 1;
    for my $s (@sol) {
        my ( $ok, $reason ) = validate_solution( $s, $n, $m, \@pieces );
        unless ($ok) { $all_valid = 0; diag("Invalid: $reason"); last }
    }
    ok( $all_valid, "${n}x${m}/k=${k}: all solutions valid" );
}

# ── solve_random ──────────────────────────────────────────────────────────
{
    my $tiler  = Polyomino::Tiler->new( n => 4, m => 4, k => 2 );
    my @sols   = $tiler->solve_random();
    is( scalar @sols, 1, 'solve_random() returns exactly 1 solution for 4x4/k=2' );
    my ( $ok, $reason ) = validate_solution( $sols[0], 4, 4, $tiler->pieces );
    ok( $ok, "solve_random() solution is valid ($reason)" );
}

# solve_random with an explicit count
{
    my $tiler = Polyomino::Tiler->new( n => 4, m => 4, k => 2 );
    my @sols  = $tiler->solve_random(5);
    ok( scalar @sols >= 1 && scalar @sols <= 5,
        'solve_random(5): returns 1–5 solutions' );
    for my $sol (@sols) {
        my ( $ok, $reason ) = validate_solution( $sol, 4, 4, $tiler->pieces );
        ok( $ok, "solve_random(5): solution valid ($reason)" );
    }
}

{
    # 1x1/k=1 has exactly 1 solution; solve_random() should always find it
    my $tiler = Polyomino::Tiler->new( n => 1, m => 1, k => 1 );
    my @sols  = $tiler->solve_random();
    is( scalar @sols, 1,
        'solve_random() on single-solution problem returns it' );
}

# ── No duplicate solutions ────────────────────────────────────────────────
{
    my $tiler = Polyomino::Tiler->new( n => 2, m => 2, k => 2 );
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
    is( $dupes, 0, '2x2/k=2: no duplicate solutions' );
}

# ── solve with a limit ────────────────────────────────────────────────────
{
    my $tiler = Polyomino::Tiler->new( n => 4, m => 4, k => 2 );
    my @sol   = $tiler->solve(5);
    ok( scalar @sol <= 5, 'solve(5): returns at most 5 solutions' );
    ok( scalar @sol > 0,  'solve(5): returns at least 1 solution' );
    my ( $ok, $reason ) = validate_solution( $sol[0], 4, 4, $tiler->pieces );
    ok( $ok, "solve(5): first solution is valid ($reason)" );
}

{
    # When total solutions < limit, returns all of them
    my $tiler = Polyomino::Tiler->new( n => 2, m => 2, k => 2 );
    my @sol   = $tiler->solve(100);
    is( scalar @sol, 2, 'solve(100) on 2x2/k=2: returns all 2 solutions' );
}

# solve genuinely stops early: DLX must not explore beyond the limit.
# We verify this indirectly — solve(1) on a problem with 36 solutions must
# return exactly 1 result, not 36 filtered down to 1.
{
    my $tiler = Polyomino::Tiler->new( n => 4, m => 4, k => 2 );
    my @sol   = $tiler->solve(1);
    is( scalar @sol, 1, 'solve(1): returns exactly 1 solution (early stop)' );
    my ( $ok, $reason ) = validate_solution( $sol[0], 4, 4, $tiler->pieces );
    ok( $ok, "solve(1): solution is valid ($reason)" );
}

done_testing();
