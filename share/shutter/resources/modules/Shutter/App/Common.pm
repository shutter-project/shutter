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

package Shutter::App::Common;

#modules
#--------------------------------------
use utf8;
use strict;
use Gtk2;

#Gettext and filename parsing
use POSIX qw/setlocale/;
use Locale::gettext;

#Glib
use Glib qw/TRUE FALSE/; 

#File
use File::Spec;

#--------------------------------------

##################public subs##################
sub new {
	my $class = shift;

	#constructor
	my $self = { _shutter_root => shift, _mainwindow => shift, _appname => shift, _version => shift, _rev => shift, _pid => shift };

	#vars
	$self->{_debug_cparam}              = FALSE;
	$self->{_clear_cache}               = FALSE;
	$self->{_min_cparam}                = FALSE;
	$self->{_disable_systray_cparam}    = FALSE;
	$self->{_exit_after_capture_cparam} = FALSE;
	$self->{_no_session_cparam}         = FALSE;
	$self->{_start_with}                = undef;
	$self->{_start_with_extra}          = undef;
	$self->{_profile_to_start_with}     = undef;
	$self->{_export_filename}           = undef;
	$self->{_delay}						= undef;
	$self->{_include_cursor}			= undef;
	$self->{_remove_cursor}				= undef;

	#Set LC_NUMERIC to C to prevent decimal commas (or anything else)
	setlocale(LC_NUMERIC, "C");	
	setlocale( LC_MESSAGES, "" );
	#gettext init
	$self->{_gettext_object} = Locale::gettext->domain("shutter");
	$self->{_gettext_object}->dir( $self->{_shutter_root} . "/share/locale" );
	
	#ENV needed by some plugins
	$ENV{'SHUTTER_INTL'} = $self->{_shutter_root} . "/share/locale";

	#tooltips
	$self->{_tooltips} = Gtk2::Tooltips->new;

	#notification object
	$self->{_notification};

	#globalsettings object
	$self->{_globalsettings};

	#icontheme to determine if icons exist or not
	#in some cases we deliver fallback icons
	$self->{_icontheme} = Gtk2::IconTheme->get_default;
	$self->{_icontheme}->append_search_path($self->{_shutter_root} . "/share/icons");

	#recently used upload tab
	$self->{_ruu_tab} = 0;
    #... and details
	$self->{_ruu_hosting} = 0;
	$self->{_ruu_places} = 0;
	$self->{_ruu_u1} = 0;

	#recently used save folder
	$self->{_rusf} = undef;

	#recently used open folder
	$self->{_ruof} = undef;

	bless $self, $class;
	return $self;
}

#getter / setter
sub get_root {
	my $self = shift;
	return $self->{_shutter_root};
}

sub get_pid {
	my $self = shift;
	return $self->{_pid};
}

sub set_pid {
	my $self = shift;
	if (@_) {
		$self->{_pid} = shift;
	}
	return $self->{_pid};
}

sub get_appname {
	my $self = shift;
	return $self->{_appname};
}

sub get_version {
	my $self = shift;
	return $self->{_version};
}

sub get_rev {
	my $self = shift;
	return $self->{_rev};
}

sub get_gettext {
	my $self = shift;
	return $self->{_gettext_object};
}

sub set_gettext {
	my $self = shift;
	if (@_) {
		$self->{_gettext_object} = shift;
	}
	return $self->{_gettext_object};
}

sub get_theme {
	my $self = shift;
	return $self->{_icontheme};
}

sub get_tooltips {
	my $self = shift;
	return $self->{_tooltips};
}

sub set_tooltips {
	my $self = shift;
	if (@_) {
		$self->{_tooltips} = shift;
	}
	return $self->{_tooltips};
}

sub get_notification_object {
	my $self = shift;
	return $self->{_notification};
}

sub set_notification_object {
	my $self = shift;
	if (@_) {
		$self->{_notification} = shift;
	}
	return $self->{_notification};
}

sub get_globalsettings_object {
	my $self = shift;
	return $self->{_globalsettings};
}

sub set_globalsettings_object {
	my $self = shift;
	if (@_) {
		$self->{_globalsettings} = shift;
	}
	return $self->{_globalsettings};
}

sub get_rusf {
	my $self = shift;
	return $self->{_rusf};
}

sub set_rusf {
	my $self = shift;
	if (@_) {
		$self->{_rusf} = shift;
	}
	return $self->{_rusf};
}

sub get_ruof {
	my $self = shift;
	return $self->{_ruof};
}

sub set_ruof {
	my $self = shift;
	if (@_) {
		$self->{_ruof} = shift;
	}
	return $self->{_ruof};
}

sub get_ruu_tab {
	my $self = shift;
	return $self->{_ruu_tab};
}

sub set_ruu_tab {
	my $self = shift;
	if (@_) {
		$self->{_ruu_tab} = shift;
	}
	return $self->{_ruu_tab};
}

sub get_ruu_hosting {
	my $self = shift;
	return $self->{_ruu_hosting};
}

sub get_ruu_places {
	my $self = shift;
	return $self->{_ruu_places};
}

sub get_ruu_u1 {
	my $self = shift;
	return $self->{_ruu_u1};
}

sub set_ruu_hosting {
	my $self = shift;
	if (@_) {
		$self->{_ruu_hosting} = shift;
	}
	return $self->{_ruu_hosting};
}

sub set_ruu_places {
	my $self = shift;
	if (@_) {
		$self->{_ruu_places} = shift;
	}
	return $self->{_ruu_places};
}

sub set_ruu_u1 {
	my $self = shift;
	if (@_) {
		$self->{_ruu_u1} = shift;
	}
	return $self->{_ruu_u1};
}

sub get_debug {
	my $self = shift;
	return $self->{_debug_cparam};
}

sub set_debug {
	my $self = shift;
	if (@_) {
		$self->{_debug_cparam} = shift;
	}
	return $self->{_debug_cparam};
}

sub get_clear_cache {
	my $self = shift;
	return $self->{_clear_cache};
}

sub set_clear_cache {
	my $self = shift;
	if (@_) {
		$self->{_clear_cache} = shift;
	}
	return $self->{_clear_cache};
}

sub get_mainwindow {
	my $self = shift;
	return $self->{_mainwindow};
}

sub set_mainwindow {
	my $self = shift;
	if (@_) {
		$self->{_mainwindow} = shift;
	}
	return $self->{_mainwindow};
}

sub get_min {
	my $self = shift;
	return $self->{_min_cparam};
}

sub set_min {
	my $self = shift;
	if (@_) {
		$self->{_min_cparam} = shift;
	}
	return $self->{_min_cparam};
}

sub get_disable_systray {
	my $self = shift;
	return $self->{_disable_systray_cparam};
}

sub set_disable_systray {
	my $self = shift;
	if (@_) {
		$self->{_disable_systray_cparam} = shift;
	}
	return $self->{_disable_systray_cparam};
}

sub get_exit_after_capture {
	my $self = shift;
	return $self->{_exit_after_capture_cparam};
}

sub set_exit_after_capture {
	my $self = shift;
	if (@_) {
		$self->{_exit_after_capture_cparam} = shift;
	}
	return $self->{_exit_after_capture_cparam};
}

sub get_no_session {
	my $self = shift;
	return $self->{_no_session_cparam};
}

sub set_no_session {
	my $self = shift;
	if (@_) {
		$self->{_no_session_cparam} = shift;
	}
	return $self->{_no_session_cparam};
}

sub get_start_with {
	my $self = shift;
	return ($self->{_start_with}, $self->{_start_with_extra});
}

sub set_start_with {
	my $self = shift;
	if (@_) {
		$self->{_start_with} = shift;
		$self->{_start_with_extra} = shift;
	}
	return ($self->{_start_with}, $self->{_start_with_extra});
}

sub get_profile_to_start_with {
	my $self = shift;
	return $self->{_profile_to_start_with};
}

sub set_profile_to_start_with {
	my $self = shift;
	if (@_) {
		$self->{_profile_to_start_with} = shift;
	}
	return $self->{_profile_to_start_with};
}

sub get_export_filename {
	my $self = shift;
	return $self->{_export_filename};
}

sub set_export_filename {
	my $self = shift;
	if (@_) {
		$self->{_export_filename} = shift;
	}
	return $self->{_export_filename};
}

sub get_include_cursor {
	my $self = shift;
	return $self->{_include_cursor};
}

sub set_include_cursor {
	my $self = shift;
	if (@_) {
		$self->{_include_cursor} = shift;
	}
	return $self->{_include_cursor};
}

sub get_remove_cursor {
	my $self = shift;
	return $self->{_remove_cursor};
}

sub set_remove_cursor {
	my $self = shift;
	if (@_) {
		$self->{_remove_cursor} = shift;
	}
	return $self->{_remove_cursor};
}

sub get_delay {
	my $self = shift;
	return $self->{_delay};
}

sub set_delay {
	my $self = shift;
	if (@_) {
		$self->{_delay} = shift;
	}
	return $self->{_delay};
}

sub get_current_monitor {
	my $self = shift;
	my ( $window_at_pointer, $x, $y, $mask ) = Gtk2::Gdk->get_default_root_window->get_pointer;
	my $mon = Gtk2::Gdk::Screen->get_default->get_monitor_geometry( Gtk2::Gdk::Screen->get_default->get_monitor_at_point ($x, $y));
	return ($mon);
}

1;
