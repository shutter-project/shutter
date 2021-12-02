###################################################
#
#  Copyright (C) 2021 Alexander Ruzhnikov <ruzhnikov85@gmail.com>
#
#  This file is part of Shutter.
#
#  Shutter is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  Shutter is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with Shutter; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
#
###################################################

package Shutter::Draw::Utils;

use 5.010;
use strict;
use warnings;

use Gtk3;
use GooCanvas2;

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
