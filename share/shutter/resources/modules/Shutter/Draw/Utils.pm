package Shutter::Draw::Utils;

use 5.010;
use strict;
use warnings;

use Gtk3;
use GooCanvas2;

our @EXPORT_OK = qw/ points_to_canvas_points /;

use Exporter;

sub points_to_canvas_points {
    my @points = @_;

    my $num_points = scalar(@points) / 2;
    my $result     = GooCanvas2::CanvasPoints->new( num_points => $num_points );

    for ( my $i = 0; $i < @points; $i += 2 ) {
        $result->set_point( $i / 2, $points[$i], $points[ $i + 1 ] );
    }

    return $result;
}

1;
