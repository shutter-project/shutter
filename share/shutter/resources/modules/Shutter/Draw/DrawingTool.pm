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

package Shutter::Draw::DrawingTool;

#modules
#--------------------------------------
use utf8;
use strict;
use Exporter;
use Goo::Canvas;
use File::Basename;
use Data::Dumper;

#load and save settings
use XML::Simple;

#--------------------------------------

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

sub new {
	my $class = shift;

	my $self = { _shutter_common => shift };

	#file
	$self->{_filename}    = undef;
	$self->{_filetype}    = undef;
	$self->{_import_hash} = undef;

	#ui
	$self->{_uimanager} = undef;
	$self->{_factory}   = undef;

	#canvas
	$self->{_canvas}     = undef;
	
	#all items are stored here
	$self->{_items} = undef;
	$self->{_items_history} = undef;
	
	#undo and redo stacks
	$self->{_undo}      = undef;
	$self->{_redo}      = undef;
	
	#autoscroll option, disabled by default
	$self->{_autoscroll} = FALSE;

	#drawing colors and line width
	#general - shown in the bottom hbox
	$self->{_fill_color}         = Gtk2::Gdk::Color->parse('#0000ff');
	$self->{_fill_color_alpha}   = 0.25;
	$self->{_stroke_color}       = Gtk2::Gdk::Color->parse('#000000');
	$self->{_stroke_color_alpha} = 1;
	$self->{_line_width} 		 = 3;
	$self->{_font} 				 = 'Sans Italic 16';

	#remember drawing colors, line width and font settings
	#maybe we have to restore them
	$self->{_last_fill_color}         = Gtk2::Gdk::Color->parse('#0000ff');
	$self->{_last_fill_color_alpha}   = 0.25;
	$self->{_last_stroke_color}       = Gtk2::Gdk::Color->parse('#000000');
	$self->{_last_stroke_color_alpha} = 1;
	$self->{_last_line_width} 		  = 3;
	$self->{_last_font} 			  = 'Sans Italic 16';

	#some globals
	$self->{_last_item}               = undef;
	$self->{_current_item}            = undef;
	$self->{_current_new_item}        = undef;
	$self->{_current_copy_item}       = undef;
	$self->{_last_mode}            	  = 10;
	$self->{_current_mode}            = 10;
	$self->{_current_mode_descr}      = "select";
	$self->{_last_mode_descr}         = "select";
	$self->{_current_pixbuf}          = undef;
	$self->{_current_pixbuf_filename} = undef;
	$self->{_cut}					  = FALSE;

	$self->{_start_time} = undef;

	bless $self, $class;

	return $self;
}

sub show {
	my $self        = shift;
	my $filename    = shift;
	my $filetype    = shift;
	my $import_hash = shift;

	$self->{_filename}    = $filename;
	$self->{_filetype}    = $filetype;
	$self->{_import_hash} = $import_hash;

	my $d = $self->{_shutter_common}->get_gettext;

	#root window
	$self->{_root} = Gtk2::Gdk->get_default_root_window;
	( $self->{_root}->{x}, $self->{_root}->{y}, $self->{_root}->{w}, $self->{_root}->{h} ) = $self->{_root}->get_geometry;
	( $self->{_root}->{x}, $self->{_root}->{y} ) = $self->{_root}->get_origin;

	$self->{_drawing_window} = Gtk2::Window->new('toplevel');
	$self->{_drawing_window}->set_title( "Shutter DrawingTool - " . $self->{_filename} );
	$self->{_drawing_window}->set_position('center');
	$self->{_drawing_window}->set_modal(1);
	$self->{_drawing_window}->signal_connect( 'delete_event', sub { return $self->quit(TRUE) } );

	#adjust toplevel window size
	if ( $self->{_root}->{w} > 640 && $self->{_root}->{h} > 480 ) {
		$self->{_drawing_window}->set_default_size( 640, 480 );
	} else {
		$self->{_drawing_window}->set_default_size( $self->{_root}->{w} - 100, $self->{_root}->{h} - 100 );
	}

	#dialogs and thumbnail generator
	$self->{_dialogs} = Shutter::App::SimpleDialogs->new( $self->{_drawing_window} );
	$self->{_thumbs}  = Shutter::Pixbuf::Thumbnail->new( $self->{_shutter_common} );

	$self->{_uimanager} = $self->setup_uimanager();

	#load settings
	$self->load_settings;

	#load file
	eval{
		$self->{_drawing_pixbuf} = Gtk2::Gdk::Pixbuf->new_from_file( $self->{_filename} );
	};
	if($@){
		my $response = $self->{_dialogs}->dlg_error_message( 
			sprintf( $d->get("Error while opening image %s."), "'" . $filename . "'"),
			$d->get( "There was an error opening the image." ),
			undef, undef, undef,
			undef, undef, undef,
			$@
		);
		
		$self->{_drawing_window}->destroy if $self->{_drawing_window};
		Gtk2->main_quit();
		return FALSE;		
	
	}
	
	#create canvas
	$self->{_canvas} = Goo::Canvas->new();
	my $gray = Gtk2::Gdk::Color->parse('gray');
	$self->{_canvas}->set( 'background-color' => sprintf( "#%04x%04x%04x", $gray->red, $gray->green, $gray->blue ) );

	#create rectangle to resize the background
	$self->{_canvas_bg_rect} = Goo::Canvas::Rect->new(
		$self->{_canvas}->get_root_item, 0, 0, $self->{_drawing_pixbuf}->get_width, $self->{_drawing_pixbuf}->get_height,
		'fill-pattern' => $self->create_color('gray', 1.0),
		'line-dash'    => Goo::Canvas::LineDash->new( [ 5, 5 ] ),
		'line-width'   => 1,
		'stroke-color' => 'black',
	);	
	$self->setup_item_signals( $self->{_canvas_bg_rect} );

	$self->handle_bg_rects( 'create' );
	$self->handle_bg_rects( 'update' );

	#create canvas background (:= screenshot)
	$self->{_canvas_bg} = Goo::Canvas::Image->new( $self->{_canvas}->get_root_item, $self->{_drawing_pixbuf}, 0, 0 );
	$self->setup_item_signals( $self->{_canvas_bg} );

	$self->handle_bg_rects( 'raise' );

	#packing
	$self->{_scrolled_window} = Gtk2::ScrolledWindow->new;
	$self->{_scrolled_window}->set_policy( 'automatic', 'automatic' );
	$self->{_scrolled_window}->add( $self->{_canvas} );

	$self->{_hscroll_hid} = $self->{_scrolled_window}->get_hscrollbar->signal_connect('value-changed' => sub { $self->adjust_rulers} );
	$self->{_vscroll_hid} = $self->{_scrolled_window}->get_vscrollbar->signal_connect('value-changed' => sub { $self->adjust_rulers} );
	
	my $drawing_vbox       = Gtk2::VBox->new( FALSE, 0 );
	my $drawing_inner_vbox = Gtk2::VBox->new( FALSE, 0 );
	my $drawing_hbox       = Gtk2::HBox->new( FALSE, 0 );

	#disable undo/redo actions at startup
	#~ $self->{_uimanager}->get_widget("/MenuBar/Edit/Undo")->set_sensitive(FALSE);
	#~ $self->{_uimanager}->get_widget("/MenuBar/Edit/Redo")->set_sensitive(FALSE);

	#do show these actions because the user would be confused
	#to see multiple shortcuts to handle zooming
	#controlequal is used for english keyboard layouts for example
	$self->{_uimanager}->get_action("/MenuBar/View/ControlEqual")->set_visible(FALSE);
	$self->{_uimanager}->get_action("/MenuBar/View/ControlKpAdd")->set_visible(FALSE);
	$self->{_uimanager}->get_action("/MenuBar/View/ControlKpSub")->set_visible(FALSE);

	#create a table for placing the ruler and scrolle window
	my $table = new Gtk2::Table( 3, 2, FALSE );

	$self->{_drawing_window}->add($drawing_vbox);

	my $menubar = $self->{_uimanager}->get_widget("/MenuBar");
	$drawing_vbox->pack_start( $menubar, FALSE, FALSE, 0 );

	my $toolbar_drawing = $self->{_uimanager}->get_widget("/ToolBarDrawing");
	$toolbar_drawing->set_orientation('vertical');
	$toolbar_drawing->set_style('icons');
	$toolbar_drawing->set_icon_size('menu');
	$toolbar_drawing->set_show_arrow(FALSE);
	$drawing_hbox->pack_start( $toolbar_drawing, FALSE, FALSE, 0 );

	#vruler
	$self->{_vruler} = Gtk2::VRuler->new;
	$self->{_vruler}->set_metric('pixels');
	$self->{_vruler}->set_range( 0, $self->{_drawing_pixbuf}->get_height, 0, $self->{_drawing_pixbuf}->get_height );

	#hruler
	$self->{_hruler} = Gtk2::HRuler->new;
	$self->{_hruler}->set_metric('pixels');
	$self->{_hruler}->set_range( 0, $self->{_drawing_pixbuf}->get_width, 0, $self->{_drawing_pixbuf}->get_width );

	#attach scrolled window and rulers to the table
	$table->attach( $self->{_scrolled_window}, 1, 2, 1, 2, [ 'expand', 'fill' ], [ 'expand', 'fill' ], 0, 0 );

	$table->attach( $self->{_hruler}, 1, 2, 0, 1, [ 'expand', 'shrink', 'fill' ], [], 0, 0 );
	$table->attach( $self->{_vruler}, 0, 1, 1, 2, [], [ 'fill', 'expand', 'shrink' ], 0, 0 );

	$drawing_inner_vbox->pack_start( $table,                   TRUE,  TRUE, 0 );
	$drawing_inner_vbox->pack_start( $self->setup_bottom_hbox, FALSE, TRUE, 0 );
	$drawing_hbox->pack_start( $drawing_inner_vbox, TRUE, TRUE, 0 );

	my $toolbar = $self->{_uimanager}->get_widget("/ToolBar");
	$drawing_vbox->pack_start( $self->{_uimanager}->get_widget("/ToolBar"), FALSE, FALSE, 0 );

	$drawing_vbox->pack_start( $drawing_hbox, TRUE, TRUE, 0 );

	$self->{_drawing_statusbar} = Gtk2::Statusbar->new;
	$drawing_vbox->pack_start( $self->{_drawing_statusbar}, FALSE, FALSE, 0 );

	$self->{_drawing_window}->show_all();

	$self->{_drawing_window}->window->focus(time);

	$self->adjust_rulers;

	#save start time to show in close dialog
	$self->{_start_time} = time;

	#init current tool
	$self->set_drawing_action(int($self->{_current_mode}/10));
	$self->change_drawing_tool_cb($self->{_current_mode});

	#remember drawing colors, line width and font settings
	#maybe we have to restore them
	$self->{_last_fill_color}         = $self->{_fill_color_w}->get_color;
	$self->{_last_fill_color_alpha}   = $self->{_fill_color_w}->get_alpha;
	$self->{_last_stroke_color}       = $self->{_stroke_color_w}->get_color;
	$self->{_last_stroke_color_alpha} = $self->{_stroke_color_w}->get_alpha;
	$self->{_last_line_width} 		  = $self->{_line_spin_w}->get_value;
	$self->{_last_font} 			  = $self->{_font_btn_w}->get_font_name;

	#remember the last mode as well
	$self->{_last_mode}            	  = $self->{_current_mode};
	$self->{_last_mode_descr}         = $self->{_current_mode_descr};	

	Gtk2->main;

	return TRUE;
}

sub setup_bottom_hbox {
	my $self = shift;

	my $d = $self->{_shutter_common}->get_gettext;

	#Tooltips
	my $tooltips = $self->{_shutter_common}->get_tooltips;

	my $drawing_bottom_hbox = Gtk2::HBox->new( FALSE, 5 );

	#fill color
	my $fill_color_label = Gtk2::Label->new( $d->get("Fill color") . ":" );
	$self->{_fill_color_w} = Gtk2::ColorButton->new();
	$self->{_fill_color_w}->set_color( $self->{_fill_color} );
	$self->{_fill_color_w}->set_alpha( int( $self->{_fill_color_alpha} * 65636 ) );
	$self->{_fill_color_w}->set_use_alpha(TRUE);
	$self->{_fill_color_w}->set_title( $d->get("Choose fill color") );

	$tooltips->set_tip( $fill_color_label, $d->get("Adjust fill color and opacity") );
	$tooltips->set_tip( $self->{_fill_color_w}, $d->get("Adjust fill color and opacity") );

	$drawing_bottom_hbox->pack_start( $fill_color_label, FALSE, FALSE, 5 );
	$drawing_bottom_hbox->pack_start( $self->{_fill_color_w}, FALSE, FALSE, 5 );

	#stroke color
	my $stroke_color_label = Gtk2::Label->new( $d->get("Stroke color") . ":" );
	$self->{_stroke_color_w} = Gtk2::ColorButton->new();
	$self->{_stroke_color_w}->set_color( $self->{_stroke_color} );
	$self->{_stroke_color_w}->set_alpha( int( $self->{_stroke_color_alpha} * 65535 ) );
	$self->{_stroke_color_w}->set_use_alpha(TRUE);
	$self->{_stroke_color_w}->set_title( $d->get("Choose stroke color") );

	$tooltips->set_tip( $stroke_color_label, $d->get("Adjust stroke color and opacity") );
	$tooltips->set_tip( $self->{_stroke_color_w}, $d->get("Adjust stroke color and opacity") );

	$drawing_bottom_hbox->pack_start( $stroke_color_label, FALSE, FALSE, 5 );
	$drawing_bottom_hbox->pack_start( $self->{_stroke_color_w}, FALSE, FALSE, 5 );

	#line_width
	my $linew_label = Gtk2::Label->new( $d->get("Line width") . ":" );
	$self->{_line_spin_w} = Gtk2::SpinButton->new_with_range( 0.5, 20, 0.1 );
	$self->{_line_spin_w}->set_value( $self->{_line_width} );

	$tooltips->set_tip( $linew_label, $d->get("Adjust line width") );
	$tooltips->set_tip( $self->{_line_spin_w},   $d->get("Adjust line width") );

	$drawing_bottom_hbox->pack_start( $linew_label, FALSE, FALSE, 5 );
	$drawing_bottom_hbox->pack_start( $self->{_line_spin_w},   FALSE, FALSE, 5 );

	#font button
	my $font_label = Gtk2::Label->new( $d->get("Font") . ":" );
	$self->{_font_btn_w} = Gtk2::FontButton->new();
	$self->{_font_btn_w}->set_font_name( $self->{_font} );

	$tooltips->set_tip( $font_label, $d->get("Select font family and size") );
	$tooltips->set_tip( $self->{_font_btn_w}, $d->get("Select font family and size") );

	$drawing_bottom_hbox->pack_start( $font_label, FALSE, FALSE, 5 );
	$drawing_bottom_hbox->pack_start( $self->{_font_btn_w}, FALSE, FALSE, 5 );

	#image button
	my $image_label = Gtk2::Label->new( $d->get("Insert image") . ":" );
	my $image_btn = Gtk2::MenuToolButton->new( undef, undef );
	$image_btn->set_menu( $self->ret_objects_menu($image_btn) );

	#handle property changes 
	#changes are applied directly to the current item
	$self->{_line_spin_wh} = $self->{_line_spin_w}->signal_connect(
		'value-changed' => sub {
			$self->{_line_width} = $self->{_line_spin_w}->get_value;

			if($self->{_current_item}){
				#apply all changes directly
				my $item 	= $self->{_current_item};
				if(my $child = $self->get_child_item($item)){
					$item = $child;
				}
				my $parent 	= $self->get_parent_item($item);
				#determine key for item hash
				my $key = $self->get_item_key($item, $parent);

				$self->apply_properties($item, $parent, $key, $self->{_fill_color_w}, 
										$self->{_stroke_color_w}, $self->{_line_spin_w}, 
										$self->{_stroke_color_w}, $self->{_font_btn_w});
										
			}

		}
	);
	
	$self->{_stroke_color_wh} = $self->{_stroke_color_w}->signal_connect(
		'color-set' => sub {
			$self->{_stroke_color}       = $self->{_stroke_color_w}->get_color;
			$self->{_stroke_color_alpha} = $self->{_stroke_color_w}->get_alpha / 65535;

			if($self->{_current_item}){
				#apply all changes directly
				my $item 	= $self->{_current_item};
				if(my $child = $self->get_child_item($item)){
					$item = $child;
				}
				my $parent 	= $self->get_parent_item($item);
				#determine key for item hash
				my $key = $self->get_item_key($item, $parent);

				$self->apply_properties($item, $parent, $key, $self->{_fill_color_w}, 
										$self->{_stroke_color_w}, $self->{_line_spin_w}, 
										$self->{_stroke_color_w}, $self->{_font_btn_w});
										
			}	

		}
	);
	
	$self->{_fill_color_wh} = $self->{_fill_color_w}->signal_connect(
		'color-set' => sub {
			$self->{_fill_color}       = $self->{_fill_color_w}->get_color;
			$self->{_fill_color_alpha} = $self->{_fill_color_w}->get_alpha / 65636;

			if($self->{_current_item}){
				#apply all changes directly
				my $item 	= $self->{_current_item};
				if(my $child = $self->get_child_item($item)){
					$item = $child;
				}
				my $parent 	= $self->get_parent_item($item);
				#determine key for item hash
				my $key = $self->get_item_key($item, $parent);

				$self->apply_properties($item, $parent, $key, $self->{_fill_color_w}, 
										$self->{_stroke_color_w}, $self->{_line_spin_w}, 
										$self->{_stroke_color_w}, $self->{_font_btn_w});
										
			}
		
		}
	);
	
	$self->{_font_btn_wh} = $self->{_font_btn_w}->signal_connect(
		'font-set' => sub {
			my $font_descr = Gtk2::Pango::FontDescription->from_string( $self->{_font_btn_w}->get_font_name );
			$self->{_font} = $font_descr->to_string;

			if($self->{_current_item}){
				#apply all changes directly
				my $item 	= $self->{_current_item};
				if(my $child = $self->get_child_item($item)){
					$item = $child;
				}
				my $parent 	= $self->get_parent_item($item);
				#determine key for item hash
				my $key = $self->get_item_key($item, $parent);

				$self->apply_properties($item, $parent, $key, $self->{_fill_color_w}, 
										$self->{_stroke_color_w}, $self->{_line_spin_w}, 
										$self->{_stroke_color_w}, $self->{_font_btn_w});
										
			}	

		}
	);
	
	$image_btn->signal_connect(
		'clicked' => sub {
			$self->{_canvas}->window->set_cursor($self->change_cursor_to_current_pixbuf);
		}
	);

	$tooltips->set_tip( $image_label, $d->get("Insert an arbitrary object or file") );
	$tooltips->set_tip( $image_btn,   $d->get("Insert an arbitrary object or file") );

	$drawing_bottom_hbox->pack_start( $image_label, FALSE, FALSE, 5 );
	$drawing_bottom_hbox->pack_start( $image_btn,   FALSE, FALSE, 5 );

	return $drawing_bottom_hbox;
}

sub push_to_statusbar {
	my $self = shift;
	my $x = shift;
	my $y = shift;
	my $action = shift || 'none';

	my $d = $self->{_shutter_common}->get_gettext;

	my $status_text = int( $x ) . " x " . int( $y );
		
	if ( $self->{_current_mode} == 10 ) {

		if($action eq 'resize'){
			$status_text .= " ".$d->get("Click-Drag to scale (try Control to scale uniformly)");	
		}elsif($action eq 'canvas_resize'){
			$status_text .= " ".$d->get("Click-Drag to resize the canvas");				
		}
		
	} elsif ( $self->{_current_mode} == 20 || $self->{_current_mode} == 30) {

		$status_text .= " ".$d->get("Click to paint (try Control or Shift for a straight line)");
		
	} elsif ( $self->{_current_mode} == 40 ) {

		$status_text .= " ".$d->get("Click-Drag to create a new straight line");

	} elsif ( $self->{_current_mode} == 50 ) {

		$status_text .= " ".$d->get("Click-Drag to create a new arrow");

	} elsif ( $self->{_current_mode} == 60 ) {

		$status_text .= " ".$d->get("Click-Drag to create a new rectangle");

	} elsif ( $self->{_current_mode} == 70 ) {

		$status_text .= " ".$d->get("Click-Drag to create a new ellipse");

	} elsif ( $self->{_current_mode} == 80 ) {

		$status_text .= " ".$d->get("Click-Drag to add a new text area");

	} elsif ( $self->{_current_mode} == 90 ) {

		$status_text .= " ".$d->get("Click to censor (try Control or Shift for a straight line)");

	} elsif ( $self->{_current_mode} == 100 ) {

		$status_text .= " ".$d->get("Select an object to delete it from the canvas");

	} elsif ( $self->{_current_mode} == 110 ) {

		$status_text .= " ".$d->get("Delete all objects");

	} 	

	#update statusbar
	$self->{_drawing_statusbar}->push( 0, $status_text );
	
	return TRUE;		

}

sub change_drawing_tool_cb {
	my $self   = shift;
	my $action = shift;

	eval { $self->{_current_mode} = $action->get_current_value; };
	if ($@) {
		$self->{_current_mode} = $action;
	}

	#define own icons
	my $dicons = $self->{_shutter_common}->get_root . "/share/shutter/resources/icons/drawing_tool";
	my $cursor = Gtk2::Gdk::Cursor->new('left-ptr');

	#tool is switched from "highlighter" OR censor to something else (excluding select tool)
	if($self->{_current_mode} != 30 && $self->{_current_mode} != 90 && $self->{_current_mode} != 10){
	
		$self->restore_drawing_properties;
	
	}

	if ( $self->{_current_mode} == 10 ) {

		$self->{_current_mode_descr} = "select";

	} elsif ( $self->{_current_mode} == 20 ) {

		$self->{_current_mode_descr} = "freehand";
		$cursor = Gtk2::Gdk::Cursor->new('pencil');
	
	} elsif ( $self->{_current_mode} == 30 ) {

		$self->{_current_mode_descr} = "highlighter";
		$cursor = Gtk2::Gdk::Cursor->new('dotbox');

	} elsif ( $self->{_current_mode} == 40 ) {

		$self->{_current_mode_descr} = "line";
		$cursor = Gtk2::Gdk::Cursor->new_from_pixbuf(
			Gtk2::Gdk::Display->get_default,
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-line.png"),
			Gtk2::IconSize->lookup('menu')
		);

	} elsif ( $self->{_current_mode} == 50 ) {

		$self->{_current_mode_descr} = "arrow";
		$cursor = Gtk2::Gdk::Cursor->new_from_pixbuf(
			Gtk2::Gdk::Display->get_default,
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-arrow.png"),
			Gtk2::IconSize->lookup('menu')
		);

	} elsif ( $self->{_current_mode} == 60 ) {

		$self->{_current_mode_descr} = "rect";
		$cursor = Gtk2::Gdk::Cursor->new_from_pixbuf(
			Gtk2::Gdk::Display->get_default,
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-rectangle.png"),
			Gtk2::IconSize->lookup('menu')
		);

	} elsif ( $self->{_current_mode} == 70 ) {

		$self->{_current_mode_descr} = "ellipse";
		$cursor = Gtk2::Gdk::Cursor->new_from_pixbuf(
			Gtk2::Gdk::Display->get_default,
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-ellipse.png"),
			Gtk2::IconSize->lookup('menu')
		);

	} elsif ( $self->{_current_mode} == 80 ) {

		$self->{_current_mode_descr} = "text";
		$cursor = Gtk2::Gdk::Cursor->new_from_pixbuf(
			Gtk2::Gdk::Display->get_default,
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-text.png"),
			Gtk2::IconSize->lookup('menu')
		);
	} elsif ( $self->{_current_mode} == 90 ) {

		$self->{_current_mode_descr} = "censor";
		$cursor = Gtk2::Gdk::Cursor->new_from_pixbuf(
			Gtk2::Gdk::Display->get_default,
			Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-censor.png"),
			Gtk2::IconSize->lookup('menu')
		);

	} elsif ( $self->{_current_mode} == 100 ) {

		$self->{_current_mode_descr} = "clear";

	} elsif ( $self->{_current_mode} == 110 ) {

		$self->{_current_mode_descr} = "clear_all";

		foreach(keys %{$self->{_items}}){
			$self->clear_item_from_canvas($self->{_items}{$_});	
		}
		
		$self->set_drawing_action(0);
		$self->change_drawing_tool_cb(10);

	} 

	if($self->{_canvas}){
		$self->{_canvas}->window->set_cursor($cursor);
	}

	return TRUE;
}

sub zoom_in_cb {
	my $self = shift;
	$self->{_canvas}->set_scale( $self->{_canvas}->get_scale + 0.25 );
	$self->adjust_rulers;
	return TRUE;
}

sub zoom_out_cb {
	my $self      = shift;
	my $new_scale = $self->{_canvas}->get_scale - 0.25;
	if ( $new_scale < 0.25 ) {
		$self->{_canvas}->set_scale(0.25);
	} else {
		$self->{_canvas}->set_scale($new_scale);
	}
	$self->adjust_rulers;
	return TRUE;
}

sub zoom_normal_cb {
	my $self = shift;
	$self->{_canvas}->set_scale(1);
	$self->adjust_rulers;
	return TRUE;
}

sub adjust_rulers {
	my $self = shift;
	my $ev   = shift;
	my $item = shift;

	my $s = $self->{_canvas}->get_scale;

	my ( $hlower, $hupper, $hposition, $hmax_size ) = $self->{_hruler}->get_range;
	my ( $vlower, $vupper, $vposition, $vmax_size ) = $self->{_vruler}->get_range;
		
	if($ev){
						
		my $copy_event = $ev->copy;
			
		#modify event to respect scrollbars and canvas scale
		$copy_event->x( ($copy_event->x_root - $hlower) * $s);
		$copy_event->y( ($copy_event->y_root - $vlower) * $s);	

		$self->{_hruler}->signal_emit('motion-notify-event', $copy_event);
		$self->{_vruler}->signal_emit('motion-notify-event', $copy_event);
	
	}else{

		#modify rulers (e.g. done when scrolling or zooming)
		if($self->{_hruler} && $self->{_hruler}){

			my ( $x, $y, $width, $height, $depth ) = $self->{_canvas}->window->get_geometry;
			my $ha = $self->{_scrolled_window}->get_hadjustment->value / $s;
			my $va = $self->{_scrolled_window}->get_vadjustment->value / $s;

			$self->{_hruler}->set_range( $ha, $ha + $width  / $s, 0, $hmax_size );
			$self->{_vruler}->set_range( $va, $va + $height / $s, 0, $vmax_size );

		}
		
	}

	return TRUE;
}

sub quit {
	my $self         = shift;
	my $show_warning = shift;

	my $d = $self->{_shutter_common}->get_gettext;

	my ( $name, $folder, $type ) = fileparse( $self->{_filename}, '\..*' );

	#we are closing the drawing tool as well after saving the changes
	#so save changes to a file in the shutter folder
	#is there already a .shutter folder?
	mkdir("$ENV{ 'HOME' }/.shutter")
		unless ( -d "$ENV{ 'HOME' }/.shutter" );

	$self->save_settings;

	if ( $show_warning && scalar( keys %{ $self->{_items} } ) > 0 ) {

		#warn the user if there are any unsaved changes
		my $warn_dialog = Gtk2::MessageDialog->new( $self->{_drawing_window}, [qw/modal destroy-with-parent/], 'other', 'none', undef );

		#set question text
		$warn_dialog->set( 'text' => sprintf( $d->get("Save the changes to image %s before closing?"), "'$name$type'" ) );

		#set text...
		$self->update_warning_text($warn_dialog);

		#...and update it
		my $id = Glib::Timeout->add(
			1000,
			sub {
				$self->update_warning_text($warn_dialog);
				return TRUE;
			}
		);

		$warn_dialog->set( 'image' => Gtk2::Image->new_from_stock( 'gtk-save', 'dialog' ) );

		$warn_dialog->set( 'title' => $d->get("Close") . " " . $name . $type );

		#don't save button
		my $dsave_btn = Gtk2::Button->new_with_mnemonic( $d->get("Do_n't save") );
		$dsave_btn->set_image( Gtk2::Image->new_from_stock( 'gtk-delete', 'button' ) );

		#cancel button
		my $cancel_btn = Gtk2::Button->new_from_stock('gtk-cancel');
		$cancel_btn->can_default(TRUE);

		#save button
		my $save_btn = Gtk2::Button->new_from_stock('gtk-save');

		$warn_dialog->add_action_widget( $dsave_btn,  10 );
		$warn_dialog->add_action_widget( $cancel_btn, 20 );
		$warn_dialog->add_action_widget( $save_btn,   30 );

		$warn_dialog->set_default_response(20);

		$warn_dialog->vbox->show_all;
		my $response = $warn_dialog->run;
		Glib::Source->remove($id);
		if ( $response == 20 ) {
			$warn_dialog->destroy;
			return TRUE;
		} elsif ( $response == 30 ) {
			$self->save();
		}

		$warn_dialog->destroy;

	}
	$self->{_drawing_window}->destroy if $self->{_drawing_window};
	Gtk2->main_quit();

	return FALSE;
}

sub update_warning_text {
	my $self        = shift;
	my $warn_dialog = shift;

	my $d = $self->{_shutter_common}->get_gettext;

	my $minutes = int( ( time - $self->{_start_time} ) / 60 );
	$minutes = 1 if $minutes == 0;
	$warn_dialog->set(
		'secondary-text' => sprintf(
			$d->nget(
				"If you don't save the image, changes from the last minute will be lost",
				"If you don't save the image, changes from the last %d minutes will be lost",
				$minutes
			),
			$minutes,
			)
			. "."
	);
	return TRUE;
}

sub load_settings {
	my $self = shift;

	my $shutter_hfunct = Shutter::App::HelperFunctions->new( $self->{_shutter_common} );

	#settings file
	my $settingsfile = "$ENV{ HOME }/.shutter/drawingtool.xml";

	my $settings_xml;
	if ( $shutter_hfunct->file_exists($settingsfile) ) {
		eval {
			$settings_xml = XMLin($settingsfile);
	
			#window size and position
			if($settings_xml->{'drawing'}->{'x'} && $settings_xml->{'drawing'}->{'y'}){
				$self->{_drawing_window}->move($settings_xml->{'drawing'}->{'x'}, $settings_xml->{'drawing'}->{'y'});
			}
	
			if($settings_xml->{'drawing'}->{'width'} && $settings_xml->{'drawing'}->{'height'}){
				$self->{_drawing_window}->resize($settings_xml->{'drawing'}->{'width'}, $settings_xml->{'drawing'}->{'height'});			
			}	
			
			#current mode
			if($settings_xml->{'drawing'}->{'mode'}){
				$self->{_current_mode} = $settings_xml->{'drawing'}->{'mode'};
			}
					
			#autoscroll
			my $autoscroll_toggle = $self->{_uimanager}->get_widget("/MenuBar/Edit/Autoscroll");
			$autoscroll_toggle->set_active( $settings_xml->{'drawing'}->{'autoscroll'} );

			#drawing colors
			$self->{_fill_color}         = Gtk2::Gdk::Color->parse( $settings_xml->{'drawing'}->{'fill_color'} );
			$self->{_fill_color_alpha}   = $settings_xml->{'drawing'}->{'fill_color_alpha'};
			$self->{_stroke_color}       = Gtk2::Gdk::Color->parse( $settings_xml->{'drawing'}->{'stroke_color'} );
			$self->{_stroke_color_alpha} = $settings_xml->{'drawing'}->{'stroke_color_alpha'};

			#line_width
			$self->{_line_width} = $settings_xml->{'drawing'}->{'line_width'};

			#font
			$self->{_font} = $settings_xml->{'drawing'}->{'font'};				
		};
		if ($@) {
			warn "ERROR: Settings of DrawingTool could not be restored: $@ - ignoring\n";
		}
	}
	return TRUE;
}

sub save_settings {
	my $self = shift;

	#to avoid saving the properties of the highlighter
	#this does not make any sense
	$self->restore_drawing_properties;

	#settings file
	my $settingsfile = "$ENV{ HOME }/.shutter/drawingtool.xml";

	eval {
		open( SETTFILE, ">$settingsfile" );

		my %settings;    #hash to store settings

		#window size and position
		my ($w, $h) = $self->{_drawing_window}->get_size;
		my ($x, $y) = $self->{_drawing_window}->get_position;
		$settings{'drawing'}->{'x'} = $x;
		$settings{'drawing'}->{'y'} = $y;
		$settings{'drawing'}->{'width'} = $w;
		$settings{'drawing'}->{'height'} = $h;
		
		#current action
		$settings{'drawing'}->{'mode'} = $self->{_current_mode}; 

		#autoscroll
		my $autoscroll_toggle = $self->{_uimanager}->get_widget("/MenuBar/Edit/Autoscroll");
		$settings{'drawing'}->{'autoscroll'} = $autoscroll_toggle->get_active();

		#drawing colors
		$settings{'drawing'}->{'fill_color'}
			= sprintf( "#%04x%04x%04x", $self->{_fill_color}->red, $self->{_fill_color}->green, $self->{_fill_color}->blue );
		$settings{'drawing'}->{'fill_color_alpha'} = $self->{_fill_color_alpha};
		$settings{'drawing'}->{'stroke_color'}
			= sprintf( "#%04x%04x%04x", $self->{_stroke_color}->red, $self->{_stroke_color}->green, $self->{_stroke_color}->blue );
		$settings{'drawing'}->{'stroke_color_alpha'} = $self->{_stroke_color_alpha};

		#line_width
		$settings{'drawing'}->{'line_width'} = $self->{_line_width};

		#font
		$settings{'drawing'}->{'font'} = $self->{_font};

		#settings
		print SETTFILE XMLout( \%settings );

		close(SETTFILE);
	};
	if ($@) {
		warn "ERROR: Settings of DrawingTool could not be saved: $@ - ignoring\n";
	}

	return TRUE;
}

sub save {
	my $self = shift;

	#we are closing the drawing tool as well after saving the changes
	#so save changes to a file in the shutter folder
	#is there already a .shutter folder?
	mkdir("$ENV{ 'HOME' }/.shutter")
		unless ( -d "$ENV{ 'HOME' }/.shutter" );

	$self->save_settings;

	#make sure not to save the bounding rectangles
	$self->deactivate_all;
	$self->handle_bg_rects('hide');

	my $surface = Cairo::ImageSurface->create( 'argb32', $self->{_canvas_bg}->get('width'), $self->{_canvas_bg}->get('height') );

	my $cr   = Cairo::Context->create($surface);
	$self->{_canvas}->get_root_item->paint( $cr, $self->{_canvas_bg}->get_bounds, 1 );

	my $loader = Gtk2::Gdk::PixbufLoader->new;
	$surface->write_to_png_stream(
		sub {
			my ( $closure, $data ) = @_;
			$loader->write($data);
		}
	);
	$loader->close;
	my $pixbuf = $loader->get_pixbuf;

	#save pixbuf to file
	my $pixbuf_save = Shutter::Pixbuf::Save->new( $self->{_shutter_common}, $self->{_drawing_window} );
	return $pixbuf_save->save_pixbuf_to_file($pixbuf, $self->{_filename}, $self->{_filename}, $self->{_filetype});

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

	$self->adjust_rulers($ev, $item);
	
	#autoscroll if enabled
	if (   $self->{_autoscroll}
		&& $self->{_current_mode_descr} ne "clear"
		&& $ev->state >= 'button1-mask' )
	{
		
		my ( $x, $y, $width, $height, $depth ) = $self->{_canvas}->window->get_geometry;
		my $s  = $self->{_canvas}->get_scale;
		my $ha = $self->{_scrolled_window}->get_hadjustment->value;
		my $va = $self->{_scrolled_window}->get_vadjustment->value;

		#autoscroll >> down and right
		if (   $ev->x_root > ( $ha / $s + $width / $s - 100 / $s )
			&& $ev->y_root > ( $va / $s + $height / $s - 100 / $s ) )
		{
			$self->{_canvas}->scroll_to(
				$ha / $s + 10 / $s,
				$va / $s + 10 / $s
			);
		} elsif ( $ev->x_root > ( $ha / $s + $width / $s - 100 / $s ) ) {
			$self->{_canvas}->scroll_to(
				$ha / $s + 10 / $s,
				$va / $s
			);
		} elsif ( $ev->y_root > ( $va / $s + $height / $s - 100 / $s ) ) {
			$self->{_canvas}->scroll_to(
				$ha / $s,
				$va / $s + 10 / $s
			);
		}

		#autoscroll >> up and left
		if (   $ev->x_root < ( $ha / $s + 100 / $s )
			&& $ev->y_root < ( $va / $s + 100 / $s ) )
		{
			$self->{_canvas}->scroll_to(
				$ha / $s - 10 / $s,
				$va / $s - 10 / $s
			);
		} elsif ( $ev->x_root < ( $ha / $s + 100 / $s ) ) {
			$self->{_canvas}->scroll_to(
				$ha / $s - 10 / $s,
				$va / $s
			);
		} elsif ( $ev->y_root < ( $va / $s + 100 / $s ) ) {
			$self->{_canvas}->scroll_to(
				$ha / $s,
				$va / $s - 10 / $s
			);
		}
	}

	#move
	if ( $item->{dragging} && $ev->state >= 'button1-mask' ) {

		if ( $item->isa('Goo::Canvas::Rect') ) {

			my $new_x = $self->{_items}{$item}->get('x') + $ev->x_root - $item->{drag_x};
			my $new_y = $self->{_items}{$item}->get('y') + $ev->y_root - $item->{drag_y};

			$self->{_items}{$item}->set(
				'x' => $new_x,
				'y' => $new_y,
			);

			$item->{drag_x} = $ev->x_root;
			$item->{drag_y} = $ev->y_root;

			$self->handle_rects( 'update', $item );
			$self->handle_embedded( 'update', $item );

		} else {

			$item->translate( $ev->x - $item->{drag_x}, $ev->y - $item->{drag_y} )
				unless $item == $self->{_canvas_bg};
		}

		#freehand line
	} elsif ( ($self->{_current_mode_descr} eq "freehand" || $self->{_current_mode_descr} eq "highlighter" ||$self->{_current_mode_descr} eq "censor") && $ev->state >= 'button1-mask' ) {

		#mark as active item
		my $item = undef;
		if($self->{_current_new_item}){
			$item = $self->{_current_new_item};
			$self->{_current_new_item} = undef;
			$self->{_current_item} = $item;
			
			#apply item properties to widgets
			#line width, fill color, stroke color etc.
			$self->set_and_save_drawing_properties($item, FALSE);
		}else{
			$item = $self->{_current_item};	
		}
		
		if($ev->state >= 'control-mask'){
			my $last_point = pop @{ $self->{_items}{$item}{'points'} };
			$last_point = $ev->y_root unless $last_point;
			push @{ $self->{_items}{$item}{'points'} }, $last_point, $ev->x_root, $last_point;
		}elsif($ev->state >= 'shift-mask'){
			my $last_point_y = pop @{ $self->{_items}{$item}{'points'} };
			my $last_point_x = pop @{ $self->{_items}{$item}{'points'} };
			$last_point_x = $ev->x_root unless $last_point_x;
			$last_point_y = $ev->y_root unless $last_point_y;
			push @{ $self->{_items}{$item}{'points'} }, $last_point_x, $last_point_y, $last_point_x, $ev->y_root;		
		}else{
			push @{ $self->{_items}{$item}{'points'} }, $ev->x_root, $ev->y_root;		
		}
		$self->{_items}{$item}->set( points => Goo::Canvas::Points->new( $self->{_items}{$item}{'points'} ) );
		
		#new item is already on the canvas with small initial size
		#drawing is like resizing, so set up for resizing
	} elsif (
		(      $self->{_current_mode_descr} eq "rect"
			|| $self->{_current_mode_descr} eq "line"
			|| $self->{_current_mode_descr} eq "arrow"
			|| $self->{_current_mode_descr} eq "ellipse"
			|| $self->{_current_mode_descr} eq "text"
			|| $self->{_current_mode_descr} eq "image"
		)
		&& $ev->state >= 'button1-mask'
		&& !$item->{resizing} #if item is not in resize mode already
		)
	{

		my $item = $self->{_current_new_item};
		$self->{_current_new_item} = undef;
		$self->{_current_item} = $item;
	
		#apply item properties to widgets / or only save it
		#line width, fill color, stroke color etc.
		$self->set_and_save_drawing_properties($self->{_current_item}, TRUE);	
		
		$self->{_items}{$item}{'bottom-right-corner'}->{res_x}    = $ev->x_root;
		$self->{_items}{$item}{'bottom-right-corner'}->{res_y}    = $ev->y_root;
		$self->{_items}{$item}{'bottom-right-corner'}->{resizing} = TRUE;
		$self->{_canvas}->pointer_grab( $self->{_items}{$item}{'bottom-right-corner'}, [ 'pointer-motion-mask', 'button-release-mask' ], Gtk2::Gdk::Cursor->new('bottom-right-corner'), $ev->time );

	#item is resizing mode already
	} elsif ( $item->{resizing} && $ev->state >= 'button1-mask' ) {

		$self->{_current_mode_descr} = "resize";

			#canvas resizing shape
		if ( $self->{_canvas_bg_rect}{'right-side'} == $item ) {

			my $new_width = $self->{_canvas_bg_rect}->get('width') +  ( $ev->x_root - $item->{res_x} );

			unless ( $new_width < 0 ) {

				$self->{_canvas_bg_rect}->set(
					'width'  => $new_width,
				);
				
				$self->handle_bg_rects('update');			

			}
	
		} elsif ( $self->{_canvas_bg_rect}{'bottom-side'} == $item ) {

			my $new_height = $self->{_canvas_bg_rect}->get('height') + ( $ev->y_root - $item->{res_y} );
	
			unless ( $new_height < 0 ) {
						
				$self->{_canvas_bg_rect}->set(
					'height'  => $new_height,
				);
				
				$self->handle_bg_rects('update');
		
			}
		
		} elsif ( $self->{_canvas_bg_rect}{'bottom-right-corner'} == $item ) {			

			my $new_width = $self->{_canvas_bg_rect}->get('width') +  ( $ev->x_root - $item->{res_x} );
			my $new_height = $self->{_canvas_bg_rect}->get('height') + ( $ev->y_root - $item->{res_y} );

			unless ( $new_width < 0 || $new_height < 0) {		
			
				$self->{_canvas_bg_rect}->set(
					'width'  => $new_width,
					'height'  => $new_height,
				);
				
				$self->handle_bg_rects('update');

			}
			
			#item resizing shape
		}else {
			
			my $curr_item = $self->{_current_item};
			my $cursor = undef;

			#calculate aspect ratio (resizing when control is pressed)
			my $ratio = 1;
			$ratio = $self->{_items}{$curr_item}->get('width')/$self->{_items}{$curr_item}->get('height') if $self->{_items}{$curr_item}->get('height') != 0;

			foreach ( keys %{ $self->{_items}{$curr_item} } ) {

				#fancy resizing using our little resize boxes
				if ( $item == $self->{_items}{$curr_item}{$_} ) {

					my $new_x      = 0;
					my $new_y      = 0;
					my $new_width  = 0;
					my $new_height = 0;

					if ( $_ eq 'top-left-corner' ) {
						
						$cursor = $_;
						
						if($ev->state >= 'control-mask'){
							$new_x = $self->{_items}{$curr_item}->get('x') + ($ev->y_root - $item->{res_y}) * $ratio;
							$new_y = $self->{_items}{$curr_item}->get('y') + ($ev->y_root - $item->{res_y});						
							$new_width  = $self->{_items}{$curr_item}->get('width') +  ( $self->{_items}{$curr_item}->get('x') - $new_x );
							$new_height = $self->{_items}{$curr_item}->get('height') + ( $self->{_items}{$curr_item}->get('y') - $new_y );
						}else{
							$new_x = $self->{_items}{$curr_item}->get('x') + $ev->x_root - $item->{res_x};
							$new_y = $self->{_items}{$curr_item}->get('y') + $ev->y_root - $item->{res_y};						
							$new_width  = $self->{_items}{$curr_item}->get('width') +  ( $self->{_items}{$curr_item}->get('x') - $new_x );
							$new_height = $self->{_items}{$curr_item}->get('height') + ( $self->{_items}{$curr_item}->get('y') - $new_y );
						}

					} elsif ( $_ eq 'top-side' ) {

						$cursor = $_;

						$new_x = $self->{_items}{$curr_item}->get('x');
						$new_y = $self->{_items}{$curr_item}->get('y') + $ev->y_root - $item->{res_y};

						$new_width = $self->{_items}{$curr_item}->get('width');
						$new_height = $self->{_items}{$curr_item}->get('height') + ( $self->{_items}{$curr_item}->get('y') - $new_y );
					
					} elsif ( $_ eq 'top-right-corner' ) {

							$cursor = $_;

							$new_x = $self->{_items}{$curr_item}->get('x');
							$new_y = $self->{_items}{$curr_item}->get('y') + $ev->y_root - $item->{res_y};

						if($ev->state >= 'control-mask'){
							$new_width  = $self->{_items}{$curr_item}->get('width') - ( $ev->y_root - $item->{res_y} ) * $ratio;
							$new_height = $self->{_items}{$curr_item}->get('height') + ( $self->{_items}{$curr_item}->get('y') - $new_y );		
						}else{
							$new_width  = $self->{_items}{$curr_item}->get('width') +  ( $ev->x_root - $item->{res_x} );
							$new_height = $self->{_items}{$curr_item}->get('height') + ( $self->{_items}{$curr_item}->get('y') - $new_y );					
						}

					} elsif ( $_ eq 'left-side' ) {

						$cursor = $_;

						$new_x = $self->{_items}{$curr_item}->get('x') + $ev->x_root - $item->{res_x};
						$new_y = $self->{_items}{$curr_item}->get('y');

						$new_width = $self->{_items}{$curr_item}->get('width') + ( $self->{_items}{$curr_item}->get('x') - $new_x );
						$new_height = $self->{_items}{$curr_item}->get('height');

					} elsif ( $_ eq 'right-side' ) {

						$cursor = $_;
		
						$new_x = $self->{_items}{$curr_item}->get('x');
						$new_y = $self->{_items}{$curr_item}->get('y');

						$new_width = $self->{_items}{$curr_item}->get('width') + ( $ev->x_root - $item->{res_x} );
						$new_height = $self->{_items}{$curr_item}->get('height');

					} elsif ( $_ eq 'bottom-left-corner' ) {

						$cursor = $_;

						if($ev->state >= 'control-mask'){
							$new_x = $self->{_items}{$curr_item}->get('x') - $ev->y_root + $item->{res_y};
							$new_y = $self->{_items}{$curr_item}->get('y');
							
							$new_width  = $self->{_items}{$curr_item}->get('width') + ( $self->{_items}{$curr_item}->get('x') - $new_x );
							$new_height = $self->{_items}{$curr_item}->get('height') + ( $ev->y_root - $item->{res_y} ) / $ratio;
						}else{
							$new_x = $self->{_items}{$curr_item}->get('x') + $ev->x_root - $item->{res_x};
							$new_y = $self->{_items}{$curr_item}->get('y');

							$new_width  = $self->{_items}{$curr_item}->get('width') +  ( $self->{_items}{$curr_item}->get('x') - $new_x );
							$new_height = $self->{_items}{$curr_item}->get('height') + ( $ev->y_root - $item->{res_y} );					
						}

					} elsif ( $_ eq 'bottom-side' ) {

						$cursor = $_;

						$new_x = $self->{_items}{$curr_item}->get('x');
						$new_y = $self->{_items}{$curr_item}->get('y');

						$new_width = $self->{_items}{$curr_item}->get('width');
						$new_height = $self->{_items}{$curr_item}->get('height') + ( $ev->y_root - $item->{res_y} );

					} elsif ( $_ eq 'bottom-right-corner' ) {

						$cursor = $_;

						$new_x = $self->{_items}{$curr_item}->get('x');
						$new_y = $self->{_items}{$curr_item}->get('y');

						if($ev->state >= 'control-mask'){
							$new_width  = $self->{_items}{$curr_item}->get('width') +  ( $ev->y_root - $item->{res_y} ) * $ratio;
							$new_height = $self->{_items}{$curr_item}->get('height') + ( $ev->y_root - $item->{res_y} );						
						}else{
							$new_width  = $self->{_items}{$curr_item}->get('width') +  ( $ev->x_root - $item->{res_x} );
							$new_height = $self->{_items}{$curr_item}->get('height') + ( $ev->y_root - $item->{res_y} );					
						}

					}

					#set cursor
					$self->{_canvas}->window->set_cursor( Gtk2::Gdk::Cursor->new($cursor) );
					
					#when width or height are too small we switch to opposite rectangle and do the resizing in this way
					if($ev->state >= 'control-mask' && $new_width < 1 && $new_height < 1){
						$new_x = $self->{_items}{$curr_item}->get('x');
						$new_y = $self->{_items}{$curr_item}->get('y');
						$new_width = $self->{_items}{$curr_item}->get('width');
						$new_height = $self->{_items}{$curr_item}->get('height');
					}elsif ( $new_width < 0 || $new_height < 0) {
						$self->{_canvas}->pointer_ungrab($item, $ev->time);
						my $oppo = $self->get_opposite_rect($item, $curr_item, $new_width, $new_height);				
						$self->{_items}{$curr_item}{$oppo}->{res_x}    = $ev->x_root;
						$self->{_items}{$curr_item}{$oppo}->{res_y}    = $ev->y_root;
						$self->{_items}{$curr_item}{$oppo}->{resizing} = TRUE;
						$self->{_canvas}->pointer_grab( $self->{_items}{$curr_item}{$oppo}, [ 'pointer-motion-mask', 'button-release-mask' ], Gtk2::Gdk::Cursor->new($oppo), $ev->time );
						$self->handle_embedded( 'mirror', $curr_item, $new_width, $new_height);
						$new_width  = 0 if $new_width < 0;
						$new_height = 0 if $new_height < 0;
					}

					$self->{_items}{$curr_item}->set(
						'x'      => $new_x,
						'y'      => $new_y,
						'width'  => $new_width,
						'height' => $new_height,
					);

					$self->handle_rects( 'update', $curr_item );
					$self->handle_embedded( 'update', $curr_item );
						
				}
			}
		}

		$item->{res_x} = $ev->x_root;
		$item->{res_y} = $ev->y_root;
		
	}else {

		if (   $item->isa('Goo::Canvas::Rect') ) {

				#embedded item?
			my $parent = $self->get_parent_item($item);
			$item = $parent if $parent;

				#shape
			if ( exists $self->{_items}{$item} ) {
				$self->push_to_statusbar( int( $ev->x_root ), int( $ev->y_root ) );
			
				#canvas resizing shape
			} elsif (  $self->{_canvas_bg_rect}{'right-side'} == $item
					|| $self->{_canvas_bg_rect}{'bottom-side'} == $item
					|| $self->{_canvas_bg_rect}{'bottom-right-corner'} == $item ) 
			{
				$self->push_to_statusbar( int( $ev->x_root ), int( $ev->y_root ), 'canvas_resize' );		
			
				#resizing shape
			}else{
				$self->push_to_statusbar( int( $ev->x_root ), int( $ev->y_root ), 'resize' );					
			}
		}else{
			$self->push_to_statusbar( int( $ev->x_root ), int( $ev->y_root ) );	
		}

	}

	return TRUE;
}

sub get_opposite_rect {
	my $self = shift;
	my $rect = shift;
	my $item = shift;
	my $width = shift;
	my $height = shift;

	foreach ( keys %{ $self->{_items}{$item} } ) {

		#fancy resizing using our little resize boxes
		if ( $rect == $self->{_items}{$item}{$_} ) {

			if ( $_ eq 'top-left-corner' ) {
			
				return 'top-right-corner' if $width < 0;	
				return 'bottom-left-corner' if $height < 0;
				
			} elsif ( $_ eq 'top-side' ) {

				return 'bottom-side';
	
			} elsif ( $_ eq 'top-right-corner' ) {

				return 'top-left-corner' if $width < 0;	
				return 'bottom-right-corner' if $height < 0;

			} elsif ( $_ eq 'left-side' ) {

				return 'right-side';

			} elsif ( $_ eq 'right-side' ) {

				return 'left-side';

			} elsif ( $_ eq 'bottom-left-corner' ) {

				return 'bottom-right-corner' if $width < 0;	
				return 'top-left-corner' if $height < 0;

			} elsif ( $_ eq 'bottom-side' ) {

				return 'top-side';

			} elsif ( $_ eq 'bottom-right-corner' ) {
				
				return 'bottom-left-corner' if $width < 0;	
				return 'top-right-corner' if $height < 0;

			}
		}
	}		
	
	return FALSE;	
}

sub get_parent_item {
	my $self = shift;
	my $item = shift;

	my $parent = undef;
	foreach ( keys %{ $self->{_items} } ) {
		$parent = $self->{_items}{$_} if $self->{_items}{$_}{ellipse} == $item;
		$parent = $self->{_items}{$_} if $self->{_items}{$_}{text} == $item;
		$parent = $self->{_items}{$_} if $self->{_items}{$_}{image} == $item;
		$parent = $self->{_items}{$_} if $self->{_items}{$_}{line} == $item;
	}

	return $parent;
}

sub get_child_item {
	my $self = shift;
	my $item = shift;

	my $child = undef;

	$child = $self->{_items}{$item}{ellipse} if exists $self->{_items}{$item}{ellipse};
	$child = $self->{_items}{$item}{text}    if exists $self->{_items}{$item}{text};
	$child = $self->{_items}{$item}{image}   if exists $self->{_items}{$item}{image};
	$child = $self->{_items}{$item}{line}   if exists $self->{_items}{$item}{line};

	return $child;
}

sub abort_current_mode {
	my $self = shift;

	$self->set_drawing_action(int($self->{_current_mode}/10));
	$self->change_drawing_tool_cb($self->{_current_mode});

	return TRUE;
}	

sub clear_item_from_canvas {
	my $self = shift;
	my $item = shift;

	if ($item) {
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
			eval{
				$self->store_to_xdo_stack($_, 'delete', 'undo');
				$_->set('visibility' => 'GOO_CANVAS_ITEM_HIDDEN');
				$self->handle_rects('hide', $_);
				$self->handle_embedded('hide', $_);
			};
		}
	}
	
	$self->{_last_item}        = undef;
	$self->{_current_item}     = undef;
	$self->{_current_new_item} = undef;	

	return TRUE;
}

sub store_to_xdo_stack {
	#~ my $self = shift;
	#~ my $item = shift;
	#~ my $action = shift;
	#~ my $xdo = shift;
#~ 
	#~ return FALSE unless $item; 
	#~ 
	#~ my %do_info = ();
	#~ #general properties for ellipse, rectangle, image, text
	#~ if($item->isa('Goo::Canvas::Rect')){
#~ 
		#~ my $stroke_pattern = $self->create_color( $self->{_items}{$item}{stroke_color}, $self->{_items}{$item}{stroke_color_alpha} ) if exists $self->{_items}{$item}{stroke_color};
		#~ my $fill_pattern   = $self->create_color( $self->{_items}{$item}{fill_color},   $self->{_items}{$item}{fill_color_alpha} ) if exists $self->{_items}{$item}{fill_color};
		#~ my $line_width = $self->{_items}{$item}->get('line-width');
#~ 
		#~ #rectangle props
		#~ %do_info = (
			#~ 'item' => $self->{_items}{$item},
			#~ 'action' => $action,
			#~ 'x' => $self->{_items}{$item}->get('x'),
			#~ 'y' => $self->{_items}{$item}->get('y'),
			#~ 'width' => $self->{_items}{$item}->get('width'),
			#~ 'height' => $self->{_items}{$item}->get('height'),
			#~ 'fill-pattern' => $fill_pattern,
			#~ 'stroke-pattern' => $stroke_pattern,
			#~ 'line-width' => $line_width,
		#~ );
#~ 
		#~ if ( exists $self->{_items}{$item}{ellipse} ) {
#~ 
		#~ }elsif ( exists $self->{_items}{$item}{text} ) {
#~ 
		#~ }elsif ( exists $self->{_items}{$item}{image} ) {
#~ 
		#~ }elsif ( exists $self->{_items}{$item}{line} ) {
		#~ 
		#~ }else{
		#~ 
		#~ }			
		#~ 
	#~ }
#~ 
	#~ #add polyline specific properties to hash
	#~ if($item->isa('Goo::Canvas::Polyline')){
		#~ %do_info = (
			#~ item => $self->{_items}{$item},
			#~ action => $action,
			#~ points => $self->{_items}{$item}->get('points'),
		#~ );
	#~ }
	#~ 
	#~ if($xdo eq 'undo'){
		#~ push @{ $self->{_undo} }, \%do_info; 		
	#~ }elsif($xdo eq 'redo'){
		#~ push @{ $self->{_redo} }, \%do_info; 
	#~ }
#~ 
	#~ #disable undo/redo actions at startup
	#~ $self->{_uimanager}->get_widget("/MenuBar/Edit/Undo")->set_sensitive(scalar @{ $self->{_undo} }) if defined $self->{_undo};
	#~ $self->{_uimanager}->get_widget("/MenuBar/Edit/Redo")->set_sensitive(scalar @{ $self->{_redo} }) if defined $self->{_redo};
	#~ 
	#~ return TRUE;	
}

sub undo {
	#~ my $self = shift;
#~ 
	#~ my $undo = pop @{ $self->{_undo} };
#~ 
	#~ my $item = $undo->{'item'};
	#~ my $action = $undo->{'action'};
#~ 
	#~ #store to redo stack
	#~ $self->store_to_xdo_stack($item, $action, 'redo'); 
#~ 
	#~ $self->deactivate_all;
	#~ 
	#~ #finally undo the last event
	#~ if($action eq 'modify'){
		#~ $self->{_items}{$item}->set(
			#~ 'x' => $undo->{'x'},
			#~ 'y' => $undo->{'y'},
			#~ 'width' => 	$undo->{'width'},
			#~ 'height' => $undo->{'height'},
			#~ 'fill-pattern' => $undo->{'fill-pattern'},
			#~ 'stroke-pattern' => $undo->{'stroke-pattern'},
			#~ 'line-width' => $undo->{'line-width'},	
		#~ );
		#~ $self->handle_rects( 'update', $self->{_items}{$item} );
		#~ $self->handle_embedded( 'update', $self->{_items}{$item} );		
		#~ $self->{_current_item} = $item;	
	#~ }elsif($action eq 'delete'){
		#~ $self->{_items}{$item}->set('visibility' => 'GOO_CANVAS_ITEM_VISIBLE');
		#~ $self->handle_rects( 'update', $self->{_items}{$item} );
		#~ $self->handle_embedded( 'update', $self->{_items}{$item} );
		#~ $self->{_current_item} = $item;		
	#~ }elsif($action eq 'create'){
		#~ $self->{_items}{$item}->set('visibility' => 'GOO_CANVAS_ITEM_HIDDEN');
		#~ $self->handle_rects( 'hide', $self->{_items}{$item} );
		#~ $self->handle_embedded( 'hide', $self->{_items}{$item} );		
	#~ }
	#~ 
	#~ #disable undo/redo actions at startup
	#~ $self->{_uimanager}->get_widget("/MenuBar/Edit/Undo")->set_sensitive(scalar @{ $self->{_undo} }) if defined $self->{_undo};
	#~ $self->{_uimanager}->get_widget("/MenuBar/Edit/Redo")->set_sensitive(scalar @{ $self->{_redo} }) if defined $self->{_redo};	
	#~ 
	#~ return TRUE;	
}

sub redo {
	#~ my $self = shift;
#~ 
	#~ my $redo = pop @{ $self->{_redo} };
#~ 
	#~ my $item = $redo->{'item'};
	#~ my $action = $redo->{'action'};
#~ 
	#~ #store to undo stack
	#~ $self->store_to_xdo_stack($item, $action, 'undo'); 
#~ 
	#~ $self->deactivate_all;
#~ 
	#~ #finally undo the last event
	#~ if($action eq 'modify'){
		#~ $self->{_items}{$item}->set(
			#~ 'x' => $redo->{'x'},
			#~ 'y' => $redo->{'y'},
			#~ 'width' => 	$redo->{'width'},
			#~ 'height' => $redo->{'height'},
			#~ 'fill-pattern' => $redo->{'fill-pattern'},
			#~ 'stroke-pattern' => $redo->{'stroke-pattern'},
			#~ 'line-width' => $redo->{'line-width'},			
		#~ );
		#~ $self->handle_rects( 'update', $self->{_items}{$item} );
		#~ $self->handle_embedded( 'update', $self->{_items}{$item} );		
		#~ $self->{_current_item} = $item;	
	#~ }elsif($action eq 'delete'){
		#~ $self->{_items}{$item}->set('visibility' => 'GOO_CANVAS_ITEM_HIDDEN');
		#~ $self->handle_rects( 'hide', $self->{_items}{$item} );
		#~ $self->handle_embedded( 'hide', $self->{_items}{$item} );
		#~ $self->{_current_item} = $item;		
	#~ }elsif($action eq 'create'){
		#~ $self->{_items}{$item}->set('visibility' => 'GOO_CANVAS_ITEM_VISIBLE');
		#~ $self->handle_rects( 'update', $self->{_items}{$item} );
		#~ $self->handle_embedded( 'update', $self->{_items}{$item} );		
	#~ }
#~ 
	#~ #disable undo/redo actions at startup
	#~ $self->{_uimanager}->get_widget("/MenuBar/Edit/Undo")->set_sensitive(scalar @{ $self->{_undo} }) if defined $self->{_undo};
	#~ $self->{_uimanager}->get_widget("/MenuBar/Edit/Redo")->set_sensitive(scalar @{ $self->{_redo} }) if defined $self->{_redo};	
	#~ 
	#~ return TRUE;	
}

sub set_and_save_drawing_properties {
	my $self 	= shift;
	my $item 	= shift;
	
	my $save_only = shift;

	#determine key for item hash
	if(my $child = $self->get_child_item($item)){
		$item = $child;
	}
	my $parent 	= $self->get_parent_item($item);
	my $key = $self->get_item_key($item, $parent);

	#we do not remember the properties for some tools
	if($self->{_items}{$key}{type} ne "highlighter" && 
	   $self->{_items}{$key}{type} ne "highlighter" && 
	   $self->{_items}{$key}{type} ne "image")
	{
				
		#remember drawing colors, line width and font settings
		#maybe we have to restore them
		$self->{_last_fill_color}         = $self->{_fill_color_w}->get_color;
		$self->{_last_fill_color_alpha}   = $self->{_fill_color_w}->get_alpha;
		$self->{_last_stroke_color}       = $self->{_stroke_color_w}->get_color;
		$self->{_last_stroke_color_alpha} = $self->{_stroke_color_w}->get_alpha;
		$self->{_last_line_width} 		  = $self->{_line_spin_w}->get_value;
		$self->{_last_font} 			  = $self->{_font_btn_w}->get_font_name;

		#remember the last mode as well
		$self->{_last_mode}            	  = $self->{_current_mode};
		$self->{_last_mode_descr}         = $self->{_current_mode_descr};

	}
	
	return TRUE if $save_only;
	
	#block 'value-change' handlers for widgets
	#so we do not apply the changes twice
	$self->{_line_spin_w}->signal_handler_block ($self->{_line_spin_wh});
	$self->{_stroke_color_w}->signal_handler_block ($self->{_stroke_color_wh});
	$self->{_fill_color_w}->signal_handler_block ($self->{_fill_color_wh});
	$self->{_font_btn_w}->signal_handler_block ($self->{_font_btn_wh});

	if (   $item->isa('Goo::Canvas::Rect')
		|| $item->isa('Goo::Canvas::Ellipse')
		|| $item->isa('Goo::Canvas::Polyline') )
	{
				
		#line width
		$self->{_line_spin_w}->set_value( $item->get('line-width') );
			
		#stroke color
		#some items, e.g. censor tool, do not have a color - skip them
		if($self->{_items}{$key}{stroke_color}){
			$self->{_stroke_color_w}->set_color( $self->{_items}{$key}{stroke_color} );
			$self->{_stroke_color_w}->set_alpha( int( $self->{_items}{$key}{stroke_color_alpha} * 65535 ) );
		}
	
		if ( $item->isa('Goo::Canvas::Rect') || $item->isa('Goo::Canvas::Ellipse') ) {
	
			#fill color
			$self->{_fill_color_w}->set_color( $self->{_items}{$key}{fill_color} );
			$self->{_fill_color_w}->set_alpha( int( $self->{_items}{$key}{fill_color_alpha} * 65535 ) );
	
		}

	}elsif ( $item->isa('Goo::Canvas::Text') ) {

		#determine font description from string
		my ( $attr_list, $text_raw, $accel_char ) = Gtk2::Pango->parse_markup( $item->get('text') );
		my $font_desc = Gtk2::Pango::FontDescription->from_string( $self->{_font} );

		#FIXME, maybe the pango version installed is too old
		eval {
			$attr_list->filter(
				sub {
					my $attr = shift;
					$font_desc = $attr->copy->desc
						if $attr->isa('Gtk2::Pango::AttrFontDesc');
					return TRUE;
				},
			);
		};
		if ($@) {
			print "\nERROR: Pango Markup could not be parsed:\n$@";
		}

		#font color
		$self->{_stroke_color_w}->set_color( $self->{_items}{$key}{stroke_color} );
		$self->{_stroke_color_w}->set_alpha( int( $self->{_items}{$key}{stroke_color_alpha} * 65535 ) );

		#apply current font settings to button
		$self->{_font_btn_w}->set_font_name( $font_desc->to_string );
		
	}

	#update global values
	$self->{_line_width} 			= $self->{_line_spin_w}->get_value;	
	$self->{_stroke_color}       	= $self->{_stroke_color_w}->get_color;
	$self->{_stroke_color_alpha} 	= $self->{_stroke_color_w}->get_alpha / 65535;		
	$self->{_fill_color}       		= $self->{_fill_color_w}->get_color;
	$self->{_fill_color_alpha} 		= $self->{_fill_color_w}->get_alpha / 65636;
	my $font_descr = Gtk2::Pango::FontDescription->from_string( $self->{_font_btn_w}->get_font_name );
	$self->{_font} 					= $font_descr->to_string;

	#unblock 'value-change' handlers for widgets
	$self->{_line_spin_w}->signal_handler_unblock ($self->{_line_spin_wh});
	$self->{_stroke_color_w}->signal_handler_unblock ($self->{_stroke_color_wh});
	$self->{_fill_color_w}->signal_handler_unblock ($self->{_fill_color_wh});
	$self->{_font_btn_w}->signal_handler_unblock ($self->{_font_btn_wh});

}

sub restore_drawing_properties {
	my $self = shift;

	#saved properties available?
	return FALSE unless defined $self->{_last_fill_color};

	#block 'value-change' handlers for widgets
	#so we do not apply the changes twice
	$self->{_line_spin_w}->signal_handler_block ($self->{_line_spin_wh});
	$self->{_stroke_color_w}->signal_handler_block ($self->{_stroke_color_wh});
	$self->{_fill_color_w}->signal_handler_block ($self->{_fill_color_wh});
	$self->{_font_btn_w}->signal_handler_block ($self->{_font_btn_wh});

	#restore them
	$self->{_fill_color_w}->set_color($self->{_last_fill_color});
	$self->{_fill_color_w}->set_alpha($self->{_last_fill_color_alpha});
	$self->{_stroke_color_w}->set_color($self->{_last_stroke_color});
	$self->{_stroke_color_w}->set_alpha($self->{_last_stroke_color_alpha});
	$self->{_line_spin_w}->set_value($self->{_last_line_width});
	$self->{_font_btn_w}->set_font_name($self->{_last_font});	
	
	#update global values
	$self->{_line_width} 			= $self->{_line_spin_w}->get_value;	
	$self->{_stroke_color}       	= $self->{_stroke_color_w}->get_color;
	$self->{_stroke_color_alpha} 	= $self->{_stroke_color_w}->get_alpha / 65535;		
	$self->{_fill_color}       		= $self->{_fill_color_w}->get_color;
	$self->{_fill_color_alpha} 		= $self->{_fill_color_w}->get_alpha / 65636;
	my $font_descr = Gtk2::Pango::FontDescription->from_string( $self->{_font_btn_w}->get_font_name );
	$self->{_font} 					= $font_descr->to_string;
		
	#unblock 'value-change' handlers for widgets
	$self->{_line_spin_w}->signal_handler_unblock ($self->{_line_spin_wh});
	$self->{_stroke_color_w}->signal_handler_unblock ($self->{_stroke_color_wh});
	$self->{_fill_color_w}->signal_handler_unblock ($self->{_fill_color_wh});
	$self->{_font_btn_w}->signal_handler_unblock ($self->{_font_btn_wh});
	
}

sub event_item_on_button_press {
	my ( $self, $item, $target, $ev ) = @_;

	my $d      = $self->{_shutter_common}->get_gettext;
	my $cursor = Gtk2::Gdk::Cursor->new('left-ptr');

	#~ my $valid = FALSE;
	#~ $valid = TRUE if $self->{_canvas}->get_item_at( $ev->x, $ev->y, TRUE );

	#activate item
	if ($self->{_current_mode_descr} eq "select") {

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if ( exists $self->{_items}{$item} ) {

			$self->{_last_item}        = $self->{_current_item};
			$self->{_current_item}     = $item;
			$self->{_current_new_item} = undef;
			$self->handle_rects( 'hide',   $self->{_last_item} );
			$self->handle_rects( 'update', $self->{_current_item} );
			
			#apply item properties to widgets
			#line width, fill color, stroke color etc.
			$self->set_and_save_drawing_properties($self->{_current_item}, FALSE);

		}
	} else {
		
		$self->deactivate_all;
	
	}

	if ( $ev->type eq 'button-press' && $ev->button == 1 ) {

		my $root   = $self->{_canvas}->get_root_item;

		#CLEAR
		if ( $self->{_current_mode_descr} eq "clear" ) {

			return TRUE if $item == $self->{_canvas_bg};

			#embedded item?
			my $parent = $self->get_parent_item($item);
			$item = $parent if $parent;

			#only real shapes can be deleted
			#don't delete resize boxes or boundaries
			if ( exists $self->{_items}{$item} ) {

				$self->clear_item_from_canvas($item);
					
			}

			$self->{_canvas}->window->set_cursor($cursor);

		#MOVE AND SELECT
		} elsif ( $self->{_current_mode_descr} eq "select" ) {

			#			return TRUE if $item == $self->{_canvas_bg};

			if ( $item->isa('Goo::Canvas::Rect') ) {

				#real shape
				if ( exists $self->{_items}{$item} ) {
					$item->{drag_x}   = $ev->x_root;
					$item->{drag_y}   = $ev->y_root;
					$item->{dragging} = TRUE;

					$cursor = Gtk2::Gdk::Cursor->new('fleur');
					
					#add to undo stack
					$self->store_to_xdo_stack($self->{_current_item} , 'modify', 'undo');

					#resizing shape
				} else {

					$item->{res_x}    = $ev->x_root;
					$item->{res_y}    = $ev->y_root;
					$item->{resizing} = TRUE;

					$cursor = undef;

					#add to undo stack
					$self->store_to_xdo_stack($self->{_current_item} , 'modify', 'undo');

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

				#add to undo stack
				$self->store_to_xdo_stack($self->{_current_item} , 'modify', 'undo');

				$cursor = undef;

			}

			$self->{_canvas}->pointer_grab( $item, [ 'pointer-motion-mask', 'button-release-mask' ], $cursor, $ev->time );

		} else {

				#freehand
			if ( $self->{_current_mode_descr} eq "freehand" ) {

				$self->create_polyline( $ev, undef, FALSE );

				#highlighter
			} elsif ( $self->{_current_mode_descr} eq "highlighter" ) {

				$self->create_polyline( $ev, undef, TRUE );

				#Line
			} elsif ( $self->{_current_mode_descr} eq "line" ) {

				$self->create_line( $ev, undef );

				#Arrow
			} elsif ( $self->{_current_mode_descr} eq "arrow" ) {

				$self->create_line( $ev, undef, TRUE, FALSE );
				
				#Censor
			} elsif ( $self->{_current_mode_descr} eq "censor" ) {

				$self->create_censor( $ev, undef );

				#RECTANGLES
			} elsif ( $self->{_current_mode_descr} eq "rect" ) {

				$self->create_rectangle( $ev, undef );

				#ELLIPSE
			} elsif ( $self->{_current_mode_descr} eq "ellipse" ) {

				$self->create_ellipse( $ev, undef );

				#TEXT
			} elsif ( $self->{_current_mode_descr} eq "text" ) {

				$self->create_text( $ev, undef );

				#IMAGE
			} elsif ( $self->{_current_mode_descr} eq "image" ) {

				$self->create_image( $ev, undef );

			}
		}
	} elsif ( $ev->button == 2 && $self->{_current_mode_descr} eq "select") {

		#right click => show context menu, double-click => show properties directly 
	} elsif ( ($ev->type eq '2button-press' || $ev->button == 3) && $self->{_current_mode_descr} eq "select") {
		
		#no menu for background and image
		return TRUE if ($item == $self->{_canvas_bg} || $item == $self->{_canvas_bg_rect});
	
		$self->{_canvas}->pointer_ungrab( $item, $ev->time );

		#determine key for item hash
		if(my $child = $self->get_child_item($item)){
			$item = $child;
		}
		my $parent 	= $self->get_parent_item($item);
		my $key = $self->get_item_key($item, $parent);

		if ( exists $self->{_items}{$key} ) {		
			if( $ev->type eq '2button-press' ) {
				
				$self->show_item_properties($item, $parent);
				
			}elsif( $ev->type eq 'button-press' ){
				
				my $item_menu = $self->ret_item_menu($item, $parent);

				$item_menu->popup(
					undef,    # parent menu shell
					undef,    # parent menu item
					undef,    # menu pos func
					undef,    # data
					$ev->button,
					$ev->time
				);								
			}				
		}

	#zooming using the mouse wheel
	#~ } elsif ( $ev->button == 4  ) {
		#~ $self->zoom_in_cb;		
	#~ } elsif ( $ev->button == 5  ) {
		#~ $self->zoom_out_cb;
	}		

	return TRUE;
}

sub ret_item_menu {
	my $self   = shift;
	my $item   = shift;
	my $parent = shift;

	my $d      = $self->{_shutter_common}->get_gettext;
	my $dicons = $self->{_shutter_common}->get_root . "/share/shutter/resources/icons/drawing_tool";

	my $menu_item = Gtk2::Menu->new;

	#raise
	my $raise_item = Gtk2::ImageMenuItem->new( $d->get("Raise") );
	$raise_item->set_image(
		Gtk2::Image->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file_at_size( "$dicons/draw-raise.png", Gtk2::IconSize->lookup('menu') ) ) );
	$raise_item->signal_connect(
		'activate' => sub {
			$item->raise;
			if ($parent) {
				$parent->raise;
				$self->handle_rects( 'raise', $parent );
			} else {
				$self->handle_rects( 'raise', $item );
			}
		}
	);

	$menu_item->append($raise_item);

	#lower
	my $lower_item = Gtk2::ImageMenuItem->new( $d->get("Lower") );
	$lower_item->set_image(
		Gtk2::Image->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file_at_size( "$dicons/draw-lower.png", Gtk2::IconSize->lookup('menu') ) ) );

	$lower_item->signal_connect(
		'activate' => sub {
			$item->lower;
			if ($parent) {
				$parent->lower;
				$self->handle_rects( 'lower', $parent );
			} else {
				$self->handle_rects( 'lower', $item );
			}
			$self->{_canvas_bg}->lower;
			$self->{_canvas_bg_rect}->lower;
		}
	);

	$menu_item->append($lower_item);

	$menu_item->append( Gtk2::SeparatorMenuItem->new );

	#delete item
	my $remove_item = Gtk2::ImageMenuItem->new_from_stock('gtk-delete');

	$remove_item->signal_connect(
		'activate' => sub {
			$self->clear_item_from_canvas($item, $parent);
		}
	);

	$menu_item->append($remove_item);

	$menu_item->append( Gtk2::SeparatorMenuItem->new );

	#properties
	my $prop_item = Gtk2::ImageMenuItem->new_from_stock('gtk-properties');
	
	#some items do not have properties, e.g. images or censor
	$prop_item->set_sensitive(FALSE) if $item->isa('Goo::Canvas::Image') || !exists($self->{_items}{$item}{stroke_color});
	
	$prop_item->signal_connect(
		'activate' => sub {

			$self->show_item_properties($item, $parent);

		}
	);

	$menu_item->append($prop_item);

	$menu_item->show_all;

	return $menu_item;
}

sub get_item_key {
	my $self 	= shift;
	my $item 	= shift;
	my $parent 	= shift;
	if ( exists $self->{_items}{$item} ) {
		return $item;
	} else {
		return $parent;
	}
}

sub show_item_properties {
	my $self 	= shift;
	my $item 	= shift;
	my $parent 	= shift;

	#determine key for item hash
	my $key = $self->get_item_key($item, $parent);

	my $d = $self->{_shutter_common}->get_gettext;

	#create dialog
	my $prop_dialog = Gtk2::Dialog->new(
		$d->get("Preferences"),
		$self->{_drawing_window},
		[qw/modal destroy-with-parent/],
		'gtk-cancel' => 'cancel',
		'gtk-apply'  => 'apply'
	);

	$prop_dialog->set_default_response('apply');

	#RECT OR ELLIPSE OR POLYLINE
	my $line_spin 		= undef;
	my $fill_color 		= undef;
	my $stroke_color 	= undef;
	if (   $item->isa('Goo::Canvas::Rect')
		|| $item->isa('Goo::Canvas::Ellipse')
		|| $item->isa('Goo::Canvas::Polyline') )
	{

		my $general_vbox = Gtk2::VBox->new( FALSE, 5 );

		my $label_general = Gtk2::Label->new;
		$label_general->set_markup( $d->get("<i>Main</i>") );
		my $frame_general = Gtk2::Frame->new();
		$frame_general->set_label_widget($label_general);
		$frame_general->set_border_width(5);
		$prop_dialog->vbox->add($frame_general);

		#line_width
		my $line_hbox = Gtk2::HBox->new( TRUE, 5 );
		$line_hbox->set_border_width(5);
		my $linew_label = Gtk2::Label->new( $d->get("Line width") );
		$line_spin = Gtk2::SpinButton->new_with_range( 0.5, 20, 0.1 );

		$line_spin->set_value( $item->get('line-width') );

		$line_hbox->pack_start_defaults($linew_label);
		$line_hbox->pack_start_defaults($line_spin);
		$general_vbox->pack_start( $line_hbox, FALSE, FALSE, 0 );

		if ( $item->isa('Goo::Canvas::Rect') || $item->isa('Goo::Canvas::Ellipse') ) {

			#fill color
			my $fill_color_hbox = Gtk2::HBox->new( TRUE, 5 );
			$fill_color_hbox->set_border_width(5);
			my $fill_color_label = Gtk2::Label->new( $d->get("Fill color") );
			$fill_color = Gtk2::ColorButton->new();

			$fill_color->set_color( $self->{_items}{$key}{fill_color} );
			$fill_color->set_alpha( int( $self->{_items}{$key}{fill_color_alpha} * 65535 ) );
			$fill_color->set_use_alpha(TRUE);
			$fill_color->set_title( $d->get("Choose fill color") );

			$fill_color_hbox->pack_start_defaults($fill_color_label);
			$fill_color_hbox->pack_start_defaults($fill_color);
			$general_vbox->pack_start( $fill_color_hbox, FALSE, FALSE, 0 );
			
		}

		#some items, e.g. censor tool, do not have a color - skip them
		if($self->{_items}{$key}{stroke_color}){
			#stroke color
			my $stroke_color_hbox = Gtk2::HBox->new( TRUE, 5 );
			$stroke_color_hbox->set_border_width(5);
			my $stroke_color_label = Gtk2::Label->new( $d->get("Stroke color") );
			$stroke_color = Gtk2::ColorButton->new();

			$stroke_color->set_color( $self->{_items}{$key}{stroke_color} );
			$stroke_color->set_alpha( int( $self->{_items}{$key}{stroke_color_alpha} * 65535 ) );
			$stroke_color->set_use_alpha(TRUE);
			$stroke_color->set_title( $d->get("Choose stroke color") );

			$stroke_color_hbox->pack_start_defaults($stroke_color_label);
			$stroke_color_hbox->pack_start_defaults($stroke_color);
			$general_vbox->pack_start( $stroke_color_hbox, FALSE, FALSE, 0 );
		}

		$frame_general->add($general_vbox);

	}

	#ARROW
	my $end_arrow 		= undef;
	my $start_arrow 	= undef;	
	my $arrow_spin 		= undef;
	my $arrowl_spin 	= undef;
	my $arrowt_spin 	= undef;
	if ($item->isa('Goo::Canvas::Polyline') 
		&& defined $self->{_items}{$key}{end_arrow} 
		&& defined $self->{_items}{$key}{start_arrow})
	{
		my $arrow_vbox = Gtk2::VBox->new( FALSE, 5 );

		my $label_arrow = Gtk2::Label->new;
		$label_arrow->set_markup( $d->get("<i>Arrow</i>") );
		my $frame_arrow = Gtk2::Frame->new();
		$frame_arrow->set_label_widget($label_arrow);
		$frame_arrow->set_border_width(5);
		$prop_dialog->vbox->add($frame_arrow);

		#arrow_width
		my $arrow_hbox = Gtk2::HBox->new( TRUE, 5 );
		$arrow_hbox->set_border_width(5);
		my $arroww_label = Gtk2::Label->new( $d->get("Width") );
		$arrow_spin = Gtk2::SpinButton->new_with_range( 0.5, 10, 0.1 );

		$arrow_spin->set_value( $item->get('arrow-width') );

		$arrow_hbox->pack_start_defaults($arroww_label);
		$arrow_hbox->pack_start_defaults($arrow_spin);
		$arrow_vbox->pack_start( $arrow_hbox, FALSE, FALSE, 0 );

		#arrow_length
		my $arrowl_hbox = Gtk2::HBox->new( TRUE, 5 );
		$arrowl_hbox->set_border_width(5);
		my $arrowl_label = Gtk2::Label->new( $d->get("Length") );
		$arrowl_spin = Gtk2::SpinButton->new_with_range( 0.5, 10, 0.1 );

		$arrowl_spin->set_value( $item->get('arrow-length') );

		$arrowl_hbox->pack_start_defaults($arrowl_label);
		$arrowl_hbox->pack_start_defaults($arrowl_spin);
		$arrow_vbox->pack_start( $arrowl_hbox, FALSE, FALSE, 0 );

		#arrow_tip_length
		my $arrowt_hbox = Gtk2::HBox->new( TRUE, 5 );
		$arrowt_hbox->set_border_width(5);
		my $arrowt_label = Gtk2::Label->new( $d->get("Tip length") );
		$arrowt_spin = Gtk2::SpinButton->new_with_range( 0.5, 10, 0.1 );

		$arrowt_spin->set_value( $item->get('arrow-tip-length') );

		$arrowt_hbox->pack_start_defaults($arrowt_label);
		$arrowt_hbox->pack_start_defaults($arrowt_spin);
		$arrow_vbox->pack_start( $arrowt_hbox, FALSE, FALSE, 0 );
	
		#checkboxes for start and end arrows
		$end_arrow   = Gtk2::CheckButton->new ($d->get("Display an arrow at the end of the line"));
		$end_arrow->set_active($self->{_items}{$key}{end_arrow});
		$start_arrow = Gtk2::CheckButton->new ($d->get("Display an arrow at the start of the line"));
		$start_arrow->set_active($self->{_items}{$key}{start_arrow});

		my $end_arrow_hbox = Gtk2::HBox->new( TRUE, 5 );
		$end_arrow_hbox->set_border_width(5);
		
		my $start_arrow_hbox = Gtk2::HBox->new( TRUE, 5 );
		$start_arrow_hbox->set_border_width(5);
		
		$end_arrow_hbox->pack_start_defaults($end_arrow);
		$start_arrow_hbox->pack_start_defaults($start_arrow);

		$arrow_vbox->pack_start( $start_arrow_hbox, FALSE, FALSE, 0 );
		$arrow_vbox->pack_start( $end_arrow_hbox, FALSE, FALSE, 0 );
		
		#final packing
		$frame_arrow->add($arrow_vbox);
			
	}

	#TEXT
	my $font_btn;
	my $text;
	my $textview;
	my $font_color;
	if ( $item->isa('Goo::Canvas::Text') ) {

		my $text_vbox = Gtk2::VBox->new( FALSE, 5 );

		my $label_text = Gtk2::Label->new;
		$label_text->set_markup( $d->get("<i>Text</i>") );
		my $frame_text = Gtk2::Frame->new();
		$frame_text->set_label_widget($label_text);
		$frame_text->set_border_width(5);
		$prop_dialog->vbox->add($frame_text);

		#font button
		my $font_hbox = Gtk2::HBox->new( TRUE, 5 );
		$font_hbox->set_border_width(5);
		my $font_label = Gtk2::Label->new( $d->get("Font") );
		$font_btn = Gtk2::FontButton->new();

		#determine font description from string
		my ( $attr_list, $text_raw, $accel_char ) = Gtk2::Pango->parse_markup( $item->get('text') );
		my $font_desc = Gtk2::Pango::FontDescription->from_string( $self->{_font} );

		#FIXME, maybe the pango version installed is too old
		eval {
			$attr_list->filter(
				sub {
					my $attr = shift;
					$font_desc = $attr->copy->desc
						if $attr->isa('Gtk2::Pango::AttrFontDesc');
					return TRUE;
				},
			);
		};
		if ($@) {
			print "\nERROR: Pango Markup could not be parsed:\n$@";
		}

		$font_hbox->pack_start_defaults($font_label);
		$font_hbox->pack_start_defaults($font_btn);
		$text_vbox->pack_start( $font_hbox, FALSE, FALSE, 0 );

		#font color
		my $font_color_hbox = Gtk2::HBox->new( TRUE, 5 );
		$font_color_hbox->set_border_width(5);
		my $font_color_label = Gtk2::Label->new( $d->get("Font color") );
		$font_color = Gtk2::ColorButton->new();
		$font_color->set_use_alpha(TRUE);

		$font_color->set_alpha( int( $self->{_items}{$key}{stroke_color_alpha} * 65535 ) );
		$font_color->set_color( $self->{_items}{$key}{stroke_color} );
		$font_color->set_title( $d->get("Choose font color") );

		$font_color_hbox->pack_start_defaults($font_color_label);
		$font_color_hbox->pack_start_defaults($font_color);

		$text_vbox->pack_start( $font_color_hbox, FALSE, FALSE, 0 );

		#initial buffer
		my $text = Gtk2::TextBuffer->new;
		$text->set_text($text_raw);

		#textview
		my $textview_hbox = Gtk2::HBox->new( FALSE, 5 );
		$textview_hbox->set_border_width(5);
		$textview = Gtk2::TextView->new_with_buffer($text);
		$textview->set_size_request( 150, 200 );
		$textview_hbox->pack_start_defaults($textview);

		$text_vbox->pack_start_defaults($textview_hbox);

		#apply changes directly
		$font_btn->signal_connect(
			'font-set' => sub {

				$self->modify_text_in_properties( $font_btn, $textview, $font_color, $item );

			}
		);

		$font_color->signal_connect(
			'color-set' => sub {

				$self->modify_text_in_properties( $font_btn, $textview, $font_color, $item );

			}
		);

		#apply current font settings to button
		$font_btn->set_font_name( $font_desc->to_string );

		#FIXME >> why do we have to invoke this manually??
		$font_btn->signal_emit('font-set');

		$frame_text->add($text_vbox);
	}

	#run dialog
	$prop_dialog->show_all;
	my $prop_dialog_res = $prop_dialog->run;
	if ( $prop_dialog_res eq 'apply' ) {

		$self->apply_properties($item, $parent, $key, 
								$fill_color, $stroke_color, $line_spin, 
								$font_color, $font_btn, $textview, 
								$end_arrow , $start_arrow, $arrow_spin, $arrowl_spin, $arrowt_spin);

		#apply item properties to widgets
		#line width, fill color, stroke color etc.
		$self->set_and_save_drawing_properties($self->{_current_item}, FALSE);
		
		$prop_dialog->destroy;
		return TRUE;
	} else {

		$prop_dialog->destroy;
		return FALSE;
	}
	
}

sub apply_properties {
	my $self 		= shift;
	
	#item related infos
	my $item 		= shift;
	my $parent 		= shift;
	my $key 		= shift;
	
	#general properties
	my $fill_color 	= shift;
	my $stroke_color= shift;
	my $line_spin 	= shift;
	
	#only text
	my $font_color 	= shift;
	my $font_btn 	= shift;
	my $textview 	= shift;
	
	#only arrow
	my $end_arrow   = shift;
	my $start_arrow = shift;	
	my $arrow_spin 	= shift;
	my $arrowl_spin = shift;
	my $arrowt_spin = shift;

	#remember drawing colors, line width and font settings
	#maybe we have to restore them
	if($self->{_items}{$key}{type} ne "highlighter" && 
	   $self->{_items}{$key}{type} ne "censor")
	{
				
		$self->{_last_fill_color}         = $self->{_fill_color_w}->get_color;
		$self->{_last_fill_color_alpha}   = $self->{_fill_color_w}->get_alpha;
		$self->{_last_stroke_color}       = $self->{_stroke_color_w}->get_color;
		$self->{_last_stroke_color_alpha} = $self->{_stroke_color_w}->get_alpha;
		$self->{_last_line_width} 		  = $self->{_line_spin_w}->get_value;
		$self->{_last_font} 			  = $self->{_font_btn_w}->get_font_name;

		#remember the last mode as well
		$self->{_last_mode}            	  = $self->{_current_mode};
		$self->{_last_mode_descr}         = $self->{_current_mode_descr};

	}
	
	#add to undo stack
	$self->store_to_xdo_stack($self->{_current_item} , 'modify', 'undo');

	#apply rect or ellipse options
	if ( $item->isa('Goo::Canvas::Rect') || $item->isa('Goo::Canvas::Ellipse') ) {

		my $fill_pattern   = $self->create_color( $fill_color->get_color,   $fill_color->get_alpha / 65535 );
		my $stroke_pattern = $self->create_color( $stroke_color->get_color, $stroke_color->get_alpha / 65535 );
		$item->set(
			'line-width'     => $line_spin->get_value,
			'fill-pattern'   => $fill_pattern,
			'stroke-pattern' => $stroke_pattern
		);

		#save color and opacity as well
		$self->{_items}{$key}{fill_color}         = $fill_color->get_color;
		$self->{_items}{$key}{fill_color_alpha}   = $fill_color->get_alpha / 65535;
		$self->{_items}{$key}{stroke_color}       = $stroke_color->get_color;
		$self->{_items}{$key}{stroke_color_alpha} = $stroke_color->get_alpha / 65535;
	}

	#apply polyline options (arrow) 
	if ($item->isa('Goo::Canvas::Polyline') 
		&& defined $self->{_items}{$key}{end_arrow} 
		&& defined $self->{_items}{$key}{start_arrow})
	{

		my $stroke_pattern = $self->create_color( $stroke_color->get_color, $stroke_color->get_alpha / 65535 );

		#these values are only available in the item menu
		if(	   defined $arrowl_spin 
			&& defined $arrow_spin 
			&& defined $arrowt_spin 
			&& defined $end_arrow 
			&& defined $start_arrow)
		{
			$item->set(
				'line-width'     	=> $line_spin->get_value,
				'stroke-pattern' 	=> $stroke_pattern,
				'end-arrow' 	 	=> $end_arrow->get_active,
				'start-arrow' 	 	=> $start_arrow->get_active,
				'arrow-length'	 	=> $arrowl_spin->get_value,
				'arrow-width'	 	=> $arrow_spin->get_value,
				'arrow-tip-length'	=> $arrowt_spin->get_value,		
			);
						
		}else{
			$item->set(
				'line-width'     	=> $line_spin->get_value,
				'stroke-pattern' 	=> $stroke_pattern,	
				'end-arrow' 	 	=> $self->{_items}{$key}{line}->get('end-arrow'),
				'start-arrow' 	 	=> $self->{_items}{$key}{line}->get('start-arrow'),
			);			
		}

		#save color and opacity as well
		$self->{_items}{$key}{stroke_color}       = $stroke_color->get_color;
		$self->{_items}{$key}{stroke_color_alpha} = $stroke_color->get_alpha / 65535;		

		#save arrow specific properties
		$self->{_items}{$key}{end_arrow} 		= $self->{_items}{$key}{line}->get('end-arrow');
		$self->{_items}{$key}{start_arrow} 		= $self->{_items}{$key}{line}->get('start-arrow');
		$self->{_items}{$key}{arrow_width} 		= $self->{_items}{$key}{line}->get('arrow-width');
		$self->{_items}{$key}{arrow_length} 	= $self->{_items}{$key}{line}->get('arrow-length');
		$self->{_items}{$key}{arrow_tip_length} = $self->{_items}{$key}{line}->get('arrow-tip-length');

	#apply polyline options (freehand, highlighter) 
	}elsif ( $item->isa('Goo::Canvas::Polyline') 
		&& defined $self->{_items}{$key}{stroke_color}) 
	{
		my $stroke_pattern = $self->create_color( $stroke_color->get_color, $stroke_color->get_alpha / 65535 );
		$item->set(
			'line-width'     => $line_spin->get_value,
			'stroke-pattern' => $stroke_pattern,
		);

		#save color and opacity as well
		$self->{_items}{$key}{stroke_color}       = $stroke_color->get_color;
		$self->{_items}{$key}{stroke_color_alpha} = $stroke_color->get_alpha / 65535;
	}

	#apply text options
	if ( $item->isa('Goo::Canvas::Text') ) {
		my $font_descr = Gtk2::Pango::FontDescription->from_string( $font_btn->get_font_name );

		my $fill_pattern = $self->create_color( $font_color->get_color, $font_color->get_alpha / 65535 );
		
		my $new_text = undef;
		if($textview){
			$new_text
				= $textview->get_buffer->get_text( $textview->get_buffer->get_start_iter, $textview->get_buffer->get_end_iter, FALSE )
				|| "New Text...";
		}else{
			#determine font description and text from string
			my ( $attr_list, $text_raw, $accel_char ) = Gtk2::Pango->parse_markup( $item->get('text') );
			$new_text = $text_raw;	
		}

		$item->set(
			'text'         => "<span font_desc=' " . $font_descr->to_string . " ' >" . $new_text . "</span>",
			'use-markup'   => TRUE,
			'fill-pattern' => $fill_pattern
		);

		#adjust rectangle to display text properly
		#~ my $no_lines  = $textview->get_buffer->get_line_count;
		#~ my $font_size = $font_descr->get_size / 1024;
#~ 
		#~ if ( ( $no_lines * $font_size ) + $parent->get('height') > ( $self->{_drawing_pixbuf}->get_height - 50 ) ) {
			#~ $parent->set( 'height' => ( $self->{_drawing_pixbuf}->get_height - $parent->get('height') ) );
		#~ } else {
			#~ $parent->set( 'height' => $no_lines * $font_size + $no_lines * 20 );
		#~ }

		$self->handle_rects( 'update', $parent );
		$self->handle_embedded( 'update', $parent );

		#save color and opacity as well
		$self->{_items}{$key}{stroke_color}       = $font_color->get_color;
		$self->{_items}{$key}{stroke_color_alpha} = $font_color->get_alpha / 65535;

	}
		
}

sub modify_text_in_properties {
	my $self       = shift;
	my $font_btn   = shift;
	my $textview   = shift;
	my $font_color = shift;
	my $item       = shift;

	my $font_descr = Gtk2::Pango::FontDescription->from_string( $font_btn->get_font_name );
	my $texttag    = Gtk2::TextTag->new;
	$texttag->set( 'font-desc' => $font_descr, 'foreground-gdk' => $font_color->get_color );
	my $texttagtable = Gtk2::TextTagTable->new;
	$texttagtable->add($texttag);
	my $text = Gtk2::TextBuffer->new($texttagtable);
	$text->signal_connect(
		'changed' => sub {
			$text->apply_tag( $texttag, $text->get_start_iter, $text->get_end_iter );
		}
	);

	$text->set_text( $textview->get_buffer->get_text( $textview->get_buffer->get_start_iter, $textview->get_buffer->get_end_iter, FALSE ) );
	$text->apply_tag( $texttag, $text->get_start_iter, $text->get_end_iter );
	$textview->set_buffer($text);

	return TRUE;
}

sub deactivate_all {
	my $self    = shift;
	my $exclude = shift;

	foreach ( keys %{ $self->{_items} } ) {

		my $item = $self->{_items}{$_};

		next if $item == $exclude;

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if ( exists $self->{_items}{$item} ) {
			$self->handle_rects( 'hide', $item );
		}

	}

	$self->{_last_item}        = undef;
	$self->{_current_item}     = undef;
	$self->{_current_new_item} = undef;

	return TRUE;
}

sub handle_embedded {	
	my $self   		= shift;
	my $action 		= shift;
	my $item   		= shift;
	my $new_width 	= shift;
	my $new_height 	= shift;

	return FALSE unless ( $item && exists $self->{_items}{$item} );

	if ( $action eq 'update' ) {

		my $visibilty = 'visible';

		#embedded ellipse
		if ( exists $self->{_items}{$item}{ellipse} ) {

			$self->{_items}{$item}{ellipse}->set(
				'center-x' => $self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width') / 2,
				'center-y' => $self->{_items}{$item}->get('y') + $self->{_items}{$item}->get('height') / 2,
			);
			$self->{_items}{$item}{ellipse}->set(
				'radius-x' => $self->{_items}{$item}->get('x') 
					+ $self->{_items}{$item}->get('width')
					- $self->{_items}{$item}{ellipse}->get('center-x'),
				'radius-y' => $item->get('y') + $self->{_items}{$item}->get('height') - $self->{_items}{$item}{ellipse}->get('center-y'),
				'visibility' => $visibilty,
			);

		} elsif ( exists $self->{_items}{$item}{text} ) {
			$self->{_items}{$item}{text}->set(
				'x'     => $self->{_items}{$item}->get('x'),
				'y'     => $self->{_items}{$item}->get('y'),
				'width' => $self->{_items}{$item}->get('width'),
				'visibility' => $visibilty,
			);
		} elsif ( exists $self->{_items}{$item}{line} ) {
		
				#handle possible arrows properly
				#arrow is always and end-arrow
				if($self->{_items}{$item}{mirrored_w} < 0 && $self->{_items}{$item}{mirrored_h} < 0){		
					$self->{_items}{$item}{line}->set(
						'points' => Goo::Canvas::Points->new( 
						[$self->{_items}{$item}->get('x')+$self->{_items}{$item}->get('width'),
						$self->{_items}{$item}->get('y')+$self->{_items}{$item}->get('height'),
						$self->{_items}{$item}->get('x'),
						$self->{_items}{$item}->get('y')]), 
						'visibility'  => $visibilty	
					);
				}elsif($self->{_items}{$item}{mirrored_w} < 0){			
					$self->{_items}{$item}{line}->set(
						'points' => Goo::Canvas::Points->new( 
						[$self->{_items}{$item}->get('x')+$self->{_items}{$item}->get('width'),
						$self->{_items}{$item}->get('y'),
						$self->{_items}{$item}->get('x'),
						$self->{_items}{$item}->get('y')+$self->{_items}{$item}->get('height')]), 
						'visibility'  => $visibilty	
					);
				}elsif($self->{_items}{$item}{mirrored_h} < 0){
					$self->{_items}{$item}{line}->set(
						'points' => Goo::Canvas::Points->new( 
						[$self->{_items}{$item}->get('x'),
						$self->{_items}{$item}->get('y')+$self->{_items}{$item}->get('height'),
						$self->{_items}{$item}->get('x')+$self->{_items}{$item}->get('width'),
						$self->{_items}{$item}->get('y')]), 
						'visibility'  => $visibilty	
					);
				}else{
					$self->{_items}{$item}{line}->set(
						'points' => Goo::Canvas::Points->new( 
						[$self->{_items}{$item}->get('x'),
						$self->{_items}{$item}->get('y'),
						$self->{_items}{$item}->get('x')+$self->{_items}{$item}->get('width'),
						$self->{_items}{$item}->get('y')+$self->{_items}{$item}->get('height')]),
						'visibility' => $visibilty
					);							
				}	
		
		} elsif ( exists $self->{_items}{$item}{image} ) {

			if($self->{_items}{$item}->get('width') == $self->{_items}{$item}{image}->get('width') && $self->{_items}{$item}->get('height') == $self->{_items}{$item}{image}->get('height')){
				
				$self->{_items}{$item}{image}->set(
					'x'      => int $self->{_items}{$item}->get('x'),
					'y'      => int $self->{_items}{$item}->get('y'),
					'width'  => $self->{_items}{$item}->get('width'),
					'height' => $self->{_items}{$item}->get('height'),
					'visibility' => $visibilty,
				);			

			}else{

				#be careful when resizing images
				#don't do anything when width or height are too small
				if($self->{_items}{$item}->get('width') > 5 && $self->{_items}{$item}->get('height') > 5){
					$self->{_items}{$item}{image}->set(
						'x'      => int $self->{_items}{$item}->get('x'),
						'y'      => int $self->{_items}{$item}->get('y'),
						'width'  => $self->{_items}{$item}->get('width'),
						'height' => $self->{_items}{$item}->get('height'),
						'pixbuf' => $self->{_items}{$item}{orig_pixbuf}->scale_simple( $self->{_items}{$item}->get('width'), $self->{_items}{$item}->get('height'), 'nearest' ),
						'visibility' => $visibilty,
					);			
				}else{
					$self->{_items}{$item}{image}->set(
						'x'      => int $self->{_items}{$item}->get('x'),
						'y'      => int $self->{_items}{$item}->get('y'),
						'width'  => $self->{_items}{$item}->get('width'),
						'height' => $self->{_items}{$item}->get('height'),
						'pixbuf' => undef,
						'visibility' => $visibilty,
					);						
				}
	
			}

		}
	}elsif( $action eq 'hide' ) {

		my $visibilty = 'hidden';

		#ellipse => hide rectangle as well
		if ( exists $self->{_items}{$item}{ellipse} ) {
			$self->{_items}{$item}{ellipse}->set( 'visibility' => $visibilty );
		}

		#text => hide rectangle as well
		if ( exists $self->{_items}{$item}{text} ) {
			$self->{_items}{$item}{text}->set( 'visibility' => $visibilty );
		}

		#image => hide rectangle as well
		if ( exists $self->{_items}{$item}{image} ) {
			$self->{_items}{$item}{image}->set( 'visibility' => $visibilty );
		}

		#line => hide rectangle as well
		if ( exists $self->{_items}{$item}{line} ) {
			$self->{_items}{$item}{line}->set( 'visibility' => $visibilty );
		}		

	}elsif( $action eq 'mirror' ) {
		if ( exists $self->{_items}{$item}{line} ) {				
			#width
			if ($new_width < 0 && $self->{_items}{$item}{mirrored_w} >= 0){
				$self->{_items}{$item}{mirrored_w} = $new_width;
			}elsif($new_width < 0 && $self->{_items}{$item}{mirrored_w} < 0){
				$self->{_items}{$item}{mirrored_w} = 0;				
			}
			
			#height
			if ($new_height < 0 && $self->{_items}{$item}{mirrored_h} >= 0){
				$self->{_items}{$item}{mirrored_h} = $new_height;
			}elsif($new_height < 0 && $self->{_items}{$item}{mirrored_h} < 0){
				$self->{_items}{$item}{mirrored_h} = 0;
			}
		}
	}

	return TRUE;
}

sub handle_bg_rects {
	my $self   = shift;
	my $action = shift;

	my $middle_h = $self->{_canvas_bg_rect}->get('x') + $self->{_canvas_bg_rect}->get('width') / 2 ;

	my $middle_v = $self->{_canvas_bg_rect}->get('y') + $self->{_canvas_bg_rect}->get('height') / 2 ;

	my $bottom = $self->{_canvas_bg_rect}->get('y') + $self->{_canvas_bg_rect}->get('height');

	my $top = $self->{_canvas_bg_rect}->get('y');

	my $left = $self->{_canvas_bg_rect}->get('x');

	my $right = $self->{_canvas_bg_rect}->get('x') + $self->{_canvas_bg_rect}->get('width');
	
	if ( $action eq 'create' ) {

		my $pattern = $self->create_color( 'black', 0.3 );

		$self->{_canvas_bg_rect}{'bottom-side'} = Goo::Canvas::Rect->new(
			$self->{_canvas}->get_root_item, $middle_h, $bottom, 8, 8,
			'fill-pattern' => $pattern,
			'line-width'   => 1
		);

		$self->{_canvas_bg_rect}{'bottom-right-corner'} = Goo::Canvas::Rect->new(
			$self->{_canvas}->get_root_item, $right, $bottom, 8, 8,
			'fill-pattern' => $pattern,
			'line-width'   => 1
		);

		$self->{_canvas_bg_rect}{'right-side'} = Goo::Canvas::Rect->new(
			$self->{_canvas}->get_root_item, $right, $middle_v, 8, 8,
			'fill-pattern' => $pattern,
			'line-width'   => 1
		);

		$self->setup_item_signals( $self->{_canvas_bg_rect}{'bottom-side'} );
		$self->setup_item_signals( $self->{_canvas_bg_rect}{'bottom-right-corner'} );
		$self->setup_item_signals( $self->{_canvas_bg_rect}{'right-side'} );
		$self->setup_item_signals_extra( $self->{_canvas_bg_rect}{'bottom-side'} );
		$self->setup_item_signals_extra( $self->{_canvas_bg_rect}{'bottom-right-corner'} );
		$self->setup_item_signals_extra( $self->{_canvas_bg_rect}{'right-side'} );

	}elsif($action eq 'hide'){

		my $visibilty = 'hidden';

		foreach ( keys %{ $self->{_canvas_bg_rect} } ) {
			$self->{_canvas_bg_rect}{$_}->set(
				'visibility' => $visibilty,
			);
		}    #end determine rect

		$self->{_canvas_bg_rect}->set(
			'visibility' => $visibilty,
		);

	}elsif($action eq 'update'){

		#update the canvas bounds as well
		$self->{_canvas}->set_bounds(0, 0, $self->{_canvas_bg_rect}->get('width'), $self->{_canvas_bg_rect}->get('height'));
			
		$self->{_canvas_bg_rect}{'bottom-side'}->set(
			'x'          => $middle_h - 8,
			'y'          => $bottom - 8,
		);

		$self->{_canvas_bg_rect}{'bottom-right-corner'}->set(
			'x'          => $right - 8,
			'y'          => $bottom - 8,
		);

		$self->{_canvas_bg_rect}{'right-side'}->set(
			'x'          => $right - 8,
			'y'          => $middle_v - 8,
		);

		$self->handle_bg_rects('raise');

	}elsif($action eq 'raise'){
		$self->{_canvas_bg_rect}{'bottom-side'}->raise;
		$self->{_canvas_bg_rect}{'bottom-right-corner'}->raise;
		$self->{_canvas_bg_rect}{'right-side'}->raise;			
	}
}

sub handle_rects {
	my $self   = shift;
	my $action = shift;
	my $item   = shift;

	return FALSE unless $item;
	return FALSE unless exists $self->{_items}{$item};

	#get root item
	my $root = $self->{_canvas}->get_root_item;

	#do we have a blessed reference?
	eval { $self->{_items}{$item}->can('isa'); };
	if ($@) {
		#~ print $@;
		return FALSE;
	}

	if ( $self->{_items}{$item}->isa('Goo::Canvas::Rect') ) {

		my $middle_h = $self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width') / 2 ;

		my $middle_v = $self->{_items}{$item}->get('y') + $self->{_items}{$item}->get('height') / 2 ;

		my $bottom = $self->{_items}{$item}->get('y') + $self->{_items}{$item}->get('height');

		my $top = $self->{_items}{$item}->get('y');

		my $left = $self->{_items}{$item}->get('x');

		my $right = $self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width');

		if ( $action eq 'create' ) {

			my $pattern = $self->create_color( 'green', 0.3 );

			$self->{_items}{$item}{'top-side'} = Goo::Canvas::Rect->new(
				$root, $middle_h, $top, 8, 8,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden',
				'line-width'   => 1
			);

			$self->{_items}{$item}{'top-left-corner'} = Goo::Canvas::Rect->new(
				$root, $left, $top, 8, 8,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden',
				'line-width'   => 1
			);

			$self->{_items}{$item}{'top-right-corner'} = Goo::Canvas::Rect->new(
				$root, $right, $top, 8, 8,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden',
				'line-width'   => 1
			);

			$self->{_items}{$item}{'bottom-side'} = Goo::Canvas::Rect->new(
				$root, $middle_h, $bottom, 8, 8,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden',
				'line-width'   => 1
			);

			$self->{_items}{$item}{'bottom-left-corner'} = Goo::Canvas::Rect->new(
				$root, $left, $bottom, 8, 8,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden',
				'line-width'   => 1
			);

			$self->{_items}{$item}{'bottom-right-corner'} = Goo::Canvas::Rect->new(
				$root, $right, $bottom, 8, 8,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden',
				'line-width'   => 1
			);

			$self->{_items}{$item}{'left-side'} = Goo::Canvas::Rect->new(
				$root, $left - 8, $middle_v, 8, 8,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden',
				'line-width'   => 1
			);

			$self->{_items}{$item}{'right-side'} = Goo::Canvas::Rect->new(
				$root, $right, $middle_v, 8, 8,
				'fill-pattern' => $pattern,
				'visibility'   => 'hidden',
				'line-width'   => 1
			);

			$self->setup_item_signals( $self->{_items}{$item}{'top-side'} );
			$self->setup_item_signals( $self->{_items}{$item}{'top-left-corner'} );
			$self->setup_item_signals( $self->{_items}{$item}{'top-right-corner'} );
			$self->setup_item_signals( $self->{_items}{$item}{'bottom-side'} );
			$self->setup_item_signals( $self->{_items}{$item}{'bottom-left-corner'} );
			$self->setup_item_signals( $self->{_items}{$item}{'bottom-right-corner'} );
			$self->setup_item_signals( $self->{_items}{$item}{'left-side'} );
			$self->setup_item_signals( $self->{_items}{$item}{'right-side'} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{'top-side'} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{'top-left-corner'} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{'top-right-corner'} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{'bottom-side'} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{'bottom-left-corner'} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{'bottom-right-corner'} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{'left-side'} );
			$self->setup_item_signals_extra( $self->{_items}{$item}{'right-side'} );

		} elsif ( $action eq 'update' || $action eq 'hide' ) {

			my $visibilty = 'visible';
			$visibilty = 'hidden' if $action eq 'hide';

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

			#line => hide rectangle as well
			if ( exists $self->{_items}{$item}{line} ) {
				$self->{_items}{$item}->set( 'visibility' => $visibilty );
			}

			$self->{_items}{$item}{'top-side'}->set(
				'x'          => $middle_h - 4,
				'y'          => $top - 8,
				'visibility' => $visibilty,
			);
			$self->{_items}{$item}{'top-left-corner'}->set(
				'x'          => $left - 8,
				'y'          => $top - 8,
				'visibility' => $visibilty,
			);

			$self->{_items}{$item}{'top-right-corner'}->set(
				'x'          => $right,
				'y'          => $top - 8,
				'visibility' => $visibilty,
			);

			$self->{_items}{$item}{'bottom-side'}->set(
				'x'          => $middle_h - 4,
				'y'          => $bottom,
				'visibility' => $visibilty,
			);

			$self->{_items}{$item}{'bottom-left-corner'}->set(
				'x'          => $left - 8,
				'y'          => $bottom,
				'visibility' => $visibilty,
			);

			$self->{_items}{$item}{'bottom-right-corner'}->set(
				'x'          => $right,
				'y'          => $bottom,
				'visibility' => $visibilty,
			);

			$self->{_items}{$item}{'left-side'}->set(
				'x'          => $left - 8,
				'y'          => $middle_v - 4,
				'visibility' => $visibilty,
			);
			$self->{_items}{$item}{'right-side'}->set(
				'x'          => $right,
				'y'          => $middle_v - 4,
				'visibility' => $visibilty,
			);

			$self->handle_bg_rects('raise');

		} elsif ( $action eq 'raise' ) {

			$self->{_items}{$item}{'top-side'}->raise;
			$self->{_items}{$item}{'top-left-corner'}->raise;
			$self->{_items}{$item}{'top-right-corner'}->raise;
			$self->{_items}{$item}{'bottom-side'}->raise;
			$self->{_items}{$item}{'bottom-left-corner'}->raise;
			$self->{_items}{$item}{'bottom-right-corner'}->raise;
			$self->{_items}{$item}{'left-side'}->raise;
			$self->{_items}{$item}{'right-side'}->raise;

		} elsif ( $action eq 'lower' ) {

			$self->{_items}{$item}{'top-side'}->lower;
			$self->{_items}{$item}{'top-left-corner'}->lower;
			$self->{_items}{$item}{'top-right-corner'}->lower;
			$self->{_items}{$item}{'bottom-side'}->lower;
			$self->{_items}{$item}{'bottom-left-corner'}->lower;
			$self->{_items}{$item}{'bottom-right-corner'}->lower;
			$self->{_items}{$item}{'left-side'}->lower;
			$self->{_items}{$item}{'right-side'}->lower;

		}
	}

	return TRUE;
}

sub event_item_on_button_release {
	my ( $self, $item, $target, $ev ) = @_;
	my $canvas = $item->get_canvas;
	$canvas->pointer_ungrab( $item, $ev->time );

	my $d = $self->{_shutter_common}->get_gettext;

	#we handle some minimum sizes here if the new items are too small
	#maybe the user just wanted to place an rect or an object on the canvas
	#and clicked on it without describing an rectangular area
	my $nitem = $self->{_current_new_item};

	if ($nitem) {

		#set minimum sizes
		if ( $nitem->isa('Goo::Canvas::Rect') ) {

			#real shape
			if ( exists $self->{_items}{$nitem} ) {

				#images
				if (exists $self->{_items}{$nitem}{image}){
					
					#~ my ($maxw, $maxh) = Gtk2::Gdk::Display->get_default->get_maximal_cursor_size;
					#~ $self->{_items}{$nitem}->set(
						#~ 'width' => $maxw,
						#~ 'height' => $maxh
					#~ );

					$self->{_items}{$nitem}->set(
						'x' => $ev->x_root - $self->{_items}{$nitem}{orig_pixbuf}->get_width,
						'y' => $ev->y_root - $self->{_items}{$nitem}{orig_pixbuf}->get_height,
						'width' => $self->{_items}{$nitem}{orig_pixbuf}->get_width,
						'height' => $self->{_items}{$nitem}{orig_pixbuf}->get_height,
					);
			
				#all other objects
				}else{
					
					$nitem->set( 
						'x'  		=> $ev->x_root - 100, 
						'y' 		=> $ev->y_root - 100, 			
						'width' 	=> 100,
						'height' 	=> 100,
					);
					
				}

			}

		}

		$self->handle_rects( 'update', $nitem );
		$self->handle_embedded( 'update', $nitem );

	}

	#unset action flags
	$item->{dragging} = FALSE;
	$item->{resizing} = FALSE;

	#because of performance reason we load the current image new from file when
	#the current action is over => button-release
	#when resizing or moving the image we just scale the current image with low quality settings
	#see handle_embedded
	my $child = $self->get_child_item($self->{_current_new_item});
	$child = $self->get_child_item($self->{_current_item}) unless $child;
	
	if ( $child && $child->isa('Goo::Canvas::Image') ){
		my $parent = $self->get_parent_item($child);
		
		my $copy = Gtk2::Gdk::Pixbuf->new_from_file_at_scale($self->{_items}{$parent}{orig_pixbuf_filename},$self->{_items}{$parent}->get('width'), $self->{_items}{$parent}->get('height'), FALSE);
				
		$self->{_items}{$parent}{image}->set(
			'x'      => int $self->{_items}{$parent}->get('x'),
			'y'      => int $self->{_items}{$parent}->get('y'),
			'width'  => $self->{_items}{$parent}->get('width'),
			'height' => $self->{_items}{$parent}->get('height'),
			'pixbuf' => $copy
		);
	}	

	$self->set_drawing_action(int($self->{_current_mode}/10));
	$self->change_drawing_tool_cb($self->{_current_mode});
		
	return TRUE;
}

sub event_item_on_enter_notify {
	my ( $self, $item, $target, $ev ) = @_;
	
	if (   $item->isa('Goo::Canvas::Rect')
		|| $item->isa('Goo::Canvas::Ellipse')
		|| $item->isa('Goo::Canvas::Text')
		|| $item->isa('Goo::Canvas::Image')
		|| $item->isa('Goo::Canvas::Polyline') )
	{

		my $cursor = Gtk2::Gdk::Cursor->new('left-ptr');

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if ( exists $self->{_items}{$item} ) {
			
			$cursor = Gtk2::Gdk::Cursor->new('fleur');

			#set cursor
			if ( $self->{_current_mode_descr} eq "select" ) {
				$self->{_canvas}->window->set_cursor($cursor);
			} elsif ( $self->{_current_mode_descr} eq "clear" ) {
				my $dicons = $self->{_shutter_common}->get_root . "/share/shutter/resources/icons/drawing_tool";
				$cursor = Gtk2::Gdk::Cursor->new_from_pixbuf(
					Gtk2::Gdk::Display->get_default,
					Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-eraser.png"),
					Gtk2::IconSize->lookup('menu')
				);
				$self->{_canvas}->window->set_cursor($cursor);
			}

			#canvas resizing shape
		} elsif (  $self->{_canvas_bg_rect}{'right-side'} == $item
				|| $self->{_canvas_bg_rect}{'bottom-side'} == $item
				|| $self->{_canvas_bg_rect}{'bottom-right-corner'} == $item ) 
		{

			if ( $self->{_current_mode_descr} eq "select" ) {

				my $pattern = $self->create_color( 'black', 1.0 );
				$item->set( 'fill-pattern' => $pattern );

				foreach ( keys %{ $self->{_canvas_bg_rect} } ) {
					if ( $item == $self->{_canvas_bg_rect}{$_} ) {
						my $cursor = Gtk2::Gdk::Cursor->new($_);
						$self->{_canvas}->window->set_cursor($cursor);
					}
				}    #end determine cursor
			}		

			#resizing shape
		} else {
			
			#don't change color when an action is already taking place
			#e.g. resizing
			if ( $self->{_current_mode_descr} eq "select" ) {
				my $pattern = $self->create_color( 'red', 0.5 );
				$item->set( 'fill-pattern' => $pattern );
			}

			#activate correct item if not activated yet
			my $curr_item = $self->{_current_new_item} || $self->{_current_item};

			$self->{_current_new_item} = undef;
			$self->{_last_item}        = $curr_item;
			$self->{_current_item}     = $curr_item;

			$self->handle_rects( 'hide',   $self->{_last_item} );
			$self->handle_rects( 'update', $curr_item );

			if ( $self->{_current_mode_descr} eq "select" ) {
				foreach ( keys %{ $self->{_items}{$curr_item} } ) {
					if ( $item == $self->{_items}{$curr_item}{$_} ) {
						$cursor = Gtk2::Gdk::Cursor->new($_);
						$self->{_canvas}->window->set_cursor($cursor);
					}
				}    #end determine cursor
			}

		}

	}

	return TRUE;
}

sub event_item_on_leave_notify {
	my ( $self, $item, $target, $ev ) = @_;

	if (   $item->isa('Goo::Canvas::Rect')
		|| $item->isa('Goo::Canvas::Ellipse')
		|| $item->isa('Goo::Canvas::Text')
		|| $item->isa('Goo::Canvas::Image')
		|| $item->isa('Goo::Canvas::Polyline') )
	{

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if ( exists $self->{_items}{$item} ) {

			#canvas resizing shape
		} elsif (  $self->{_canvas_bg_rect}{'right-side'} == $item
				|| $self->{_canvas_bg_rect}{'bottom-side'} == $item
				|| $self->{_canvas_bg_rect}{'bottom-right-corner'} == $item ) 
		{

			my $pattern = $self->create_color( 'black', 0.3 );
			$item->set( 'fill-pattern' => $pattern );

			#resizing shape
		} else {
			my $pattern = $self->create_color( 'green', 0.3 );
			$item->set( 'fill-pattern' => $pattern );
		}
	}

	my $cursor = Gtk2::Gdk::Cursor->new('left-ptr');
	$self->{_canvas}->window->set_cursor($cursor)
		if ( $self->{_current_mode_descr} eq "select"
		|| $self->{_current_mode_descr} eq "clear" );

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

	return FALSE unless defined $color_name;
	return FALSE unless defined $alpha;

	my $color;
	#if it is a color, we do not need to parse it
	unless ( $color_name->isa('Gtk2::Gdk::Color') ) {
		$color = Gtk2::Gdk::Color->parse($color_name);
	} else {
		$color = $color_name;
	}

	my $pattern = Cairo::SolidPattern->create_rgba( $color->red / 257 / 255, $color->green / 257 / 255, $color->blue / 257 / 255, $alpha );

	return Goo::Cairo::Pattern->new($pattern);
}

#ui related stuff
sub setup_uimanager {
	my $self = shift;
	my $d    = $self->{_shutter_common}->get_gettext;

	#define own icons
	my $dicons = $self->{_shutter_common}->get_root . "/share/shutter/resources/icons/drawing_tool";

	$self->{_factory} = Gtk2::IconFactory->new();
	$self->{_factory}->add( 'shutter-ellipse',   Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-ellipse.png") ) );
	$self->{_factory}->add( 'shutter-eraser',    Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-eraser.png") ) );
	$self->{_factory}->add( 'shutter-freehand',  Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-freehand.png") ) );
	$self->{_factory}->add( 'shutter-highlighter',  Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-highlighter.png") ) );
	$self->{_factory}->add( 'shutter-pointer',   Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-pointer.png") ) );
	$self->{_factory}->add( 'shutter-rectangle', Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-rectangle.png") ) );
	$self->{_factory}->add( 'shutter-line', Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-line.png") ) );
	$self->{_factory}->add( 'shutter-arrow', Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-arrow.png") ) );
	$self->{_factory}->add( 'shutter-text',      Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-text.png") ) );
	$self->{_factory}->add( 'shutter-censor',      Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-censor.png") ) );
	$self->{_factory}->add_default();

	my @default_actions = ( [ "File", undef, $d->get("_File") ], [ "Edit", undef, $d->get("_Edit") ], [ "View", undef, $d->get("_View") ] );

	my @menu_actions = (
		[ "Undo", 'gtk-undo', undef, "<control>Z", undef, sub { $self->undo } ],
		[ "Redo", 'gtk-redo', undef, "<control>Y", undef, sub { $self->redo } ],
		[ "Copy", 'gtk-copy', undef, "<control>C", undef, sub { $self->{_cut} = FALSE; $self->{_current_copy_item} = $self->{_current_item}; } ],
		[ "Cut", 'gtk-cut', undef, "<control>X", undef, sub { $self->{_cut} = TRUE; $self->{_current_copy_item} = $self->{_current_item}; $self->clear_item_from_canvas( $self->{_current_copy_item}); } ],
		[ "Paste", 'gtk-paste', undef, "<control>V", undef, sub { $self->paste_item($self->{_current_copy_item}, $self->{_cut} ); $self->{_cut} = FALSE; } ],
		[ "Delete", 'gtk-delete', undef, "Delete", undef, sub { $self->clear_item_from_canvas( $self->{_current_item}); } ],
		[ "Stop", 'gtk-stop', undef, "Escape", undef, sub { $self->abort_current_mode } ]

	);

	my @menu_toggle_actions = (
		[   "Autoscroll", undef, $d->get("Automatic scrolling"), undef, undef, sub { my $widget = shift; $self->{_autoscroll} = $widget->get_active; }
		]
	);

	my @toolbar_actions = (
		[ "Close", 'gtk-close', undef, "<control>Q", undef, sub { $self->quit(TRUE) } ],
		[ "Save",       'gtk-save',     undef, "<control>S",     undef, sub { $self->save(), $self->quit(FALSE) } ],
		[ "ZoomIn",     'gtk-zoom-in',  undef, "<control>plus",  undef, sub { $self->zoom_in_cb($self) } ],
		[ "ControlEqual",  'gtk-zoom-in',  undef, "<control>equal",  undef, sub { $self->zoom_in_cb($self) } ],
		[ "ControlKpAdd",  'gtk-zoom-in',  undef, "<control>KP_Add",  undef, sub { $self->zoom_in_cb($self) } ],
		[ "ZoomOut",    'gtk-zoom-out', undef, "<control>minus", undef, sub { $self->zoom_out_cb($self) } ],
		[ "ControlKpSub",    'gtk-zoom-out', undef, "<control>KP_Subtract", undef, sub { $self->zoom_out_cb($self) } ],
		[ "ZoomNormal", 'gtk-zoom-100', undef, "<control>0",     undef, sub { $self->zoom_normal_cb($self) } ]
	);

	my @toolbar_drawing_actions = (
		[ "Select",  'shutter-pointer',   undef, undef, $d->get("Select item to move or resize it"),    10 ],
		[ "Freehand",    'shutter-freehand',  undef, undef, $d->get("Draw a freehand line"), 20 ],
		[ "Highlighter",    'shutter-highlighter',  undef, undef, $d->get("Highlighter"), 30 ],
		[ "Line",    'shutter-line', undef, undef, $d->get("Draw a straight line"),                    40 ],
		[ "Arrow",    'shutter-arrow', undef, undef, $d->get("Draw an arrow"),                    50 ],
		[ "Rect",    'shutter-rectangle', undef, undef, $d->get("Draw a rectangle"),                    60 ],
		[ "Ellipse", 'shutter-ellipse',   undef, undef, $d->get("Draw a ellipse"),                      70 ],
		[ "Text",    'shutter-text',      undef, undef, $d->get("Add some text to the screenshot"),     80 ],
		[ "Censor",    'shutter-censor',      undef, undef, $d->get("Censor portions of your screenshot to hide private data"),     90 ],
		[ "Clear",   'shutter-eraser',    undef, undef, $d->get("Delete objects"),                      100 ],
		[ "ClearAll",'gtk-clear',  	 undef, undef, $d->get("Delete all objects"),                  110 ]
	);

	my $uimanager = Gtk2::UIManager->new();

	#keyboard accel_group
	my $accelgroup = $uimanager->get_accel_group;
	$self->{_drawing_window}->add_accel_group($accelgroup);

	# Setup the default group.
	my $default_group = Gtk2::ActionGroup->new("default");
	$default_group->add_actions( \@default_actions );

	# Setup the menu group.
	my $menu_group = Gtk2::ActionGroup->new("menu");
	$menu_group->add_actions( \@menu_actions );

	#setup the menu toggle group
	my $menu_toggle_group = Gtk2::ActionGroup->new("menu_toggle");
	$menu_toggle_group->add_toggle_actions( \@menu_toggle_actions );

	# Setup the toolbar group.
	my $toolbar_group = Gtk2::ActionGroup->new("toolbar");
	$toolbar_group->add_actions( \@toolbar_actions );

	# Setup the drawing group.
	my $toolbar_drawing_group = Gtk2::ActionGroup->new("drawing");
	$toolbar_drawing_group->add_radio_actions( \@toolbar_drawing_actions, 10, sub { my $action = shift; $self->deactivate_all; $self->change_drawing_tool_cb($action); } );

	$uimanager->insert_action_group( $default_group,         0 );
	$uimanager->insert_action_group( $menu_group,            0 );
	$uimanager->insert_action_group( $menu_toggle_group,     0 );
	$uimanager->insert_action_group( $toolbar_group,         0 );
	$uimanager->insert_action_group( $toolbar_drawing_group, 0 );

      #~ <menuitem action = 'Undo'/>
      #~ <menuitem action = 'Redo'/>
	  #~ <separator/>

	my $ui_info = "
<ui>
  <menubar name = 'MenuBar'>
    <menu action = 'File'>
      <menuitem action = 'Save'/>
      <separator/>
      <menuitem action = 'Close'/>
    </menu>
    <menu action = 'Edit'>

      <menuitem action = 'Copy'/>
      <menuitem action = 'Cut'/>
      <menuitem action = 'Paste'/>
      <menuitem action = 'Delete'/>
      <separator/>
      <menuitem action = 'Stop'/>
      <separator/>
      <menuitem action = 'Autoscroll'/>
    </menu>
    <menu action = 'View'>
      <menuitem action = 'ControlEqual'/>	
      <menuitem action = 'ControlKpAdd'/>	
      <menuitem action = 'ZoomIn'/>
      <menuitem action = 'ZoomOut'/>
      <menuitem action = 'ControlKpSub'/>		  
      <menuitem action = 'ZoomNormal'/>
    </menu>
  </menubar>
  <toolbar name = 'ToolBar'>
    <toolitem action='Close'/>
    <toolitem action='Save'/>
    <separator/>
    <toolitem action='ZoomIn'/>
    <toolitem action='ZoomOut'/>
    <toolitem action='ZoomNormal'/>
  </toolbar>
  <toolbar name = 'ToolBarDrawing'>
    <toolitem action='Select'/>
    <separator/>
    <toolitem action='Freehand'/>
    <toolitem action='Highlighter'/>
    <toolitem action='Line'/>
    <toolitem action='Arrow'/>
    <toolitem action='Rect'/>
    <toolitem action='Ellipse'/>
    <toolitem action='Text'/>
    <toolitem action='Censor'/>
    <separator/>
    <toolitem action='Clear'/>
    <toolitem action='ClearAll'/>
  </toolbar>  
</ui>";

	eval { $uimanager->add_ui_from_string($ui_info) };

	if ($@) {
		die "Unable to create menus: $@\n";
	}

	return $uimanager;
}

sub ret_objects_menu {
	my $self   = shift;
	my $button = shift;

	my $menu_objects = Gtk2::Menu->new;

	my $d = $self->{_shutter_common}->get_gettext;

	my $dobjects = $self->{_shutter_common}->get_root . "/share/shutter/resources/icons/drawing_tool/objects";

	my @objects = glob("$dobjects/*");
	foreach my $filename (@objects) {

		#parse filename
		my ( $short, $folder, $type ) = fileparse( $filename, '\..*' );

		#create pixbufs
		my $orig_pixbuf;
		eval{
			$orig_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file($filename);		
		};
		unless($@){

			my $small_image = Gtk2::Image->new_from_pixbuf( $orig_pixbuf->scale_down_pixbuf (Gtk2::IconSize->lookup('menu')));
			#~ my $small_image_button = Gtk2::Image->new_from_pixbuf( $orig_pixbuf->scale_down_pixbuf (Gtk2::IconSize->lookup('menu')));
			my $small_image_button = Gtk2::Image->new_from_pixbuf( $small_image->get_pixbuf );

			#create items
			my $new_item = Gtk2::ImageMenuItem->new_with_label($short);
			$new_item->set_image($small_image);

			#~ &fct_load_pixbuf_async ($small_image, $filename, $new_item);

			#init
			unless ( $button->get_icon_widget ) {
				$button->set_icon_widget($small_image_button);
				$self->{_current_pixbuf} = $orig_pixbuf->copy;
				$self->{_current_pixbuf_filename} = $filename;
			}

			$new_item->signal_connect(
				'activate' => sub {
					$self->{_current_pixbuf} = $orig_pixbuf->copy;
					$self->{_current_pixbuf_filename} = $filename;
					$button->set_icon_widget($small_image_button);
					$button->show_all;
					$self->{_canvas}->window->set_cursor( $self->change_cursor_to_current_pixbuf );
				}
			);

			$menu_objects->append($new_item);
			
		}else{
			my $response = $self->{_dialogs}->dlg_error_message( 
				sprintf( $d->get("Error while opening image %s."), "'" . $filename . "'" ),
				$d->get( "There was an error opening the image." ),
				undef, undef, undef,
				undef, undef, undef,
				$@
			);		
		} 

	}

	$menu_objects->append( Gtk2::SeparatorMenuItem->new );

	#objects from session
	my $session_menu_item = Gtk2::MenuItem->new_with_label( $d->get("Import from session...") );
	$session_menu_item->set_submenu( $self->import_from_session($button) );

	$menu_objects->append($session_menu_item);

	#objects from filesystem
	my $filesystem_menu_item = Gtk2::MenuItem->new_with_label( $d->get("Import from filesystem...") );
	$filesystem_menu_item->signal_connect(
		'activate' => sub {

			my $fs = Gtk2::FileChooserDialog->new(
				$d->get("Choose file to open"), $self->{_drawing_window}, 'open',
				'gtk-cancel' => 'reject',
				'gtk-open'   => 'accept'
			);

			$fs->set_select_multiple(FALSE);

			my $filter_all = Gtk2::FileFilter->new;
			$filter_all->set_name( $d->get("All compatible image formats") );
			$fs->add_filter($filter_all);

			foreach ( Gtk2::Gdk::Pixbuf->get_formats ) {
				my $filter = Gtk2::FileFilter->new;
				$filter->set_name( $_->{name} . " - " . $_->{description} );
				foreach ( @{ $_->{extensions} } ) {
					$filter->add_pattern( "*." . uc $_ );
					$filter_all->add_pattern( "*." . uc $_ );
					$filter->add_pattern( "*." . $_ );
					$filter_all->add_pattern( "*." . $_ );
				}
				$fs->add_filter($filter);
			}

			if ( $ENV{'HOME'} ) {
				$fs->set_current_folder( $ENV{'HOME'} );
			}
			my $fs_resp = $fs->run;

			my $new_file;
			if ( $fs_resp eq "accept" ) {
				$new_file = $fs->get_filenames;

				#create pixbufs
				my $small_image        = Gtk2::Image->new_from_stock( 'gtk-new', 'menu' );
				my $small_image_button = Gtk2::Image->new_from_stock( 'gtk-new', 'menu' );
				
				my $orig_pixbuf;
				eval{
					$orig_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file($new_file);	
				};
				#check if there is any error while loading this file
				unless($@){
					$self->{_current_pixbuf}          = $orig_pixbuf->copy;
					$self->{_current_pixbuf_filename} = $new_file;
					$button->set_icon_widget($small_image_button);
					$button->show_all;
					$self->{_canvas}->window->set_cursor( $self->change_cursor_to_current_pixbuf );
				}else{
					my $response = $self->{_dialogs}->dlg_error_message( 
						sprintf( $d->get("Error while opening image %s."), "'" . $new_file. "'"),
						$d->get( "There was an error opening the image." ),
						undef, undef, undef,
						undef, undef, undef,
						$@
					);											
				}
				
				$fs->destroy();
			} else {
				$fs->destroy();
			}

		}
	);

	$menu_objects->append($filesystem_menu_item);

	$button->show_all;
	$menu_objects->show_all;

	return $menu_objects;
}

#~ sub fct_load_pixbuf_async {
#~ 
	#~ print Dumper @_;
#~ 
#~ 
	#~ my $image = shift;
	#~ my $filename = shift;
	#~ my $menu_item = shift;
	#~ 
	#~ my $loader = Gtk2::Gdk::PixbufLoader->new;
	#~ my $handle = Gnome2::VFS::Async->open_uri (Gnome2::VFS::URI->new ($filename), 'read', 10, \&fct_open_async, $loader);	
#~ 
	#~ $loader->signal_connect('closed' => sub{
		#~ print "closed\n";
		#~ $image->set_from_pixbuf($loader->get_pixbuf);
		#~ $menu_item->set_image($image);
		#~ $image->show_all;
		#~ $menu_item->show_all;
#~ 
	#~ });
	#~ $loader->signal_connect('area-updated' => sub{
		#~ print "updated\n";
		#~ $image->set_from_pixbuf($loader->get_pixbuf);
		#~ $image->show_all;
		#~ $menu_item->set_image($image);
		#~ $menu_item->show_all;
#~ 
	#~ });		
	#~ 
#~ }
#~ 
#~ sub fct_open_async {
#~ 
	#~ print Dumper @_;
#~ 
	#~ my $handle = shift;
	#~ my $result = shift;
	#~ my $loader = shift;
	#~ 
	#~ if($result eq 'ok'){
		#~ $handle->read (10000, \&fct_read_async, $loader); 
	#~ }else{
		#~ print "Error!\n";
		#~ $handle->close(\&fct_close_async, $loader);	
#~ 
	#~ }
#~ }
#~ 
#~ sub fct_read_async {
#~ 
	#~ print Dumper @_;
#~ 
	#~ my $handle = shift;
	#~ my $result = shift;
	#~ my $buffer = shift;
	#~ my $size = shift;
	#~ my $size2 = shift;
	#~ my $loader = shift;
#~ 
	#~ if($result eq 'ok'){
		#~ $loader->write($buffer);
		#~ $handle->read(10000, \&fct_read_async, $loader);	
	#~ }else{
		#~ $handle->close(\&fct_close_async, $loader);	
	#~ }
#~ }
#~ 
#~ sub fct_close_async {
#~ 
	#~ print Dumper @_;
#~ 
	#~ my $handle = shift;
	#~ my $result = shift;
	#~ my $loader = shift;
	#~ 
	#~ $loader->close;
#~ 
#~ }

sub import_from_session {
	my $self                 = shift;
	my $button               = shift;
	my $menu_session_objects = Gtk2::Menu->new;

	my $d = $self->{_shutter_common}->get_gettext;

	my %import_hash = %{ $self->{_import_hash} };

	foreach my $key ( sort keys %import_hash ) {

		my $orig_pixbuf;
		eval{
			$orig_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file( $import_hash{$key}->{'long'} );
		};
		unless($@){

			#try to generate a new thumbnail
			my $thumb = $self->{_thumbs}->get_thumbnail(
				$import_hash{$key}->{'uri'}->to_string,
				$import_hash{$key}->{'mime_type'},
				$import_hash{$key}->{'mtime'},
				0.2
			);			

			my $small_image = Gtk2::Image->new_from_pixbuf( $thumb );
			#~ my $small_image_button = Gtk2::Image->new_from_pixbuf( $orig_pixbuf->scale_down_pixbuf (Gtk2::IconSize->lookup('menu')));
			my $small_image_button = Gtk2::Image->new_from_pixbuf( $small_image->get_pixbuf );

			my $screen_menu_item = Gtk2::ImageMenuItem->new_with_label( $import_hash{$key}->{'short'} );
			$screen_menu_item->set_image($small_image);

			#set sensitive == FALSE if image eq current file
			$screen_menu_item->set_sensitive(FALSE)
				if $import_hash{$key}->{'long'} eq $self->{_filename};

			$screen_menu_item->signal_connect(
				'activate' => sub {
					$self->{_current_pixbuf}          = $orig_pixbuf->copy;
					$self->{_current_pixbuf_filename} = $import_hash{$key}->{'long'};
					$button->set_icon_widget($small_image_button);
					$button->show_all;
					$self->{_canvas}->window->set_cursor( $self->change_cursor_to_current_pixbuf );
				}
			);

			$menu_session_objects->append($screen_menu_item);

		}else{
			my $response = $self->{_dialogs}->dlg_error_message( 
				sprintf( $d->get("Error while opening image %s."), "'" . $import_hash{$key}->{'long'} . "'" ),
				$d->get( "There was an error opening the image." ),
				undef, undef, undef,
				undef, undef, undef,
				$@
			);				
		}

	}

	$menu_session_objects->show_all;

	return $menu_session_objects;
}

sub set_drawing_action {
	my $self  = shift;
	my $index = shift;

	my $toolbar = $self->{_uimanager}->get_widget("/ToolBarDrawing");
	for ( my $i = 0; $i < $toolbar->get_n_items; $i++ ) {
		my $item       = $toolbar->get_nth_item($i);
		
		#skip separators
		#we only want to activate tools
		next if $item->isa('Gtk2::SeparatorToolItem');
		my $item_index = $toolbar->get_item_index($item);
		$item->set_active(TRUE) if $item_index == $index;
	}

}

sub change_cursor_to_current_pixbuf {
	my $self = shift;

	$self->{_current_mode_descr} = "image";

	#define own icons
	my $dicons = $self->{_shutter_common}->get_root . "/share/shutter/resources/icons/drawing_tool";
	my $cursor = undef; 
	
	#very big image usually don't work as a cursor (no error though??)
	if($self->{_current_pixbuf}->get_width < 1000 && $self->{_current_pixbuf}->get_height < 1000 ){
		my $cpixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_scale($self->{_current_pixbuf_filename}, Gtk2::Gdk::Display->get_default->get_maximal_cursor_size, TRUE);
		$cursor = Gtk2::Gdk::Cursor->new_from_pixbuf( Gtk2::Gdk::Display->get_default, $cpixbuf, undef, undef );
	}else{
		$cursor = Gtk2::Gdk::Cursor->new_from_pixbuf(
				Gtk2::Gdk::Display->get_default,
				Gtk2::Gdk::Pixbuf->new_from_file("$dicons/draw-image.svg"),
				Gtk2::IconSize->lookup('menu')
		);		
	}
	
	return $cursor;
}

sub paste_item {
	my $self = shift;
	my $item = shift;
	
	#cut instead of copy
	my $delete_after = shift;

	#~ print $item."\n";

	return FALSE unless $item;
	
	my $child = $self->get_child_item($item);
	
	if ( $item->isa('Goo::Canvas::Rect') && !$child ) {
		#~ print "Creating Rectangle...\n";
		$self->create_rectangle( undef, $item );
	}elsif ( $item->isa('Goo::Canvas::Polyline') && !$child ){
		#~ print "Creating Polyline...\n";
		$self->create_polyline( undef, $item );
	}elsif ( $child->isa('Goo::Canvas::Polyline') && exists $self->{_items}{$item}{stroke_color} ){
		#~ print "Creating Line...\n";
		$self->create_line( undef, $item );
	}elsif ( $child->isa('Goo::Canvas::Polyline') ){
		#~ print "Creating Censor...\n";
		$self->create_censor( undef, $item );
	}elsif ( $child->isa('Goo::Canvas::Ellipse') ){
		#~ print "Creating Ellipse...\n";
		$self->create_ellipse( undef, $item);
	}elsif ( $child->isa('Goo::Canvas::Text') ){
		#~ print "Creating Text...\n";
		$self->create_text( undef, $item );
	}elsif ( $child->isa('Goo::Canvas::Image') ){
		#~ print "Creating Image...\n";
		$self->create_image( undef, $item );
	}	

	#cut instead of copy
	if($delete_after){
		$self->clear_item_from_canvas($item);
		$self->{_current_item} = undef;
		$self->{_current_copy_item} = undef;
	}

	return TRUE;
}	

sub create_polyline {
	my $self      	= shift;
	my $ev        	= shift;
	my $copy_item 	= shift;
	
	#this is a highlighter? 
	#we need different default values in this case
	my $highlighter = shift;

	my @points = ();
	my $stroke_pattern = $self->create_color( $self->{_stroke_color}, $self->{_stroke_color_alpha} );
	my $transform;
	my $line_width = $self->{_line_width};
	
	#use event coordinates
	if ($ev) {
		@points = ( $ev->x_root, $ev->y_root, $ev->x_root, $ev->y_root );
	#use source item coordinates
	} elsif ($copy_item) {
		foreach(@{$self->{_items}{$copy_item}{points}}){
			push @points, $_ + 20;
		}

		$stroke_pattern = $self->create_color( $self->{_items}{$copy_item}{stroke_color}, $self->{_items}{$copy_item}{stroke_color_alpha} );
		$transform = $self->{_items}{$copy_item}->get('transform');
		$line_width = $self->{_items}{$copy_item}->get('line_width');
	}

	my $item = undef;
	if($highlighter){
		$item = Goo::Canvas::Polyline->new_line(
			$self->{_canvas}->get_root_item, $points[0],$points[1],$points[2],$points[3],
			'stroke-pattern' => $self->create_color( Gtk2::Gdk::Color->parse('#FFFF00'), 0.5 ),
			'line-width'     => 18,
			'line-cap'       => 'CAIRO_LINE_CAP_ROUND',
			'line-join'      => 'CAIRO_LINE_JOIN_ROUND'
		);		
	}else{
		$item = Goo::Canvas::Polyline->new_line(
			$self->{_canvas}->get_root_item, $points[0],$points[1],$points[2],$points[3],
			'stroke-pattern' => $stroke_pattern,
			'line-width'     => $line_width,
			'line-cap'       => 'CAIRO_LINE_CAP_ROUND',
			'line-join'      => 'CAIRO_LINE_JOIN_ROUND'
		);		
	}
	 
	$self->{_current_new_item} = $item;
	$self->{_items}{$item} = $item;

	#need at least 2 points
	push @{ $self->{_items}{$item}{'points'} }, @points;
	$self->{_items}{$item}->set( points => Goo::Canvas::Points->new( $self->{_items}{$item}{'points'} ) );	
	$self->{_items}{$item}->set( transform => $transform) if $transform;

	if($highlighter){
		#set type flag
		$self->{_items}{$item}{type} = 'highlighter';		
		$self->{_items}{$item}{stroke_color}       = Gtk2::Gdk::Color->parse('#FFFF00');
		$self->{_items}{$item}{stroke_color_alpha} = 0.5;
	}else{
		#set type flag
		$self->{_items}{$item}{type} = 'freehand';
		$self->{_items}{$item}{stroke_color}       = $self->{_stroke_color};
		$self->{_items}{$item}{stroke_color_alpha} = $self->{_stroke_color_alpha};		
	}

	$self->setup_item_signals( $self->{_items}{$item} );
	$self->setup_item_signals_extra( $self->{_items}{$item} );

	#add to undo stack
	$self->store_to_xdo_stack($item , 'create', 'undo');

	return TRUE;

}

sub create_censor {
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;

	my @points = ();
	my $transform;
	
	#use event coordinates
	if ($ev) {
		@points = ( $ev->x_root, $ev->y_root, $ev->x_root, $ev->y_root );
	#use source item coordinates
	} elsif ($copy_item) {
		foreach(@{$self->{_items}{$copy_item}{points}}){
			push @points, $_ + 20;
		}
		$transform = $self->{_items}{$copy_item}->get('transform');
	}

    my @stipple_data = (255, 255, 255, 255,  255, 255, 255, 255,   255, 255, 255, 255,  255, 255, 255, 255);
   	my $stroke_pattern = $self->create_stipple('black', \@stipple_data);
		
	my $item = Goo::Canvas::Polyline->new_line(
		$self->{_canvas}->get_root_item, $points[0],$points[1],$points[2],$points[3],
		'stroke-pattern' => $stroke_pattern,
		'line-width'     => 14,
		'line-cap'       => 'CAIRO_LINE_CAP_ROUND',
		'line-join'      => 'CAIRO_LINE_JOIN_ROUND'
	);

	$self->{_current_new_item} = $item;
	$self->{_items}{$item} = $item;

	#set type flag
	$self->{_items}{$item}{type} = 'censor';

	#need at least 2 points
	push @{ $self->{_items}{$item}{'points'} }, @points;
	$self->{_items}{$item}->set( points => Goo::Canvas::Points->new( $self->{_items}{$item}{'points'} ) );	
	$self->{_items}{$item}->set( transform => $transform) if $transform;

	$self->setup_item_signals( $self->{_items}{$item} );
	$self->setup_item_signals_extra( $self->{_items}{$item} );

	#add to undo stack
	$self->store_to_xdo_stack($item , 'create', 'undo');

	return TRUE;

}

sub create_image {
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;

	my @dimensions = ( 0, 0, 0, 0 );

	#use event coordinates
	if ($ev) {
		@dimensions = ( $ev->x_root, $ev->y_root, 2, 2 );
	#use source item coordinates
	} elsif ($copy_item) {
		@dimensions = ( $copy_item->get('x') + 20, $copy_item->get('y') + 20, $self->{_items}{$copy_item}->get('width'), $self->{_items}{$copy_item}->get('height'));
	}
	
	my $pattern = $self->create_alpha;
	my $item    = Goo::Canvas::Rect->new(
		$self->{_canvas}->get_root_item, @dimensions,
		'fill-pattern' => $pattern,
		'line-dash'    => Goo::Canvas::LineDash->new( [ 5, 5 ] ),
		'line-width'   => 1,
		'stroke-color' => 'gray',
	);

	$self->{_current_new_item} = $item;
	$self->{_items}{$item} = $item;


	if ($ev) {
		$self->{_items}{$item}{orig_pixbuf} = $self->{_current_pixbuf}->copy;
		$self->{_items}{$item}{orig_pixbuf_filename} = $self->{_current_pixbuf_filename};
	} elsif ($copy_item) {
		$self->{_items}{$item}{orig_pixbuf} = $self->{_items}{$copy_item}{orig_pixbuf}->copy;
		$self->{_items}{$item}{orig_pixbuf_filename} = $self->{_items}{$copy_item}{orig_pixbuf_filename};
	}
	
	$self->{_items}{$item}{image}
		= Goo::Canvas::Image->new( 
		$self->{_canvas}->get_root_item, 
		$self->{_items}{$item}{orig_pixbuf}, 
		$item->get('x'), 
		$item->get('y'),
		'width' => 2,
		'height' => 2,
	);

	#set type flag
	$self->{_items}{$item}{type} = 'image';

	#create rectangles
	$self->handle_rects( 'create', $item );
	$self->handle_embedded('update', $item) if $copy_item;

	$self->setup_item_signals( $self->{_items}{$item}{image} );
	$self->setup_item_signals_extra( $self->{_items}{$item}{image} );

	$self->setup_item_signals( $self->{_items}{$item} );
	$self->setup_item_signals_extra( $self->{_items}{$item} );

	if ( $copy_item ){
		
		my $copy = Gtk2::Gdk::Pixbuf->new_from_file_at_scale($self->{_items}{$item}{orig_pixbuf_filename},$self->{_items}{$item}->get('width'), $self->{_items}{$item}->get('height'), FALSE);
				
		$self->{_items}{$item}{image}->set(
			'x'      => int $self->{_items}{$item}->get('x'),
			'y'      => int $self->{_items}{$item}->get('y'),
			'pixbuf' => $copy
		);
		
		$self->handle_rects( 'hide', $item );
		
	}	

	#add to undo stack
	$self->store_to_xdo_stack($item , 'create', 'undo');
	
	return TRUE;	
}

sub create_text{
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;

	my @dimensions = ( 0, 0, 0, 0 );
	my $stroke_pattern = $self->create_color( $self->{_stroke_color}, $self->{_stroke_color_alpha} );
	my $text = 'New Text...';
	my $line_width = $self->{_line_width};

	#use event coordinates and selected color
	if ($ev) {
		@dimensions = ( $ev->x_root, $ev->y_root, 2, 2 );
		#use source item coordinates and item color
	} elsif ($copy_item) {
		@dimensions = ( $copy_item->get('x') + 20, $copy_item->get('y') + 20, $copy_item->get('width'), $copy_item->get('height') );
		$stroke_pattern = $self->create_color( $self->{_items}{$copy_item}{stroke_color}, $self->{_items}{$copy_item}{stroke_color_alpha} );
		$text = $self->{_items}{$copy_item}{text}->get('text');
		$line_width = $self->{_items}{$copy_item}{text}->get('line-width');
	}

	my $pattern = $self->create_alpha;
	my $item    = Goo::Canvas::Rect->new(
		$self->{_canvas}->get_root_item, @dimensions,
		'fill-pattern' => $pattern,
		'line-dash'    => Goo::Canvas::LineDash->new( [ 5, 5 ] ),
		'line-width'   => 1,
		'stroke-color' => 'gray',
	);

	$self->{_current_new_item} = $item;
	$self->{_items}{$item} = $item;

	my $stroke_pattern = $self->create_color( $self->{_stroke_color}, $self->{_stroke_color_alpha} );

	$self->{_items}{$item}{text} = Goo::Canvas::Text->new(
		$self->{_canvas}->get_root_item, "<span font_desc='" . $self->{_font} . "' >".$text."</span>",
		$item->get('x'),
		$item->get('y'), $item->get('width'),
		'nw',
		'use-markup'   => TRUE,
		'fill-pattern' => $stroke_pattern,
		'line-width'   => $line_width,
		'visibility' => 'hidden'
	);

	#set type flag
	$self->{_items}{$item}{type} = 'text';

	$self->{_items}{$item}{stroke_color}       = $self->{_stroke_color};
	$self->{_items}{$item}{stroke_color_alpha} = $self->{_stroke_color_alpha};

	#create rectangles
	$self->handle_rects( 'create', $item );
	if ($copy_item){	
		$self->handle_embedded('update', $item); 
		$self->handle_rects('hide', $item); 	
	}

	$self->setup_item_signals( $self->{_items}{$item}{text} );
	$self->setup_item_signals_extra( $self->{_items}{$item}{text} );

	$self->setup_item_signals( $self->{_items}{$item} );
	$self->setup_item_signals_extra( $self->{_items}{$item} );

	#add to undo stack
	$self->store_to_xdo_stack($item , 'create', 'undo');
	
	return TRUE;
	
}	

sub create_line {
	my $self      			= shift;
	my $ev        			= shift;
	my $copy_item 			= shift;
	my $end_arrow 			= shift;
	my $start_arrow 		= shift;
	
	my @dimensions = ( 0, 0, 0, 0 );
	my $stroke_pattern = $self->create_color( $self->{_stroke_color}, $self->{_stroke_color_alpha} );
	my $line_width = $self->{_line_width};
	my $mirrored_w = 0;
	my $mirrored_h = 0;
	
	#default values
	my $arrow_width 		= 4;
	my $arrow_length 		= 5;
	my $arrow_tip_length 	= 4;
	
	#use event coordinates and selected color
	if ($ev) {
		@dimensions = ( $ev->x_root, $ev->y_root, 2, 2 );
		#use source item coordinates and item color
	} elsif ($copy_item) {
		@dimensions 		= ( $copy_item->get('x') + 20, $copy_item->get('y') + 20, $copy_item->get('width'), $copy_item->get('height') );
		$stroke_pattern 	= $self->create_color( $self->{_items}{$copy_item}{stroke_color}, $self->{_items}{$copy_item}{stroke_color_alpha} );
		$line_width  		= $self->{_items}{$copy_item}{line}->get('line-width');
		$mirrored_w  		= $self->{_items}{$copy_item}{mirrored_w};
		$mirrored_h  		= $self->{_items}{$copy_item}{mirrored_h};
		#arrow specific properties
		$end_arrow   		= $self->{_items}{$copy_item}{end_arrow};
		$start_arrow 		= $self->{_items}{$copy_item}{start_arrow};
		$arrow_width 		= $self->{_items}{$copy_item}{arrow_width};
		$arrow_length 		= $self->{_items}{$copy_item}{arrow_length};
		$arrow_tip_length 	= $self->{_items}{$copy_item}{arrow_tip_length};
	}

	my $pattern = $self->create_alpha;
	my $item    = Goo::Canvas::Rect->new(
		$self->{_canvas}->get_root_item, @dimensions,
		'fill-pattern' => $pattern,
		'line-dash'    => Goo::Canvas::LineDash->new( [ 5, 5 ] ),
		'line-width'   => 1,
		'stroke-color' => 'gray',
	);

	$self->{_current_new_item} = $item;
	$self->{_items}{$item} = $item;

	$self->{_items}{$item}{line} = Goo::Canvas::Polyline->new_line(
		$self->{_canvas}->get_root_item, 
		$item->get('x'), 
		$item->get('y'), 
		$item->get('x') + $item->get('width'),
		$item->get('y') + $item->get('height'),
		'stroke-pattern' 	=> $stroke_pattern,
		'line-width'     	=> $line_width,
		'line-cap'       	=> 'CAIRO_LINE_CAP_ROUND',
		'line-join'      	=> 'CAIRO_LINE_JOIN_ROUND',
		'end-arrow'      	=> $end_arrow,		
		'start-arrow'    	=> $start_arrow,
		'arrow-length'	 	=> $arrow_length,
		'arrow-width'	 	=> $arrow_width,
		'arrow-tip-length'	=> $arrow_tip_length,						
	);				
	
	if(defined $end_arrow || defined $start_arrow){
		#save arrow specific properties
		$self->{_items}{$item}{end_arrow} 			= $self->{_items}{$item}{line}->get('end-arrow');
		$self->{_items}{$item}{start_arrow} 		= $self->{_items}{$item}{line}->get('start-arrow');
		$self->{_items}{$item}{arrow_width} 		= $self->{_items}{$item}{line}->get('arrow-width');
		$self->{_items}{$item}{arrow_length} 		= $self->{_items}{$item}{line}->get('arrow-length');
		$self->{_items}{$item}{arrow_tip_length}	= $self->{_items}{$item}{line}->get('arrow-tip-length');
	}

	#set type flag
	$self->{_items}{$item}{type} = 'line';

	$self->{_items}{$item}{mirrored_w} = $mirrored_w;
	$self->{_items}{$item}{mirrored_h} = $mirrored_h;

	$self->{_items}{$item}{stroke_color}       = $self->{_stroke_color};
	$self->{_items}{$item}{stroke_color_alpha} = $self->{_stroke_color_alpha};

	#create rectangles
	$self->handle_rects( 'create', $item );
	if ($copy_item){	
		$self->handle_embedded('update', $item); 
		$self->handle_rects('hide', $item); 	
	}
	
	$self->setup_item_signals( $self->{_items}{$item}{line} );
	$self->setup_item_signals_extra( $self->{_items}{$item}{line} );

	$self->setup_item_signals( $self->{_items}{$item} );
	$self->setup_item_signals_extra( $self->{_items}{$item} );

	#add to undo stack
	$self->store_to_xdo_stack($item , 'create', 'undo');
	
	return TRUE;

}

sub create_ellipse {
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;

	my @dimensions = ( 0, 0, 0, 0 );
	my $stroke_pattern = $self->create_color( $self->{_stroke_color}, $self->{_stroke_color_alpha} );
	my $fill_pattern   = $self->create_color( $self->{_fill_color},   $self->{_fill_color_alpha} );
	my $line_width = $self->{_line_width};

	#use event coordinates and selected color
	if ($ev) {
		@dimensions = ( $ev->x_root, $ev->y_root, 2, 2 );
		#use source item coordinates and item color
	} elsif ($copy_item) {
		@dimensions = ( $copy_item->get('x') + 20, $copy_item->get('y') + 20, $copy_item->get('width'), $copy_item->get('height') );
		$stroke_pattern = $self->create_color( $self->{_items}{$copy_item}{stroke_color}, $self->{_items}{$copy_item}{stroke_color_alpha} );
		$fill_pattern   = $self->create_color( $self->{_items}{$copy_item}{fill_color},   $self->{_items}{$copy_item}{fill_color_alpha} );
		$line_width = $self->{_items}{$copy_item}{ellipse}->get('line-width');
	}

	my $pattern = $self->create_alpha;
	my $item    = Goo::Canvas::Rect->new(
		$self->{_canvas}->get_root_item, @dimensions,
		'fill-pattern' => $pattern,
		'line-dash'    => Goo::Canvas::LineDash->new( [ 5, 5 ] ),
		'line-width'   => 1,
		'stroke-color' => 'gray',
	);

	$self->{_current_new_item} = $item;
	$self->{_items}{$item} = $item;

	$self->{_items}{$item}{ellipse} = Goo::Canvas::Ellipse->new(
		$self->{_canvas}->get_root_item, $item->get('x'), $item->get('y'), $item->get('width'),
		$item->get('height'),
		'fill-pattern'   => $fill_pattern,
		'stroke-pattern' => $stroke_pattern,
		'line-width'     => $line_width,
	);

	#set type flag
	$self->{_items}{$item}{type} = 'ellipse';

	#save color and opacity as well
	$self->{_items}{$item}{fill_color}         = $self->{_fill_color};
	$self->{_items}{$item}{fill_color_alpha}   = $self->{_fill_color_alpha};
	$self->{_items}{$item}{stroke_color}       = $self->{_stroke_color};
	$self->{_items}{$item}{stroke_color_alpha} = $self->{_stroke_color_alpha};

	#create rectangles
	$self->handle_rects( 'create', $item );
	if ($copy_item){	
		$self->handle_embedded('update', $item); 
		$self->handle_rects('hide', $item); 	
	}

	$self->setup_item_signals( $self->{_items}{$item}{ellipse} );
	$self->setup_item_signals_extra( $self->{_items}{$item}{ellipse} );

	$self->setup_item_signals( $self->{_items}{$item} );
	$self->setup_item_signals_extra( $self->{_items}{$item} );

	#add to undo stack
	$self->store_to_xdo_stack($item , 'create', 'undo');
	
	return TRUE;

}


sub create_rectangle {
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;

	my @dimensions = ( 0, 0, 0, 0 );
	my $stroke_pattern = $self->create_color( $self->{_stroke_color}, $self->{_stroke_color_alpha} );
	my $fill_pattern   = $self->create_color( $self->{_fill_color},   $self->{_fill_color_alpha} );
	my $line_width = $self->{_line_width};

	#use event coordinates and selected color
	if ($ev) {
		@dimensions = ( $ev->x_root, $ev->y_root, 2, 2 );

		#use source item coordinates and item color
	} elsif ($copy_item) {
		@dimensions = ( $copy_item->get('x') + 20, $copy_item->get('y') + 20, $copy_item->get('width'), $copy_item->get('height') );
		$stroke_pattern = $self->create_color( $self->{_items}{$copy_item}{stroke_color}, $self->{_items}{$copy_item}{stroke_color_alpha} );
		$fill_pattern   = $self->create_color( $self->{_items}{$copy_item}{fill_color},   $self->{_items}{$copy_item}{fill_color_alpha} );
		$line_width = $self->{_items}{$copy_item}->get('line-width');
	}

	my $item = Goo::Canvas::Rect->new(
		$self->{_canvas}->get_root_item, @dimensions,
		'fill-pattern'   => $fill_pattern,
		'stroke-pattern' => $stroke_pattern,
		'line-width'     => $line_width,
	);

	$self->{_current_new_item} = $item;
	$self->{_items}{$item} = $item;

	#set type flag
	$self->{_items}{$item}{type} = 'rectangle';

	$self->{_items}{$item}{fill_color}         = $self->{_fill_color};
	$self->{_items}{$item}{fill_color_alpha}   = $self->{_fill_color_alpha};
	$self->{_items}{$item}{stroke_color}       = $self->{_stroke_color};
	$self->{_items}{$item}{stroke_color_alpha} = $self->{_stroke_color_alpha};

	#create rectangles
	$self->handle_rects( 'create', $item );

	$self->setup_item_signals( $self->{_items}{$item} );
	$self->setup_item_signals_extra( $self->{_items}{$item} );

	#add to undo stack
	$self->store_to_xdo_stack($item , 'create', 'undo');

	return TRUE;
}

1;
