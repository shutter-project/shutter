###################################################
#
#  Copyright (C) 2008-2012 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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
                               
package Shutter::Pixbuf::Border;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Gtk2;

#Glib
use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;

	#constructor
	my $self = { _common => shift };

	bless $self, $class;
	return $self;
}

#~ sub DESTROY {
    #~ my $self = shift;
    #~ print "$self dying at\n";
#~ } 

sub create_border {
	my $self 	= shift;
	my $pixbuf	= shift;
	my $width	= shift;
	my $color	= shift;
	
	#create new pixbuf
	my $tmp_pbuf = Gtk2::Gdk::Pixbuf->new ('rgb', TRUE, 8, $pixbuf->get_width+2*$width, $pixbuf->get_height+2*$width);	
	
	#Create a pixel specification
	my $pixel = 0;
	$pixel += ($color->red   / 257) << 24;
	$pixel += ($color->green / 257) << 16;
	$pixel += ($color->blue  / 257) <<  8;
	$pixel += 255;
	
	#fill tmp pixbuf
	$tmp_pbuf->fill($pixel);
	
	#copy source pixbuf to new pixbuf
	eval{
		$pixbuf->copy_area (0, 0, $pixbuf->get_width, $pixbuf->get_height, $tmp_pbuf, $width, $width);
	};
	if($@){
		print "create border failed: $@\n" if $self->{_common}->get_debug;
		return $pixbuf;
	}
	
	return $tmp_pbuf;
}

1;
