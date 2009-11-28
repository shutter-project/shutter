###################################################
#
#  Copyright (C) 2008, 2009 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
###################################################

package Shutter::App::Common;

#modules
#--------------------------------------
use utf8;
use strict;
use Gtk2;

#Gettext and filename parsing
use POSIX qw/setlocale strftime/;
use Locale::gettext;

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

##################public subs##################
sub new {
	my $class = shift;

	#constructor
	my $self = { _shutter_root => shift };

	#vars
	$self->{_debug_cparam}           = FALSE;
	$self->{_clear_cache}            = FALSE;
	$self->{_min_cparam}             = FALSE;
	$self->{_disable_systray_cparam} = FALSE;
	$self->{_start_with}             = undef;
	$self->{_mainwindow}             = undef;

	#gettext init
	setlocale( LC_MESSAGES, "" );
	$self->{_gettext_object} = Locale::gettext->domain("shutter");
	$self->{_gettext_object}->dir( $self->{_shutter_root} . "/share/locale" );
	
	#ENV needed by some plugins
	$ENV{'SHUTTER_INTL'} = $self->{_shutter_root} . "/share/locale";

	#tooltips
	$self->{_tooltips} = Gtk2::Tooltips->new;

	#notification object
	$self->{_notification};

	#icontheme to determine if icons exist or not
	#in some cases we deliver fallback icons
	$self->{_icontheme} = Gtk2::IconTheme->get_default;
	$self->{_icontheme}->append_search_path($self->{_shutter_root} . "/share/icons");

	bless $self, $class;
	return $self;
}

#getter / setter
sub get_root {
	my $self = shift;
	return $self->{_shutter_root};
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

sub get_start_with {
	my $self = shift;
	return $self->{_start_with};
}

sub set_start_with {
	my $self = shift;
	if (@_) {
		$self->{_start_with} = shift;
	}
	return $self->{_start_with};
}

1;
