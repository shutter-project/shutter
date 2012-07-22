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

package Shutter::App::Optional::Exif;

#modules
#--------------------------------------
use utf8;
use strict;

use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;

	my $self = { };

	#libimage-exiftool-perl
	eval { require Image::ExifTool };
	if ($@) {
		$self->{_exiftool} = FALSE;
	}else{
		$self->{_exiftool} = new Image::ExifTool;
	}

	bless $self, $class;
	return $self;
}

#getter / setter
sub get_exiftool {
	my $self = shift;
	return $self->{_exiftool};
}

1;
