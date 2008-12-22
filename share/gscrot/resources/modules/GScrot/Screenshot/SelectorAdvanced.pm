###################################################
#
#  Copyright (C) Mario Kemper 2008 <mario.kemper@googlemail.com>
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

package GScrot::Screenshot::SelectorAdvanced;

#modules
#--------------------------------------
use utf8;
use strict;
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
		$self->{_root}->{h}, $self->{_root}->get_depth
	);

	my $gc = Gtk2::Gdk::GC->new ($root_pixmap);

	$root_pixmap->draw_pixbuf ($gc, $root_pixbuf, 0, 0, 0, 0 , $self->{_root}->{w}, $self->{_root}->{h}, 'none', 0, 0);

	my $scratch = Gtk2::Invisible->new;
	$scratch->realize;

	my $layout = Gtk2::Pango::Layout->new ($scratch->create_pango_context);
	my $size = int( $self->{_root}->{w} * 0.01 );

	$layout->set_font_description(Gtk2::Pango::FontDescription->from_string ("Sans $size"));

	my $text = $d->get(
		"Draw a rectangular area using the mouse.\nTo take a screenshot, press the Enter key. Press Esc to quit.");

	$layout->set_markup("<span foreground='#000000' background='#F1EEC4'>$text</span>");

	$root_pixmap->draw_layout ($gc, 0, 0, $layout);

	my $clean_pixbuf = $root_pixbuf->copy;

	$root_pixbuf = Gtk2::Gdk::Pixbuf->get_from_drawable(
		$root_pixmap, undef, 0, 0, 0, 0,
		$self->{_root}->{w},
		$self->{_root}->{h}
	);

	my $view          = Gtk2::ImageView->new;
	my $selector      = Gtk2::ImageView::Tool::Selector->new($view);
	my $selector_init = TRUE;

	#hide help text when selector is invoked
	my $selector_handler = $selector->signal_connect(
		'selection-changed' => sub {
			if ($selector_init) {
				$view->set_pixbuf( $clean_pixbuf, FALSE );
				$selector_init = FALSE;
			}
		}
	);

	$view->set_pixbuf($root_pixbuf);

	$view->set_tool($selector);

	my $select_window = Gtk2::Window->new('toplevel');
	$select_window->set_decorated(FALSE);
	$select_window->set_skip_taskbar_hint(TRUE);
	$select_window->set_skip_pager_hint(TRUE);
	$select_window->set_keep_above(TRUE);
	$select_window->add($view);
	$select_window->move( $self->{_root}->{x}, $self->{_root}->{y} );
	$select_window->set_default_size( $self->{_root}->{w}, $self->{_root}->{h} );

	Gtk2::Gdk->keyboard_grab( $self->{_root}, 0, Gtk2->get_current_event_time );

	Gtk2::Gdk::Event->handler_set(
		sub {
			my ( $event, $data ) = @_;
			return 0 unless defined $event;

			#quit on escape
			if ( $event->type eq 'key-press' ) {
				if ( $event->keyval == $Gtk2::Gdk::Keysyms{Escape} ) {
					$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );
					$select_window->destroy;
					Gtk2::Gdk->flush;
				} elsif ( $event->keyval == $Gtk2::Gdk::Keysyms{Return} ) {
					$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );
					$select_window->destroy;
					Gtk2::Gdk->flush;
					my $selection = $selector->get_selection;

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
		},
		'advanced'
	);

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

	return $output;
}

1;
