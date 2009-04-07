###################################################
#
#  Copyright (C) Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package Shutter::Screenshot::Main;

#modules
#--------------------------------------
use utf8;
use strict;
use Gnome2::Wnck;
use Image::Magick;

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

##################public subs##################
sub new {
	my $class = shift;
	
	my $self = {
				 _gc  => shift,
				 _include_cursor => shift,
				 _delay          => shift,
			   };
			
	#root window
	$self->{ _root } = Gtk2::Gdk->get_default_root_window;
	(
	   $self->{ _root }->{ x },
	   $self->{ _root }->{ y },
	   $self->{ _root }->{ w },
	   $self->{ _root }->{ h }
	) = $self->{ _root }->get_geometry;
	( $self->{ _root }->{ x }, $self->{ _root }->{ y } ) =
		$self->{ _root }->get_origin;

	#wnck screen
	$self->{_wnck_screen} = Gnome2::Wnck::Screen->get_default;
	$self->{_wnck_screen}->force_update();	

	#gdk screen
	$self->{_gdk_screen} = Gtk2::Gdk::Screen->get_default;	
	
	#we determine the wm name but on older
	#version of libwnck (or the bindings)
	#the needed method is not available
	#in this case we use gdk to do it
	#
	#this leads to a known problem when switching
	#the wm => wm_name will still remain the old one
	$self->{_wm_manager_name} = $self->{_gdk_screen}->get_window_manager_name;
	if($self->{_wnck_screen}->can('get_window_manager_name')){
		$self->{_wm_manager_name} = $self->{_wnck_screen}->get_window_manager_name;
	}

	#workspaces
	$self->{_workspaces} = ();
	for ( my $wcount = 0 ; $wcount < $self->{_wnck_screen}->get_workspace_count ; $wcount++ )
	{
		push( @{$self->{_workspaces}}, $self->{_wnck_screen}->get_workspace( $wcount ) );
	}	

	bless $self, $class;
	return $self;
}

sub update_workspaces {
	my $self = shift;
	for ( my $wcount = 0 ; $wcount < $self->{_wnck_screen}->get_workspace_count ; $wcount++ )
	{
		push( @{$self->{_workspaces}}, $self->{_wnck_screen}->get_workspace( $wcount ) );
	}
	return $self->{_wnck_screen}->get_workspace_count;		
}

sub get_root_and_geometry {
	my $self = shift;
	return ($self->{_root}, $self->{_root}->{x}, $self->{_root}->{y}, $self->{_root}->{w}, $self->{_root}->{h});
}

sub get_root_and_current_monitor_geometry {
	my $self = shift;
	my $mainwindow = $self->{_gc}->get_mainwindow->window || $self->{_root};
	my $mon1       = $self->{_gdk_screen}
		->get_monitor_geometry( $self->{_gdk_screen}->get_monitor_at_window($mainwindow) );
	return ($self->{_root}, $mon1->x, $mon1->y, $mon1->width, $mon1->height);
}

sub get_current_monitor {
	my $self = shift;
	my $mainwindow = $self->{_gc}->get_mainwindow->window || $self->{_root};
	my $mon1       = $self->{_gdk_screen}
		->get_monitor_geometry( $self->{_gdk_screen}->get_monitor_at_window($mainwindow) );
	return ($mon1);
}

sub imagemagick_to_pixbuf {
	my ( $self, $blob, $width, $height ) = @_;
	my $pixbufloader = Gtk2::Gdk::PixbufLoader->new;
	$pixbufloader->set_size( $width, $height );
	$pixbufloader->write( $blob );
	$pixbufloader->close;
	my $pixbuf = $pixbufloader->get_pixbuf;

	return $pixbuf;
}

sub ungrab_pointer_and_keyboard {
	my ( $self, $ungrab_server, $quit_event_handler, $quit_main ) = @_;

	#ungrab pointer and keyboard
	Gtk2::Gdk::X11->ungrab_server if $ungrab_server;
	Gtk2::Gdk->pointer_ungrab( Gtk2->get_current_event_time );
	Gtk2::Gdk->keyboard_ungrab( Gtk2->get_current_event_time );
	Gtk2::Gdk::Event->handler_set( undef, undef ) if $quit_event_handler;
	Gtk2->main_quit if $quit_main;

	return TRUE unless Gtk2::Gdk->pointer_is_grabbed;
	return FALSE;
}

sub get_pixbuf_from_drawable {
	my ( $self, $drawable, $x, $y, $width, $height, $cursor, $sleep ) = @_;

	#sleep if there is any delay
	sleep $sleep if $sleep;

	#get the pixbuf from drawable and save the file
	#maybe window is partially not on the screen
	my $l_cropped = FALSE;
	my $r_cropped = FALSE;
	my $t_cropped = FALSE;
	my $b_cropped = FALSE;
	
	#right
	if ( $x + $width > $self->{ _root }->{ w } ) {
		$r_cropped = $x + $width - $self->{ _root }->{ w };
		$width -= $x + $width - $self->{ _root }->{ w };
	}
	
	#bottom
	if ( $y + $height > $self->{ _root }->{ h } ) {
		$b_cropped = $y + $height - $self->{ _root }->{ h };
		$height -= $y + $height - $self->{ _root }->{ h };
	}
	
	#left
	if ( $x < $self->{ _root }->{ x } ) {
		$l_cropped = $self->{ _root }->{ x } - $x;
		$width = $width + $x;
		$x     = 0;
	}
	
	#top
	if ( $y < $self->{ _root }->{ y } ) {
		$t_cropped = $self->{ _root }->{ y } - $y;
		$height = $height + $y;
		$y      = 0;
	}

	#get the pixbuf from drawable and save the file
	my $pixbuf =
		Gtk2::Gdk::Pixbuf->get_from_drawable( $drawable, undef, $x, $y, 0, 0,
											  $width, $height );

	$pixbuf = $self->include_cursor( $x, $y, $width, $height, $drawable, $pixbuf )
		if $self->{_include_cursor};

	return ($pixbuf, $l_cropped, $r_cropped, $t_cropped, $b_cropped);
}

#code ported and borrowed from gnome-screenshot
sub include_cursor {

	my ( $self, $xp, $yp, $widthp, $heightp, $gdk_window, $pixbuf ) = @_;

	my $cursor =
		Gtk2::Gdk::Cursor->new_for_display( Gtk2::Gdk::Display->get_default,
											'GDK_LEFT_PTR' );

#	my $cursor_pixbuf =
#		$x->XFixesGetCursorImage( Gtk2::Gdk::Display->get_default );

	my $cursor_pixbuf = $cursor->get_image;

	if ( $cursor_pixbuf ) {
		my ( $window_at_pointer, $x, $y, $mask ) = $gdk_window->get_pointer;

		my $r1 = Gtk2::Gdk::Rectangle->new( $xp, $yp, $widthp, $heightp );
		my $r2 = Gtk2::Gdk::Rectangle->new( $x, $y, $cursor_pixbuf->get_width,
											$cursor_pixbuf->get_height );

		if ( $r2 = $r1->intersect( $r2 ) ) {

			my $dest_y = $r2->y - $yp - 4;
			$dest_y = 0 if ( $dest_y < 0 );
			$cursor_pixbuf->composite(
									   $pixbuf,      $r2->x - $xp,
									   $dest_y,      $r2->width,
									   $r2->height,  $x - 6 - $xp,
									   $y - 4 - $yp, 1.0,
									   1.0,          'bilinear',
									   255
									 );
		}
	}

	return $pixbuf;
}

1;
