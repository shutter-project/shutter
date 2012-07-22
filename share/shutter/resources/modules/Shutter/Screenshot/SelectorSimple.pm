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

package Shutter::Screenshot::SelectorSimple;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Gnome2::Canvas;
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

	#subclass attributes
	$self->{_zoom_active}      = shift;
	$self->{_hide_time}		   = shift;   #a short timeout to give the server a chance to redraw the area that was obscured	

	bless $self, $class;
	return $self;
}

#~ sub DESTROY {
    #~ my $self = shift;
    #~ print "$self dying at\n";
#~ } 

sub select_simple {
	my $self = shift;

	#return value
	my $output = 5;

	#define zoom window
	my $zoom_window = Gtk2::Window->new('popup');
	$zoom_window->set_decorated(FALSE);
	$zoom_window->set_skip_taskbar_hint(TRUE);
	$zoom_window->set_skip_pager_hint(TRUE);	
	$zoom_window->set_keep_above(TRUE);
	
	#pack canvas to a scrolled window
	my $scwin = Gtk2::ScrolledWindow->new();
	$scwin->set_policy( 'never', 'never' );

	#define and setup the canvas
	my $canvas = Gnome2::Canvas->new();
	$canvas->set_size_request( 105, 105 );
	$canvas->modify_bg( 'normal', Gtk2::Gdk::Color->new( 65535, 65535, 65535 ) );
	$canvas->set_pixels_per_unit(5);
	
	my $canvas_root = $canvas->root();
	$scwin->add($canvas);

	my $xlabel  = Gtk2::Label->new("X: ");
	my $ylabel  = Gtk2::Label->new("Y: ");
	my $rlabel  = Gtk2::Label->new("0 x 0");
	
	$ylabel->set_max_width_chars (10);
	$xlabel->set_max_width_chars (10);
	$rlabel->set_max_width_chars (10);

	my $zoom_vbox = Gtk2::VBox->new;
	$zoom_vbox->pack_start_defaults($scwin);
	$zoom_vbox->pack_start_defaults($xlabel);
	$zoom_vbox->pack_start_defaults($ylabel);
	$zoom_vbox->pack_start_defaults($rlabel);

	#do some packing
	$zoom_window->add($zoom_vbox);
	$zoom_window->move( $self->{_root}->{x}, $self->{_root}->{y} );
	
	#define shutter cursor
	my $shutter_cursor_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file(
		$self->{_sc}->get_root . "/share/shutter/resources/icons/shutter_cursor.png" );

	my $shutter_cursor = Gtk2::Gdk::Cursor->new_from_pixbuf( Gtk2::Gdk::Display->get_default,
		$shutter_cursor_pixbuf, 10, 10 );	
	
	#define shutter cursor (frame)
	my $shutter_cursor_pixbuf_frame = Gtk2::Gdk::Pixbuf->new_from_file(
		$self->{_sc}->get_root . "/share/shutter/resources/icons/shutter_cursor_frame.png" );

	#create root...
	my $root_item = Gnome2::Canvas::Item->new(
		$canvas_root,
		"Gnome2::Canvas::Pixbuf",
		x      => 0,
		y      => 0,
		pixbuf => Gtk2::Gdk::Pixbuf->get_from_drawable(
			$self->{_root}, undef, 0, 0, 0, 0,
			$self->{_root}->{w},
			$self->{_root}->{h}
		),
	);

	#...and cursor icon
	my $cursor_item = Gnome2::Canvas::Item->new(
		$canvas_root,
		"Gnome2::Canvas::Pixbuf",
		x      => 0,
		y      => 0,
		pixbuf => $shutter_cursor_pixbuf_frame,
	);

	#starting point
	my ( $window_at_pointer, $xinit, $yinit, $mask ) = $self->{_root}->get_pointer;
	
	#move cursor on the canvas...
	$cursor_item->set(
		x      => $xinit - 10,
		y      => $yinit - 10,
	);
	
	#scroll region
	$canvas->set_scroll_region(
		$xinit - 9,
		$yinit - 9,
		$xinit + 10,
		$yinit + 10
	);

	#define graphics context
	my $gc = Gtk2::Gdk::GC->new( $self->{_root}, undef );
	$gc->set_line_attributes( 1, 'double-dash', 'butt', 'round' );
	$gc->set_rgb_fg_color(Gtk2::Gdk::Color->new( 65535, 65535, 65535 ));
	$gc->set_subwindow('include-inferiors');
	$gc->set_function('xor');

	#all screen events are send to shutter
	my $grab_counter = 0;
	while ( !Gtk2::Gdk->pointer_is_grabbed && $grab_counter < 400 ) {
		Gtk2::Gdk->pointer_grab(
			$self->{_root},
			0,
			[   qw/
					pointer-motion-mask
					button-press-mask
					button1-motion-mask
					button-release-mask/
			],
			undef,
			$shutter_cursor,
			Gtk2->get_current_event_time
		);
		Gtk2::Gdk->keyboard_grab( $self->{_root}, 1, Gtk2->get_current_event_time );
		$grab_counter++;
	}

	if ( Gtk2::Gdk->pointer_is_grabbed ) {
		
      #button1 pressed
      my $btn_pressed = 0;

      #rectangle coordinates
      my ( $rx, $ry, $rect_x, $rect_y, $rect_w, $rect_h ) = ( 0, 0, 0, 0, 0, 0 );
		
		Gtk2::Gdk::Event->handler_set(
			sub {
				my ( $event, $data ) = @_;
				return FALSE unless defined $event;
				
				if ( $event->type eq 'key-press' ) {
										
					#toggle zoom window
					if ( $event->keyval == Gtk2::Gdk->keyval_from_name('space') ) {
						if ($self->{_zoom_active}){
							$zoom_window->hide_all;
							$self->{_zoom_active} = FALSE;
						}else{
							$self->zoom_check_pos($zoom_window, $rect_x, $rect_y, $rect_w, $rect_h);
							$self->{_zoom_active} = TRUE;
						} 
					}
						
					#quit on escape
					if ( $event->keyval == Gtk2::Gdk->keyval_from_name('Escape') ) {
						if ( $rect_w > 1 ) {
							#clear the last rectangle
							$self->{_root}->draw_rectangle( $gc, 0, $rect_x, $rect_y, $rect_w, $rect_h );
						}
						
						$self->quit($zoom_window);

					}
					
				#take screenshot when button is released	
				} elsif ( $event->type eq 'button-release' ) {
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_debug_cparam} );
					
					#selection valid?
					if ( $rect_w > 1 ) {

						#clear the last rectangle
						$self->{_root}->draw_rectangle( $gc, 0, $rect_x, $rect_y, $rect_w, $rect_h );

						#hide zoom_window and disable Event Handler
						$zoom_window->hide;
						$self->ungrab_pointer_and_keyboard( FALSE, TRUE, FALSE );

						#A short timeout to give the server a chance to
						#redraw the area
						Glib::Timeout->add ($self->{_hide_time}, sub{		
							Gtk2->main_quit;
							return FALSE;	
						});	
						Gtk2->main();						

						($output) = $self->get_pixbuf_from_drawable( $self->{_root}, $rect_x, $rect_y, $rect_w+1, $rect_h+1);
						
						#we don't have a useful string for wildcards (e.g. $name)
						my $d = $self->{_sc}->get_gettext;
						if($output =~ /Gtk2/){
							$self->{_action_name} = $d->get("Selection");
						}
					
						#set history object
						$self->{_history} = Shutter::Screenshot::History->new($self->{_sc}, $self->{_root}, $rect_x, $rect_y, $rect_w+1, $rect_h+1);
						
						$self->quit($zoom_window);
						
					#return error	
					} else {
						$output = 0;
						$self->quit($zoom_window);
					}
					
				} elsif ( $event->type eq 'button-press' ) {
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_debug_cparam} );
					
					$btn_pressed = 1;

					#rectangle starts here...
					$rx = $event->x;
					$ry = $event->y;
					
				} elsif ( $event->type eq 'motion-notify' ) {
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_debug_cparam} );
					
					#update label in zoom_window
					$xlabel->set_text( "X: " . ($event->x + 1) );
					$ylabel->set_text( "Y: " . ($event->y + 1) );

					if($self->{_zoom_active}){
						
						#check pos and geometry of the zoom window and move it if needed
						$self->zoom_check_pos($zoom_window, $rect_x, $rect_y, $rect_w, $rect_h, $event);
	
						#move cursor on the canvas...
						$cursor_item->set(
							x      => $event->x - 10,
							y      => $event->y - 10,
						);
						
						#update scroll region
						#this is significantly faster than
						#scroll_to
						$canvas->set_scroll_region(
							$event->x - 9,
							$event->y - 9,
							$event->x + 10,
							$event->y + 10
						);
											
					}
		
					if ($btn_pressed) {

						#redraw last rect to clear it
						if ( $rect_w > 0 ) {
							$self->{_root}->draw_rectangle( $gc, 0, $rect_x, $rect_y, $rect_w, $rect_h );
						}
						
						#calculate dimensions of rect
						$rect_x = $rx;
						$rect_y = $ry;
						$rect_w = $event->x - $rect_x;
						$rect_h = $event->y - $rect_y;
						if ( $rect_w < 0 ) {
							$rect_x += $rect_w;
							$rect_w = -$rect_w;
						}
						if ( $rect_h < 0 ) {
							$rect_y += $rect_h;
							$rect_h = -$rect_h;
						}

						#update zoom_window text
						$rlabel->set_text( ($rect_w + 1) . " x " . ($rect_h + 1) );

						#draw new rect to the root window
						if ( $rect_w != 0 ) {
							$self->{_root}->draw_rectangle( $gc, 0, $rect_x, $rect_y, $rect_w, $rect_h );							
						}
					}
					
				} else {
					Gtk2->main_do_event($event);
				}
			}
		);
		
		#enable zoom window
		if($self->{_zoom_active}){
			$zoom_window->show_all;
			$self->zoom_check_pos($zoom_window);
			$zoom_window->window->set_override_redirect (TRUE);
		}
		
      #Main Loop
		Gtk2->main;
		
	#pointer not grabbed
	} else {    
		
		$zoom_window->destroy;
		$self->ungrab_pointer_and_keyboard( FALSE, FALSE, FALSE );	
		$output = 0;
	
	}
	
	return $output;
}

sub redo_capture {
	my $self = shift;
	my $output = 3;
	if(defined $self->{_history}){
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

sub zoom_check_pos{
	my $self 		= shift;
	my $zoom_window = shift;
	my $rect_x 		= shift;
	my $rect_y		= shift;
	my $rect_w		= shift;
	my $rect_h		= shift;
	my $event		= shift;

	my ( $zw, $zh ) = $zoom_window->get_size;
	my ( $zx, $zy ) = $zoom_window->get_position;

	my $sregion = undef;
	if ( defined $rect_w && $rect_w > 1 ) {
		$sregion = Gtk2::Gdk::Region->rectangle (Gtk2::Gdk::Rectangle->new ($rect_x - 150, $rect_y - 150, $rect_w + 150, $rect_h + 150));
	}elsif(defined $event){
		$sregion = Gtk2::Gdk::Region->rectangle (Gtk2::Gdk::Rectangle->new ($event->x - 150, $event->y - 150, 150, 150));						
	}else{
		my ( $window_at_pointer, $x, $y, $mask ) = $self->{_root}->get_pointer;
		$sregion = Gtk2::Gdk::Region->rectangle (Gtk2::Gdk::Rectangle->new ($x - 150, $y - 150, 150, 150));				
	}
	
	my $otype = $sregion->rect_in(Gtk2::Gdk::Rectangle->new ($zx - 150, $zy - 150, $zw + 150, $zh + 150));					
	if($otype eq 'in' || $otype eq 'part' || !$zoom_window->visible){
						
		my $moved = FALSE;
		#possible positions if we need to move the zoom window
		my @pos = (
			Gtk2::Gdk::Rectangle->new ($self->{_root}->{x}, $self->{_root}->{y}, 0, 0),
			Gtk2::Gdk::Rectangle->new (0, $self->{_root}->{h} - $zh, 0, 0),
			Gtk2::Gdk::Rectangle->new ($self->{_root}->{w} - $zw, $self->{_root}->{y}, 0, 0),
			Gtk2::Gdk::Rectangle->new ($self->{_root}->{w} - $zw, $self->{_root}->{h} - $zh, 0, 0)
		);
	
		foreach(@pos){
			
			my $otypet = $sregion->rect_in(Gtk2::Gdk::Rectangle->new ($_->x - 150, $_->y - 150, $zw + 150, $zh + 150));					
			if($otypet eq 'out'){
				#~ print $zoom_window, "\n";
				$zoom_window->move($_->x, $_->y);
				$zoom_window->show_all;
				$moved = TRUE;
				last;
			}
		
		}
		
		#if window could not be moved without covering the selection area
		unless ($moved) {
			$moved = FALSE;
			$zoom_window->hide_all;
		}
	
	}

}

sub quit {
	my $self 		= shift;
	my $zoom_window = shift;
	
	$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );
	$zoom_window->destroy;
}

1;
