###################################################
#
#  Copyright (C) 2008, 2009, 2010 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package Shutter::Screenshot::Workspace;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Shutter::Screenshot::Main;
use Shutter::Screenshot::History;
use Data::Dumper;
our @ISA = qw(Shutter::Screenshot::Main);

#Glib
use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;

	#call constructor of super class (shutter_common, include_cursor, delay, notify_timeout)
	my $self = $class->SUPER::new( shift, shift, shift, shift );

	$self->{_selected_workspace}   = shift;
	$self->{_vpx}                  = shift;
	$self->{_vpy}                  = shift;
	$self->{_current_monitor_only} = shift;

	bless $self, $class;
	return $self;
}

#~ sub DESTROY {
    #~ my $self = shift;
    #~ print "$self dying at\n";
#~ } 

sub workspace {
	my $self = shift;

	my $wrksp_changed = FALSE;

	my $active_workspace = $self->{_wnck_screen}->get_active_workspace;
	
	#valid workspace?
	return TRUE unless $active_workspace;
	
	my $active_vpx = $active_workspace->get_viewport_x;
	my $active_vpy = $active_workspace->get_viewport_y;

	#metacity etc
	if ( $self->{_selected_workspace} ) {
		foreach my $space ( @{ $self->{_workspaces} } ) {
			next unless defined $space;
			if (   $self->{_selected_workspace} == $space->get_number
				&& $self->{_selected_workspace} != $active_workspace->get_number )
			{
				$space->activate(Gtk2->get_current_event_time);
				$wrksp_changed = TRUE;
			}
		}

		#compiz
	} else {
		$self->{_wnck_screen}->move_viewport( $self->{_vpx}, $self->{_vpy} );
		$wrksp_changed = TRUE;
	}

	#we need a minimum delay of 1 second
	#to give the server a chance to
	#redraw after switching workspaces
	if ( $self->{_delay} < 2 && $wrksp_changed ) {
		$self->{_delay} = 1;
	}

	my $output = undef;
	if ( $self->{_current_monitor_only} || $self->{_gdk_screen}->get_n_monitors <= 1) {
		
		($output) = $self->get_pixbuf_from_drawable(
						$self->get_root_and_current_monitor_geometry
					);

	#When there are multiple monitors with different resolutions, the visible area
	#within the root window may not be rectangular (it may have an L-shape, for
	#example). In that case, mask out the areas of the root window which would
	#not be visible in the monitors, so that screenshot do not end up with content
	#that the user won't ever see.
	#
	#comment copied from gnome-screenshot
	#http://svn.gnome.org/viewvc/gnome-utils/trunk/gnome-screenshot/screenshot-utils.c?view=markup					
	} elsif($self->{_gdk_screen}->get_n_monitors > 1) {
		
		($output) = $self->get_pixbuf_from_drawable(
						$self->get_root_and_geometry,
						$self->get_monitor_region
					);
										
	}

	#set history object
	$self->{_history} = Shutter::Screenshot::History->new($self->{_sc});	

	#set name of the captured workspace
	#e.g. for use in wildcards
	if($output =~ /Gtk2/){
		$output->{'name'} = $self->{_wnck_screen}->get_active_workspace->get_name;
	}

	#metacity etc
	if ( $self->{_selected_workspace} ) {
		$active_workspace->activate(Gtk2->get_current_event_time) if $wrksp_changed;
	#compiz
	} else {
		$self->{_wnck_screen}->move_viewport( $active_vpx, $active_vpy );
	}

	return $output;
}

sub redo_capture {
	my $self = shift;
	my $output = 3;
	if(defined $self->{_history}){
		$output = $self->workspace();
	}
	return $output;
}	

1;
