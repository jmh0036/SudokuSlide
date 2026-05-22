use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";

use Polyomino::Renderer;

# ── Basic render structure ─────────────────────────────────────────────────
my $solution = [
    [ [ 0, 0 ], [ 0, 1 ] ],    # piece 1
    [ [ 1, 0 ], [ 1, 1 ] ],    # piece 2
];

my $rendered = Polyomino::Renderer::render( $solution, 2, 2 );

like( $rendered, qr/\+/, 'render: contains + border chars' );
like( $rendered, qr/\|/, 'render: contains | border chars' );
like( $rendered, qr/1/,  'render: contains label 1' );
like( $rendered, qr/2/,  'render: contains label 2' );
unlike( $rendered, qr/\?/, 'render: no unassigned cells' );

# n+1 horizontal bar lines for an n-row grid
my @hbars = ( $rendered =~ /(\+[-+]+\+)/g );
is( scalar @hbars, 3, 'render: 2x2 grid has 3 horizontal bar lines' );

# Each label should appear exactly k=2 times
my $count_1 = () = $rendered =~ /(?<![0-9])1(?![0-9])/g;
my $count_2 = () = $rendered =~ /(?<![0-9])2(?![0-9])/g;
is( $count_1, 2, 'render: label 1 appears exactly 2 times' );
is( $count_2, 2, 'render: label 2 appears exactly 2 times' );

# ── Label width scales with piece count ────────────────────────────────────
# 9 pieces -> width 1; 10 pieces -> width 2; 100 pieces -> width 3
{
    # 1x9 grid, 9 monominos -> labels 1..9, width=1
    my @mono9 = map { [ [ $_, 0 ] ] } ( 0 .. 8 );               # 9x1 grid
    my $r9    = Polyomino::Renderer::render( \@mono9, 9, 1 );

    # Each cell border is "| X |" with width 1 -> 5 chars wide
    like( $r9, qr/\| 9 \|/, 'render: 9 pieces uses width-1 labels' );
}

{
    # 1x10 grid, 10 monominos -> labels 1..10, width=2
    my @mono10 = map { [ [ $_, 0 ] ] } ( 0 .. 9 );                 # 10x1 grid
    my $r10    = Polyomino::Renderer::render( \@mono10, 10, 1 );

    # Width-2 labels: "| 10 |"
    like( $r10, qr/\| 10 \|/, 'render: 10 pieces uses width-2 labels' );

    # Earlier labels right-justified: "| 1 |" (space then digit)
    like( $r10, qr/\|  1 \|/,
        'render: single-digit labels are right-justified in width-2' );
}

{
    # 10x10 grid, 100 monominos -> labels 1..100, width=3
    my @mono100;
    for my $r ( 0 .. 9 ) {
        for my $c ( 0 .. 9 ) { push @mono100, [ [ $r, $c ] ] }
    }
    my $r100 = Polyomino::Renderer::render( \@mono100, 10, 10 );
    like( $r100, qr/\| 100 \|/, 'render: 100 pieces uses width-3 labels' );
    like( $r100, qr/\|   1 \|/,
        'render: single-digit labels right-justified in width-3' );
    unlike( $r100, qr/\?/,
        'render: no unassigned cells in 10x10 monomino grid' );
}

# ── Rectangular render ────────────────────────────────────────────────────
{
    my $rect_sol = [
        [ [ 0, 0 ], [ 0, 1 ] ],
        [ [ 0, 2 ], [ 1, 2 ] ],
        [ [ 1, 0 ], [ 1, 1 ] ],
    ];
    my $rect = Polyomino::Renderer::render( $rect_sol, 2, 3 );
    unlike( $rect, qr/\?/, 'render: no unassigned cells in 2x3 rect' );

    my @rect_hbars = ( $rect =~ /(\+[-+]+\+)/g );
    is( scalar @rect_hbars, 3, 'render: 2x3 grid has 3 horizontal bar lines' );

    my @rows = grep { /^\|/ } split /\n/, $rect;
    for my $row (@rows) {
        my $pipes = () = $row =~ /\|/g;
        is( $pipes, 4, 'render: 2x3 data row has 4 pipes' );
    }
}

# ── m defaults to n ───────────────────────────────────────────────────────
{
    my $sq = Polyomino::Renderer::render( $solution, 2 );
    is( $sq, $rendered, 'render: m defaults to n for square grids' );
}

# ── render_all ────────────────────────────────────────────────────────────
{
    my $sol2 = [ [ [ 0, 0 ], [ 1, 0 ] ], [ [ 0, 1 ], [ 1, 1 ] ] ];
    my $all  = Polyomino::Renderer::render_all( [ $solution, $sol2 ], 2, 2 );
    like( $all, qr/Solution 1:/, 'render_all: contains Solution 1' );
    like( $all, qr/Solution 2:/, 'render_all: contains Solution 2' );
}

done_testing();
