package TestHelper;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(validate_solution);

=head1 NAME

TestHelper - Shared utilities for Polyomino::Tiler test suite

=head1 FUNCTIONS

=head2 validate_solution($solution, $n, $m, $pieces_spec)

Validates that a tiling solution is internally consistent:

=over 4

=item * Every cell in the n×m grid is covered exactly once.

=item * No cell is out of bounds.

=item * The multiset of piece sizes matches C<$pieces_spec>.

=back

Returns C<(1, "ok")> on success or C<(0, $reason)> on failure.

=cut

sub validate_solution {
    my ( $solution, $n, $m, $pieces_spec ) = @_;

    my %expected;
    $expected{$_}++ for @$pieces_spec;

    my %coverage;
    my %got_sizes;
    for my $piece (@$solution) {
        my $sz = scalar @$piece;
        $got_sizes{$sz}++;
        for my $cell (@$piece) {
            my $key = "$cell->[0],$cell->[1]";
            return ( 0, "cell $key covered twice" ) if $coverage{$key}++;
            return ( 0, "cell $key out of bounds" )
              if $cell->[0] < 0
              || $cell->[0] >= $n
              || $cell->[1] < 0
              || $cell->[1] >= $m;
        }
    }
    return ( 0, "not all cells covered" )
      unless scalar keys %coverage == $n * $m;

    for my $k ( keys %expected ) {
        return (
            0,
            sprintf(
                "wrong count of size-%d pieces: got %d, want %d",
                $k, $got_sizes{$k} // 0, $expected{$k}
            )
          )
          unless ( $got_sizes{$k} // 0 ) == $expected{$k};
    }
    return ( 1, "ok" );
}

1;
