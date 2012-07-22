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

package Shutter::App::GlobalSettings;

#modules
#--------------------------------------
use utf8;
use strict;

#Glib
use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;

	my $self = { };

	$self->{_png_quality} = undef;
	$self->{_jpg_quality} = undef;

	bless $self, $class;
	return $self;
}

#getter / setter
sub get_png_quality {
	my $self = shift;
	if(defined $self->{_png_quality}){
		return $self->{_png_quality};
	}else{
		return 9;
	}
}

sub get_jpg_quality {
	my $self = shift;
	if(defined $self->{_jpg_quality}){
		return $self->{_jpg_quality};
	}else{
		return 90;
	}
}

sub set_png_quality {
	my $self = shift;
	if (@_) {
		$self->{_png_quality} = shift;
	}
	return $self->{_png_quality};
}

sub set_jpg_quality {
	my $self = shift;
	if (@_) {
		$self->{_jpg_quality} = shift;
	}
	return $self->{_jpg_quality};
}

sub clear_quality_settings {
	my $self = shift;
	$self->{_jpg_quality} = undef;
	$self->{_png_quality} = undef;
}

1;
