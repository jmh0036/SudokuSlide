use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Polyomino::Sudoku',
    AUTHOR           => 'James Hammer',
    VERSION          => '0.01',
    ABSTRACT         => 'Polyomino-tiled Quasi Factor Pair Latin Square puzzle generator',
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.010',
    EXE_FILES        => ['bin/polyomino-sudoku'],
    PREREQ_PM        => {
        'Algorithm::DLX' => '0.03',
        'List::Util'     => '1.33',
        'Getopt::Long'   => '2.45',
        'Pod::Usage'     => '1.69',
        'Carp'           => 0,
    },
    test => { TESTS => 't/Math/Combinatorics/*.t t/Polyomino/*.t t/SudokuSlide/*.t' },
    TEST_REQUIRES => {
        'Test::More' => '0',
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        provides    => {
            'SudokuSlide::Puzzle'           => { file => 'lib/Polyomino/Sudoku/Puzzle.pm',          version => '0.01' },
            'Polyomino::Tiler'                    => { file => 'lib/Polyomino/Tiler.pm',                   version => '0.03' },
            'Polyomino::Renderer'                 => { file => 'lib/Polyomino/Renderer.pm',                version => '0.02' },
            'Math::Combinatorics::LatinSquares'   => { file => 'lib/Math/Combinatorics/LatinSquares.pm',   version => '0.03' },
        },
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
    clean => { FILES => 'PolyominoSudoku-*' },
);
