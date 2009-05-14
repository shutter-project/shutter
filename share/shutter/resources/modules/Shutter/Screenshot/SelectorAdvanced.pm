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

package Shutter::Screenshot::SelectorAdvanced;

#modules
#--------------------------------------
use SelfLoader;
use utf8;
use strict;
use Shutter::Screenshot::Main;
use Data::Dumper;
our @ISA = qw(Shutter::Screenshot::Main);

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

sub new {
	my $class = shift;

	#call constructor of super class (shutter_common, include_cursor, delay)
	my $self = $class->SUPER::new( shift, shift, shift );

	#FIXME
	#get them as params 
	#because there is a leak when 
	#we declare them each time	
	$self->{_view} 		= shift;
	$self->{_selector} 	= shift;
	$self->{_dragger} 	= shift;

	bless $self, $class;
	return $self;
}

#~ 1;
#~ 
#~ __DATA__

sub select_advanced {
	my $self = shift;
	
	#return value
	my $output = 5;

	my $d = $self->{_gc}->get_gettext;

	my $root_pixbuf = Gtk2::Gdk::Pixbuf->get_from_drawable(
		$self->{_root}, undef, 0, 0, 0, 0,
		$self->{_root}->{w},
		$self->{_root}->{h}
	);

	my $root_pixmap = Gtk2::Gdk::Pixmap->new(
		undef,
		$self->{_root}->{w},
		$self->{_root}->{h},
		$self->{_root}->get_depth
	);

	my $gc = Gtk2::Gdk::GC->new($root_pixmap);

	$root_pixmap->draw_pixbuf(
		$gc, $root_pixbuf, 0, 0, 0, 0,
		$self->{_root}->{w},
		$self->{_root}->{h},
		'none', 0, 0
	);

	#we display the tip only on the current monitor
	#if we would use the root window we would display the next
	#right in the middle of both screens, this is pretty ugly
	my $mon1 = $self->get_current_monitor;

	print "Using monitor: "
		. $mon1->x . " - "
		. $mon1->y . " - "
		. $mon1->width . " - "
		. $mon1->height . "\n"
		if $self->{_gc}->get_debug;

	#obtain current colors and font_desc from the main window
    my $style 		= $self->{_gc}->get_mainwindow->get_style;
	my $sel_bg 		= $style->bg('selected');
	my $sel_tx 		= $style->text('selected');
	my $font_fam 	= $style->font_desc->get_family;

	#create cairo context und layout
	my $cr     = Gtk2::Gdk::Cairo::Context->create($root_pixmap);
	my $layout = Gtk2::Pango::Cairo::create_layout($cr);
	$layout->set_width( int( $mon1->width / 2 ) * Gtk2::Pango->scale );
	$layout->set_justify(TRUE);
	$layout->set_alignment('center');
	$layout->set_wrap('word');
	
	#determine font-size
	my $size = int( $mon1->width * 0.014 );
	my $size2 = int( $mon1->width * 0.009 );
	
	my $text
		= $d->get(
		"Draw a rectangular area using the mouse. To take a screenshot, press the Enter key. Press Esc to quit."
		);

	my $sec_text
		= $d->get(
		"ctrl + scrollwheel = zoom in/out\ncursor keys + alt = move selection\ncursor keys + ctrl = resize selection"
		);
	$layout->set_markup("<span font_desc=\"$font_fam $size\" foreground=\"#FFFFFF\">$text</span>\n\n<span font_desc=\"$font_fam $size2\" foreground=\"#FFFFFF\">$sec_text</span>");

	#draw the rectangle
	$cr->set_source_rgba( $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255, 0.85 );

	my ( $lw, $lh ) = $layout->get_pixel_size;

	my $w = $lw + $size * 2;
	my $h = $lh + $size * 2;
	my $x = int( ( $mon1->width - $w ) / 2 ) + $mon1->x;
	my $y = int( ( $mon1->height - $h ) / 2 ) + $mon1->y;
	my $r = 40;

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

	#...and place the text above
	$cr->set_source_rgba( $sel_tx->red / 257 / 255, $sel_tx->green / 257 / 255, $sel_tx->blue / 257 / 255, 0.8 );
	$cr->set_operator('over');
	$cr->move_to( $x + $size, $y + $size );

	Gtk2::Pango::Cairo::show_layout( $cr, $layout );

	#keep a clean copy of the pixbuf and show it
	#after pressing the mouse button
	my $clean_pixbuf = $root_pixbuf->copy;

	$root_pixbuf = Gtk2::Gdk::Pixbuf->get_from_drawable(
		$root_pixmap, undef, 0, 0, 0, 0,
		$self->{_root}->{w},
		$self->{_root}->{h}
	);

	#~ my $self->{_view}          = Gtk2::ImageView->new;
	#~ my $self->{_selector}      = Gtk2::ImageView::Tool::Selector->new($self->{_view});
	$self->{_selector_init} = TRUE;

	#hide help text when selector is invoked
	$self->{_selector_handler} = $self->{_selector}->signal_connect(
		'selection-changed' => sub {
			if ($self->{_selector_init}) {
				$self->{_view}->set_pixbuf( $clean_pixbuf, FALSE );
				$self->{_selector_init} = FALSE;
			}
		}
	);

	#handle zoom events
	#ignore zoom values smaller 1
	$self->{_view_zoom_handler} = $self->{_view}->signal_connect(
		'zoom-changed' => sub {
			if($self->{_view}->get_zoom < 1){
				$self->{_view}->set_zoom(1);	
			}
		}
	);

	$self->{_view}->set_pixbuf($root_pixbuf);

	#~ $self->{_view}->set_tool($self->{_selector});

	$self->{_select_window} = Gtk2::Window->new('toplevel');
	$self->{_select_window}->set_type_hint('dock');
	$self->{_select_window}->set_decorated(FALSE);
	$self->{_select_window}->set_skip_taskbar_hint(TRUE);
	$self->{_select_window}->set_skip_pager_hint(TRUE);
	$self->{_select_window}->set_keep_above(TRUE);
	$self->{_select_window}->add($self->{_view});
	$self->{_select_window}->show_all;

	#all screen events are send to shutter
	my $grab_counter = 0;
	while ( !Gtk2::Gdk->pointer_is_grabbed && $grab_counter < 400 ) {
		Gtk2::Gdk->pointer_grab(
			$self->{_select_window}->window,
			1,
			[   qw/
					pointer-motion-mask
					button-press-mask
					button1-motion-mask
					button-release-mask/
			],
			undef,
			undef,
			Gtk2->get_current_event_time
		);
		Gtk2::Gdk->keyboard_grab( $self->{_select_window}->window, 1, Gtk2->get_current_event_time );
		$grab_counter++;
	}

	if ( Gtk2::Gdk->pointer_is_grabbed ) {

		Gtk2::Gdk::Event->handler_set(
			sub {
				my ( $event, $data ) = @_;
				return 0 unless defined $event;

				my $s = $self->{_selector}->get_selection;				
								
				#handle button-press
				if ( $event->type eq 'button-press') {		


					#see docs
					#http://library.gnome.org/devel/gdk/stable/gdk-Events.html
					#
					#GDK_2BUTTON_PRESS
					#a mouse button has been double-clicked 
					#(clicked twice within a short period of time). 
					#Note that each click also generates a GDK_BUTTON_PRESS event.
					#
					#we peek the next event to check it is a GDK_2BUTTON_PRESS 			
					my $ev1 = Gtk2::Gdk::Event->peek;
									
					if(defined $ev1){
						if($ev1->type eq '2button-press'){

							#left mouse button
							if($ev1->button == 1){			
								$output = $self->take_screenshot($s, $output);
							}

						}else{
							Gtk2->main_do_event($event);
							Gtk2->main_do_event($ev1);
						}
					}else{
						Gtk2->main_do_event($event);	
					}
					
				#handle key-press
				}elsif ( $event->type eq 'key-press' ) {
					
					#abort screenshot				
					if ( $event->keyval == $Gtk2::Gdk::Keysyms{Escape} ) {
												
						$self->quit;
					
					#move / resize selector
					} elsif ( $event->keyval == $Gtk2::Gdk::Keysyms{Up} && $s) {
						
						if ($event->state >= 'control-mask'){
							$s->height($s->height-1);
							$self->{_selector}->set_selection($s);							
						}elsif ($event->state >= 'mod1-mask'){	
							$s->y($s->y-1);
							$self->{_selector}->set_selection($s);
						}else{
							Gtk2->main_do_event($event);
						}
						
					} elsif ( $event->keyval == $Gtk2::Gdk::Keysyms{Down} && $s) {

						if ($event->state >= 'control-mask'){
							$s->height($s->height+1);
							$self->{_selector}->set_selection($s);						
						}elsif ($event->state >= 'mod1-mask'){	
							$s->y($s->y+1);
							$self->{_selector}->set_selection($s);
						}else{
							Gtk2->main_do_event($event);
						}
						
					} elsif ( $event->keyval == $Gtk2::Gdk::Keysyms{Left} && $s) {

						if ($event->state >= 'control-mask'){
							$s->width($s->width-1);
							$self->{_selector}->set_selection($s);
						}elsif ($event->state >= 'mod1-mask'){	
							$s->x($s->x-1);
							$self->{_selector}->set_selection($s);
						}else{
							Gtk2->main_do_event($event);
						}
						
					} elsif ( $event->keyval == $Gtk2::Gdk::Keysyms{Right} && $s) {	

						if ($event->state >= 'control-mask'){
							$s->width($s->width+1);
							$self->{_selector}->set_selection($s);
						}elsif ($event->state >= 'mod1-mask'){	
							$s->x($s->x+1);
							$self->{_selector}->set_selection($s);
						}else{
							Gtk2->main_do_event($event);
						}
													
					#take screenshot
					} elsif ( $event->keyval == $Gtk2::Gdk::Keysyms{Return}) {
						
						$output = $self->take_screenshot($s, $output);
										
					}else{
						Gtk2->main_do_event($event);
					}
				
				}else{
						Gtk2->main_do_event($event);		
				}	
			}
		);

		$self->{_select_window}->move( $self->{_root}->{x}, $self->{_root}->{y} );
		$self->{_select_window}->set_default_size( $self->{_root}->{w}, $self->{_root}->{h} );
		$self->{_select_window}->show_all();

		#see docs
		#http://library.gnome.org/devel/gtk/stable/GtkWindow.html
		#asks the window manager to move window to the given position.
		#Window managers are free to ignore this;
		#most window managers ignore requests for initial window positions
		#(instead using a user-defined placement algorithm) and
		#honor requests after the window has already been shown.
		$self->{_select_window}->move( $self->{_root}->{x}+100, $self->{_root}->{y}+100 );
		$self->{_select_window}->set_size_request( $self->{_root}->{w}, $self->{_root}->{h} );

		$self->{_select_window}->window->move_resize(
			$self->{_root}->{x},
			$self->{_root}->{y},
			$self->{_root}->{w},
			$self->{_root}->{h}
		);

		#finally focus it
		$self->{_select_window}->window->focus(time);

		Gtk2->main();

	}else{
		$output = 0;
		$self->{_select_window}->destroy;
	}

	return $output;
}

sub take_screenshot {
	my $self 			= shift;
	my $s				= shift;
	my $output 			= shift;

	$self->quit;

	if ($s) {
		sleep 1 if $self->{_delay} < 1;
		($output) = $self->get_pixbuf_from_drawable( 
			$self->{_root}, 
			$s->x, $s->y, $s->width, $s->height,
			$self->{_include_cursor},
			$self->{_delay} );
	} else {
		$output = 0;
	}
	
	return $output;	
	
}

sub quit {
	
	my $self = shift;
	
	$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );
	$self->{_selector}->signal_handler_disconnect ($self->{_selector_handler});
	$self->{_view}->signal_handler_disconnect ($self->{_view_zoom_handler});
	$self->{_select_window}->destroy;
	Gtk2::Gdk->flush;
	
}

1;
