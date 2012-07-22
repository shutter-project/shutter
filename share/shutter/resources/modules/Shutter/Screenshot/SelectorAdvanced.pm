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

package Shutter::Screenshot::SelectorAdvanced;

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

	$self->{_zoom_active} 	= shift;
	$self->{_hide_time}		= shift;   #a short timeout to give the server a chance to redraw the area that was obscured
	$self->{_show_help}		= shift;   #hide help text?

	#FIXME
	#get them as params 
	#because there is a leak when 
	#we declare them each time	
	$self->{_view} 		= shift;
	$self->{_selector} 	= shift;
	$self->{_dragger} 	= shift;
	
	#initial selection size
	$self->{_init_x} = shift;
	$self->{_init_y} = shift;
	$self->{_init_w} = shift;
	$self->{_init_h} = shift;
	
	#WORKAROUND
	#upstream bug
	#http://trac.bjourne.webfactional.com/ticket/21						
	#left  => zoom in
	#right => zoom out
	$self->{_view}->signal_connect('scroll-event', sub{
		my ($view, $ev) = @_;		
		if($ev->direction eq 'left'){
			$ev->direction('up');
		}elsif($ev->direction eq 'right'){
			$ev->direction('down');
		}
		return FALSE;
	});

	bless $self, $class;
	return $self;
}

#~ sub DESTROY {
    #~ my $self = shift;
    #~ print "$self dying at\n";
#~ } 

sub select_advanced {
	my $self = shift;
	
	#return value
	my $output = 5;

	my $d = $self->{_sc}->get_gettext;

	#create pixbuf (root window)
	my $clean_pixbuf = Gtk2::Gdk::Pixbuf->get_from_drawable(
		$self->{_root}, undef, 0, 0, 0, 0,
		$self->{_root}->{w},
		$self->{_root}->{h}
	);

	$self->{_view}->set_pixbuf($clean_pixbuf);

	#show help text (do not show help text if predefined selection area is enabled)?
	if($self->{_init_w} < 1 || $self->{_init_h} < 1) {
		if($self->{_show_help}) {
		
			Glib::Idle->add(sub{
				
				#we display the tip only on the current monitor
				#if we would use the root window we would display the next
				#right in the middle of both screens, this is pretty ugly
				my $mon1 = $self->get_current_monitor;

				print "Using monitor: "
					. $mon1->x . " - "
					. $mon1->y . " - "
					. $mon1->width . " - "
					. $mon1->height . "\n"
					if $self->{_sc}->get_debug;

				#obtain current colors and font_desc from the main window
				my $style = $self->{_sc}->get_mainwindow->get_style;
				my $sel_bg = Gtk2::Gdk::Color->parse('#131313');
				my $sel_tx = $style->text('selected');
				my $font_fam = $style->font_desc->get_family;
				my $font_size = $style->font_desc->get_size / Gtk2::Pango->scale;
				
				#create cairo context und layout
				my $surface = Cairo::ImageSurface->create( 'argb32', $self->{_root}->{w}, $self->{_root}->{h} );
				my $cr = Cairo::Context->create($surface);

				#set_source_pixbuf
				Gtk2::Gdk::Cairo::Context::set_source_pixbuf( $cr, $clean_pixbuf, 0, 0 );
				$cr->paint;

				my $layout = Gtk2::Pango::Cairo::create_layout($cr);
				$layout->set_width( int( $mon1->width / 2 ) * Gtk2::Pango->scale );
				$layout->set_alignment('left');
				$layout->set_wrap('word');
				
				#determine font-size
				my $size1 = int ($font_size * 2.0);
				my $size2 = int ($font_size * 1.5);
				my $size3 = int ($font_size * 1.0);
				
				my $text1 = 
					$d->get("Draw a rectangular area using the mouse.");
				
				my $text2 =
					$d->get("To take a screenshot, press the Enter key. Press Esc to quit.");

				my $text3 = 
					$d->get("<b>shift/right-click</b> → selection dialog on/off")."\n".
					$d->get("<b>ctrl + scrollwheel</b> → zoom in/out")."\n".
					$d->get("<b>space</b> → zoom window on/off")."\n".
					$d->get("<b>cursor keys</b> → move cursor")."\n".
					$d->get("<b>cursor keys + alt</b> → move selection")."\n".
					$d->get("<b>cursor keys + ctrl</b> → resize selection");

				#use this one for white font-color	
				$layout->set_markup("<span font_desc=\"$font_fam $size1\" foreground=\"#FFFFFF\">$text1</span>\n<span font_desc=\"$font_fam $size2\" foreground=\"#FFFFFF\">$text2</span>\n\n<span font_desc=\"$font_fam $size3\" foreground=\"#FFFFFF\">$text3</span>");
				
				#draw the rectangle
				$cr->set_source_rgba( $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255, 0.85 );

				my ( $lw, $lh ) = $layout->get_pixel_size;

				my $w = $lw + $size1 * 2;
				my $h = $lh + $size1 * 2;
				my $x = int( ( $mon1->width - $w ) / 2 ) + $mon1->x;
				my $y = int( ( $mon1->height - $h ) / 2 ) + $mon1->y;
				my $r = 20;

				$cr->move_to( $x + $r, $y );
				$cr->line_to( $x + $w - $r, $y );
				$cr->curve_to( $x + $w, $y, $x + $w, $y, $x + $w, $y + $r );
				$cr->line_to( $x + $w, $y + $h - $r );
				$cr->curve_to( $x + $w, $y + $h, $x + $w, $y + $h, $x + $w - $r, $y + $h );
				$cr->line_to( $x + $r, $y + $h );
				$cr->curve_to( $x, $y + $h, $x, $y + $h, $x, $y + $h - $r );
				$cr->line_to( $x, $y + $r );
				$cr->curve_to( $x, $y, $x, $y, $x + $r, $y );
				$cr->fill;

				$cr->move_to( $x + $size1, $y + $size1 );
				
				#draw the pango layout
				Gtk2::Pango::Cairo::show_layout( $cr, $layout );

				#write surface to pixbuf
				my $loader = Gtk2::Gdk::PixbufLoader->new;
				$surface->write_to_png_stream(
					sub {
						my ( $closure, $data ) = @_;
						$loader->write($data);
					}
				);
				$loader->close;
				
				#set pixbuf
				$self->{_view}->set_pixbuf($loader->get_pixbuf);

				return FALSE;
			});

		}
	}

	#define zoom window
	$self->{_zoom_window} = Gtk2::Window->new('popup');
	$self->{_zoom_window}->set_decorated(FALSE);
	$self->{_zoom_window}->set_skip_taskbar_hint(TRUE);
	$self->{_zoom_window}->set_skip_pager_hint(TRUE);	
	$self->{_zoom_window}->set_keep_above(TRUE);
	$self->{_zoom_window}->set_accept_focus(FALSE);
	
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

	my $xlabel	= Gtk2::Label->new("X: ");
	my $ylabel	= Gtk2::Label->new("Y: ");
	my $rlabel	= Gtk2::Label->new("0 x 0");
	
	$ylabel->set_max_width_chars (10);
	$xlabel->set_max_width_chars (10);
	$rlabel->set_max_width_chars (10);
		
	my $zoom_vbox = Gtk2::VBox->new;
	$zoom_vbox->pack_start_defaults($scwin);
	$zoom_vbox->pack_start_defaults($xlabel);
	$zoom_vbox->pack_start_defaults($ylabel);
	$zoom_vbox->pack_start_defaults($rlabel);

	#do some packing
	$self->{_zoom_window}->add($zoom_vbox);
	$self->{_zoom_window}->move( $self->{_root}->{x}, $self->{_root}->{y} );
	
	#define shutter cursor (frame)
	my $shutter_cursor_pixbuf_frame = Gtk2::Gdk::Pixbuf->new_from_file(
		$self->{_sc}->get_root . "/share/shutter/resources/icons/shutter_cursor_frame.png" );

	#create root...
	my $root_item = Gnome2::Canvas::Item->new(
		$canvas_root,
		"Gnome2::Canvas::Pixbuf",
		x      => 0,
		y      => 0,
		pixbuf => $clean_pixbuf
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

	#window to manipulate the selection
	$self->{_prop_window} = $self->select_dialog();
	$self->{_prop_active} = FALSE;

	#window that contains the imageview widget
	$self->{_select_window} = Gtk2::Window->new('popup');
	$self->{_select_window}->set_type_hint('splashscreen');
	$self->{_select_window}->set_has_frame(FALSE);
	$self->{_select_window}->can_focus(TRUE);
	$self->{_select_window}->set_accept_focus(TRUE);
	$self->{_select_window}->set_modal(TRUE);
	$self->{_select_window}->set_decorated(FALSE);
	$self->{_select_window}->set_skip_taskbar_hint(TRUE);
	$self->{_select_window}->set_skip_pager_hint(TRUE);
	$self->{_select_window}->set_keep_above(TRUE);
	$self->{_select_window}->add($self->{_view});
	$self->{_select_window}->set_default_size($self->{_root}->{w}, $self->{_root}->{h});
	$self->{_select_window}->resize($self->{_root}->{w}, $self->{_root}->{h});
	$self->{_select_window}->move($self->{_root}->{x}, $self->{_root}->{y});	
	$self->{_select_window}->show_all;
	$self->{_select_window}->present;

	#init state flags
	if($self->{_show_help}) {
		$self->{_selector_init} = TRUE;
	}else{
		$self->{_selector_init} = FALSE;
	}
	$self->{_selector_init_zoom} = 0;

	#hide help text when selector is invoked
	$self->{_selector_handler} = $self->{_selector}->signal_connect(
		'selection-changed' => sub {
			
			#hide initial text
			if ($self->{_selector_init}) {
				$self->{_view}->set_pixbuf( $clean_pixbuf, FALSE );
				$self->{_selector_init} = FALSE;
				$self->{_selector_init_zoom}++;
			}
			
			#update prop dialog values
			$self->adjust_prop_values();
					
		}
	);

	#handle zoom events
	#ignore zoom values smaller 1
	$self->{_view_zoom_handler} = $self->{_view}->signal_connect(
		'zoom-changed' => sub {
			if($self->{_view}->get_zoom < 1){
				$self->{_view}->set_zoom(1);	
			}elsif($self->{_view}->get_zoom > 10){
				$self->{_view}->set_zoom(10);
			}elsif($self->{_view}->get_zoom > 1){
				if($self->{_zoom_active}){
					$self->{_zoom_window}->hide_all;	
				}
			}else{
				if($self->{_zoom_active}){
					$self->{_zoom_window}->show_all;
					$self->zoom_check_pos();	
				}					
			}
			
			#hide help text when zoomed
			if ($self->{_selector_init_zoom} == 1) {
				$self->{_view}->set_pixbuf( $clean_pixbuf, FALSE );
				$self->{_selector_init} = FALSE;
			}else{
				$self->{_selector_init_zoom}++;
			}

		}
	);

	#set initial size
	Glib::Idle->add(sub{	
		if($self->{_init_w} && $self->{_init_h}){
			$self->{_selector}->set_selection(
				Gtk2::Gdk::Rectangle->new($self->{_init_x}, $self->{_init_y}, $self->{_init_w}, $self->{_init_h})
			);			
		}
		return FALSE;
	});
	
	#event-handling
	#we simulate a 2button-press here	
	$self->{_view_button_handler} = $self->{_view}->signal_connect('button-press-event' =>
		sub {
			my ( $view, $event ) = @_;
			return FALSE unless defined $event;
			
			my $s = $self->{_selector}->get_selection;
			
			if ($event->button == 1) {
			
				unless(defined $self->{_dclick}){

					$self->{_dclick} = $event->time;
					return FALSE;	

				}else{

					if($event->time - $self->{_dclick} <= 500){
					
						$self->{_select_window}->hide;
						$self->{_zoom_window}->hide;
						$self->{_prop_window}->hide;
						
						#A short timeout to give the server a chance to
						#redraw the area
						Glib::Timeout->add ($self->{_hide_time}, sub{		
							Gtk2->main_quit;
							return FALSE;	
						});	
						Gtk2->main();

						$output = $self->take_screenshot($s, $clean_pixbuf);
						$self->quit;
					
					}else{
						
						$self->{_dclick} = $event->time;
						return FALSE;
					
					}					
				}

			}
		}
	);

	#event-handling
	#all other events
	$self->{_view_event_handler} = $self->{_view}->signal_connect('event' =>
		sub {
			my ( $window, $event ) = @_;
			return FALSE unless defined $event;

			my $s = $self->{_selector}->get_selection;				
			
			#~ print $event->type, "\n";
							
			#handle button-release event
			if ( $event->type eq 'button-release' ) {		
				
				if($event->button == 3){
					if($self->{_prop_active}){
						Gtk2::Gdk->keyboard_ungrab( Gtk2->get_current_event_time );
						$self->{_prop_window}->hide_all;
						$self->{_prop_active} = FALSE;
						Gtk2::Gdk->keyboard_grab( $self->{_select_window}->window, 0, Gtk2->get_current_event_time );
					}else{
						Gtk2::Gdk->keyboard_ungrab( Gtk2->get_current_event_time );
						my ( $window_at_pointer, $x, $y, $mask ) = $self->{_root}->get_pointer;
						$self->{_prop_window}->move( $x, $y );
						$self->{_prop_window}->show_all;
						$self->{_prop_active} = TRUE;	
					    Gtk2::Gdk->keyboard_grab( $self->{_prop_window}->window, 0, Gtk2->get_current_event_time );		
					}					
				}
								
			#handle motion-notify
			}elsif ( $event->type eq 'motion-notify' ) {

				#update zoom window
				if($self->{_zoom_active} && $self->{_view}->get_zoom == 1){
																
					my $s = $self->{_selector}->get_selection;
					my $v = $self->{_view}->get_viewport;
					
					my ( $window_at_pointer, $x, $y, $mask ) = $self->{_root}->get_pointer;

					#event coordinates
					my $ev_x = int($v->x / $self->{_view}->get_zoom + $x / $self->{_view}->get_zoom);
					my $ev_y = int($v->y / $self->{_view}->get_zoom + $y / $self->{_view}->get_zoom);
				
					#sync cursor with selection
					my $cursor = $self->{_selector}->cursor_at_point ($x, $y);
					if(defined $s){
						
						my $sx = $s->x;
						my $sy = $s->y;
						my $sw = $s->width; 
						my $sh = $s->height;
						
						if($cursor->type eq 'bottom-right-corner'){

							$ev_x = $sx + $sw - 1;	 
							$ev_y = $sy + $sh - 1;
							
						}elsif($cursor->type eq 'right-side'){
							
							$ev_x = $sx + $sw - 1;	 
						
						}elsif($cursor->type eq 'top-right-corner'){
						
							$ev_x = $sx + $sw - 1;	 
							$ev_y = $sy;
							
						}elsif($cursor->type eq 'top-side'){
							
							$ev_y = $sy;
							
						}elsif($cursor->type eq 'top-left-corner'){
							
							$ev_x = $sx;	 
							$ev_y = $sy;
							
						}elsif($cursor->type eq 'left-side'){

							$ev_x = $sx;
									
						}elsif($cursor->type eq 'bottom-left-corner'){

							$ev_x = $sx;	 
							$ev_y = $sy + $sh - 1;
									
						}elsif($cursor->type eq 'bottom-side'){
							
							$ev_y = $sy + $sh - 1;			
						
						}
													
					}	

					#update label in zoom_window
					$xlabel->set_text( "X: " . ($ev_x + 1) );
					$ylabel->set_text( "Y: " . ($ev_y + 1) );
																	
					#check pos and geometry of the zoom window and move it if needed
					$self->zoom_check_pos();
				
					#move cursor on the canvas...
					$cursor_item->set(
						x      => $ev_x - 10,
						y      => $ev_y - 10,
					);
					
					#update scroll region
					#this is significantly faster than
					#scroll_to
					$canvas->set_scroll_region(
						$ev_x - 9,
						$ev_y - 9,
						$ev_x + 10,
						$ev_y + 10
					);
				
					#update zoom_window text
					if(defined $s){
						$rlabel->set_text( $s->width . " x " . $s->height );
					}else{
						$rlabel->set_text( "0 x 0" );
					}
									
				}#zoom active
															
			#handle key-press
			}elsif ( $event->type eq 'key-press' ) {
								
				#where is the pointer currently?
				my ( $window_at_pointer, $x, $y, $mask ) = $self->{_root}->get_pointer;

				#toggle zoom window
				if ( $event->keyval == Gtk2::Gdk->keyval_from_name('space') ) {
					
					if ($self->{_zoom_active}){
						$self->{_zoom_window}->hide_all;
						$self->{_zoom_active} = FALSE;
					}elsif($self->{_view}->get_zoom == 1){
						$self->zoom_check_pos();
						$self->{_zoom_active} = TRUE;
					} 

				#toggle prop dialog				
				}elsif ( $event->keyval == Gtk2::Gdk->keyval_from_name('Shift_L') || $event->keyval == Gtk2::Gdk->keyval_from_name('Shift_R') ) {
					
					if($self->{_prop_active}){
						Gtk2::Gdk->keyboard_ungrab( Gtk2->get_current_event_time );
						$self->{_prop_window}->hide_all;
						$self->{_prop_active} = FALSE;
						Gtk2::Gdk->keyboard_grab( $self->{_select_window}->window, 0, Gtk2->get_current_event_time );
					}else{
						Gtk2::Gdk->keyboard_ungrab( Gtk2->get_current_event_time );
						my ( $window_at_pointer, $x, $y, $mask ) = $self->{_root}->get_pointer;
						$self->{_prop_window}->move( $x, $y );
						$self->{_prop_window}->show_all;
						$self->{_prop_active} = TRUE;	
					    Gtk2::Gdk->keyboard_grab( $self->{_prop_window}->window, 0, Gtk2->get_current_event_time );		
					}
						
				#abort screenshot				
				}elsif ( $event->keyval == Gtk2::Gdk->keyval_from_name('Escape') ) {
											
					$self->quit;
				
				#move / resize selector
				} elsif ( $event->keyval == Gtk2::Gdk->keyval_from_name('Up') ) {
					
					if ($event->state >= 'control-mask' && $s){
						$s->height($s->height-1);
						$self->{_selector}->set_selection($s);
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->width + $s->x, $s->height + $s->y);		
					}elsif ($event->state >= 'mod1-mask' && $s){	
						$s->y($s->y-1);
						$self->{_selector}->set_selection($s);
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->x, $s->y);
					}else{
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x, $y-1);
					}
					
				} elsif ( $event->keyval == Gtk2::Gdk->keyval_from_name('Down') ) {

					if ($event->state >= 'control-mask' && $s){
						$s->height($s->height+1);
						$self->{_selector}->set_selection($s);
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->width + $s->x, $s->height + $s->y);					
					}elsif ($event->state >= 'control-mask'){
						$self->{_selector}->set_selection(
							Gtk2::Gdk::Rectangle->new($x, $y, 1, 2)
						);
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x+1, $y+2);							
					}elsif ($event->state >= 'mod1-mask' && $s){	
						$s->y($s->y+1);
						$self->{_selector}->set_selection($s);
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->x, $s->y);
					}else{
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x, $y+1);
					}
					
				} elsif ( $event->keyval == Gtk2::Gdk->keyval_from_name('Left') ) {

					if ($event->state >= 'control-mask' && $s){
						$s->width($s->width-1);
						$self->{_selector}->set_selection($s);
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->width + $s->x, $s->height + $s->y);
					}elsif ($event->state >= 'mod1-mask' && $s){	
						$s->x($s->x-1);
						$self->{_selector}->set_selection($s);
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->x, $s->y);
					}else{
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x-1, $y);
					}
					
				} elsif ( $event->keyval == Gtk2::Gdk->keyval_from_name('Right') ) {	

					if ($event->state >= 'control-mask' && $s){
						$s->width($s->width+1);
						$self->{_selector}->set_selection($s);
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->width + $s->x, $s->height + $s->y);	
					}elsif ($event->state >= 'control-mask'){
						$self->{_selector}->set_selection(
							Gtk2::Gdk::Rectangle->new($x, $y, 2, 1)
						);
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x+2, $y+1);
					}elsif ($event->state >= 'mod1-mask' && $s){	
						$s->x($s->x+1);
						$self->{_selector}->set_selection($s);
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->x, $s->y);
					}else{
						$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x+1, $y);
					}
				
				#zoom in
				} elsif ( 
					$event->keyval == Gtk2::Gdk->keyval_from_name('KP_Add') ||
					$event->keyval == Gtk2::Gdk->keyval_from_name('plus') ||
					$event->keyval == Gtk2::Gdk->keyval_from_name('equal')		
				) {	

					if ($event->state >= 'control-mask'){
						$self->{_view}->zoom_in;
					}

				#zoom out
				} elsif ( 
					$event->keyval == Gtk2::Gdk->keyval_from_name('KP_Subtract')||
					$event->keyval == Gtk2::Gdk->keyval_from_name('minus')
				) {	

					if ($event->state >= 'control-mask'){
						$self->{_view}->zoom_out;
					}

				#zoom normal
				} elsif ( 
					$event->keyval == Gtk2::Gdk->keyval_from_name('0')
				) {	

					if ($event->state >= 'control-mask'){
						$self->{_view}->set_zoom(1);
					}
												
				#take screenshot
				} elsif ( $event->keyval == Gtk2::Gdk->keyval_from_name('Return') || $event->keyval == Gtk2::Gdk->keyval_from_name('KP_Enter')) {
					
					$self->{_select_window}->hide;
					$self->{_zoom_window}->hide;
					$self->{_prop_window}->hide;
					
					#A short timeout to give the server a chance to
					#redraw the area
					Glib::Timeout->add ($self->{_hide_time}, sub{		
						Gtk2->main_quit;
						return FALSE;	
					});	
					Gtk2->main();
					
					$output = $self->take_screenshot($s, $clean_pixbuf);
					$self->quit;
									
				}
			}	
		}
	);
	
	my $status = Gtk2::Gdk->keyboard_grab( $self->{_select_window}->window, 0, Gtk2->get_current_event_time );
		
	#~ if($status eq 'success'){	
		if($self->{_zoom_active}){
			$self->{_zoom_window}->show_all;
			$self->{_zoom_window}->window->set_override_redirect(TRUE);
			$self->zoom_check_pos();
			$self->{_zoom_window}->window->raise;
		}
		Gtk2->main();
	#~ }else{
		#~ $output = 1;
		#~ $self->clean;
	#~ }

	return $output;
}

sub zoom_check_pos{
	my $self = shift;

	my $s = $self->{_selector}->get_selection;
	my $v = $self->{_view}->get_viewport;
	
	return FALSE unless defined $v;
	
	my ( $window_at_pointer, $x, $y, $mask ) = $self->{_root}->get_pointer;

	#event coordinates
	my $ev_x = int($v->x / $self->{_view}->get_zoom + $x / $self->{_view}->get_zoom);
	my $ev_y = int($v->y / $self->{_view}->get_zoom + $y / $self->{_view}->get_zoom);

	my ( $zw, $zh ) = $self->{_zoom_window}->get_size;
	my ( $zx, $zy ) = $self->{_zoom_window}->get_position;

	my $sregion  = undef;
	if ( defined $s ) {
		$sregion = Gtk2::Gdk::Region->rectangle (Gtk2::Gdk::Rectangle->new ($s->x - 50, $s->y - 50, $s->width + 50, $s->height + 50));
	}else{
		$sregion = Gtk2::Gdk::Region->rectangle (Gtk2::Gdk::Rectangle->new ($ev_x - 50, $ev_y - 50, 50, 50));						
	}
	
	my $otype = $sregion->rect_in(Gtk2::Gdk::Rectangle->new ($zx - 50, $zy - 50, $zw + 50, $zh + 50));					
	if($otype eq 'in' || $otype eq 'part' || !$self->{_zoom_window}->visible){
						
		my $moved = FALSE;
		#possible positions if we need to move the zoom window
		my @pos = (
			Gtk2::Gdk::Rectangle->new ($self->{_root}->{x}, $self->{_root}->{y}, 0, 0),
			Gtk2::Gdk::Rectangle->new (0, $self->{_root}->{h} - $zh, 0, 0),
			Gtk2::Gdk::Rectangle->new ($self->{_root}->{w} - $zw, $self->{_root}->{y}, 0, 0),
			Gtk2::Gdk::Rectangle->new ($self->{_root}->{w} - $zw, $self->{_root}->{h} - $zh, 0, 0)
		);

		foreach(@pos){
			
			my $otypet = $sregion->rect_in(Gtk2::Gdk::Rectangle->new ($_->x - 50, $_->y - 50, $zw + 50, $zh + 50));					
			if($otypet eq 'out'){
				$self->{_zoom_window}->move($_->x, $_->y);
				$self->{_zoom_window}->show_all;
				$moved = TRUE;
				last;
			}
		
		}
	
		#if window could not be moved without covering the selection area
		unless ($moved) {
			$moved = FALSE;
			$self->{_zoom_window}->hide_all;
		}
	}
	
}

sub adjust_prop_values{
	my $self 	= shift;

	#block 'value-change' handlers for widgets
	#so we do not apply the changes twice
	$self->{_x_spin_w}->signal_handler_block ($self->{_x_spin_w_handler});
	$self->{_y_spin_w}->signal_handler_block ($self->{_y_spin_w_handler});
	$self->{_width_spin_w}->signal_handler_block ($self->{_width_spin_w_handler});
	$self->{_height_spin_w}->signal_handler_block ($self->{_height_spin_w_handler});
	
	my $s = $self->{_selector}->get_selection;

	if ($s) {
		$self->{_x_spin_w}->set_value( $s->x );
		$self->{_x_spin_w}->set_range( 0, $self->{_root}->{w} - $s->width );
		
		$self->{_y_spin_w}->set_value( $s->y );
		$self->{_y_spin_w}->set_range( 0, $self->{_root}->{h} - $s->height );
		
		$self->{_width_spin_w}->set_value( $s->width );
		$self->{_width_spin_w}->set_range( 0, $self->{_root}->{w} - $s->x );
		
		$self->{_height_spin_w}->set_value( $s->height );				
		$self->{_height_spin_w}->set_range( 0, $self->{_root}->{h} - $s->y );			
	}	

	#unblock 'value-change' handlers for widgets
	$self->{_x_spin_w}->signal_handler_unblock ($self->{_x_spin_w_handler});
	$self->{_y_spin_w}->signal_handler_unblock ($self->{_y_spin_w_handler});
	$self->{_width_spin_w}->signal_handler_unblock ($self->{_width_spin_w_handler});
	$self->{_height_spin_w}->signal_handler_unblock ($self->{_height_spin_w_handler});
	
	return TRUE;

}

sub select_dialog {
	my $self = shift;
	
	my $d = $self->{_sc}->get_gettext;
	
	#current selection
	my $s = $self->{_selector}->get_selection;
	
	my $sx = 0;
	my $sy = 0;
	my $sw = 0; 
	my $sh = 0;	
	
	if(defined $s){
		$sx = $s->x;
		$sy = $s->y;
		$sw = $s->width; 
		$sh = $s->height;	
	}
	
	#X
	my $xw_label = Gtk2::Label->new( $d->get("X") . ":" );
	$self->{_x_spin_w} = Gtk2::SpinButton->new_with_range( 0, $self->{_root}->{w}, 1 );
	$self->{_x_spin_w}->set_value( $sx );
	$self->{_x_spin_w_handler} = $self->{_x_spin_w}->signal_connect(
		'value-changed' => sub {
			$self->{_selector}->set_selection(
				Gtk2::Gdk::Rectangle->new(
				$self->{_x_spin_w}->get_value, $self->{_y_spin_w}->get_value,
				$self->{_width_spin_w}->get_value, $self->{_height_spin_w}->get_value
				)
			);
		}
	);

	my $xw_hbox = Gtk2::HBox->new( FALSE, 5 );
	$xw_hbox->pack_start( $xw_label, FALSE, FALSE, 5 );
	$xw_hbox->pack_start( $self->{_x_spin_w}, FALSE, FALSE, 5 );

	#y
	my $yw_label = Gtk2::Label->new( $d->get("Y") . ":" );
	$self->{_y_spin_w} = Gtk2::SpinButton->new_with_range( 0, $self->{_root}->{h}, 1 );
	$self->{_y_spin_w}->set_value( $sy );
	$self->{_y_spin_w_handler} = $self->{_y_spin_w}->signal_connect(
		'value-changed' => sub {
			$self->{_selector}->set_selection(
				Gtk2::Gdk::Rectangle->new(
				$self->{_x_spin_w}->get_value, $self->{_y_spin_w}->get_value,
				$self->{_width_spin_w}->get_value, $self->{_height_spin_w}->get_value
				)
			);
		}
	);

	my $yw_hbox = Gtk2::HBox->new( FALSE, 5 );
	$yw_hbox->pack_start( $yw_label, FALSE, FALSE, 5 );
	$yw_hbox->pack_start( $self->{_y_spin_w}, FALSE, FALSE, 5 );

	#width
	my $widthw_label = Gtk2::Label->new( $d->get("Width") . ":" );
	$self->{_width_spin_w} = Gtk2::SpinButton->new_with_range( 0, $self->{_root}->{w}, 1 );
	$self->{_width_spin_w}->set_value( $sw );
	$self->{_width_spin_w_handler} = $self->{_width_spin_w}->signal_connect(
		'value-changed' => sub {
			$self->{_selector}->set_selection(
				Gtk2::Gdk::Rectangle->new(
				$self->{_x_spin_w}->get_value, $self->{_y_spin_w}->get_value,
				$self->{_width_spin_w}->get_value, $self->{_height_spin_w}->get_value
				)
			);
		}
	);

	my $ww_hbox = Gtk2::HBox->new( FALSE, 5 );
	$ww_hbox->pack_start( $widthw_label, FALSE, FALSE, 5 );
	$ww_hbox->pack_start( $self->{_width_spin_w}, FALSE, FALSE, 5 );

	#height
	my $heightw_label = Gtk2::Label->new( $d->get("Height") . ":" );
	$self->{_height_spin_w} = Gtk2::SpinButton->new_with_range( 0, $self->{_root}->{h}, 1 );
	$self->{_height_spin_w}->set_value( $sh );
	$self->{_height_spin_w_handler} = $self->{_height_spin_w}->signal_connect(
		'value-changed' => sub {
			$self->{_selector}->set_selection(
				Gtk2::Gdk::Rectangle->new(
				$self->{_x_spin_w}->get_value, $self->{_y_spin_w}->get_value,
				$self->{_width_spin_w}->get_value, $self->{_height_spin_w}->get_value
				)
			);
		}
	);

	my $hw_hbox = Gtk2::HBox->new( FALSE, 5 );
	$hw_hbox->pack_start( $heightw_label, FALSE, FALSE, 5 );
	$hw_hbox->pack_start( $self->{_height_spin_w}, FALSE, FALSE, 5 );

	my $prop_dialog = Gtk2::Window->new('toplevel');
	$prop_dialog->set_modal(TRUE);
	$prop_dialog->set_decorated(FALSE);
	$prop_dialog->set_skip_taskbar_hint(TRUE);
	$prop_dialog->set_skip_pager_hint(TRUE);	
	$prop_dialog->set_keep_above(TRUE);
	$prop_dialog->set_accept_focus(TRUE);
	$prop_dialog->set_resizable(FALSE);	

	$prop_dialog->signal_connect('key-press-event' => sub { 
		my $window = shift;
		my $event  = shift;
		
		#toggle zoom window
		if ( $event->keyval == Gtk2::Gdk->keyval_from_name('Space') ) {
			
			if ($self->{_zoom_active}){
				$self->{_zoom_window}->hide_all;
				$self->{_zoom_active} = FALSE;
			}elsif($self->{_view}->get_zoom == 1){
				$self->zoom_check_pos();
				$self->{_zoom_active} = TRUE;
			} 
	
		#toggle prop dialog				
		}elsif ( $event->keyval == Gtk2::Gdk->keyval_from_name('Shift_L') || $event->keyval == Gtk2::Gdk->keyval_from_name('Shift_R') ) {
			
			if($self->{_prop_active}){
				Gtk2::Gdk->keyboard_ungrab( Gtk2->get_current_event_time );
				$self->{_prop_window}->hide_all;
				$self->{_prop_active} = FALSE;
				Gtk2::Gdk->keyboard_grab( $self->{_select_window}->window, 0, Gtk2->get_current_event_time );
			}else{
				Gtk2::Gdk->keyboard_ungrab( Gtk2->get_current_event_time );
				my ( $window_at_pointer, $x, $y, $mask ) = $self->{_root}->get_pointer;
				$self->{_prop_window}->move( $x, $y );
				$self->{_prop_window}->show_all;
				$self->{_prop_active} = TRUE;	
			    Gtk2::Gdk->keyboard_grab( $self->{_prop_window}->window, 0, Gtk2->get_current_event_time );		
			}
				
		#abort screenshot				
		}elsif ( $event->keyval == Gtk2::Gdk->keyval_from_name('Escape') ) {
									
			$self->quit;
		
		}
			 
	});	

	my $hide_btn = Gtk2::Button->new_with_mnemonic( $d->get("_Hide") );
	$hide_btn->set_image( Gtk2::Image->new_from_stock( 'gtk-close', 'button' ) );
	$hide_btn->can_default(TRUE);
	$hide_btn->signal_connect('clicked' => sub { 
		Gtk2::Gdk->keyboard_ungrab( Gtk2->get_current_event_time );
		$prop_dialog->hide_all;
		$self->{_prop_active} = FALSE;
		Gtk2::Gdk->keyboard_grab( $self->{_select_window}->window, 0, Gtk2->get_current_event_time );		 
	});		

	#final_packing
	#all labels = one size
	$xw_label->set_alignment( 0, 0.5 );
	$yw_label->set_alignment( 0, 0.5 );
	$widthw_label->set_alignment( 0, 0.5 );
	$heightw_label->set_alignment( 0, 0.5 );

	my $sg_main = Gtk2::SizeGroup->new('horizontal');
	$sg_main->add_widget($xw_label);
	$sg_main->add_widget($yw_label);
	$sg_main->add_widget($widthw_label);
	$sg_main->add_widget($heightw_label);

	my $vbox = Gtk2::VBox->new( FALSE, 5 );	
	$vbox->pack_start( $xw_hbox, FALSE, FALSE, 3 );
	$vbox->pack_start( $yw_hbox, FALSE, FALSE, 3 );
	$vbox->pack_start( $ww_hbox, FALSE, FALSE, 3 );
	$vbox->pack_start( $hw_hbox, FALSE, FALSE, 3 );
	$vbox->pack_start( $hide_btn, FALSE, FALSE, 3 );

	#nice frame as well
	my $frame_label = Gtk2::Label->new;
	$frame_label->set_markup( "<b>" . $d->get("Selection") . "</b>" );

	my $frame = Gtk2::Frame->new();
	$frame->set_border_width(5);
	$frame->set_label_widget($frame_label);
	$frame->set_shadow_type('none');

	$frame->add($vbox);

	$prop_dialog->add($frame);
	
	$prop_dialog->realize;
	$prop_dialog->set_transient_for($self->{_select_window});
	$prop_dialog->window->set_override_redirect(TRUE);
	
	return $prop_dialog;
}	

sub take_screenshot {
	my $self 			= shift;
	my $s				= shift;
	my $clean_pixbuf	= shift;

	my $d = $self->{_sc}->get_gettext;
	
	my $output;
	#no delay? then we take a subsection of the pixbuf in memory
	if ($s && $clean_pixbuf && $self->{_delay} == 0) {
		$output = $clean_pixbuf->new_subpixbuf($s->x, $s->y, $s->width, $s->height);

		#include cursor
		if($self->{_include_cursor}){
			$output = $self->include_cursor( $s->x, $s->y, $s->width, $s->height, $self->{_root}, $output);
		}
	
	#if there is a delay != 0 set, we have to wait and get a new pixbuf from the root window
	}elsif ($s && $self->{_delay} != 0) {
		($output) = $self->get_pixbuf_from_drawable( $self->{_root}, $s->x, $s->y, $s->width, $s->height);
	
	#section not valid
	} else {
		$output = 0;
	}

	#we don't have a useful string for wildcards (e.g. $name)
	if($output =~ /Gtk2/){
		$self->{_action_name} = $d->get("Selection");
	}
	
	#set history object
	if($s){
		$self->{_history} = Shutter::Screenshot::History->new($self->{_sc}, $self->{_root}, $s->x, $s->y, $s->width, $s->height);
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

sub quit {
	my $self = shift;
	
	$self->ungrab_pointer_and_keyboard( FALSE, FALSE, TRUE );
	$self->clean;
}

sub clean {
	my $self = shift;
	
	$self->{_selector}->signal_handler_disconnect ($self->{_selector_handler});
	$self->{_view}->signal_handler_disconnect ($self->{_view_zoom_handler});
	$self->{_view}->signal_handler_disconnect ($self->{_view_button_handler});
	$self->{_view}->signal_handler_disconnect ($self->{_view_event_handler});
	$self->{_select_window}->destroy;
	$self->{_zoom_window}->destroy;
	$self->{_prop_window}->destroy;
}

1;
