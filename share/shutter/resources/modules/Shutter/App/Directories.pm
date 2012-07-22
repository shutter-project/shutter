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

package Shutter::App::Directories;

use utf8;
use strict;
use warnings;

#Glib
use Glib qw/TRUE FALSE/; 

sub new {
	my $class = shift;

	my $self = { };

	bless $self, $class;
	return $self;
}

sub create_if_not_exists {
	my $self = shift;
	my $dir = shift;
	mkdir($dir) unless (-d $dir && -r $dir);
	return $dir;
}

sub get_root_dir {
	my $self = shift;
	return $self->create_if_not_exists(Glib::get_user_cache_dir."/shutter");
}

sub get_cache_dir {
	my $self = shift;
	return $self->create_if_not_exists($self->get_root_dir."/unsaved");
}

sub get_temp_dir {
	my $self = shift;
	return $self->create_if_not_exists($self->get_root_dir."/temp");	
}

sub get_autostart_dir {
	my $self = shift;
	return $self->create_if_not_exists(Glib::get_user_config_dir."/autostart");		
}

sub get_home_dir {
	my $self = shift;
	return Glib::get_home_dir;
}

sub get_settings_dir {
	#not implemented
}

1;
