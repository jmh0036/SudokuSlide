package Polyomino::Renderer;

use strict;
use warnings;

our $VERSION = '0.02';

=head1 NAME

Polyomino::Renderer - Render polyomino tiling solutions as ASCII grids

=head1 SYNOPSIS

    use Polyomino::Renderer;

    my $str = Polyomino::Renderer::render($solution, $n, $m);
    print $str;

=cut

=head1 FUNCTIONS

=head2 render($solution, $n, $m)

Render a single solution as a bordered ASCII grid string.
C<$solution> is an arrayref of pieces; C<$n> rows, C<$m> cols.
C<$m> defaults to C<$n> for square grids.

=cut

sub render {
    my ( $solution, $n, $m ) = @_;
    $m //= $n;

    my @grid;
    for my $r ( 0 .. $n - 1 ) {
        for my $c ( 0 .. $m - 1 ) {
            $grid[$r][$c] = '?';
        }
    }

    my $num_pieces = scalar @$solution;
    my $width = length("$num_pieces");    # 1 for ≤9, 2 for ≤99, 3 for ≤999, ...

    my $piece_num = 0;
    for my $piece (@$solution) {
        my $label = $piece_num + 1;    # 1-indexed so label width matches $width
        for my $cell (@$piece) {
            $grid[ $cell->[0] ][ $cell->[1] ] = $label;
        }
        $piece_num++;
    }

    my $hbar = '+' . ( ( '-' x ( $width + 2 ) . '+' ) x $m ) . "\n";

    my $out = $hbar;
    for my $r ( 0 .. $n - 1 ) {
        $out .= '|';
        for my $c ( 0 .. $m - 1 ) {
            $out .= sprintf " %*s |", $width, $grid[$r][$c];
        }
        $out .= "\n$hbar";
    }
    return $out;
}

=head2 render_all($solutions, $n, $m)

Render all solutions, each prefixed with a "Solution N:" header.

=cut

sub render_all {
    my ( $solutions, $n, $m ) = @_;
    $m //= $n;
    my $out = '';
    my $i   = 0;
    for my $sol (@$solutions) {
        $i++;
        $out .= "Solution $i:\n";
        $out .= render( $sol, $n, $m );
        $out .= "\n";
    }
    return $out;
}

1;

=head1 AUTHOR

James Hammer <DERHAMMER>

=head1 LICENSE

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
