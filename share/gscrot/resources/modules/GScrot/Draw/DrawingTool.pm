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

package GScrot::Draw::DrawingTool;

#modules
#--------------------------------------
use utf8;
use strict;
use Exporter;
use Goo::Canvas;
use File::Basename;

#--------------------------------------

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

sub new {
	my $class = shift;

	my $self = { _gscrot_common => shift };

	#file
	$self->{_filename} = undef;
	$self->{_filetype} = undef;

	#ui
	$self->{_uimanager} = undef;
	$self->{_factory}   = undef;

	#canvas data
	$self->{_canvas} = undef;
	$self->{_items}  = undef;

	#drawing colors
	$self->{_fill_color}         = Gtk2::Gdk::Color->parse('#0000ff');
	$self->{_fill_color_alpha}   = 0.25;
	$self->{_stroke_color}       = Gtk2::Gdk::Color->parse('#000000');
	$self->{_stroke_color_alpha} = 0.95;

	#help variables
	$self->{_last_item}          = undef;
	$self->{_current_item}       = undef;
	$self->{_current_new_item}   = undef;
	$self->{_current_mode}       = 10;
	$self->{_current_mode_descr} = "select";
	$self->{_current_pixbuf}     = undef;

	bless $self, $class;

	return $self;
}

sub show {
	my $self     = shift;
	my $filename = shift;
	my $filetype = shift;

	$self->{_filename} = $filename;
	$self->{_filetype} = $filetype;

	my $d = $self->{_gscrot_common}->get_gettext;

	$self->{_uimanager} = $self->setup_uimanager();

	$self->{_drawing_window} = Gtk2::Window->new('toplevel');
	$self->{_drawing_window}->set_title($filename);
	$self->{_drawing_window}->set_modal(1);
	$self->{_drawing_window}->signal_connect( 'destroy', \&quit );
	$self->{_drawing_window}
		->signal_connect( 'delete_event', sub { $self->{_drawing_window}->destroy() } );

	#load file
	$self->{_drawing_pixbuf} = Gtk2::Gdk::Pixbuf->new_from_file($filename);

	#create canvas
	$self->{_canvas} = Goo::Canvas->new();
	$self->{_canvas}->set_size_request( 640, 480 );

#	$self->{_canvas}->modify_bg( 'normal', Gtk2::Gdk::Color->parse( 'gray' ));

	$self->{_canvas}->set('background-color' => Gtk2::Gdk::Color->parse( 'gray' )->to_string);

	$self->{_canvas}->set_bounds(
		0, 0,
		$self->{_drawing_pixbuf}->get_width,
		$self->{_drawing_pixbuf}->get_height
	);
	my $root = $self->{_canvas}->get_root_item;

	$self->{_canvas_bg} = Goo::Canvas::Image->new( $root, $self->{_drawing_pixbuf}, 0, 0 );
	$self->setup_item_signals( $self->{_canvas_bg} );

	#packing
	my $scrolled_drawing_window = Gtk2::ScrolledWindow->new;
	$scrolled_drawing_window->set_policy( 'automatic', 'automatic' );
	$scrolled_drawing_window->add( $self->{_canvas} );

	my $drawing_vbox = Gtk2::VBox->new( FALSE, 0 );

	my $drawing_hbox = Gtk2::HBox->new( FALSE, 0 );

	$self->{_drawing_window}->add($drawing_vbox);

	my $toolbar_drawing = $self->{_uimanager}->get_widget("/ToolBarDrawing");
	$toolbar_drawing->set_orientation('vertical');
	$toolbar_drawing->set_style('icons');
	$toolbar_drawing->set_icon_size('menu');
	$toolbar_drawing->set_show_arrow(TRUE);
	$drawing_hbox->pack_start( $toolbar_drawing,         FALSE, FALSE, 0 );
	$drawing_hbox->pack_start( $scrolled_drawing_window, TRUE,  TRUE,  0 );

	my $toolbar = $self->{_uimanager}->get_widget("/ToolBar");
	$toolbar->set_show_arrow(TRUE);
	$drawing_vbox->pack_start( $self->{_uimanager}->get_widget("/ToolBar"), FALSE, FALSE, 0 );

	my $drawing_statusbar = Gtk2::Statusbar->new;
	$drawing_vbox->pack_start( $drawing_hbox,      TRUE,  TRUE,  0 );
	$drawing_vbox->pack_start( $drawing_statusbar, FALSE, FALSE, 0 );

	$self->{_drawing_window}->show_all();

	Gtk2->main;

	return TRUE;
}

sub change_drawing_tool_cb {
	my $self   = shift;
	my $action = shift;

	eval { $self->{_current_mode} = $action->get_current_value; };
	if ($@) {
		$self->{_current_mode} = $action;
	}

	if ( $self->{_current_mode} == 10 ) {
		$self->{_current_mode_descr} = "select";
	} elsif ( $self->{_current_mode} == 20 ) {
		$self->{_current_mode_descr} = "line";
	} elsif ( $self->{_current_mode} == 30 ) {
		$self->{_current_mode_descr} = "rect";
	} elsif ( $self->{_current_mode} == 40 ) {
		$self->{_current_mode_descr} = "ellipse";
	} elsif ( $self->{_current_mode} == 50 ) {
		$self->{_current_mode_descr} = "image";
	} elsif ( $self->{_current_mode} == 60 ) {
		$self->{_current_mode_descr} = "text";
	} elsif ( $self->{_current_mode} == 70 ) {
		$self->{_current_mode_descr} = "clear";
	}

	return TRUE;
}

sub selfcanvas {
	my $self = shift;
	print $self->{_canvas} . "\n";
}

sub zoom_in_cb {
	my $self = shift;
	$self->{_canvas}->set_scale( $self->{_canvas}->get_scale + 0.5 );
	return TRUE;
}

sub zoom_out_cb {
	my $self      = shift;
	my $new_scale = $self->{_canvas}->get_scale - 0.5;
	if ( $new_scale > 1 ) {
		$self->{_canvas}->set_scale($new_scale);
	} else {
		$self->{_canvas}->set_scale(1);
	}
	return TRUE;
}

sub zoom_normal_cb {
	my $self = shift;
	$self->{_canvas}->set_scale(1);
	return TRUE;
}

sub quit {
	my $self = shift;
	$self->{_drawing_window}->destroy if $self->{_drawing_window};
	Gtk2->main_quit();
	return TRUE;
}

sub save {
	my $self = shift;

	#make sure not to save the bounding rectangles
	$self->deactivate_all;

	my $surface = Cairo::ImageSurface->create(
		'argb32',
		$self->{_canvas_bg}->get('width'),
		$self->{_canvas_bg}->get('height')
	);

	my $cr = Cairo::Context->create($surface);
	my $root = $self->{_canvas}->get_root_item;
	$root->paint( $cr, $self->{_canvas_bg}->get_bounds , 1 );

	my $loader = Gtk2::Gdk::PixbufLoader->new;
	$surface->write_to_png_stream(
		sub {
			my ( $closure, $data ) = @_;
			$loader->write($data);
		}
	);
	$loader->close;
	my $pixbuf = $loader->get_pixbuf;

	$pixbuf->save( $self->{_filename}, $self->{_filetype} );
	$self->quit;

	return TRUE;
}

#ITEM SIGNALS
sub setup_item_signals {
	my ( $self, $item ) = @_;

	$item->signal_connect(
		'motion_notify_event',
		sub {
			my ( $item, $target, $ev ) = @_;
			$self->event_item_on_motion_notify( $item, $target, $ev );
		}
	);
	$item->signal_connect(
		'button_press_event',
		sub {
			my ( $item, $target, $ev ) = @_;
			$self->event_item_on_button_press( $item, $target, $ev );
		}
	);
	$item->signal_connect(
		'button_release_event',
		sub {
			my ( $item, $target, $ev ) = @_;
			$self->event_item_on_button_release( $item, $target, $ev );
		}
	);

	return TRUE;
}

sub setup_item_signals_extra {
	my ( $self, $item ) = @_;

	$item->signal_connect(
		'enter_notify_event',
		sub {
			my ( $item, $target, $ev ) = @_;
			$self->event_item_on_enter_notify( $item, $target, $ev );
		}
	);

	$item->signal_connect(
		'leave_notify_event',
		sub {
			my ( $item, $target, $ev ) = @_;
			$self->event_item_on_leave_notify( $item, $target, $ev );
		}
	);

	return TRUE;
}

sub event_item_on_motion_notify {
	my ( $self, $item, $target, $ev ) = @_;

	#move
	if ( $item->{dragging} && $ev->state >= 'button1-mask' ) {

		if ( $item->isa('Goo::Canvas::Rect') ) {

			my $new_x = $self->{_items}{$item}->get('x') + $ev->x - $item->{drag_x};
			my $new_y = $self->{_items}{$item}->get('y') + $ev->y - $item->{drag_y};

			$self->{_items}{$item}->set(
				'x' => $new_x,
				'y' => $new_y,
			);

			$item->{drag_x} = $ev->x;
			$item->{drag_y} = $ev->y;

			$self->handle_rects( 'update', $item );
			$self->handle_embedded( 'update', $item );

		} elsif ( $item->isa('Goo::Canvas::Ellipse')
			|| $item->isa('Goo::Canvas::Text')
			|| $item->isa('Goo::Canvas::Image') )
		{

			my $parent = $self->get_parent_item($item);

			if ($parent) {
				my $new_x = $self->{_items}{$parent}->get('x') + $ev->x - $item->{drag_x};
				my $new_y = $self->{_items}{$parent}->get('y') + $ev->y - $item->{drag_y};

				$self->{_items}{$parent}->set(
					'x' => $new_x,
					'y' => $new_y,
				);

				$item->{drag_x} = $ev->x;
				$item->{drag_y} = $ev->y;

				$self->handle_rects( 'update', $parent );
				$self->handle_embedded( 'update', $parent );

				#no rect and no parent? => we are handling the background image here
			} else {
	  #				$self->{_canvas}->scroll_to( $ev->x, $ev->y );
	  #				$self->{_canvas}->request_redraw(Goo::Canvas::Bounds->new($self->{_canvas}->get_bounds));
			}

		} else {

			$item->translate( $ev->x - $item->{drag_x}, $ev->y - $item->{drag_y} );

		}

		#freehand line
	} elsif ( $self->{_current_mode_descr} eq "line" && $ev->state >= 'button1-mask' ) {

		my $item = $self->{_current_new_item};

		push @{ $self->{_items}{$item}{'points'} }, $ev->x, $ev->y;
		$self->{_items}{$item}
			->set( points => Goo::Canvas::Points->new( $self->{_items}{$item}{'points'} ) );

		#items
	} elsif (
		(      $self->{_current_mode_descr} eq "rect"
			|| $self->{_current_mode_descr} eq "ellipse"
			|| $self->{_current_mode_descr} eq "text"
			|| $self->{_current_mode_descr} eq "image"
		)
		&& $ev->state >= 'button1-mask'
		)
	{

		my $item = $self->{_current_new_item};

		my $new_width  = $ev->x - $self->{_items}{$item}->get('x');
		my $new_height = $ev->y - $self->{_items}{$item}->get('y');

		$new_width  = 1 if $new_width < 1;
		$new_height = 1 if $new_height < 1;

		$self->{_items}{$item}->set(
			'width'  => $new_width,
			'height' => $new_height,
		);

		$self->handle_rects( 'update', $item );
		$self->handle_embedded( 'update', $item );

	} elsif ( $item->{resizing} && $ev->state >= 'button1-mask' ) {

		my $curr_item = $self->{_current_item};

		foreach ( keys %{ $self->{_items}{$curr_item} } ) {

			#fancy resizing using our little resize boxes
			if ( $item == $self->{_items}{$curr_item}{$_} ) {

				my $new_x      = 0;
				my $new_y      = 0;
				my $new_width  = 0;
				my $new_height = 0;

				if ( $_ =~ /top.*left/ ) {

					$new_x = $self->{_items}{$curr_item}->get('x') + $ev->x - $item->{res_x};
					$new_y = $self->{_items}{$curr_item}->get('y') + $ev->y - $item->{res_y};

					$new_width = $self->{_items}{$curr_item}->get('width')
						+ ( $self->{_items}{$curr_item}->get('x') - $new_x );
					$new_height = $self->{_items}{$curr_item}->get('height')
						+ ( $self->{_items}{$curr_item}->get('y') - $new_y );

				} elsif ( $_ =~ /top.*middle/ ) {

					$new_x = $self->{_items}{$curr_item}->get('x');
					$new_y = $self->{_items}{$curr_item}->get('y') + $ev->y - $item->{res_y};

					$new_width  = $self->{_items}{$curr_item}->get('width');
					$new_height = $self->{_items}{$curr_item}->get('height')
						+ ( $self->{_items}{$curr_item}->get('y') - $new_y );
				} elsif ( $_ =~ /top.*right/ ) {

					$new_x = $self->{_items}{$curr_item}->get('x');
					$new_y = $self->{_items}{$curr_item}->get('y') + $ev->y - $item->{res_y};

					$new_width
						= $self->{_items}{$curr_item}->get('width') + ( $ev->x - $item->{res_x} );
					$new_height = $self->{_items}{$curr_item}->get('height')
						+ ( $self->{_items}{$curr_item}->get('y') - $new_y );

				} elsif ( $_ =~ /middle.*left/ ) {

					$new_x = $self->{_items}{$curr_item}->get('x') + $ev->x - $item->{res_x};
					$new_y = $self->{_items}{$curr_item}->get('y');

					$new_width = $self->{_items}{$curr_item}->get('width')
						+ ( $self->{_items}{$curr_item}->get('x') - $new_x );
					$new_height = $self->{_items}{$curr_item}->get('height');

				} elsif ( $_ =~ /middle.*right/ ) {

					$new_x = $self->{_items}{$curr_item}->get('x');
					$new_y = $self->{_items}{$curr_item}->get('y');

					$new_width
						= $self->{_items}{$curr_item}->get('width') + ( $ev->x - $item->{res_x} );
					$new_height = $self->{_items}{$curr_item}->get('height');

				} elsif ( $_ =~ /bottom.*left/ ) {

					$new_x = $self->{_items}{$curr_item}->get('x') + $ev->x - $item->{res_x};
					$new_y = $self->{_items}{$curr_item}->get('y');

					$new_width = $self->{_items}{$curr_item}->get('width')
						+ ( $self->{_items}{$curr_item}->get('x') - $new_x );
					$new_height
						= $self->{_items}{$curr_item}->get('height') + ( $ev->y - $item->{res_y} );

				} elsif ( $_ =~ /bottom.*middle/ ) {

					$new_x = $self->{_items}{$curr_item}->get('x');
					$new_y = $self->{_items}{$curr_item}->get('y');

					$new_width = $self->{_items}{$curr_item}->get('width');
					$new_height
						= $self->{_items}{$curr_item}->get('height') + ( $ev->y - $item->{res_y} );

				} elsif ( $_ =~ /bottom.*right/ ) {

					$new_x = $self->{_items}{$curr_item}->get('x');
					$new_y = $self->{_items}{$curr_item}->get('y');

					$new_width
						= $self->{_items}{$curr_item}->get('width') + ( $ev->x - $item->{res_x} );
					$new_height
						= $self->{_items}{$curr_item}->get('height') + ( $ev->y - $item->{res_y} );

				}

				$item->{res_x} = $ev->x;
				$item->{res_y} = $ev->y;

				#min size while resizing
				if ( $new_width <= 5 ) {
					$new_x         = $self->{_items}{$curr_item}->get('x');
					$new_width     = $self->{_items}{$curr_item}->get('width');
					$item->{res_x} = $new_x;
				}
				if ( $new_height <= 5 ) {
					$new_y         = $self->{_items}{$curr_item}->get('y');
					$new_height    = $self->{_items}{$curr_item}->get('height');
					$item->{res_y} = $new_y;
				}

				$self->{_items}{$curr_item}->set(
					'x'      => $new_x,
					'y'      => $new_y,
					'width'  => $new_width,
					'height' => $new_height,
				);

				$self->handle_rects( 'update', $self->{_items}{$curr_item} );
				$self->handle_embedded( 'update', $self->{_items}{$curr_item} );

			}
		}

	}

	return TRUE;
}

sub get_parent_item {
	my $self = shift;
	my $item = shift;

	my $parent = undef;
	foreach ( keys %{ $self->{_items} } ) {
		$parent = $self->{_items}{$_} if $self->{_items}{$_}{ellipse} == $item;
		$parent = $self->{_items}{$_} if $self->{_items}{$_}{text} == $item;
		$parent = $self->{_items}{$_} if $self->{_items}{$_}{image} == $item;
	}

	return $parent;
}

sub event_item_on_button_press {
	my ( $self, $item, $target, $ev ) = @_;

	my $valid = FALSE;
	$valid = TRUE if $self->{_canvas}->get_item_at( $ev->x, $ev->y, TRUE );

	if ( $ev->button == 1 && $valid ) {

		my $canvas = $item->get_canvas;
		my $root   = $canvas->get_root_item;

		#CLEAR
		if ( $self->{_current_mode_descr} eq "clear" ) {

			return TRUE if $item == $self->{_canvas_bg};

			my @items_to_delete;
			push @items_to_delete, $item;

			#maybe there is a parent item to delete?
			my $parent = $self->get_parent_item($item);
			if ($parent) {
				push @items_to_delete, $parent;
				foreach ( keys %{ $self->{_items}{$parent} } ) {
					push @items_to_delete, $self->{_items}{$parent}{$_};
				}
			} else {
				foreach ( keys %{ $self->{_items}{$item} } ) {
					push @items_to_delete, $self->{_items}{$item}{$_};
				}
			}

			foreach (@items_to_delete) {
				eval {
					my $bigparent = $_->get_parent;
					$bigparent->remove_child( $bigparent->find_child($_) );
				};
			}

			#MOVE AND SELECT
		} elsif ( $self->{_current_mode_descr} eq "select" ) {
			if ( $item->isa('Goo::Canvas::Rect') ) {

				#real shape
				if ( exists $self->{_items}{$item} ) {
					$item->{drag_x}   = $ev->x;
					$item->{drag_y}   = $ev->y;
					$item->{dragging} = TRUE;

					#resizing shape
				} else {
					$item->{res_x}    = $ev->x;
					$item->{res_y}    = $ev->y;
					$item->{resizing} = TRUE;
				}

			} else {

				#click on background => deactivate all selected items
				if ( $item == $self->{_canvas_bg} ) {

					$self->deactivate_all;

				}

				#no rect and no background, just move it ...
				$item->{drag_x}   = $ev->x;
				$item->{drag_y}   = $ev->y;
				$item->{dragging} = TRUE;

			}

			$canvas->pointer_grab(
				$item,
				[ 'pointer-motion-mask', 'button-release-mask' ],
				Gtk2::Gdk::Cursor->new('fleur'), $ev->time
			);

		} else {

			#FREEHAND
			if ( $self->{_current_mode_descr} eq "line" ) {

				my $stroke_pattern
					= $self->create_color( $self->{_stroke_color}, $self->{_stroke_color_alpha} );
				my $fill_pattern
					= $self->create_color( $self->{_fill_color}, $self->{_fill_color_alpha} );
				my $item = Goo::Canvas::Polyline->new_line(
					$root, $ev->x, $ev->y, $ev->x, $ev->y,
					'stroke-pattern' => $stroke_pattern,
					'line-width'     => 1
				);

				$self->{_current_new_item} = $item;
				$self->{_items}{$item} = $item;

				#need at least 2 points
				$self->{_items}{$item}{'points'} = [ $ev->x, $ev->y, $ev->x, $ev->y ];

				$self->setup_item_signals( $self->{_items}{$item} );

				#RECTANGLES
			} elsif ( $self->{_current_mode_descr} eq "rect" ) {

				my $stroke_pattern
					= $self->create_color( $self->{_stroke_color}, $self->{_stroke_color_alpha} );
				my $fill_pattern
					= $self->create_color( $self->{_fill_color}, $self->{_fill_color_alpha} );
				my $item = Goo::Canvas::Rect->new(
					$root, $ev->x, $ev->y, 2, 2,
					'fill-pattern'   => $fill_pattern,
					'stroke-pattern' => $stroke_pattern,
					'line-width'     => 1,
				);

				$self->{_current_new_item} = $item;
				$self->{_items}{$item} = $item;

				#create rectangles
				$self->handle_rects( 'create', $item );

				$self->setup_item_signals( $self->{_items}{$item} );
				$self->setup_item_signals_extra( $self->{_items}{$item} );

				#ELLIPSE
			} elsif ( $self->{_current_mode_descr} eq "ellipse" ) {

				my $pattern = $self->create_alpha;
				my $item    = Goo::Canvas::Rect->new(
					$root, $ev->x, $ev->y, 2, 2,
					'fill-pattern' => $pattern,
					'line-dash'    => Goo::Canvas::LineDash->new( [ 5, 5 ] ),
					'line-width'   => 1,
					'stroke-color' => 'gray',
				);

				$self->{_current_new_item} = $item;
				$self->{_items}{$item} = $item;

				#				my @stipple_data = ( 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255 );
				#				my $pattern = $self->create_stipple( 'cadetblue', \@stipple_data );

				my $stroke_pattern
					= $self->create_color( $self->{_stroke_color}, $self->{_stroke_color_alpha} );
				my $fill_pattern
					= $self->create_color( $self->{_fill_color}, $self->{_fill_color_alpha} );

				$self->{_items}{$item}{ellipse} = Goo::Canvas::Ellipse->new(
					$root, $item->get('x'), $item->get('y'), $item->get('width'),
					$item->get('height'),
					'fill-pattern'   => $fill_pattern,
					'stroke-pattern' => $stroke_pattern,
					'line-width'     => 1,
				);

				#create rectangles
				$self->handle_rects( 'create', $item );

				$self->setup_item_signals( $self->{_items}{$item}{ellipse} );
				$self->setup_item_signals_extra( $self->{_items}{$item}{ellipse} );

				$self->setup_item_signals( $self->{_items}{$item} );
				$self->setup_item_signals_extra( $self->{_items}{$item} );

				#TEXT
			} elsif ( $self->{_current_mode_descr} eq "text" ) {

				my $pattern = $self->create_alpha;
				my $item    = Goo::Canvas::Rect->new(
					$root, $ev->x, $ev->y, 2, 2,
					'fill-pattern' => $pattern,
					'line-dash'    => Goo::Canvas::LineDash->new( [ 5, 5 ] ),
					'line-width'   => 1,
					'stroke-color' => 'gray',
				);

				$self->{_current_new_item} = $item;
				$self->{_items}{$item} = $item;

				#				my @stipple_data = ( 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255 );
				#				my $pattern = $self->create_stipple( 'cadetblue', \@stipple_data );

				my $stroke_pattern
					= $self->create_color( $self->{_stroke_color}, $self->{_stroke_color_alpha} );
				my $fill_pattern
					= $self->create_color( $self->{_fill_color}, $self->{_fill_color_alpha} );

				$self->{_items}{$item}{text} = Goo::Canvas::Text->new(
					$root, 'New Text...', $item->get('x'), $item->get('y'), $item->get('width'),
					'nw',
					'fill-pattern'   => $fill_pattern,
					'stroke-pattern' => $stroke_pattern,
					'line-width'     => 1,
				);

				#create rectangles
				$self->handle_rects( 'create', $item );

				$self->setup_item_signals( $self->{_items}{$item}{text} );
				$self->setup_item_signals_extra( $self->{_items}{$item}{text} );

				$self->setup_item_signals( $self->{_items}{$item} );
				$self->setup_item_signals_extra( $self->{_items}{$item} );

				#IMAGE
			} elsif ( $self->{_current_mode_descr} eq "image" ) {

				my $pattern = $self->create_alpha;
				my $item    = Goo::Canvas::Rect->new(
					$root, $ev->x, $ev->y, 2, 2,
					'fill-pattern' => $pattern,
					'line-dash'    => Goo::Canvas::LineDash->new( [ 5, 5 ] ),
					'line-width'   => 1,
					'stroke-color' => 'gray',
				);

				$self->{_current_new_item} = $item;
				$self->{_items}{$item} = $item;

				my $copy = $self->{_current_pixbuf}->copy;
				$self->{_items}{$item}{orig_pixbuf} = $self->{_current_pixbuf}->copy;

				$self->{_items}{$item}{image} = Goo::Canvas::Image->new(
					$root,
					$copy->scale_simple( $item->get('width'), $item->get('height'), 'bilinear' ),
					$item->get('x'), $item->get('y'),
					'width'  => $item->get('width'),
					'height' => $item->get('height'),
				);

				#create rectangles
				$self->handle_rects( 'create', $item );

				$self->setup_item_signals( $self->{_items}{$item}{image} );
				$self->setup_item_signals_extra( $self->{_items}{$item}{image} );

				$self->setup_item_signals( $self->{_items}{$item} );
				$self->setup_item_signals_extra( $self->{_items}{$item} );

			}

		}
	} elsif ( $ev->button == 2 && $valid ) {
		$item->lower;
	} elsif ( $ev->button == 3 && $valid ) {
		$item->raise;
	}
	return TRUE;
}

sub deactivate_all {
	my $self = shift;

	foreach ( keys %{ $self->{_items} } ) {

		my $item = $self->{_items}{$_};

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if ( exists $self->{_items}{$item} ) {
			$self->handle_rects( 'hide', $item );
		}

	}

	$self->{_last_item}    = undef;
	$self->{_current_item} = undef;
	return TRUE;

}

sub handle_embedded {
	my $self   = shift;
	my $action = shift;
	my $item   = shift;

	return FALSE unless ( $item && exists $self->{_items}{$item} );

	if ( $action eq 'update' ) {

		#embedded ellipse
		if ( exists $self->{_items}{$item}{ellipse} ) {

			$self->{_items}{$item}{ellipse}->set(
				'center-x' => int(
					$self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width') / 2
				),
				'center-y' => int(
					$self->{_items}{$item}->get('y') + $self->{_items}{$item}->get('height') / 2
				),
			);
			$self->{_items}{$item}{ellipse}->set(
				'radius-x' => $self->{_items}{$item}->get('x')
					+ $self->{_items}{$item}->get('width')
					- $self->{_items}{$item}{ellipse}->get('center-x'),
				'radius-y' => $item->get('y') 
					+ $self->{_items}{$item}->get('height')
					- $self->{_items}{$item}{ellipse}->get('center-y'),
			);

		} elsif ( exists $self->{_items}{$item}{text} ) {
			$self->{_items}{$item}{text}->set(
				'x'     => $self->{_items}{$item}->get('x'),
				'y'     => $self->{_items}{$item}->get('y'),
				'width' => $self->{_items}{$item}->get('width'),
			);
		} elsif ( exists $self->{_items}{$item}{image} ) {

			my $copy = $self->{_items}{$item}{orig_pixbuf}->copy;

			$self->{_items}{$item}{image}->set(
				'x'      => $self->{_items}{$item}->get('x'),
				'y'      => $self->{_items}{$item}->get('y'),
				'width'  => $self->{_items}{$item}->get('width'),
				'height' => $self->{_items}{$item}->get('height'),
				'pixbuf' => $copy->scale_simple(
					$self->{_items}{$item}->get('width'), $self->{_items}{$item}->get('height'),
					'bilinear'
				)
			);

		}

	}

	return TRUE;
}

sub handle_rects {
	my $self   = shift;
	my $action = shift;
	my $item   = shift;


	return FALSE unless ( $item && exists $self->{_items}{$item} );

	#get root item
	my $root = $self->{_canvas}->get_root_item;

	if ( $self->{_items}{$item}->isa('Goo::Canvas::Rect') ) {

		my $middle_h
			= $self->{_items}{$item}->get('x') + int( $self->{_items}{$item}->get('width') / 2 );

		my $middle_v
			= $self->{_items}{$item}->get('y') + int( $self->{_items}{$item}->get('height') / 2 );

		my $bottom = $self->{_items}{$item}->get('y') + $self->{_items}{$item}->get('height');

		my $top = $self->{_items}{$item}->get('y');

		my $left = $self->{_items}{$item}->get('x');

		my $right = $self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width');

		if ( $action eq 'create' ) {

			my $pattern = $self->create_color( 'blue', 0.3 );

			$self->{_items}{$item}{top_middle} = Goo::Canvas::Rect->new(
				$root, $middle_h, $top, 5, 5,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden'
			);

			$self->{_items}{$item}{top_left} = Goo::Canvas::Rect->new(
				$root, $left, $top, 5, 5,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden'
			);

			$self->{_items}{$item}{top_right} = Goo::Canvas::Rect->new(
				$root, $right, $top, 5, 5,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden'
			);

			$self->{_items}{$item}{bottom_middle} = Goo::Canvas::Rect->new(
				$root, $middle_h, $bottom, 5, 5,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden'
			);

			$self->{_items}{$item}{bottom_left} = Goo::Canvas::Rect->new(
				$root, $left, $bottom, 5, 5,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden'
			);

			$self->{_items}{$item}{bottom_right} = Goo::Canvas::Rect->new(
				$root, $right, $bottom, 5, 5,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden'
			);

			$self->{_items}{$item}{middle_left} = Goo::Canvas::Rect->new(
				$root, $left - 5, $middle_v, 5, 5,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden'
			);

			$self->{_items}{$item}{middle_right} = Goo::Canvas::Rect->new(
				$root, $right, $middle_v, 5, 5,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden'
			);

			$self->setup_item_signals( $self->{_items}{$item}{top_middle} );
			$self->setup_item_signals( $self->{_items}{$item}{top_left} );
			$self->setup_item_signals( $self->{_items}{$item}{top_right} );
			$self->setup_item_signals( $self->{_items}{$item}{bottom_middle} );
			$self->setup_item_signals( $self->{_items}{$item}{bottom_left} );
			$self->setup_item_signals( $self->{_items}{$item}{bottom_right} );
			$self->setup_item_signals( $self->{_items}{$item}{middle_left} );
			$self->setup_item_signals( $self->{_items}{$item}{middle_right} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{top_middle} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{top_left} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{top_right} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{bottom_middle} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{bottom_left} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{bottom_right} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{middle_left} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{middle_right} );

		} elsif ( $action eq 'update' || $action eq 'hide' ) {

			my $visibilty = 'visible';
			if ( $action eq 'hide' ) {
				$visibilty = 'hidden';

				#ellipse => hide rectangle as well
				if ( exists $self->{_items}{$item}{ellipse} ) {
					$self->{_items}{$item}->set( 'visibility' => 'invisible' );
				}

				#text => hide rectangle as well
				if ( exists $self->{_items}{$item}{text} ) {
					$self->{_items}{$item}->set( 'visibility' => 'invisible' );
				}

				if ( exists $self->{_items}{$item}{image} ) {
					$self->{_items}{$item}->set( 'visibility' => 'invisible' );
				}

			} else {

				#ellipse => hide rectangle as well
				if ( exists $self->{_items}{$item}{ellipse} ) {
					$self->{_items}{$item}->set( 'visibility' => $visibilty );
				}

				#text => hide rectangle as well
				if ( exists $self->{_items}{$item}{text} ) {
					$self->{_items}{$item}->set( 'visibility' => $visibilty );
				}

				#image => hide rectangle as well
				if ( exists $self->{_items}{$item}{image} ) {
					$self->{_items}{$item}->set( 'visibility' => $visibilty );
				}

			}

			my $pattern = $self->create_color( 'blue', 0.3 );

			$self->{_items}{$item}{top_middle}->set(
				'x'            => $middle_h,
				'y'            => $top - 5,
				'visibility'   => $visibilty,
				'fill-pattern' => $pattern
			);
			$self->{_items}{$item}{top_left}->set(
				'x'            => $left - 5,
				'y'            => $top - 5,
				'visibility'   => $visibilty,
				'fill-pattern' => $pattern
			);

			$self->{_items}{$item}{top_right}->set(
				'x'            => $right,
				'y'            => $top - 5,
				'visibility'   => $visibilty,
				'fill-pattern' => $pattern
			);

			$self->{_items}{$item}{bottom_middle}->set(
				'x'            => $middle_h,
				'y'            => $bottom,
				'visibility'   => $visibilty,
				'fill-pattern' => $pattern
			);

			$self->{_items}{$item}{bottom_left}->set(
				'x'            => $left - 5,
				'y'            => $bottom,
				'visibility'   => $visibilty,
				'fill-pattern' => $pattern
			);

			$self->{_items}{$item}{bottom_right}->set(
				'x'            => $right,
				'y'            => $bottom,
				'visibility'   => $visibilty,
				'fill-pattern' => $pattern
			);

			$self->{_items}{$item}{middle_left}->set(
				'x'            => $left - 5,
				'y'            => $middle_v,
				'visibility'   => $visibilty,
				'fill-pattern' => $pattern
			);
			$self->{_items}{$item}{middle_right}->set(
				'x'            => $right,
				'y'            => $middle_v,
				'visibility'   => $visibilty,
				'fill-pattern' => $pattern
			);
		}
	}

}

sub event_item_on_button_release {
	my ( $self, $item, $target, $ev ) = @_;
	my $canvas = $item->get_canvas;
	$canvas->pointer_ungrab( $item, $ev->time );

	#we handle some minimum sizes here if the new items are too small
	#maybe the user just wanted to place an rect or an object on the canvas
	#and clicked on it without describing an rectangular area
	my $nitem = $self->{_current_new_item};
	if ($nitem) {

		#set minimum sizes
		if ( $nitem->isa('Goo::Canvas::Rect') ) {

			#real shape
			if ( exists $self->{_items}{$nitem} ) {

				$nitem->set( 'width'  => 100 ) if ( $nitem->get('width') < 10 );
				$nitem->set( 'height' => 100 ) if ( $nitem->get('height') < 10 );

			}

		} elsif ( $item->isa('Goo::Canvas::Ellipse') ) {

			$nitem->set( 'x-radius' => 50 ) if ( $nitem->get('x-radius') < 5 );
			$nitem->set( 'y-radius' => 50 ) if ( $nitem->get('y-radius') < 5 );

		} elsif ( $item->isa('Goo::Canvas::Text') ) {

			$nitem->set( 'width' => 100 ) if ( $nitem->get('width') < 10 );

		} elsif ( $item->isa('Goo::Canvas::Image') && $self->{_current_mode_descr} ne "line") {

			my $copy = $self->{_items}{$item}{orig_pixbuf}->copy;

			if ( $nitem->get('width') < 10 ) {
				$self->{_items}{$item}{image}->set(
					'width'  => $copy->get_width,
					'pixbuf' => $copy
				);

			}
		}

		#parent?
		my $nparent = $self->get_parent_item($nitem);
		$nitem = $nparent if $nparent;

		#update only real shape
		if ( exists $self->{_items}{$nitem} ) {

			$self->handle_rects( 'update', $nitem );
			$self->handle_embedded( 'update', $nitem );

		}

	}

	#unset action flags
	$item->{dragging} = FALSE;
	$item->{resizing} = FALSE;

	$self->{_current_new_item} = undef;
	$self->set_drawing_action(0);

	return TRUE;
}

sub event_item_on_enter_notify {
	my ( $self, $item, $target, $ev ) = @_;
	if (   $item->isa('Goo::Canvas::Rect')
		|| $item->isa('Goo::Canvas::Ellipse')
		|| $item->isa('Goo::Canvas::Text')
		|| $item->isa('Goo::Canvas::Image') )
	{

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if ( exists $self->{_items}{$item} ) {

			$self->{_last_item}    = $self->{_current_item};
			$self->{_current_item} = $item;
			$self->handle_rects( 'hide',   $self->{_last_item} );
			$self->handle_rects( 'update', $self->{_current_item} );

			#resizing shape
		} else {
			my $pattern = $self->create_color( 'red', 0.5 );
			$item->set( 'fill-pattern' => $pattern );

#			my $curr_item = $self->{_current_item};
#
#			my $cursor = Gtk2::Gdk::Cursor->new('fleur');
#			foreach ( keys %{ $self->{_items}{$curr_item} } ) {
#
#				if ( $item == $self->{_items}{$curr_item}{$_} ) {
#
#					if ( $_ =~ /top.*left/ ) {
#
#						$cursor = Gtk2::Gdk::Cursor->new('top-left-corner');
#
#					} elsif ( $_ =~ /top.*middle/ ) {
#
#						$cursor = Gtk2::Gdk::Cursor->new('top-side');
#
#					} elsif ( $_ =~ /top.*right/ ) {
#
#						$cursor = Gtk2::Gdk::Cursor->new('top-right-corner');
#
#					} elsif ( $_ =~ /middle.*left/ ) {
#
#						$cursor = Gtk2::Gdk::Cursor->new('left-side');
#
#					} elsif ( $_ =~ /middle.*right/ ) {
#
#						$cursor = Gtk2::Gdk::Cursor->new('right-side');
#
#					} elsif ( $_ =~ /bottom.*left/ ) {
#
#						$cursor = Gtk2::Gdk::Cursor->new('bottom-left-corner');
#
#					} elsif ( $_ =~ /bottom.*middle/ ) {
#
#						$cursor = Gtk2::Gdk::Cursor->new('bottom-side');
#
#					} elsif ( $_ =~ /bottom.*right/ ) {
#
#						$cursor = Gtk2::Gdk::Cursor->new('bottom-right-corner');
#
#					}
#
#				}
#			}
#
#			$self->{_canvas}->pointer_grab( $item, [ 'pointer-motion-mask', 'button-release-mask' ],
#				$cursor, $ev->time );

		}
	}
	return TRUE;
}

sub event_item_on_leave_notify {
	my ( $self, $item, $target, $ev ) = @_;

	if (   $item->isa('Goo::Canvas::Rect')
		|| $item->isa('Goo::Canvas::Ellipse')
		|| $item->isa('Goo::Canvas::Text')
		|| $item->isa('Goo::Canvas::Image') )
	{

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if ( exists $self->{_items}{$item} ) {

			#resizing shape
		} else {
			my $pattern = $self->create_color( 'blue', 0.3 );
			$item->set( 'fill-pattern' => $pattern );
		}
	}
	return TRUE;
}

sub create_stipple {
	my $self = shift;
	our @stipples;
	my ( $color_name, $stipple_data ) = @_;
	my $color = Gtk2::Gdk::Color->parse($color_name);
	$stipple_data->[2] = $stipple_data->[14] = $color->red >> 8;
	$stipple_data->[1] = $stipple_data->[13] = $color->green >> 8;
	$stipple_data->[0] = $stipple_data->[12] = $color->blue >> 8;
	my $stipple_str = join( '', map {chr} @$stipple_data );
	push @stipples, \$stipple_str;    # make $stipple_str refcnt increase
	my $surface = Cairo::ImageSurface->create_for_data( $stipple_str, 'argb32', 2, 2, 8 );
	my $pattern = Cairo::SurfacePattern->create($surface);
	$pattern->set_extend('repeat');
	return Goo::Cairo::Pattern->new($pattern);
}

sub create_alpha {
	my $self = shift;
	my $pattern = Cairo::SolidPattern->create_rgba( 0, 0, 0, 0 );
	return Goo::Cairo::Pattern->new($pattern);
}

sub create_color {
	my $self       = shift;
	my $color_name = shift;
	my $alpha      = shift;

	my $color;

	#if it is a color, we do not need to parse it
	unless ( $color_name->isa('Gtk2::Gdk::Color') ) {
		$color = Gtk2::Gdk::Color->parse($color_name);
	} else {
		$color = $color_name;
	}

	my $pattern = Cairo::SolidPattern->create_rgba(
		$color->red / 257 / 255,
		$color->green / 257 / 255,
		$color->blue / 257 / 255, $alpha
	);

	return Goo::Cairo::Pattern->new($pattern);
}

#ui related stuff
sub setup_uimanager {
	my $self = shift;
	my $d    = $self->{_gscrot_common}->get_gettext;

	#define own icons
	my $dicons = $self->{_gscrot_common}->get_root . "/share/gscrot/resources/icons/drawing_tool";

	$self->{_factory} = Gtk2::IconFactory->new();
	$self->{_factory}->add(
		'gscrot-ellipse',
		Gtk2::IconSet->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-ellipse.png")
		)
	);
	$self->{_factory}->add(
		'gscrot-eraser',
		Gtk2::IconSet->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-eraser.png")
		)
	);
	$self->{_factory}->add(
		'gscrot-freehand',
		Gtk2::IconSet->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-freehand.png")
		)
	);
	$self->{_factory}->add(
		'gscrot-pointer',
		Gtk2::IconSet->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-pointer.png")
		)
	);
	$self->{_factory}->add(
		'gscrot-rectangle',
		Gtk2::IconSet->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-rectangle.png")
		)
	);
	$self->{_factory}->add( 'gscrot-star',
		Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-star.png") )
	);
	$self->{_factory}->add( 'gscrot-text',
		Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-text.png") )
	);
	$self->{_factory}->add_default();

	my @toolbar_actions = (
		[ "Quit", 'gtk-quit', undef, "<control>W", undef, sub { $self->quit($self) } ],
		[ "Save", 'gtk-save', undef, "<control>S", undef, sub { $self->save($self) } ],
		[   "ZoomIn", 'gtk-zoom-in', undef, "<control>plus", undef, sub { $self->zoom_in_cb($self) }
		],
		[   "ZoomOut", 'gtk-zoom-out',
			undef,     "<control>minus",
			undef, sub { $self->zoom_out_cb($self) }
		],
		[   "ZoomNormal", 'gtk-zoom-100',
			undef,        "<control>0",
			undef, sub { $self->zoom_normal_cb($self) }
		]
	);

	my @toolbar_drawing_actions = (
		[   "Select", 'gscrot-pointer', undef, undef, $d->get("Select item to move or resize it"),
			10
		],
		[   "Line", 'gscrot-freehand', undef, undef, $d->get("Draw a line using the freehand tool"),
			20
		],
		[ "Rect",    'gscrot-rectangle', undef, undef, $d->get("Draw a rectangle"), 30 ],
		[ "Ellipse", 'gscrot-ellipse',   undef, undef, $d->get("Draw a ellipse"),   40 ],
		[ "Image", 'gscrot-star', undef, undef, $d->get("Insert an arbitrary object or file"), 50 ],
		[ "Text",  'gscrot-text', undef, undef, $d->get("Add some text to the screenshot"),    60 ],
		[ "Clear", 'gscrot-eraser', undef, undef, $d->get("Delete objects"), 70 ]
	);
	my @toolbar_color_actions = (
		[ "FillColor",   undef, undef, undef, undef ],
		[ "StrokeColor", undef, undef, undef, undef ]
	);

	my $uimanager = Gtk2::UIManager->new();

	# Setup the image group.
	my $toolbar_group = Gtk2::ActionGroup->new("image");
	$toolbar_group->add_actions( \@toolbar_actions );

	# Setup the drawing group.
	my $toolbar_drawing_group = Gtk2::ActionGroup->new("drawing");
	$toolbar_drawing_group->add_radio_actions( \@toolbar_drawing_actions, 10,
		sub { my $action = shift; $self->change_drawing_tool_cb($action); } );

	$uimanager->insert_action_group( $toolbar_group, 0 );

	$toolbar_drawing_group->add_actions( \@toolbar_color_actions );

	$uimanager->insert_action_group( $toolbar_drawing_group, 0 );

	my $ui_info = "
<ui>
  <toolbar name = 'ToolBar'>
    <toolitem action='Quit'/>
    <toolitem action='Save'/>
    <separator/>
    <toolitem action='ZoomIn'/>
    <toolitem action='ZoomOut'/>
    <toolitem action='ZoomNormal'/>
  </toolbar>
  <toolbar name = 'ToolBarDrawing'>
    <toolitem action='Select'/>
    <separator/>
    <toolitem action='Line'/>
    <toolitem action='Rect'/>
    <toolitem action='Ellipse'/>
    <toolitem action='Text'/>
    <toolitem action='Image'/>
    <separator/>
    <toolitem action='Clear'/>
    <separator/>
    <toolitem action='FillColor'/>
    <toolitem action='StrokeColor'/>
  </toolbar>  
</ui>";

	eval { $uimanager->add_ui_from_string($ui_info) };

	if ($@) {
		die "Unable to create menus: $@\n";
	}

	#manip color buttons
	$self->set_color_fill_color_button( $uimanager->get_widget("/ToolBarDrawing/FillColor") );
	$self->set_color_stroke_color_button( $uimanager->get_widget("/ToolBarDrawing/StrokeColor") );

	#insert menutoolbutton image
	my $toolbar = $uimanager->get_widget("/ToolBarDrawing");

	my $image_button = Gtk2::MenuToolButton->new( undef, undef );
	$image_button->set_menu( $self->ret_objects_menu($image_button) );

	$image_button->signal_connect(
		'show-menu' => sub { my ($widget) = @_; $self->ret_objects_menu($widget) } );
	$image_button->signal_connect(
		'clicked' => sub {
			$self->set_drawing_action(6);
		}
	);

	$toolbar->insert( $image_button, 12 );

	return $uimanager;
}

sub ret_objects_menu {
	my $self   = shift;
	my $button = shift;

	my $menu_objects = Gtk2::Menu->new;

	my $dobjects
		= $self->{_gscrot_common}->get_root . "/share/gscrot/resources/icons/drawing_tool/objects";

	my @objects = glob("$dobjects/*");
	foreach (@objects) {

		#parse filename
		my ( $short, $folder, $type ) = fileparse( $_, '\..*' );

		#create pixbufs
		my $small_image = Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_scale( $_, Gtk2::IconSize->lookup('menu'), TRUE ) );
		my $small_image_button = Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_scale( $_, Gtk2::IconSize->lookup('menu'), TRUE ) );
		my $orig_image = Gtk2::Image->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file($_) );

		#create items
		my $new_item = Gtk2::ImageMenuItem->new_with_label($short);
		$new_item->set_image($small_image);

		#init
		unless ( $button->get_icon_widget ) {
			$button->set_icon_widget($small_image_button);
			$self->{_current_pixbuf} = $orig_image->get_pixbuf;
		}

		$new_item->signal_connect(
			'activate' => sub {
				$self->{_current_pixbuf} = $orig_image->get_pixbuf;
				$button->set_icon_widget($small_image_button);
				$button->show_all;
				$self->set_drawing_action(6);
			}
		);

		$menu_objects->append($new_item);
	}

	$button->show_all;
	$menu_objects->show_all;

	return $menu_objects;
}

sub set_color_fill_color_button {
	my $self           = shift;
	my $fill_color_btn = shift;

	my $btn = $fill_color_btn->get_child;
	$btn->remove( $btn->get_child );
	$btn->set_border_width(3);

	$btn->set_state('prelight');
	$btn->modify_bg( 'normal',      $self->{_fill_color} );
	$btn->modify_bg( 'prelight',    $self->{_fill_color} );
	$btn->modify_bg( 'active',      $self->{_fill_color} );
	$btn->modify_bg( 'insensitive', $self->{_fill_color} );
	$btn->modify_bg( 'selected',    $self->{_fill_color} );

	$btn->signal_connect( 'state-changed' => sub { $btn->set_state('prelight') } );

	$btn->signal_connect(
		clicked => sub {
			my $d = $self->{_gscrot_common}->get_gettext;

			my $color_dialog = Gtk2::Dialog->new(
				$d->get("Choose fill color"),
				$self->{_drawing_window},
				[qw/modal destroy-with-parent/],
				'gtk-cancel'       => 'reject',
				'gtk-select-color' => 'accept'
			);
			$color_dialog->set_default_response('accept');

			my $color_select = Gtk2::ColorSelection->new;
			$color_select->set_has_opacity_control(TRUE);
			$color_select->set_current_color( $self->{_fill_color} );
			$color_select->set_current_alpha( int( $self->{_fill_color_alpha} * 65636 ) );

			$color_dialog->vbox->add($color_select);
			$color_dialog->show_all;

			if ( 'accept' eq $color_dialog->run ) {
				$self->{_fill_color}       = $color_select->get_current_color;
				$self->{_fill_color_alpha} = $color_select->get_current_alpha / 65636;

				$btn->set_state('prelight');
				$btn->modify_bg( 'normal',      $self->{_fill_color} );
				$btn->modify_bg( 'prelight',    $self->{_fill_color} );
				$btn->modify_bg( 'active',      $self->{_fill_color} );
				$btn->modify_bg( 'insensitive', $self->{_fill_color} );
				$btn->modify_bg( 'selected',    $self->{_fill_color} );

			}
			$color_dialog->destroy;
		}
	);

	$btn->show_all;

	return TRUE;
}

sub set_color_stroke_color_button {
	my $self             = shift;
	my $stroke_color_btn = shift;

	my $btn = $stroke_color_btn->get_child;
	$btn->remove( $btn->get_child );
	$btn->set_border_width(10);

	$btn->set_state('prelight');
	$btn->modify_bg( 'normal',      $self->{_stroke_color} );
	$btn->modify_bg( 'prelight',    $self->{_stroke_color} );
	$btn->modify_bg( 'active',      $self->{_stroke_color} );
	$btn->modify_bg( 'insensitive', $self->{_stroke_color} );
	$btn->modify_bg( 'selected',    $self->{_stroke_color} );

	$btn->signal_connect( 'state-changed' => sub { $btn->set_state('prelight') } );

	$btn->signal_connect(
		clicked => sub {
			my $d = $self->{_gscrot_common}->get_gettext;

			my $color_dialog = Gtk2::Dialog->new(
				$d->get("Choose stroke color"),
				$self->{_drawing_window},
				[qw/modal destroy-with-parent/],
				'gtk-cancel'       => 'reject',
				'gtk-select-color' => 'accept'
			);
			$color_dialog->set_default_response('accept');

			my $color_select = Gtk2::ColorSelection->new;
			$color_select->set_has_opacity_control(TRUE);
			$color_select->set_current_color( $self->{_stroke_color} );
			$color_select->set_current_alpha( int( $self->{_stroke_color_alpha} * 65636 ) );

			$color_dialog->vbox->add($color_select);
			$color_dialog->show_all;

			if ( 'accept' eq $color_dialog->run ) {
				$self->{_stroke_color}       = $color_select->get_current_color;
				$self->{_stroke_color_alpha} = $color_select->get_current_alpha / 65636;

				$btn->set_state('prelight');
				$btn->modify_bg( 'normal',      $self->{_stroke_color} );
				$btn->modify_bg( 'prelight',    $self->{_stroke_color} );
				$btn->modify_bg( 'active',      $self->{_stroke_color} );
				$btn->modify_bg( 'insensitive', $self->{_stroke_color} );
				$btn->modify_bg( 'selected',    $self->{_stroke_color} );
			}
			$color_dialog->destroy;
		}
	);

	$btn->show_all;

	return TRUE;
}

sub set_drawing_action {
	my $self  = shift;
	my $index = shift;

	my $toolbar = $self->{_uimanager}->get_widget("/ToolBarDrawing");
	for ( my $i = 0; $i < $toolbar->get_n_items; $i++ ) {
		my $item       = $toolbar->get_nth_item($i);
		my $item_index = $toolbar->get_item_index($item);
		$item->set_active(TRUE) if $item_index == $index;
	}

}

1;
