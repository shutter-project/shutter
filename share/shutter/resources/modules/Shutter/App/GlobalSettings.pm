###################################################
#
#  Copyright (C) 2008-2013 Mario Kemper <mario.kemper@gmail.com>
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

package Shutter::App::GlobalSettings;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

#Glib
use Glib qw/TRUE FALSE/;

#--------------------------------------

sub new {
	my $class = shift;

	my $self = {};

	$self->{_image_quality} = {
		"png" => undef,
		"jpg" => undef,
		"webp" => undef,
		"avif" => undef
	};

	$self->{_default_image_quality} = {
		"png" => 9,
		"jpg" => 90,
		"webp" => 98,
		"avif" => 68
	};

	bless $self, $class;
	return $self;
}

#getter / setter

sub get_image_quality {
	my $self = shift;
	my $format = shift;
	if (defined $self->{_image_quality}{$format}) {
		return $self->{_image_quality}{$format};
	} else {
		return $self->{_default_image_quality}{$format};
	}
}

sub set_image_quality {
	my $self = shift;
	my $format = shift;
	if (@_) {
		$self->{_image_quality}{$format} = shift;
	}
	return $self->{_image_quality}{$format};
}

sub clear_quality_settings {
	my $self = shift;
	$self->{_image_quality} = {
		"png" => undef,
		"jpg" => undef,
		"webp" => undef,
		"avif" => undef
	};
}

1;
