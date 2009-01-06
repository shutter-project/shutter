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

package GScrot::Screenshot::SelectorSimple;

#modules
#--------------------------------------
use utf8;
use strict;
use Gnome2::Canvas;
use GScrot::Screenshot::Main;
our @ISA = qw(GScrot::Screenshot::Main);

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

sub new {
	my $class = shift;

	#call constructor of super class (gscrot_common, include_cursor, delay)
	my $self = $class->SUPER::new( shift, shift, shift );

	#subclass attributes
	$self->{_zoom_size_factor} = shift;
	$self->{_zoom_active}      = shift;

	bless $self, $class;
	return $self;
}

sub select_simple {
	my $self = shift;

	#return value
	my $output = 5;

	my $root_item   = undef;
	my $cursor_item = undef;

	#define zoom window
	my $zoom_window = Gtk2::Window->new('toplevel');
	$zoom_window->set_decorated(FALSE);
	$zoom_window->set_skip_taskbar_hint(TRUE);
	$zoom_window->set_keep_above(TRUE);
	my ( $zoom_window_width, $zoom_window_height ) = $zoom_window->get_size;
	my ( $zoom_window_x,     $zoom_window_y )      = $zoom_window->get_position;
	my $zoom_window_init = TRUE;

	#pack canvas to a scrolled window
	my $scwin = Gtk2::ScrolledWindow->new();
	$scwin->set_size_request( 100 * $self->{_zoom_size_factor}, 100 * $self->{_zoom_size_factor} );
	$scwin->set_policy( 'never', 'never' );

	#define and setup the canvas
	my $canvas = Gnome2::Canvas->new();
	$canvas->modify_bg( 'normal', Gtk2::Gdk::Color->new( 65535, 65535, 65535 ) );
	$canvas->set_pixels_per_unit(5);
	$canvas->set_scroll_region(
		-10 * $self->{_zoom_size_factor},
		-10 * $self->{_zoom_size_factor},
		$self->{_root}->{w} + 50 * $self->{_zoom_size_factor},
		$self->{_root}->{h} + 50 * $self->{_zoom_size_factor}
	);
	my $canvas_root = $canvas->root();
	$scwin->add($canvas);
	my $xlabel    = Gtk2::Label->new("X: ");
	my $ylabel    = Gtk2::Label->new("Y: ");
	my $rect      = Gtk2::Label->new("0 x 0");
	my $zoom_vbox = Gtk2::VBox->new;
	$zoom_vbox->pack_start_defaults($scwin);
	$zoom_vbox->pack_start_defaults($xlabel);
	$zoom_vbox->pack_start_defaults($ylabel);
	$zoom_vbox->pack_start_defaults($rect);

	#do some packing
	$zoom_window->add($zoom_vbox);
	$zoom_window->move( $self->{_root}->{x}, $self->{_root}->{y} );
	$root_item->destroy if defined($root_item);
	$root_item = Gnome2::Canvas::Item->new(
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

	#define gscrot cursor
	my $gscrot_cursor_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file(
		$self->{_gc}->get_root . "/share/gscrot/resources/icons/gscrot_cursor.png" );
	my $gscrot_cursor = Gtk2::Gdk::Cursor->new_from_pixbuf( Gtk2::Gdk::Display->get_default,
		$gscrot_cursor_pixbuf, 10, 10 );

	#define graphics context
	my $white = Gtk2::Gdk::Color->new( 65535, 65535, 65535 );
	my $black = Gtk2::Gdk::Color->new( 0,     0,     0 );
	my $gc = Gtk2::Gdk::GC->new( $self->{_root}, undef );
	$gc->set_line_attributes( 1, 'double-dash', 'round', 'round' );

	$gc->set_rgb_bg_color($black);
	$gc->set_rgb_fg_color($white);
	$gc->set_subwindow('include-inferiors');
	$gc->set_function('xor');
	$gc->set_exposures(TRUE);

	#all screen events are send to gscrot
	my $grab_counter = 0;
	while ( !Gtk2::Gdk->pointer_is_grabbed && $grab_counter < 100 ) {
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
			$gscrot_cursor,
			Gtk2->get_current_event_time
		);
		Gtk2::Gdk->keyboard_grab( $self->{_root}, 0, Gtk2->get_current_event_time );
		$grab_counter++;
	}

	if ( Gtk2::Gdk->pointer_is_grabbed ) {
		Gtk2::Gdk::X11->grab_server unless $self->{_zoom_active};
		my ( $rx, $ry, $rw, $rh, $rect_x, $rect_y, $rect_w, $rect_h ) = ( 0, 0, 0, 0, 0, 0, 0, 0 );
		my ( $btn_pressed, $last_selected_window ) = ( 0, 0 );
		my %smallest_coords = ();
		my $drawable        = undef;
		Gtk2::Gdk::Event->handler_set(
			sub {
				my ( $event, $data ) = @_;
				return 0 unless defined $event;

				#quit on escape
				if ( $event->type eq 'key-press' ) {
					if ( $event->keyval == $Gtk2::Gdk::Keysyms{Escape} ) {
						if ( $rect_w > 1 ) {

							#clear the last rectangle
							$self->{_root}
								->draw_rectangle( $gc, 0, $rect_x, $rect_y, $rect_w, $rect_h );
						}

						$zoom_window->destroy;
						Gtk2::Gdk->flush;

						$self->ungrab_pointer_and_keyboard( !$self->{_zoom_active}, TRUE, TRUE );

					}
				} elsif ( $event->type eq 'button-release' ) {
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_debug_cparam} );
					print "Trying to clear a rectangle ($rect_x, $rect_y, $rect_w, $rect_h)\n"
						if $self->{_debug_cparam};

					#capture is finished, delete zoom
					$zoom_window->destroy;
					Gtk2::Gdk->flush;

					$self->ungrab_pointer_and_keyboard( !$self->{_zoom_active}, TRUE, TRUE );

					if ( $rect_w > 1 ) {

						#clear the last rectangle
						$self->{_root}
							->draw_rectangle( $gc, 0, $rect_x, $rect_y, $rect_w, $rect_h );
						Gtk2::Gdk->flush;

						$output = $self->get_pixbuf_from_drawable(
							$self->{_root}, $rect_x, $rect_y,
							$rect_w + 1,
							$rect_h + 1,
							$self->{_include_cursor},
							$self->{_delay}
						);

					} else {
						$output = 0;
					}
				} elsif ( $event->type eq 'button-press' ) {
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_debug_cparam} );
					$btn_pressed = 1;
					if ( defined $smallest_coords{'last_win'} ) {
						$self->{_root}->draw_rectangle(
							$gc,
							0,
							$smallest_coords{'last_win'}->{'x'},
							$smallest_coords{'last_win'}->{'y'},
							$smallest_coords{'last_win'}->{'width'},
							$smallest_coords{'last_win'}->{'height'}
						);
					}

					#rectangle starts here...
					$rx = $event->x;
					$ry = $event->y;
				} elsif ( $event->type eq 'motion-notify' ) {
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_debug_cparam} );
					$xlabel->set_text( "X: " . $event->x );
					$ylabel->set_text( "Y: " . $event->y );

					#check pos and geometry of the zoom window and move it if needed
					( $zoom_window_width, $zoom_window_height ) = $zoom_window->get_size;
					( $zoom_window_x,     $zoom_window_y )      = $zoom_window->get_position;

					if ((      ( $event->x >= $zoom_window_x - 150 )
							&& ( $event->x <= ( $zoom_window_x + $zoom_window_width + 150 ) )
						)
						&& (   ( $event->y >= $zoom_window_y - 150 )
							&& ( $event->y <= ( $zoom_window_y + $zoom_window_height + 150 ) ) )
						)
					{

						if ($zoom_window_init) {
							$zoom_window->move( $self->{_root}->{x}, $self->{_root}->{y} );
							$zoom_window_init = FALSE;
						} else {
							$zoom_window->move( 0, $self->{_root}->{h} - $zoom_window_height );
							$zoom_window_init = TRUE;
						}
					}

					#~ #draw cursor on the canvas...
					$cursor_item->destroy if defined($cursor_item);
					$cursor_item = Gnome2::Canvas::Item->new(
						$canvas_root,
						"Gnome2::Canvas::Pixbuf",
						x      => $event->x - 10,
						y      => $event->y - 10,
						pixbuf => $gscrot_cursor_pixbuf,
					);

					#...scroll to centered position (*5 because of zoom factor)
					$canvas->scroll_to( $event->x * 5, $event->y * 5 );
					if ($btn_pressed) {

						#redraw last rect to clear it
						if ( $rect_w > 0 ) {
							print
								"Trying to clear a rectangle ($rect_x, $rect_y, $rect_w, $rect_h)\n"
								if $self->{_debug_cparam};

							$self->{_root}
								->draw_rectangle( $gc, 0, $rect_x, $rect_y, $rect_w, $rect_h );

						}
						$rect_x = $rx;
						$rect_y = $ry;
						$rect_w = $event->x - $rect_x;
						$rect_h = $event->y - $rect_y;
						if ( $rect_w < 0 ) {
							$rect_x += $rect_w;
							$rect_w = 0 - $rect_w;
						}
						if ( $rect_h < 0 ) {
							$rect_y += $rect_h;
							$rect_h = 0 - $rect_h;
						}

						my $print_w = $rect_w + 1;
						my $print_h = $rect_h + 1;
						$rect->set_text( $print_w . " x " . $print_h );

						#draw new rect to the root window
						if ( $rect_w != 0 ) {
							print
								"Trying to draw a rectangle ($rect_x, $rect_y, $rect_w, $rect_h)\n"
								if $self->{_debug_cparam};

							$self->{_root}
								->draw_rectangle( $gc, 0, $rect_x, $rect_y, $rect_w, $rect_h );

						}
					}
				} else {
					Gtk2->main_do_event($event);
				}
			},
			'rect'
		);
		$zoom_window->show_all if $self->{_zoom_active};
		Gtk2->main;
	} else {    #pointer not grabbed
		$zoom_window->destroy;
		Gtk2::Gdk->flush;

		$self->ungrab_pointer_and_keyboard( FALSE, FALSE, FALSE );

		$output = 0;
	}
	return $output;
}

1;
