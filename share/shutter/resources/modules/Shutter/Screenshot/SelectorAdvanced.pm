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

package Shutter::Screenshot::SelectorAdvanced;

#modules
#--------------------------------------
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

	#call constructor of super class (gscrot_common, include_cursor, delay)
	my $self = $class->SUPER::new( shift, shift, shift );

	#FIXME
	#get them as params 
	#because there is a leak when 
	#we declare them each time
	my $v = shift;
	my $s= shift;
	
	$self->{_view} = $$v;
	$self->{_selector} = $$s;
	
	

	bless $self, $class;
	return $self;
}

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

	#create cairo context und layout
	my $cr     = Gtk2::Gdk::Cairo::Context->create($root_pixmap);
	my $layout = Gtk2::Pango::Cairo::create_layout($cr);
	$layout->set_width( int( $mon1->width / 2 ) * Gtk2::Pango->scale );
	$layout->set_wrap('word');

	#create font family and determine size
	my $size = int( $mon1->width * 0.02 );
	$layout->set_font_description( Gtk2::Pango::FontDescription->from_string("Sans $size") );
	my $text
		= $d->get(
		"Draw a rectangular area using the mouse. To take a screenshot, press the Enter key. Press Esc to quit."
		);
	$layout->set_markup("<span foreground='#FFFFFF'>$text</span>");

	#draw the rectangle
	$cr->set_source_rgba( 0, 0, 0, 0.8 );

	my ( $lw, $lh ) = $layout->get_pixel_size;

	my $w = $lw + $size * 2;
	my $h = $lh + $size * 2;
	my $x = int( ( $mon1->width - $w ) / 2 ) + $mon1->x;
	my $y = int( ( $mon1->height - $h ) / 2 ) + $mon1->y;
	my $r = 30;

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
	$cr->set_source_rgb( 0.0, 0.0, 1.0 );
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

	$self->{_view}->set_pixbuf($root_pixbuf);

	#~ $self->{_view}->set_tool($self->{_selector});

	my $select_window = Gtk2::Window->new('toplevel');
	$select_window->set_decorated(FALSE);
	$select_window->set_skip_taskbar_hint(TRUE);
	$select_window->set_skip_pager_hint(TRUE);
	$select_window->set_keep_above(TRUE);
	$select_window->add($self->{_view});
	$select_window->show_all;

	#all screen events are send to shutter
	my $grab_counter = 0;
	while ( !Gtk2::Gdk->pointer_is_grabbed && $grab_counter < 400 ) {
		Gtk2::Gdk->pointer_grab(
			$select_window->window,
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
		Gtk2::Gdk->keyboard_grab( $select_window->window, 1, Gtk2->get_current_event_time );
		$grab_counter++;
	}

	if ( Gtk2::Gdk->pointer_is_grabbed ) {

		Gtk2::Gdk::Event->handler_set(
			sub {
				my ( $event, $data ) = @_;
				return 0 unless defined $event;

				#quit on escape
				if ( $event->type eq 'key-press' ) {
					if ( $event->keyval == $Gtk2::Gdk::Keysyms{Escape} ) {
						$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );
						$self->{_selector}->signal_handler_disconnect ($self->{_selector_handler});
						$select_window->destroy;
						Gtk2::Gdk->flush;
					} elsif ( $event->keyval == $Gtk2::Gdk::Keysyms{Return} ) {
						$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );
						$self->{_selector}->signal_handler_disconnect ($self->{_selector_handler});
						$select_window->destroy;
						Gtk2::Gdk->flush;
						my $selection = $self->{_selector}->get_selection;

						if ($selection) {
							sleep 1 if $self->{_delay} < 1;
							$output
								= $self->get_pixbuf_from_drawable( $self->{_root}, $selection->x,
								$selection->y, $selection->width, $selection->height,
								$self->{_include_cursor},
								$self->{_delay} );
						} else {
							$output = 0;
						}
					}
				} else {
					Gtk2->main_do_event($event);
				}
			}
		);

		$select_window->move( $self->{_root}->{x}, $self->{_root}->{y} );
		$select_window->set_default_size( $self->{_root}->{w}, $self->{_root}->{h} );
		$select_window->show_all();
		$select_window->window->set_type_hint('dock');

		#see docs
		#http://library.gnome.org/devel/gtk/stable/GtkWindow.html
		#asks the window manager to move window to the given position.
		#Window managers are free to ignore this;
		#most window managers ignore requests for initial window positions
		#(instead using a user-defined placement algorithm) and
		#honor requests after the window has already been shown.
		$select_window->move( $self->{_root}->{x}, $self->{_root}->{y} );
		$select_window->set_size_request( $self->{_root}->{w}, $self->{_root}->{h} );

		$select_window->window->move_resize(
			$self->{_root}->{x},
			$self->{_root}->{y},
			$self->{_root}->{w},
			$self->{_root}->{h}
		);

		#finally focus it
		$select_window->window->focus(time);

		Gtk2->main();

	}else{
		$output = 0;
		$select_window->destroy;
	}

	return $output;
}

1;
