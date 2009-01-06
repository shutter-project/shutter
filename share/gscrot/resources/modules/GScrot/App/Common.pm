###################################################
#
#  Copyright (C) Mario Kemper 2008 - 2009 <mario.kemper@googlemail.com>
#
#  This file is part of GScrot.
#
#  GScrot is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  GScrot is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with GScrot; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
###################################################

package GScrot::App::Common;

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
	my $self = { _gscrot_root => shift };

	#vars
	$self->{_debug_cparam}           = FALSE;
	$self->{_clear_cache}            = FALSE;
	$self->{_min_cparam}             = FALSE;
	$self->{_disable_systray_cparam} = FALSE;
	$self->{_start_with}             = undef;
	$self->{_mainwindow}             = undef;

	#gettext init
	setlocale( LC_MESSAGES, "" );
	$self->{_gettext_object} = Locale::gettext->domain("gscrot");
	$self->{_gettext_object}->dir( $self->{_gscrot_root} . "/share/locale" );
	$ENV{'GSCROT_INTL'} = $self->{_gscrot_root} . "/share/locale";

	#tooltips
	$self->{_tooltips} = Gtk2::Tooltips->new;

	bless $self, $class;
	return $self;
}

#getter / setter
sub get_root {
	my $self = shift;
	return $self->{_gscrot_root};
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
