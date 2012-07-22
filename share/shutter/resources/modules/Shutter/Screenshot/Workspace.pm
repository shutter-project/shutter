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

sub workspaces {
	my $self = shift;

	my $d = $self->{_sc}->get_gettext;

	my $active_workspace = $self->{_wnck_screen}->get_active_workspace;
	
	#valid workspace?
	return TRUE unless $active_workspace;

	my $active_vpx = $active_workspace->get_viewport_x;
	my $active_vpy = $active_workspace->get_viewport_y;

	#create shutter region object
	my $sr = Shutter::Geometry::Region->new();
	
	#variables to save the pixbuf
	my $output = undef;
	my $pixbuf = undef;

	my $wspaces_region = Gtk2::Gdk::Region->new;
	my @pixbuf_array;
	my @rects_array;
	my $row 	= 0;
	my $column 	= 0;
	my $height 	= 0;
	my $width 	= 0;
	foreach my $space ( @{ $self->{_workspaces} } ) {
		next unless defined $space;

		#compiz
		if ( $self->{_wm_manager_name} =~ /compiz/i ){

			#calculate viewports with size of workspace
			my $vpx = $space->get_viewport_x;
			my $vpy = $space->get_viewport_y;

			my $n_viewports_column = int( $space->get_width / $self->{_wnck_screen}->get_width );
			my $n_viewports_rows   = int( $space->get_height / $self->{_wnck_screen}->get_height );

			#rows
			for ( my $j = 0; $j < $n_viewports_rows; $j++ ) {
				#columns
				for ( my $i = 0; $i < $n_viewports_column; $i++ ) {
					my @vp = ( $i * $self->{_wnck_screen}->get_width, $j * $self->{_wnck_screen}->get_height );
					
					#set coordinates
					$self->{_vpx} = $vp[0];
					$self->{_vpy} = $vp[1];
					
					#and disable workspace
					$self->{_selected_workspace} = undef;
					
					#capture viewport
					$pixbuf = $self->workspace(TRUE, TRUE);
										
					my $rect = Gtk2::Gdk::Rectangle->new($width, $height, $pixbuf->get_width, $pixbuf->get_height);
					$wspaces_region->union_with_rect($rect);
					push @pixbuf_array, $pixbuf;
					push @rects_array, $rect;			

					#increase width according to current column
					$width += $pixbuf->get_width;
					
				}
				
				#next row
				# > set height to clipbox-height
				# > set width to 0, because we start in column 0 again
				$height	= $sr->get_clipbox($wspaces_region)->height;
				$width 	= 0;
			
			}


		#all other wm manager like metacity etc.		
		}else{

			#capture next workspace
			$self->{_selected_workspace} = $space->get_number;
			#~ print "Capturing Workspace: ".$space->get_number." Layout-Row:". $space->get_layout_row ." Layout-Column:". $space->get_layout_column ."\n";
			$pixbuf = $self->workspace(TRUE, TRUE);

			if ($column < $space->get_layout_column){
				$width += $pixbuf->get_width;			
			}elsif ($column > $space->get_layout_column){
				$width = 0;	
			}
			$column = $space->get_layout_column;
			
			$height = $sr->get_clipbox($wspaces_region)->height if ($row != $space->get_layout_row);
			$row = $space->get_layout_row;
			
			my $rect = Gtk2::Gdk::Rectangle->new($width, $height, $pixbuf->get_width, $pixbuf->get_height);
			$wspaces_region->union_with_rect($rect);
			push @pixbuf_array, $pixbuf;
			push @rects_array, $rect;			
			
		}
				
	}

	if($wspaces_region->get_rectangles){
		$output = Gtk2::Gdk::Pixbuf->new ('rgb', TRUE, 8, $sr->get_clipbox($wspaces_region)->width, $sr->get_clipbox($wspaces_region)->height);	
		$output->fill(0x00000000);
		
		#copy images to the blank pixbuf
		my $rect_counter = 0;
		foreach my $pixbuf (@pixbuf_array){
			$pixbuf->copy_area (0, 0, $pixbuf->get_width, $pixbuf->get_height, $output, $rects_array[$rect_counter]->x, $rects_array[$rect_counter]->y);
			$rect_counter++;
		}	
	}
	
	#this value will be overwritten - restore for history
	$self->{_selected_workspace} = 'all';

	#set history object
	$self->{_history} = Shutter::Screenshot::History->new($self->{_sc});	

	#set name of the captured workspace
	#e.g. for use in wildcards
	if($output =~ /Gtk2/){
		$self->{_action_name} = $d->get("Workspaces");
	}

	#compiz
	if ( $self->{_wm_manager_name} =~ /compiz/i ){
		$self->{_wnck_screen}->move_viewport( $active_vpx, $active_vpy );
	#metacity etc.
	}else{
		$active_workspace->activate(Gtk2->get_current_event_time);
	}
	
	return $output;
}

sub workspace {
	my $self 			= shift;
	my $no_active_check	= shift || FALSE;
	my $no_finishing 	= shift || FALSE;

	my $wrksp_changed = FALSE;

	my $active_workspace = $self->{_wnck_screen}->get_active_workspace;
	
	#valid workspace?
	return TRUE unless $active_workspace;
	
	my $active_vpx = $active_workspace->get_viewport_x;
	my $active_vpy = $active_workspace->get_viewport_y;

	#metacity etc
	if ( defined $self->{_selected_workspace} ) {
		foreach my $space ( @{ $self->{_workspaces} } ) {
			next unless defined $space;
			if ( $self->{_selected_workspace} == $space->get_number
				&& ($no_active_check || $self->{_selected_workspace} != $active_workspace->get_number) )
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

	unless($no_finishing){

		#set history object
		$self->{_history} = Shutter::Screenshot::History->new($self->{_sc});	

		#set name of the captured workspace
		#e.g. for use in wildcards
		if($output =~ /Gtk2/){
			$self->{_action_name} = $self->{_wnck_screen}->get_active_workspace->get_name;
		}

		#metacity etc
		if ( $self->{_selected_workspace} ) {
			$active_workspace->activate(Gtk2->get_current_event_time) if $wrksp_changed;
		#compiz
		} else {
			$self->{_wnck_screen}->move_viewport( $active_vpx, $active_vpy );
		}

	}

	return $output;
}

sub redo_capture {
	my $self = shift;
	my $output = 3;
	if(defined $self->{_history} && $self->{_selected_workspace} eq 'all'){
		$output = $self->workspaces();
	}elsif(defined $self->{_history}){
		$output = $self->workspace();
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

1;
