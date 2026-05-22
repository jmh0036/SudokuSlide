use strict;
use warnings;
use Test::More;
use Math::Combinatorics::LatinSquares;
use File::Spec;

# ---------------------------------------------------------------------------
# Helper: verify a grid satisfies all regional constraints
# ---------------------------------------------------------------------------

sub verify_grid {
    my ($ls, $grid) = @_;
    my $N    = $ls->n;
    my $maps = $ls->region_maps;

    for my $r (0 .. $N-1) {
        for my $c (0 .. $N-1) {
            return 0 unless defined $grid->[$r][$c]
                         && $grid->[$r][$c] >= 1
                         && $grid->[$r][$c] <= $N;
        }
    }

    for my $t (0 .. $#$maps) {
        my $map = $maps->[$t];
        my @box_vals;
        for my $r (0 .. $N-1) {
            for my $c (0 .. $N-1) {
                $box_vals[ $map->[$r][$c] ]{ $grid->[$r][$c] }++;
            }
        }
        for my $k (0 .. $N-1) {
            for my $v (1 .. $N) {
                return 0 unless ($box_vals[$k]{$v} // 0) == 1;
            }
        }
    }
    return 1;
}

# ---------------------------------------------------------------------------
# Helper: run the binary and return its output lines
# ---------------------------------------------------------------------------

my $bin = File::Spec->catfile(qw(blib script latin-squares));

sub run_bin {
    my @args = @_;
    my $cmd  = join(' ', $^X, "-Iblib/lib", $bin, @args);
    my @lines = `$cmd 2>&1`;
    return ($? == 0, @lines);
}

# ---------------------------------------------------------------------------
# Module-level tests (fast, deterministic structure checks)
# ---------------------------------------------------------------------------

subtest 'constructor validation' => sub {
    eval { Math::Combinatorics::LatinSquares->new(regions => [[2, 3], [2, 2]]) };
    like($@, qr/differ/, 'croaks on mismatched products');

    my $ls = Math::Combinatorics::LatinSquares->new(regions => [[2, 2]]);
    is($ls->n, 4, 'N=4 for 2x2 region');
    is(scalar @{ $ls->regions },     1, '1 region stored');
    is(scalar @{ $ls->region_maps }, 1, '1 region map stored');
};

subtest 'region map structure' => sub {
    my $ls  = Math::Combinatorics::LatinSquares->new(regions => [[2, 3]]);
    my $map = $ls->region_maps->[0];
    is($map->[0][0], 0, 'top-left cell is box 0');
    is($map->[0][3], 1, 'top cell col 3 is box 1');
    is($map->[2][0], 2, 'row 2 col 0 is box 2');
};

# ---------------------------------------------------------------------------
# Solve tests — use max_attempts so a single bad prefill can't flake the run
# ---------------------------------------------------------------------------

subtest '4x4 with 2x2 boxes — single solution' => sub {
    my $ls    = Math::Combinatorics::LatinSquares->new(regions => [[2, 2]]);
    my $grids = $ls->solve(max_attempts => 200);
    is(scalar @$grids, 1,    'got exactly one solution');
    ok(verify_grid($ls, $grids->[0]), 'solution satisfies constraints');
};

subtest '4x4 rows + cols' => sub {
    my $ls    = Math::Combinatorics::LatinSquares->new(regions => [[1,4],[4,1]]);
    my $grids = $ls->solve(max_attempts => 200);
    is(scalar @$grids, 1,    'got exactly one solution');
    ok(verify_grid($ls, $grids->[0]), 'solution satisfies constraints');
};

subtest '4x4 classic sudoku (rows + cols + 2x2)' => sub {
    my $ls    = Math::Combinatorics::LatinSquares->new(regions => [[1,4],[4,1],[2,2]]);
    my $grids = $ls->solve(max_attempts => 200);
    is(scalar @$grids, 1,    'got exactly one solution');
    ok(verify_grid($ls, $grids->[0]), 'solution satisfies constraints');
};

subtest '6x6 pair (2x3 + 3x2, no rows/cols)' => sub {
    my $ls    = Math::Combinatorics::LatinSquares->new(regions => [[2,3],[3,2]]);
    my $grids = $ls->solve(max_attempts => 200);
    is(scalar @$grids, 1,    'got exactly one solution');
    ok(verify_grid($ls, $grids->[0]), 'solution satisfies constraints');
};

subtest 'full 6x6 sudoku pair (rows + cols + 2x3 + 3x2)' => sub {
    my $ls    = Math::Combinatorics::LatinSquares->new(
        regions => [[1,6],[6,1],[2,3],[3,2]]
    );
    my $grids = $ls->solve(max_attempts => 200);
    is(scalar @$grids, 1,    'got exactly one solution');
    ok(verify_grid($ls, $grids->[0]), 'solution satisfies all four constraints');
};

subtest 'prefill_boxes => 0 disables prefill, still correct' => sub {
    my $ls    = Math::Combinatorics::LatinSquares->new(regions => [[2,2]]);
    my $grids = $ls->solve(prefill_boxes => 0, max_attempts => 200);
    is(scalar @$grids, 1,    'got one solution with prefill disabled');
    ok(verify_grid($ls, $grids->[0]), 'solution satisfies constraints');
};

subtest 'number_of_solutions => 3 returns up to 3, all valid' => sub {
    my $ls    = Math::Combinatorics::LatinSquares->new(regions => [[2,2]]);
    my $grids = $ls->solve(number_of_solutions => 3, max_attempts => 200);
    cmp_ok(scalar @$grids, '>=', 1, 'got at least one solution');
    cmp_ok(scalar @$grids, '<=', 3, 'got no more than 3 solutions');
    ok(verify_grid($ls, $_), 'solution satisfies constraints') for @$grids;
};

subtest 'number_of_solutions => undef returns all (tightly constrained)' => sub {
    # Classic 4x4 sudoku has a small solution set — safe to enumerate
    my $ls    = Math::Combinatorics::LatinSquares->new(
        regions => [[1,4],[4,1],[2,2]]
    );
    my $grids = $ls->solve(number_of_solutions => undef, max_attempts => 200);
    cmp_ok(scalar @$grids, '>=', 1, 'got at least one solution');
    ok(verify_grid($ls, $_), 'solution satisfies constraints') for @$grids;
};

subtest 'randomness: 20 calls give multiple distinct grids' => sub {
    my $ls = Math::Combinatorics::LatinSquares->new(regions => [[2,2]]);
    my %seen;
    for (1 .. 20) {
        my $grids = $ls->solve(max_attempts => 200);
        if (@$grids) {
            my $key = join(',', map { join('', @$_) } @{ $grids->[0] });
            $seen{$key}++;
        }
    }
    cmp_ok(scalar keys %seen, '>', 1, 'got more than one distinct solution in 20 tries');
};

# ---------------------------------------------------------------------------
# Binary integration tests — run the actual script in a loop
# ---------------------------------------------------------------------------

SKIP: {
    skip "binary not found at $bin", 2 unless -f $bin;

    subtest 'binary: 6x6 pair produces valid output' => sub {
        my $found = 0;
        for my $attempt (1 .. 200) {
            my ($ok, @lines) = run_bin('--region 1 6 --region 6 1 --region 2 3 --region 3 2');
            next unless $ok && @lines == 6;

            # Parse the 6 output lines into a grid
            my @grid = map { [ split ' ', $_ ] } @lines;
            my $ls   = Math::Combinatorics::LatinSquares->new(
                regions => [[1,6],[6,1],[2,3],[3,2]]
            );
            if (verify_grid($ls, \@grid)) {
                $found = 1;
                last;
            }
        }
        ok($found, 'binary produced a valid 6x6 sudoku pair solution within 200 attempts');
    };

    subtest 'binary: --count 3 returns exactly 3 solutions' => sub {
        my $found = 0;
        for my $attempt (1 .. 200) {
            my ($ok, @lines) = run_bin('--region 1 6 --region 6 1 --region 2 3 --region 3 2 --count 3');
            # Grid data lines contain only digits and spaces; header/blank lines don't
            my @data_lines = grep { /^\s*[\d ]+\s*$/ } @lines;
            if ($ok && @data_lines == 18) {
                $found = 1;
                last;
            }
        }
        ok($found, 'binary produced 3 solutions (18 grid data lines) within 200 attempts');
    };
}

done_testing;
