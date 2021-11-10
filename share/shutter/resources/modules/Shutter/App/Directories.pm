###################################################
#
#  Copyright (C) 2008-2013 Mario Kemper <mario.kemper@gmail.com>
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

package Shutter::App::Directories;

use 5.010;
use strict;
use warnings;

use Glib qw/ TRUE /;

use constant {
    SHUTTER_DIR        => "shutter",
    UNSAVED_DIR        => "unsaved",
    TEMP_DIR           => "temp",
    AUTOSTART_DIR      => "autostart",
    HIDDEN_SHUTTER_DIR => ".shutter",
    PROFILES_DIR       => "profiles"
};

sub create_if_not_exists : prototype($) {
    my $dir = shift;

    mkdir $dir unless -d $dir && -r $dir;

    return $dir;
}

sub get_root_dir {
    return create_if_not_exists( Glib::get_user_cache_dir . "/" . SHUTTER_DIR );
}

sub get_cache_dir {
    return create_if_not_exists( get_root_dir() . "/" . UNSAVED_DIR );
}

sub get_temp_dir {
    return create_if_not_exists( get_root_dir() . "/" . TEMP_DIR );
}

sub get_autostart_dir {
    return create_if_not_exists( Glib::get_user_config_dir . "/" . AUTOSTART_DIR );
}

sub get_home_dir   {Glib::get_home_dir}
sub get_config_dir {Glib::get_user_config_dir}

sub create_hidden_home_dir_if_not_exist {
    my $hidden_dir          = $ENV{HOME} . "/" . HIDDEN_SHUTTER_DIR;
    my $hidden_profiles_dir = "$hidden_dir" . "/" . PROFILES_DIR;

    mkdir $hidden_dir          unless -d $hidden_dir;
    mkdir $hidden_profiles_dir unless -d $hidden_profiles_dir;

    return TRUE;
}

1;
