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

#perl -x -S perltidy -l=0 -b "%f"

package Shutter::Screenshot::SelectorGnomeWayland;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Shutter::Screenshot::Main;
use Shutter::Screenshot::History;
use File::Temp qw/ tempfile tempdir /;

use Data::Dumper;
our @ISA = qw(Shutter::Screenshot::Main);

#Glib
use Glib qw/TRUE FALSE/;

#--------------------------------------

sub new {
	my $class = shift;

	#call constructor of super class (shutter_common, include_cursor, delay, notify_timeout)
	my $self = $class->SUPER::new(shift, shift, shift, shift);

	$self->{_hide_time}   = shift;    #a short timeout to give the server a chance to redraw the area that was obscured

	$self->{_dpi_scale} = Gtk3::Window->new('toplevel')->get('scale-factor');

	bless $self, $class;
	return $self;
}

sub select_gnome_wayland {
	my $self = shift;

	#return value
	my $output = 5;
	
	my $cmdcursor = undef;

	if ($self->{_include_cursor}) {
		$cmdcursor = "-p";
	}
	else {
		$cmdcursor = "";
	}
	
	#A short timeout to give the server a chance to
	#redraw the area
	Glib::Timeout->add(
		$self->{_hide_time},
		sub {
			Gtk3->main_quit;
			return FALSE;
		});
	Gtk3->main();	
	 
	my $fh = File::Temp->new();
	my $tmpfilename = $fh->filename;
	
	system("gnome-screenshot", "-a", "-f", $tmpfilename, "-d", $self->{_delay}, $cmdcursor);
	
	my $image = Gtk3::Image->new();
	$image->set_from_file($tmpfilename);
	$output = $image->get_pixbuf();

	my $d = $self->{_sc}->get_gettext;

	return $output;
}


sub redo_capture {
	my $self   = shift;
	my $output = 3;
	if (defined $self->{_history}) {
		($output) = $self->get_pixbuf_from_drawable($self->{_history}->get_last_capture);
	}
	return $output;
}

sub get_history {
	my $self = shift;
	return $self->{_history};
}

sub get_error_text {
	my $self = shift;
	return $self->{_error_text};
}

sub get_action_name {
	my $self = shift;
	return $self->{_action_name};
}

sub quit {
	my $self = shift;

	$self->ungrab_pointer_and_keyboard(FALSE, FALSE, TRUE);
	$self->clean;
}

sub clean {
	my $self = shift;

	$self->{_selector}->signal_handler_disconnect($self->{_selector_handler});
	$self->{_view}->signal_handler_disconnect($self->{_view_zoom_handler});
	$self->{_view}->signal_handler_disconnect($self->{_view_button_handler});
	$self->{_view}->signal_handler_disconnect($self->{_view_event_handler});
	$self->{_select_window}->signal_handler_disconnect($self->{_key_handler});
	$self->{_select_window}->destroy;
	$self->{_zoom_window}->destroy;
	$self->{_prop_window}->destroy;
}

1;
