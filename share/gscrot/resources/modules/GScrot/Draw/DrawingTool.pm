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

our ( @ISA, @EXPORT );
@ISA    = qw(Exporter);
@EXPORT = qw(&fct_start_drawing);

#modules
#--------------------------------------
use utf8;
use strict;
use Exporter;
use Goo::Canvas;

#--------------------------------------

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

sub new {
	my $class = shift;

	my $self = { _gscrot_common => shift };

	$self->{_factory} = undef;

	$self->{_canvas} = undef;
	$self->{_lines} = undef;
	$self->{_count} = undef;

	$self->{_current_mode}       = 10;
	$self->{_current_mode_descr} = "select";

	bless $self, $class;

	return $self;
}

sub show {
	my $self     = shift;
	my $filename = shift;
	my $filetype = shift;

	my $d = $self->{_gscrot_common}->get_gettext;

	my $uimanager = $self->setup_uimanager();

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

	$self->{_canvas}->modify_bg( 'normal', Gtk2::Gdk::Color->new( 0xFFFF, 0xFFFF, 0xFFFF ) );

	$self->{_canvas}->set_bounds(
		0, 0,
		$self->{_drawing_pixbuf}->get_width,
		$self->{_drawing_pixbuf}->get_height
	);
	my $root = $self->{_canvas}->get_root_item;
	$root->signal_connect( 'button_press_event', $self->event_on_background_button_press );

	$self->{_canvas_bg} = Goo::Canvas::Image->new( $root, $self->{_drawing_pixbuf}, 0, 0 );
	$self->setup_item_signals($self->{_canvas_bg});


	# Width
	my $width_label = Gtk2::Label->new( $self->{_gscrot_common}->get_gettext->get("Width:") );
	my $sb_width = Gtk2::SpinButton->new_with_range( 1, 20, 1 );
	$sb_width->set_value(3);

	# create a color button
	my $col_label = Gtk2::Label->new( $self->{_gscrot_common}->get_gettext->get("Color:") );
	my $colbut1   = Gtk2::ColorButton->new();
	$colbut1->set_color( Gtk2::Gdk::Color->new( 0xFFFF, 0, 0 ) );

	# a save button
	my $save_button = Gtk2::Button->new_from_stock('gtk-save');

	# .. And a quit button
	my $quit_button = Gtk2::Button->new_from_stock('gtk-close');
	$quit_button->signal_connect( clicked => sub { $self->{_drawing_window}->destroy() } );

	my @stipple_data = ( 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255 );
	my $pattern = $self->create_stipple( 'cadetblue', \@stipple_data );
	my $ellipse3 = Goo::Canvas::Ellipse->new(
		$root, 245, 110, 35, 30,
		'fill-pattern' => $pattern,
		'stroke-color' => 'black',
		'line-width'   => 1,
	);
	$self->setup_item_signals($ellipse3);

	#packing
	my $scrolled_drawing_window = Gtk2::ScrolledWindow->new;
	$scrolled_drawing_window->set_policy( 'automatic', 'automatic' );
	$scrolled_drawing_window->add( $self->{_canvas} );

	my $drawing_vbox = Gtk2::VBox->new( FALSE, 0 );

	#	my $drawing_box_buttons = Gtk2::HBox->new( FALSE, 0 );
	my $drawing_hbox = Gtk2::HBox->new( FALSE, 0 );

	$self->{_drawing_window}->add($drawing_vbox);

	my $toolbar_drawing = $uimanager->get_widget("/ToolBarDrawing");
	$toolbar_drawing->set_orientation('vertical');
	$toolbar_drawing->set_style('icons');
	$toolbar_drawing->set_icon_size('small-toolbar');
	$drawing_hbox->pack_start( $toolbar_drawing,         FALSE, FALSE, 0 );
	$drawing_hbox->pack_start( $scrolled_drawing_window, FALSE, FALSE, 0 );

	#	$drawing_boxh->pack_start( $drawing_box_buttons,     FALSE, FALSE, 5 );

	my $toolbar = $uimanager->get_widget("/ToolBar");
	$drawing_vbox->pack_start( $uimanager->get_widget("/ToolBar"), FALSE, FALSE, 0 );

	my $drawing_statusbar = Gtk2::Statusbar->new;
	$drawing_vbox->pack_start( $drawing_hbox,      FALSE, FALSE, 0 );
	$drawing_vbox->pack_start( $drawing_statusbar, FALSE, FALSE, 0 );

	$self->{_drawing_window}->show_all();

	Gtk2->main;

	return TRUE;
}

sub setup_uimanager {
	my $self = shift;

	my $d = $self->{_gscrot_common}->get_gettext;

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

	my $uimanager = Gtk2::UIManager->new();

	# Setup the image group.
	my $toolbar_group = Gtk2::ActionGroup->new("image");
	$toolbar_group->add_actions( \@toolbar_actions );

	$uimanager->insert_action_group( $toolbar_group, 0 );

	# Setup the drawing group.
	my $toolbar_drawing_group = Gtk2::ActionGroup->new("drawing");
	$toolbar_drawing_group->add_radio_actions( \@toolbar_drawing_actions, 10,
		sub { my $action = shift; $self->change_drawing_tool_cb($action); } );

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
    <separator/>
    <toolitem action='Select'/>
    <separator/>
    <toolitem action='Line'/>
    <toolitem action='Rect'/>
    <toolitem action='Ellipse'/>
    <toolitem action='Text'/>
    <toolitem action='Image'/>
    <separator/>
    <toolitem action='Clear'/>
  </toolbar>  
</ui>";

	eval { $uimanager->add_ui_from_string($ui_info) };

	if ($@) {
		die "Unable to create menus: $@\n";
	}

	return $uimanager;
}

sub change_drawing_tool_cb {
	my $self   = shift;
	my $action = shift;

	$self->{_current_mode} = $action->get_current_value;

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

#sub event_drawing_handler {
#	my ( $widget, $event ) = @_;
#	my $scale = $adj_zoom->get_value;
#	if ( $event->type eq "button-press" ) {
#		$draw_flag = 1;
#
#		#start a new line curve
#		$count++;
#		my ( $x, $y ) = ( $event->x, $event->y );
#
#		$lines{$count}{'points'}
#			= [ $x / $scale, $y / $scale, $x / $scale, $y / $scale ];    #need at least 2 points
#
#		#		$lines{$count}{'line'} = Goo::Canvas::Polyline->new_line(
#		#			$root,                       $lines{$count}{'points'}[0], $lines{$count}{'points'}[1],
#		#			$lines{$count}{'points'}[2], $lines{$count}{'points'}[3]
#		#		);
#
#		#		$lines{$count}{'line'} = Goo::Canvas::Rect->new(
#		#			$root,                       $lines{$count}{'points'}[0], $lines{$count}{'points'}[1],
#		#			$lines{$count}{'points'}[2], $lines{$count}{'points'}[3]
#		#		);
#
#	}
#	if ( $event->type eq "button-release" ) {
#		$draw_flag = 0;
#	}
#
#	if ( $event->type eq "focus-change" ) {
#		return 0;
#	}
#
#	if ( $event->type eq "expose" ) {
#		return 0;
#	}
#
#	if ($draw_flag) {
#
#		#left with motion-notify
#		if ( $event->type eq "motion-notify" ) {
#			my ( $x, $y ) = ( $event->x, $event->y );
#			push @{ $lines{$count}{'points'} }, $x / $scale, $y / $scale;
#			$lines{$count}{'line'}
#				->set( points => Goo::Canvas::Points->new( $lines{$count}{'points'} ) );
#
#		}
#	}
#}

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

	#enter routine to save here
	return TRUE;
}

#handle events here
sub event_on_background_button_press {
	my $self = shift;

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

sub event_item_on_motion_notify {
	my ( $self, $item, $target, $ev ) = @_;

	#move an item
	if ( $item->{dragging} && $ev->state >= 'button1-mask' ) {

		$item->translate( $ev->x - $item->{drag_x}, $ev->y - $item->{drag_y} );

		#		my $new_x = abs( $ev->x - $item->get('center-x') );
		#		my $new_y = abs( $ev->y - $item->get('center-y') );
		#
		#		$item->set(
		#			'radius-x' => $new_x,
		#			'radius-y' => $new_y,
		#		);


	#freehand line
	}elsif ($self->{_current_mode_descr} eq "line" && $ev->state >= 'button1-mask'){
				
			my $count = $self->{_count};
			push @{ $self->{_lines}{$count}{'points'} }, $ev->x, $ev->y ;
			$self->{_lines}{$count}{'line'}
				->set( points => Goo::Canvas::Points->new( $self->{_lines}{$count}{'points'} ) );		
	
	}
	return TRUE;
}

sub event_item_on_button_press {
	my ( $self, $item, $target, $ev ) = @_;
	if ( $ev->button == 1 ) {

		print $self->{_current_mode_descr} . "\n";

		#delete items - shift or clear mode
		if ( $ev->state >= 'shift-mask' || $self->{_current_mode_descr} eq "clear" ) {
			my $parent = $item->get_parent;
			$parent->remove_child( $parent->find_child($item) );

			#start other actions here
		} else {
			my $canvas = $item->get_canvas;
			my $root = $canvas->get_root_item;

			#MOVE AND SELECT
			if ( $self->{_current_mode_descr} eq "select" ) {
				$item->{drag_x} = $ev->x;
				$item->{drag_y} = $ev->y;
				my $fleur  = Gtk2::Gdk::Cursor->new('fleur');
				
				$canvas->pointer_grab( $item, [ 'pointer-motion-mask', 'button-release-mask' ],
					$fleur, $ev->time );
				$item->{dragging} = TRUE;

			#FREEHAND
			} elsif ( $self->{_current_mode_descr} eq "line" ) {
			  	
			  	#new line
			  	$self->{_count}++;
			  	my $count = $self->{_count};
			  
			  	#need at least 2 points
				$self->{_lines}{$count}{'points'}
					= [ $ev->x , $ev->y , $ev->x , $ev->y  ];    

				$self->{_lines}{$count}{'line'} = Goo::Canvas::Polyline->new_line(
					$root, $self->{_lines}{$count}{'points'}[0], $self->{_lines}{$count}{'points'}[1],
					$self->{_lines}{$count}{'points'}[2], $self->{_lines}{$count}{'points'}[3]
				);			  

				$self->setup_item_signals($self->{_lines}{$count}{'line'});
		  					
			}

		}
	} elsif ( $ev->button == 2 ) {
		$item->lower;
	} elsif ( $ev->button == 3 ) {
		$item->raise;
	}
	return TRUE;
}

sub event_item_on_button_release {
	my ( $self, $item, $target, $ev ) = @_;
	my $canvas = $item->get_canvas;
	$canvas->pointer_ungrab( $item, $ev->time );
	
	#unset action flags
	$item->{dragging} = FALSE;

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

1;
