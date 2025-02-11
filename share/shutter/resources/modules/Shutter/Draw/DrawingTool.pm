###################################################
#
#  Copyright (C) 2008-2013 Mario Kemper <mario.kemper@gmail.com>
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

#perl -x -S perltidy -l=0 -b "%f"

# Native Gtk3::IconSize doesn't work for some reason
# FIXME This package should be cleaned up when fixing DrawingTool
package Gtk3::IconSize;
sub lookup {
	my $self = shift;
	my $size = shift;
	Shutter::App::HelperFunctions->icon_size($size);
}

1;

package Shutter::Draw::DrawingTool;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use constant {
	DEFAULT_FONT => "Sans Regular 16"
};

use Gtk3;

use Exporter;
use GooCanvas2;
use GooCanvas2::CairoTypes;
use File::Basename qw/ fileparse dirname basename /;
use File::Glob qw/ bsd_glob /;
use File::Temp qw/ tempfile tempdir /;
use Data::Dumper;

#Sort::Naturally - sort lexically, but sort numeral parts numerically
use Sort::Naturally;

#load and save settings
use XML::Simple;

#Glib
use Glib qw/TRUE FALSE/;

require Shutter::Draw::Utils;
require Shutter::App::Directories;
require Shutter::Draw::UIManager;

#--------------------------------------

sub new {
	my $class = shift;

	my $self = {_sc => shift};
	$self->{_shf} = Shutter::App::HelperFunctions->new($self->{_sc});

	#view, selector, dragger
	$self->{_view}     = Gtk3::ImageView->new;
	$self->{_selector} = Gtk3::ImageView::Tool::Selector->new($self->{_view});
	$self->{_dragger}  = Gtk3::ImageView::Tool::Dragger->new($self->{_view});
	$self->{_view}->set_tool($self->{_selector});
	$self->{_view_css_provider_alpha} = Gtk3::CssProvider->new;
	$self->{_view}->get_style_context->add_provider($self->{_view_css_provider_alpha}, 0);
	$self->{_view}->set('zoom-step', 1.2);

	#WORKAROUND
	#upstream bug
	#http://trac.bjourne.webfactional.com/ticket/21
	#left  => zoom in
	#right => zoom out
	$self->{_view}->signal_connect(
		'scroll-event',
		sub {
			my ($view, $ev) = @_;
			if ($ev->direction eq 'left') {
				$ev->direction('up');
			} elsif ($ev->direction eq 'right') {
				$ev->direction('down');
			}
			return FALSE;
		});

	#handle zoom events
	#ignore zoom values greater 10 (see: #654185)
	$self->{_view}->signal_connect(
		'zoom-changed' => sub {
			my ($view, $zoom) = @_;
			if ($zoom >= 1) {
				$view->set_interpolation('nearest');
				$view->set_zoom(10) if $zoom > 10;
			} else {
				$view->set_interpolation('bilinear');
			}
		});

	#clipboard
	$self->{_clipboard} = Gtk3::Clipboard::get($Gtk3::Gdk::SELECTION_CLIPBOARD);

	#file
	$self->{_filename}    = undef;
	$self->{_filetype}    = undef;
	$self->{_mimetype}    = undef;
	$self->{_import_hash} = undef;

	#custom cursors
	$self->{_cursors} = undef;

	#ui
	$self->{_uimanager} = undef;
	$self->{_factory}   = undef;

	#canvas
	$self->{_canvas} = undef;

	#all items are stored here
	$self->{_uid}           = time;
	$self->{_items}         = undef;
	$self->{_items_history} = undef;

	#undo and redo stacks
	$self->{_undo} = undef;
	$self->{_redo} = undef;

	#autoscroll option, disabled by default
	$self->{_autoscroll} = FALSE;

	#drawing colors and line width
	#general - shown in the bottom hbox
	$self->{_fill_color}         = Gtk3::Gdk::RGBA::parse('#0000ff');
	$self->{_fill_color}->alpha(0.25);
	$self->{_stroke_color}       = Gtk3::Gdk::RGBA::parse('#ff0000');
	$self->{_stroke_color}->alpha(1);
	$self->{_line_width}         = 3;
	$self->{_font}               = DEFAULT_FONT;

	#obtain current colors and font_desc from the main window
	$self->{_style}    = $self->{_sc}->get_mainwindow->get_style_context;
	$self->{_style_bg} = $self->{_style}->get_background_color('selected');
	$self->{_style_bg}->alpha(1);
	#$self->{_style_tx} = $self->{_style}->text('selected');

	#remember drawing colors, line width and font settings
	#maybe we have to restore them
	$self->{_last_fill_color}         = Gtk3::Gdk::RGBA::parse('#0000ff');
	$self->{_last_fill_color}->alpha(0.25);
	$self->{_last_stroke_color}       = Gtk3::Gdk::RGBA::parse('#ff0000');
	$self->{_last_stroke_color}->alpha(1);
	$self->{_last_line_width}         = 3;
	$self->{_last_font}               = DEFAULT_FONT;

	#some status variables
	$self->{_busy}                    = undef;
	$self->{_current_item}            = undef;
	$self->{_current_new_item}        = undef;
	$self->{_current_copy_item}       = undef;
	$self->{_last_mode}               = 10;
	$self->{_current_mode}            = 10;
	$self->{_current_mode_descr}      = "select";
	$self->{_current_pixbuf}          = undef;
	$self->{_current_pixbuf_filename} = undef;
	$self->{_cut}                     = FALSE;

	$self->{_start_time} = undef;

	$self->{_stipple_pixbuf} = Gtk3::Gdk::Pixbuf->new_from_file($self->{_sc}->get_root . '/share/shutter/resources/gui/stipple.png');

	bless $self, $class;

	return $self;
}

#~ sub DESTROY {
#~ my $self = shift;
#~ print "$self dying at\n";
#~ }

sub show {
	my $self = shift;

	$self->{_filename}    = shift;
	$self->{_filetype}    = shift;
	$self->{_mimetype}    = shift;
	$self->{_name}        = shift;
	$self->{_is_unsaved}  = shift;
	$self->{_import_hash} = shift;

	#gettext
	$self->{_d} = $self->{_sc}->get_gettext;

	#define own icons
	$self->{_dicons} = $self->{_sc}->get_root . "/share/shutter/resources/icons/drawing_tool";
	$self->{_icons}  = $self->{_sc}->get_root . "/share/shutter/resources/icons";

	#MAIN WINDOW
	#-------------------------------------------------
	$self->{_root} = Gtk3::Gdk::get_default_root_window();
	($self->{_root}->{x}, $self->{_root}->{y}, $self->{_root}->{w}, $self->{_root}->{h}) = $self->{_root}->get_geometry;
	($self->{_root}->{x}, $self->{_root}->{y}) = $self->{_root}->get_origin;

	$self->{_drawing_window} = Gtk3::Window->new('toplevel');
	if (defined $self->{_is_unsaved} && $self->{_is_unsaved}) {
		$self->{_drawing_window}->set_title("*" . $self->{_name} . " - Shutter DrawingTool");
	} else {
		$self->{_drawing_window}->set_title($self->{_filename} . " - Shutter DrawingTool");
	}
	$self->{_drawing_window}->set_position('center');
	$self->{_drawing_window}->set_modal(1);
	$self->{_drawing_window}->signal_connect('delete_event', sub { return $self->quit(TRUE) });

	#adjust toplevel window size
	if ($self->{_root}->{w} > 640 && $self->{_root}->{h} > 480) {
		$self->{_drawing_window}->set_default_size(640, 480);
	} else {
		$self->{_drawing_window}->set_default_size($self->{_root}->{w} - 100, $self->{_root}->{h} - 100);
	}

	#dialogs, thumbnail generator and pixbuf loader
	$self->{_dialogs} = Shutter::App::SimpleDialogs->new($self->{_drawing_window});
	$self->{_lp}      = Shutter::Pixbuf::Load->new($self->{_sc}, $self->{_drawing_window});
	$self->{_lp_ne}   = Shutter::Pixbuf::Load->new($self->{_sc}, $self->{_drawing_window}, TRUE);

	#setup cursor-hash
	#
	#cursors borrowed from inkscape
	#http://www.inkscape.org
	my @cursors = bsd_glob($self->{_dicons} . "/cursor/*");
	foreach my $cursor_path (@cursors) {
		my ($cname, $folder, $type) = fileparse($cursor_path, qr/\.[^.]*/);
		$self->{_cursors}{$cname} = Gtk3::Gdk::Pixbuf->new_from_file($cursor_path);

		#see 'man xcursor' for a detailed description
		#of these values
		$self->{_cursors}{$cname}{'x_hot'} = $self->{_cursors}{$cname}->get_option('x_hot');
		$self->{_cursors}{$cname}{'y_hot'} = $self->{_cursors}{$cname}->get_option('y_hot');
	}

	#setu ui
	$self->{_uimanager} = $self->setup_uimanager();

	#load settings
	$self->load_settings;

	#load file
	$self->{_drawing_pixbuf} = $self->{_lp}->load($self->{_filename}, undef, undef, undef, TRUE);
	unless ($self->{_drawing_pixbuf}) {
		$self->{_drawing_window}->destroy if $self->{_drawing_window};
		return FALSE;
	}

	#CANVAS
	#-------------------------------------------------
	$self->{_canvas} = GooCanvas2::Canvas->new();

	#enable dnd for it
	$self->{_canvas}->drag_dest_set('all', [Gtk3::TargetEntry->new('text/uri-list', [], 0)], 'copy');
	$self->{_canvas}->signal_connect(drag_data_received => sub { $self->import_from_dnd(@_) });
	$self->{_canvas}->signal_connect(drag_motion => sub {
		my ($view, $ctx, $x, $y, $time) = @_;
		for my $target (@{$ctx->list_targets}) {
			if ($target->name eq 'text/uri-list') {
				Gtk3::Gdk::drag_status($ctx, 'copy', $time);
				return TRUE;
			}
		}
		return FALSE;
	});

	#'redraw-when-scrolled' to reduce the flicker of static items
	#
	#this property is not available in older versions
	#it was added to goocanvas on Mon Nov 17 10:28:07 2008 UTC
	#http://svn.gnome.org/viewvc/goocanvas?view=revision&revision=28
	if ($self->{_canvas}->find_property('redraw-when-scrolled')) {
		$self->{_canvas}->set('redraw-when-scrolled' => TRUE);
	}

	#~ my $bg = Gtk3::Gdk::RGBA::parse('gray');
	$self->{_canvas}->set(
		'automatic-bounds'   => FALSE,
		'bounds-from-origin' => FALSE,

		#~ 'background-color' 		=> sprintf( "#%04x%04x%04x", $bg->red, $bg->green, $bg->blue ),
	);

	#and attach scroll event
	#to imitate scroll behavior of
	#Gtk3::ImageView widget Ctrl+Mouse Wheel
	$self->{_canvas}->signal_connect(
		'scroll-event' => sub {
			my ($canvas, $ev) = @_;

			my $alloc = $self->{_canvas}->get_allocation;
			my $scale = $canvas->get_scale;

			if ($ev->state >= 'control-mask' && ($ev->direction eq 'up' || $ev->direction eq 'left')) {
				$self->zoom_in_cb;
				$canvas->scroll_to(int($ev->x - $alloc->{width} / 2) / $scale, int($ev->y - $alloc->{height} / 2) / $scale);
				return TRUE;
			} elsif ($ev->state >= 'control-mask' && ($ev->direction eq 'down' || $ev->direction eq 'right')) {
				$self->zoom_out_cb;
				return TRUE;
			}
			return FALSE;
		});

	#create rectangle to resize the background
	$self->{_canvas_bg_rect} = GooCanvas2::CanvasRect->new(
		parent=>$self->{_canvas}->get_root_item, x=>0, y=>0, width=>$self->{_drawing_pixbuf}->get_width, height=>$self->{_drawing_pixbuf}->get_height,
		'fill-color-gdk-rgba' => Gtk3::Gdk::RGBA::parse('gray'),
		'line-dash'    => GooCanvas2::CanvasLineDash->newv([5, 5]),
		'line-width'   => 1,
		'stroke-color' => 'black',
	);

	#save color
	$self->{_canvas_bg_rect}{fill_color} = Gtk3::Gdk::RGBA::parse('gray');
	$self->setup_item_signals($self->{_canvas_bg_rect});

	$self->handle_bg_rects('create');
	$self->handle_bg_rects('update');

	#~ #create canvas background (:= screenshot)
	#~ $self->{_canvas_bg} = Goo::Canvas::Image->new(
	#~ $self->{_canvas}->get_root_item,
	#~ $self->{_drawing_pixbuf},
	#~ 0, 0,
	#~ );
	#~ $self->setup_item_signals( $self->{_canvas_bg} );

	#set variables
	$self->{_current_pixbuf_filename} = $self->{_filename};
	$self->{_current_pixbuf}          = $self->{_drawing_pixbuf};

	#construct an event and create a new image object
	my $initevent = Gtk3::Gdk::Event->new('motion-notify');
	$initevent->time(Gtk3::get_current_event_time());
	$initevent->window($self->{_drawing_window}->get_window);
	$initevent->x(int($self->{_canvas_bg_rect}->get('width') / 2));
	$initevent->y(int($self->{_canvas_bg_rect}->get('height') / 2));

	#new item
	my $nitem = $self->create_image($initevent, undef, TRUE);
	$self->{_canvas_bg} = $self->{_items}{$nitem}{image};

	#this item is locked at first
	$self->{_items}{$nitem}{locked} = FALSE;

	$self->handle_bg_rects('raise');

	#PACKING
	#-------------------------------------------------
	$self->{_drawing_vbox}         = Gtk3::VBox->new(FALSE, 0);
	$self->{_drawing_inner_vbox}   = Gtk3::VBox->new(FALSE, 0);
	$self->{_drawing_inner_vbox_c} = Gtk3::VBox->new(FALSE, 0);
	$self->{_drawing_hbox}         = Gtk3::HBox->new(FALSE, 0);
	$self->{_drawing_hbox_c}       = Gtk3::HBox->new(FALSE, 0);

	#mark some actions as important
	$self->{_uimanager}->get_widget("/ToolBar/Close")->set_is_important(TRUE);
	$self->{_uimanager}->get_widget("/ToolBar/Save")->set_is_important(TRUE);
	$self->{_uimanager}->get_widget("/ToolBar/Undo")->set_is_important(TRUE);

	#disable undo/redo actions at startup
	$self->{_uimanager}->get_widget("/MenuBar/Edit/Undo")->set_sensitive(FALSE);
	$self->{_uimanager}->get_widget("/MenuBar/Edit/Redo")->set_sensitive(FALSE);

	$self->{_uimanager}->get_widget("/ToolBar/Undo")->set_sensitive(FALSE);
	$self->{_uimanager}->get_widget("/ToolBar/Redo")->set_sensitive(FALSE);

	$self->{_drawing_window}->add($self->{_drawing_vbox});

	my $menubar = $self->{_uimanager}->get_widget("/MenuBar");
	$self->{_drawing_vbox}->pack_start($menubar, FALSE, FALSE, 0);

	my $toolbar_drawing = $self->{_uimanager}->get_widget("/ToolBarDrawing");
	$toolbar_drawing->set_orientation('vertical');
	$toolbar_drawing->set_style('icons');
	$toolbar_drawing->set_icon_size('menu');
	$toolbar_drawing->set_show_arrow(FALSE);
	$self->{_drawing_hbox}->pack_start($toolbar_drawing, FALSE, FALSE, 0);

	#DRAWING TOOL CONTAINER
	#-------------------------------------------------
	#scrolled window for the canvas
	$self->{_scrolled_window} = Gtk3::ScrolledWindow->new;
	$self->{_scrolled_window}->set_policy('automatic', 'automatic');
	$self->{_scrolled_window}->add($self->{_canvas});
	$self->{_hscroll_hid} = $self->{_scrolled_window}->get_hscrollbar->signal_connect('value-changed' => sub { $self->adjust_rulers });
	$self->{_vscroll_hid} = $self->{_scrolled_window}->get_vscrollbar->signal_connect('value-changed' => sub { $self->adjust_rulers });

	#vruler
	#$self->{_vruler} = Gtk3::VRuler->new;
	#$self->{_vruler}->set_metric('pixels');
	#$self->{_vruler}->set_range(0, $self->{_drawing_pixbuf}->get_height, 0, $self->{_drawing_pixbuf}->get_height);

	#hruler
	#$self->{_hruler} = Gtk3::HRuler->new;
	#$self->{_hruler}->set_metric('pixels');
	#$self->{_hruler}->set_range(0, $self->{_drawing_pixbuf}->get_width, 0, $self->{_drawing_pixbuf}->get_width);

	#create a table for placing the ruler and scrolle window
	$self->{_table} = Gtk3::Table->new(3, 2, FALSE);

	#attach scrolled window and rulers to the table
	$self->{_table}->attach($self->{_scrolled_window}, 1, 2, 1, 2, ['expand', 'fill'], ['expand', 'fill'], 0, 0);
	#$self->{_table}->attach($self->{_hruler}, 1, 2, 0, 1, ['expand', 'shrink', 'fill'], [], 0, 0);
	#$self->{_table}->attach($self->{_vruler}, 0, 1, 1, 2, [], ['fill', 'expand', 'shrink'], 0, 0);

	$self->{_bhbox} = $self->setup_bottom_hbox;
	$self->{_drawing_inner_vbox}->pack_start($self->{_table}, TRUE,  TRUE, 0);
	$self->{_drawing_inner_vbox}->pack_start($self->{_bhbox}, FALSE, TRUE, 0);

	#CROPPING TOOL CONTAINER
	#-------------------------------------------------
	#scrolled window for the cropping tool
	#$self->{_scrolled_window_c} = Gtk3::ImageView::ScrollWin->new($self->{_view});
	$self->{_scrolled_window_c} = Gtk3::ScrolledWindow->new;
	$self->{_scrolled_window_c}->add_with_viewport($self->{_view});
	($self->{_rframe_c}, $self->{_btn_ok_c}) = $self->setup_right_vbox_c;
	$self->{_drawing_hbox_c}->pack_start($self->{_scrolled_window_c}, TRUE,  TRUE,  0);
	$self->{_drawing_hbox_c}->pack_start($self->{_rframe_c},          FALSE, FALSE, 3);

	$self->{_drawing_inner_vbox_c}->pack_start($self->{_drawing_hbox_c}, TRUE, TRUE, 0);

	#MAIN CONTAINER
	#-------------------------------------------------
	#pack both containers to the main hbox
	$self->{_drawing_hbox}->pack_start($self->{_drawing_inner_vbox},   TRUE, TRUE, 0);
	$self->{_drawing_hbox}->pack_start($self->{_drawing_inner_vbox_c}, TRUE, TRUE, 0);

	$self->{_drawing_vbox}->pack_start($self->{_uimanager}->get_widget("/ToolBar"), FALSE, FALSE, 0);
	$self->{_drawing_vbox}->pack_start($self->{_drawing_hbox},                      TRUE,  TRUE,  0);

	#statusbar
	$self->{_drawing_statusbar}       = Gtk3::Statusbar->new;
	$self->{_drawing_statusbar_image} = Gtk3::Image->new;
	$self->{_drawing_statusbar}->pack_start($self->{_drawing_statusbar_image}, FALSE, FALSE, 3);
	$self->{_drawing_statusbar}->reorder_child($self->{_drawing_statusbar_image}, 0);
	$self->{_drawing_vbox}->pack_start($self->{_drawing_statusbar}, FALSE, FALSE, 6);

	$self->{_drawing_window}->show_all();

	#STARTUP PROCEDURE
	#-------------------------------------------------
	$self->{_drawing_window}->get_window->focus(Gtk3::get_current_event_time());

	$self->adjust_rulers;

	#save start time to show in close dialog
	$self->{_start_time} = time;

	#remember drawing colors, line width and font settings
	#maybe we have to restore them
	$self->{_last_fill_color}         = $self->{_fill_color_w}->get_rgba;
	$self->{_last_stroke_color}       = $self->{_stroke_color_w}->get_rgba;
	$self->{_last_line_width}         = $self->{_line_spin_w}->get_value;
	$self->{_last_font}               = $self->{_font_btn_w}->get_font_name;

	#init last mode
	$self->{_last_mode} = 0;

	#init current tool
	$self->set_drawing_action(int($self->{_current_mode} / 10));

	#do show these actions because the user would be confused
	#to see multiple shortcuts to handle zooming
	#controlequal is used for english keyboard layouts for example
	$self->{_uimanager}->get_action("/MenuBar/View/ControlEqual")->set_visible(FALSE);
	$self->{_uimanager}->get_action("/MenuBar/View/ControlKpAdd")->set_visible(FALSE);
	$self->{_uimanager}->get_action("/MenuBar/View/ControlKpSub")->set_visible(FALSE);

	#start with everything deactivated
	$self->deactivate_all;

	Gtk3->main;

	return TRUE;
}

sub setup_bottom_hbox {
	my $self = shift;

	my $drawing_bottom_hbox = Gtk3::HBox->new(FALSE, 5);

	#fill color
	my $fill_color_label = Gtk3::Label->new($self->{_d}->get("Fill color") . ":");
	$self->{_fill_color_w} = Gtk3::ColorButton->new();
	$self->{_fill_color_w}->set_rgba($self->{_fill_color});
	$self->{_fill_color_w}->set_use_alpha(TRUE);
	$self->{_fill_color_w}->set_title($self->{_d}->get("Choose fill color"));

	$fill_color_label->set_tooltip_text($self->{_d}->get("Adjust fill color and opacity"));
	$self->{_fill_color_w}->set_tooltip_text($self->{_d}->get("Adjust fill color and opacity"));

	$drawing_bottom_hbox->pack_start($fill_color_label,      FALSE, FALSE, 5);
	$drawing_bottom_hbox->pack_start($self->{_fill_color_w}, FALSE, FALSE, 5);

	#stroke color
	my $stroke_color_label = Gtk3::Label->new($self->{_d}->get("Stroke color") . ":");
	$self->{_stroke_color_w} = Gtk3::ColorButton->new();
	$self->{_stroke_color_w}->set_rgba($self->{_stroke_color});
	$self->{_stroke_color_w}->set_use_alpha(TRUE);
	$self->{_stroke_color_w}->set_title($self->{_d}->get("Choose stroke color"));

	$stroke_color_label->set_tooltip_text($self->{_d}->get("Adjust stroke color and opacity"));
	$self->{_stroke_color_w}->set_tooltip_text($self->{_d}->get("Adjust stroke color and opacity"));

	$drawing_bottom_hbox->pack_start($stroke_color_label,      FALSE, FALSE, 5);
	$drawing_bottom_hbox->pack_start($self->{_stroke_color_w}, FALSE, FALSE, 5);

	#line_width
	my $linew_label = Gtk3::Label->new($self->{_d}->get("Line width") . ":");
	$self->{_line_spin_w} = Gtk3::SpinButton->new_with_range(0.5, 20, 0.1);
	$self->{_line_spin_w}->set_value($self->{_line_width});

	$linew_label->set_tooltip_text($self->{_d}->get("Adjust line width"));
	$self->{_line_spin_w}->set_tooltip_text($self->{_d}->get("Adjust line width"));

	$drawing_bottom_hbox->pack_start($linew_label,          FALSE, FALSE, 5);
	$drawing_bottom_hbox->pack_start($self->{_line_spin_w}, FALSE, FALSE, 5);

	#font button
	my $font_label = Gtk3::Label->new($self->{_d}->get("Font") . ":");
	$self->{_font_btn_w} = Gtk3::FontButton->new();
	$self->{_font_btn_w}->set_font_name($self->{_font});

	$font_label->set_tooltip_text($self->{_d}->get("Select font family and size"));
	$self->{_font_btn_w}->set_tooltip_text($self->{_d}->get("Select font family and size"));

	$drawing_bottom_hbox->pack_start($font_label,          FALSE, FALSE, 5);
	$drawing_bottom_hbox->pack_start($self->{_font_btn_w}, FALSE, FALSE, 5);

	#image button
	my $image_label = Gtk3::Label->new($self->{_d}->get("Insert image") . ":");
	my $image_btn   = Gtk3::MenuToolButton->new(undef, undef);

	Glib::Idle->add(
		sub {
			$image_btn->set_menu($self->import_from_filesystem($image_btn));
			return FALSE;
		});

	#handle property changes
	#changes are applied directly to the current item
	$self->{_line_spin_wh} = $self->{_line_spin_w}->signal_connect(
		'value-changed' => sub {
			$self->{_line_width} = $self->{_line_spin_w}->get_value;

			if ($self->{_current_item}) {

				#apply all changes directly
				my $item = $self->{_current_item};
				if (my $child = $self->get_child_item($item)) {
					$item = $child;
				}
				my $parent = $self->get_parent_item($item);

				#determine key for item hash
				my $key = $self->get_item_key($item, $parent);

				$self->apply_properties($item, $parent, $key, $self->{_fill_color_w}, $self->{_stroke_color_w}, $self->{_line_spin_w}, $self->{_stroke_color_w}, $self->{_font_btn_w});

			}

		});

	$self->{_stroke_color_wh} = $self->{_stroke_color_w}->signal_connect(
		'color-set' => sub {
			$self->{_stroke_color}       = $self->{_stroke_color_w}->get_rgba;

			if ($self->{_current_item}) {

				#apply all changes directly
				my $item = $self->{_current_item};
				if (my $child = $self->get_child_item($item)) {
					$item = $child;
				}
				my $parent = $self->get_parent_item($item);

				#determine key for item hash
				my $key = $self->get_item_key($item, $parent);

				$self->apply_properties($item, $parent, $key, $self->{_fill_color_w}, $self->{_stroke_color_w}, $self->{_line_spin_w}, $self->{_stroke_color_w}, $self->{_font_btn_w});

			}

		});

	$self->{_fill_color_wh} = $self->{_fill_color_w}->signal_connect(
		'color-set' => sub {
			$self->{_fill_color}       = $self->{_fill_color_w}->get_rgba;

			if ($self->{_current_item}) {

				#apply all changes directly
				my $item = $self->{_current_item};
				if (my $child = $self->get_child_item($item)) {
					$item = $child;
				}
				my $parent = $self->get_parent_item($item);

				#determine key for item hash
				my $key = $self->get_item_key($item, $parent);

				$self->apply_properties($item, $parent, $key, $self->{_fill_color_w}, $self->{_stroke_color_w}, $self->{_line_spin_w}, $self->{_stroke_color_w}, $self->{_font_btn_w});

			}

		});

	$self->{_font_btn_wh} = $self->{_font_btn_w}->signal_connect(
		'font-set' => sub {
			my $font_descr = Pango::FontDescription->from_string($self->{_font_btn_w}->get_font_name);
			$self->{_font} = $self->{_font_btn_w}->get_font_name;

			if ($self->{_current_item}) {

				#apply all changes directly
				my $item = $self->{_current_item};
				if (my $child = $self->get_child_item($item)) {
					$item = $child;
				}
				my $parent = $self->get_parent_item($item);

				#determine key for item hash
				my $key = $self->get_item_key($item, $parent);

				$self->apply_properties($item, $parent, $key, $self->{_fill_color_w}, $self->{_stroke_color_w}, $self->{_line_spin_w}, $self->{_stroke_color_w}, $self->{_font_btn_w});

			}

		});

	$image_btn->signal_connect(
		'clicked' => sub {
			$self->{_canvas}->get_window->set_cursor($self->change_cursor_to_current_pixbuf);
		});

	$image_label->set_tooltip_text($self->{_d}->get("Insert an arbitrary object or file"));
	$image_btn->set_tooltip_text($self->{_d}->get("Insert an arbitrary object or file"));

	$drawing_bottom_hbox->pack_start($image_label, FALSE, FALSE, 5);
	$drawing_bottom_hbox->pack_start($image_btn,   FALSE, FALSE, 5);

	return $drawing_bottom_hbox;
}

sub setup_right_vbox_c {
	my $self = shift;

	my $cropping_bottom_vbox = Gtk3::VBox->new(FALSE, 5);

	#get current pixbuf
	my $pixbuf = $self->{_view}->get_pixbuf || $self->{_drawing_pixbuf};

	my $value_callback = sub {
		$self->{_selector}->set_selection({x=>$self->{_x_spin_w}->get_value, y=>$self->{_y_spin_w}->get_value, width=>$self->{_width_spin_w}->get_value, height=>$self->{_height_spin_w}->get_value});
	};

	#X
	my $xw_label = Gtk3::Label->new($self->{_d}->get("X") . ":");
	$self->{_x_spin_w} = Gtk3::SpinButton->new_with_range(0, $pixbuf->get_width, 1);
	$self->{_x_spin_w}->set_value(0);
	$self->{_x_spin_w_handler} = $self->{_x_spin_w}->signal_connect(
		'value-changed' => $value_callback);

	my $xw_hbox = Gtk3::HBox->new(FALSE, 5);
	$xw_hbox->pack_start($xw_label,          FALSE, FALSE, 5);
	$xw_hbox->pack_start($self->{_x_spin_w}, FALSE, FALSE, 5);

	#y
	my $yw_label = Gtk3::Label->new($self->{_d}->get("Y") . ":");
	$self->{_y_spin_w} = Gtk3::SpinButton->new_with_range(0, $pixbuf->get_height, 1);
	$self->{_y_spin_w}->set_value(0);
	$self->{_y_spin_w_handler} = $self->{_y_spin_w}->signal_connect(
		'value-changed' => $value_callback);

	my $yw_hbox = Gtk3::HBox->new(FALSE, 5);
	$yw_hbox->pack_start($yw_label,          FALSE, FALSE, 5);
	$yw_hbox->pack_start($self->{_y_spin_w}, FALSE, FALSE, 5);

	#width
	my $widthw_label = Gtk3::Label->new($self->{_d}->get("Width") . ":");
	$self->{_width_spin_w} = Gtk3::SpinButton->new_with_range(0, $pixbuf->get_width, 1);
	$self->{_width_spin_w}->set_value(0);
	$self->{_width_spin_w_handler} = $self->{_width_spin_w}->signal_connect(
		'value-changed' => $value_callback);

	my $ww_hbox = Gtk3::HBox->new(FALSE, 5);
	$ww_hbox->pack_start($widthw_label,          FALSE, FALSE, 5);
	$ww_hbox->pack_start($self->{_width_spin_w}, FALSE, FALSE, 5);

	#height
	my $heightw_label = Gtk3::Label->new($self->{_d}->get("Height") . ":");
	$self->{_height_spin_w} = Gtk3::SpinButton->new_with_range(0, $pixbuf->get_height, 1);
	$self->{_height_spin_w}->set_value(0);
	$self->{_height_spin_w_handler} = $self->{_height_spin_w}->signal_connect(
		'value-changed' => $value_callback);

	my $hw_hbox = Gtk3::HBox->new(FALSE, 5);
	$hw_hbox->pack_start($heightw_label,          FALSE, FALSE, 5);
	$hw_hbox->pack_start($self->{_height_spin_w}, FALSE, FALSE, 5);

	#the above values are changed when the selection is changed
	$self->{_selector_handler} = $self->{_selector}->signal_connect(
		'selection-changed' => sub {
			$self->adjust_crop_values($pixbuf);
		});

	#cancel button
	my $crop_c = Gtk3::Button->new_from_stock('gtk-cancel');
	$crop_c->signal_connect('clicked' => sub { $self->abort_current_mode });

	#crop button
	my $crop_ok = Gtk3::Button->new_with_mnemonic($self->{_d}->get("_Crop"));
	$crop_ok->set_image(Gtk3::Image->new_from_file($self->{_dicons} . '/transform-crop.png'));
	$crop_ok->signal_connect(
		'clicked' => sub {

			my $s = $self->{_selector}->get_selection;
			my $p = $self->{_view}->get_pixbuf;

			if ($s && $p) {

				#add to undo stack
				$self->store_to_xdo_stack($self->{_canvas_bg}, 'modify', 'undo', $s);

				#create new pixbuf
				#create temp pixbuf because selected area might be bigger than
				#source pixbuf (screenshot) => canvas area is resizeable
				my $temp = Gtk3::Gdk::Pixbuf->new($self->{_drawing_pixbuf}->get_colorspace, TRUE, 8, $p->get_width, $p->get_height);

				#whole pixbuf is transparent
				$temp->fill(0x00000000);

				#copy source image to temp pixbuf (temp pixbuf's size == $self->{_view}->get_pixbuf)
				$self->{_drawing_pixbuf}->copy_area(0, 0, $self->{_drawing_pixbuf}->get_width, $self->{_drawing_pixbuf}->get_height, $temp, 0, 0);

				#and create a new subpixbuf from the temp pixbuf
				my $new_p = $temp->new_subpixbuf($s->{x}, $s->{y}, $s->{width}, $s->{height});
				$self->{_drawing_pixbuf} = $new_p->copy;

				#update bounds and bg_rects
				$self->{_canvas_bg_rect}->set('width' => $s->{width}, 'height' => $s->{height});
				$self->handle_bg_rects('update');

				#update canvas and show the new pixbuf
				$self->{_canvas_bg}->set('pixbuf' => $new_p);

				#now move all items,
				#so they are in the right position
				#~ print $s->x ." - ".$s->y."\n";
				$self->move_all($s->{x}, $s->{y});

				#adjust stack order
				$self->{_canvas_bg}->lower;
				$self->{_canvas_bg_rect}->lower;
				$self->handle_bg_rects('raise');

			} else {

				#nothing here right now
			}

			#finally reset mode to select tool
			$self->abort_current_mode;

		});

	#put buttons in a separated box
	#all buttons = one size
	my $sg_butt = Gtk3::SizeGroup->new('vertical');
	$sg_butt->add_widget($crop_c);
	$sg_butt->add_widget($crop_ok);

	my $cropping_bottom_vbox_b = Gtk3::VBox->new(FALSE, 5);
	$cropping_bottom_vbox_b->pack_start($crop_c,  FALSE, FALSE, 0);
	$cropping_bottom_vbox_b->pack_start($crop_ok, FALSE, FALSE, 0);

	#final_packing
	#all labels = one size
	$xw_label->set_alignment(0, 0.5);
	$yw_label->set_alignment(0, 0.5);
	$widthw_label->set_alignment(0, 0.5);
	$heightw_label->set_alignment(0, 0.5);

	my $sg_main = Gtk3::SizeGroup->new('horizontal');
	$sg_main->add_widget($xw_label);
	$sg_main->add_widget($yw_label);
	$sg_main->add_widget($widthw_label);
	$sg_main->add_widget($heightw_label);

	$cropping_bottom_vbox->pack_start($xw_hbox,                FALSE, FALSE, 3);
	$cropping_bottom_vbox->pack_start($yw_hbox,                FALSE, FALSE, 3);
	$cropping_bottom_vbox->pack_start($ww_hbox,                FALSE, FALSE, 3);
	$cropping_bottom_vbox->pack_start($hw_hbox,                FALSE, FALSE, 3);
	$cropping_bottom_vbox->pack_start($cropping_bottom_vbox_b, TRUE,  TRUE,  3);

	#nice frame as well
	my $crop_frame_label = Gtk3::Label->new;
	$crop_frame_label->set_markup("<b>" . $self->{_d}->get("Selection") . "</b>");

	my $crop_frame = Gtk3::Frame->new();
	$crop_frame->set_border_width(5);
	$crop_frame->set_label_widget($crop_frame_label);
	$crop_frame->set_shadow_type('none');

	$crop_frame->add($cropping_bottom_vbox);

	return ($crop_frame, $crop_ok);
}

sub adjust_crop_values {
	my $self   = shift;
	my $pixbuf = shift;

	#block 'value-change' handlers for widgets
	#so we do not apply the changes twice
	$self->{_x_spin_w}->signal_handler_block($self->{_x_spin_w_handler});
	$self->{_y_spin_w}->signal_handler_block($self->{_y_spin_w_handler});
	$self->{_width_spin_w}->signal_handler_block($self->{_width_spin_w_handler});
	$self->{_height_spin_w}->signal_handler_block($self->{_height_spin_w_handler});

	my $s = $self->{_selector}->get_selection;

	if ($s) {
		$self->{_x_spin_w}->set_value($s->{x});
		$self->{_x_spin_w}->set_range(0, $pixbuf->get_width - $s->{width});

		$self->{_y_spin_w}->set_value($s->{y});
		$self->{_y_spin_w}->set_range(0, $pixbuf->get_height - $s->{height});

		$self->{_width_spin_w}->set_value($s->{width});
		$self->{_width_spin_w}->set_range(0, $pixbuf->get_width - $s->{x});

		$self->{_height_spin_w}->set_value($s->{height});
		$self->{_height_spin_w}->set_range(0, $pixbuf->get_height - $s->{y});
	}

	#unblock 'value-change' handlers for widgets
	$self->{_x_spin_w}->signal_handler_unblock($self->{_x_spin_w_handler});
	$self->{_y_spin_w}->signal_handler_unblock($self->{_y_spin_w_handler});
	$self->{_width_spin_w}->signal_handler_unblock($self->{_width_spin_w_handler});
	$self->{_height_spin_w}->signal_handler_unblock($self->{_height_spin_w_handler});

	return TRUE;

}

sub push_tool_help_to_statusbar {
	my ($self, $x, $y, $action) = @_;

	#init $action if not defined
	$action = 'none' unless defined $action;

	#current event coordinates
	my $status_text = int($x) . " x " . int($y);

	if ($self->{_current_mode} == 10) {

		if ($action eq 'resize') {
			$status_text .= " " . $self->{_d}->get("Click-Drag to scale (try Control to scale uniformly)");
		} elsif ($action eq 'canvas_resize') {
			$status_text .= " " . $self->{_d}->get("Click-Drag to resize the canvas");
		}

	} elsif ($self->{_current_mode} == 20 || $self->{_current_mode} == 30) {

		$status_text .= " " . $self->{_d}->get("Click to paint (try Control or Shift for a straight line)");

	} elsif ($self->{_current_mode} == 40) {

		$status_text .= " " . $self->{_d}->get("Click-Drag to create a new straight line");

	} elsif ($self->{_current_mode} == 50) {

		$status_text .= " " . $self->{_d}->get("Click-Drag to create a new arrow");

	} elsif ($self->{_current_mode} == 60) {

		$status_text .= " " . $self->{_d}->get("Click-Drag to create a new rectangle");

	} elsif ($self->{_current_mode} == 70) {

		$status_text .= " " . $self->{_d}->get("Click-Drag to create a new ellipse");

	} elsif ($self->{_current_mode} == 80) {

		$status_text .= " " . $self->{_d}->get("Click-Drag to add a new text area");

	} elsif ($self->{_current_mode} == 90) {

		$status_text .= " " . $self->{_d}->get("Click to censor (try Control or Shift for a straight line)");

	} elsif ($self->{_current_mode} == 100) {

		$status_text .= " " . $self->{_d}->get("Click-Drag to create a pixelized region");

	} elsif ($self->{_current_mode} == 110) {

		$status_text .= " " . $self->{_d}->get("Click to add an auto-increment shape");

	} elsif ($self->{_current_mode} == 120) {

		#nothing to do here....

	}

	#update statusbar
	$self->show_status_message(1, $status_text);

	return TRUE;

}

sub show_status_message {
	my $self         = shift;
	my $index        = shift;
	my $status_text  = shift;
	my $status_image = shift;    #this is a stock-id

	#~ #remove old message and timer
	#~ $self->{_drawing_statusbar}->pop($index);
	#~ Glib::Source->remove ($self->{_drawing_statusbar}->{statusbar_timer}) if defined $self->{_drawing_statusbar}->{statusbar_timer};

	#new message and image
	if (defined $status_image) {
		$self->{_drawing_statusbar_image}->set_from_stock($status_image, 'menu');
	} else {
		$self->{_drawing_statusbar_image}->clear;
	}
	$self->{_drawing_statusbar}->push($index, $status_text);

	#~ #...and remove it
	#~ $self->{_drawing_statusbar}->{statusbar_timer} = Glib::Timeout->add(
	#~ 3000,
	#~ sub {
	#~ $self->{_drawing_statusbar}->pop($index) if defined $self->{_drawing_statusbar};
	#~ return FALSE;
	#~ }
	#~ );

	return TRUE;
}

sub change_drawing_tool_cb {
	my $self   = shift;
	my $action = shift;

	#~ print "change_drawing_tool_cb\n";

	eval { $self->{_current_mode} = $action->get_current_value; };
	if ($@) {
		$self->{_current_mode} = $action;
	}

	my $cursor = Gtk3::Gdk::Cursor->new('left-ptr');

	#tool is switched from "highlighter" OR censor to something else (excluding select tool)
	if (   $self->{_current_mode} != $self->{_last_mode}
		&& $self->{_current_mode} != 10
		&& $self->{_current_mode} != 30
		&& $self->{_current_mode} != 90
		&& $self->{_current_mode} != 100
		&& $self->{_current_mode} != 120)
	{

		$self->restore_drawing_properties;

	}

	#show drawing tool widgets
	if ($self->{_current_mode} != 120) {

		#show drawing tool widgets
		$self->{_table}->show_all;
		$self->{_bhbox}->show_all;

		$self->{_drawing_inner_vbox}->show_all;

		#hide cropping tool
		$self->{_drawing_inner_vbox_c}->hide;

	}

	#enable controls again
	$self->{_fill_color_w}->set_sensitive(TRUE);
	$self->{_stroke_color_w}->set_sensitive(TRUE);
	$self->{_line_spin_w}->set_sensitive(TRUE);
	$self->{_font_btn_w}->set_sensitive(TRUE);

	if ($self->{_current_mode} == 10) {

		$self->{_current_mode_descr} = "select";

	} elsif ($self->{_current_mode} == 20) {

		$self->{_current_mode_descr} = "freehand";

		#disable controls, because they are not useful
		$self->{_fill_color_w}->set_sensitive(FALSE);
		$self->{_font_btn_w}->set_sensitive(FALSE);

	} elsif ($self->{_current_mode} == 30) {

		$self->{_current_mode_descr} = "highlighter";
		$cursor = Gtk3::Gdk::Cursor->new('dotbox');

		#disable controls, because they are not useful
		$self->{_fill_color_w}->set_sensitive(FALSE);
		$self->{_font_btn_w}->set_sensitive(FALSE);

		#restore hard-coded highlighter properties
		$self->restore_fixed_properties($self->{_current_mode_descr});

	} elsif ($self->{_current_mode} == 40) {

		$self->{_current_mode_descr} = "line";

		#disable controls, because they are not useful
		$self->{_fill_color_w}->set_sensitive(FALSE);
		$self->{_font_btn_w}->set_sensitive(FALSE);

	} elsif ($self->{_current_mode} == 50) {

		$self->{_current_mode_descr} = "arrow";

		#disable controls, because they are not useful
		$self->{_fill_color_w}->set_sensitive(FALSE);
		$self->{_font_btn_w}->set_sensitive(FALSE);

	} elsif ($self->{_current_mode} == 60) {

		$self->{_current_mode_descr} = "rect";

		#disable controls, because they are not useful
		$self->{_font_btn_w}->set_sensitive(FALSE);

	} elsif ($self->{_current_mode} == 70) {

		$self->{_current_mode_descr} = "ellipse";

		#disable controls, because they are not useful
		$self->{_font_btn_w}->set_sensitive(FALSE);

	} elsif ($self->{_current_mode} == 80) {

		$self->{_current_mode_descr} = "text";

		#disable controls, because they are not useful
		$self->{_fill_color_w}->set_sensitive(FALSE);
		$self->{_line_spin_w}->set_sensitive(FALSE);

	} elsif ($self->{_current_mode} == 90) {

		$self->{_current_mode_descr} = "censor";

		#disable controls, because they are not useful when using the
		#censor tool
		$self->{_fill_color_w}->set_sensitive(FALSE);
		$self->{_stroke_color_w}->set_sensitive(FALSE);
		$self->{_line_spin_w}->set_sensitive(FALSE);
		$self->{_font_btn_w}->set_sensitive(FALSE);

		#restore hard-coded censor properties
		$self->restore_fixed_properties($self->{_current_mode_descr});

	} elsif ($self->{_current_mode} == 100) {

		$self->{_current_mode_descr} = "pixelize";

		#disable controls, because they are not useful when using the
		#pixelize tool
		$self->{_fill_color_w}->set_sensitive(FALSE);
		$self->{_stroke_color_w}->set_sensitive(FALSE);
		$self->{_line_spin_w}->set_sensitive(FALSE);
		$self->{_font_btn_w}->set_sensitive(FALSE);

	} elsif ($self->{_current_mode} == 110) {

		$self->{_current_mode_descr} = "number";

	} elsif ($self->{_current_mode} == 120) {

		$self->{_current_mode_descr} = "crop";

		#show cropping tool
		$self->{_view}->set_pixbuf($self->save(TRUE));
		$self->{_view}->set_zoom(1);

		#adjust transp color
		my $color_string = $self->{_canvas_bg_rect}{fill_color}->to_string;
		$self->{_view_css_provider_alpha}->load_from_data("
			.imageview.transparent {
				background-color: $color_string;
			}
		");

		$self->{_view}->show_all;

		$self->{_drawing_inner_vbox_c}->show_all;

		#hide drawing tool widgets
		$self->{_drawing_inner_vbox}->hide;

		#focus crop-ok-button
		$self->{_btn_ok_c}->grab_focus;

	}

	if ($self->{_canvas} && $self->{_canvas}->get_window) {

		if (exists $self->{_cursors}{$self->{_current_mode_descr}}) {
			$cursor = Gtk3::Gdk::Cursor->new_from_pixbuf(
				Gtk3::Gdk::Display::get_default(),                          $self->{_cursors}{$self->{_current_mode_descr}},
				$self->{_cursors}{$self->{_current_mode_descr}}{'x_hot'}, $self->{_cursors}{$self->{_current_mode_descr}}{'y_hot'},
			);
		}

		$self->{_canvas}->get_window->set_cursor($cursor);
	}

	return TRUE;
}

sub zoom_in_cb {
	my $self = shift;

	if ($self->{_current_mode_descr} ne "crop") {
		$self->{_canvas}->set_scale($self->{_canvas}->get_scale + 0.2);

		#~ $self->adjust_rulers;
	} else {
		$self->{_view}->zoom_in;
	}

	return TRUE;
}

sub zoom_out_cb {
	my $self = shift;

	if ($self->{_current_mode_descr} ne "crop") {
		my $new_scale = $self->{_canvas}->get_scale - 0.2;
		if ($new_scale < 0.2) {
			$self->{_canvas}->set_scale(0.2);
		} else {
			$self->{_canvas}->set_scale($new_scale);
		}

		#~ $self->adjust_rulers;
	} else {
		$self->{_view}->zoom_out;
	}

	return TRUE;
}

sub zoom_normal_cb {
	my $self = shift;

	if ($self->{_current_mode_descr} ne "crop") {
		$self->{_canvas}->set_scale(1);

		#~ $self->adjust_rulers;
	} else {
		$self->{_view}->set_zoom(1);
	}

	return TRUE;
}

sub adjust_rulers {
	return TRUE;
	my ($self, $ev, $item) = @_;

	my $s = $self->{_canvas}->get_scale;

	my ($hlower, $hupper, $hposition, $hmax_size) = $self->{_hruler}->get_range;
	my ($vlower, $vupper, $vposition, $vmax_size) = $self->{_vruler}->get_range;

	if ($ev) {

		my $copy_event = $ev->copy;

		#modify event to respect scrollbars and canvas scale
		$copy_event->x(($copy_event->x_root - $hlower) * $s);
		$copy_event->y(($copy_event->y_root - $vlower) * $s);

		$self->{_hruler}->signal_emit('motion-notify-event', $copy_event);
		$self->{_vruler}->signal_emit('motion-notify-event', $copy_event);

	} else {

		#modify rulers (e.g. done when scrolling or zooming)
		if ($self->{_hruler} && $self->{_hruler}) {

			my ($x, $y, $width, $height, $depth) = $self->{_canvas}->get_window->get_geometry;
			my $ha = $self->{_scrolled_window}->get_hadjustment->get_value / $s;
			my $va = $self->{_scrolled_window}->get_vadjustment->get_value / $s;

			$self->{_hruler}->set_range($ha, $ha + $width / $s,  0, $hmax_size);
			$self->{_vruler}->set_range($va, $va + $height / $s, 0, $vmax_size);

		}

	}

	return TRUE;
}

sub quit {
	my ($self, $show_warning) = @_;

	my ($name, $folder, $type) = fileparse($self->{_filename}, qr/\.[^.]*/);

	#save settings to a file in the shutter folder
	#is there already a .shutter folder?
	mkdir("$ENV{ 'HOME' }/.shutter")
		unless (-d "$ENV{ 'HOME' }/.shutter");

	if ($show_warning && (defined $self->{_undo} && scalar(@{$self->{_undo}}) > 0)) {

		#warn the user if there are any unsaved changes
		my $warn_dialog = Gtk3::MessageDialog->new($self->{_drawing_window}, [qw/modal destroy-with-parent/], 'other', 'none', undef);

		#set question text
		$warn_dialog->set('text' => sprintf($self->{_d}->get("Save the changes to image %s before closing?"), "'$name$type'"));

		#set text...
		$self->update_warning_text($warn_dialog);

		#...and update it
		my $id = Glib::Timeout->add(
			1000,
			sub {
				$self->update_warning_text($warn_dialog);
				return TRUE;
			});

		$warn_dialog->set('image' => Gtk3::Image->new_from_stock('gtk-save', 'dialog'));

		$warn_dialog->set('title' => $self->{_d}->get("Close") . " " . $name . $type);

		#don't save button
		my $dsave_btn = Gtk3::Button->new_with_mnemonic($self->{_d}->get("Do_n't save"));
		$dsave_btn->set_image(Gtk3::Image->new_from_stock('gtk-delete', 'button'));

		#cancel button
		my $cancel_btn = Gtk3::Button->new_from_stock('gtk-cancel');
		$cancel_btn->set_can_default(TRUE);

		#save button
		my $save_btn = Gtk3::Button->new_from_stock('gtk-save');

		$warn_dialog->add_action_widget($dsave_btn,  10);
		$warn_dialog->add_action_widget($cancel_btn, 20);
		$warn_dialog->add_action_widget($save_btn,   30);

		$warn_dialog->set_default_response(20);

		$warn_dialog->get_child->show_all;
		my $response = $warn_dialog->run;
		Glib::Source->remove($id);
		if ($response == 20) {
			$warn_dialog->destroy;
			return TRUE;
		} elsif ($response == 30) {
			$self->save();
		}

		$self->{_drawing_window}->hide if $self->{_drawing_window};
		$warn_dialog->hide;
		$warn_dialog->destroy;

	}

	$self->save_settings;

	if ($self->{_selector_handler}) {
		$self->{_selector}->signal_handler_disconnect($self->{_selector_handler});
	}

	$self->{_drawing_window}->hide if $self->{_drawing_window};

	$self->{_drawing_window}->destroy if $self->{_drawing_window};

	#remove statusbar timer
	Glib::Source->remove($self->{_drawing_statusbar}->{statusbar_timer}) if defined $self->{_drawing_statusbar}->{statusbar_timer};

	#delete hash entries to avoid any
	#possible circularity
	#
	#this would lead to a memory leak
	foreach (keys %{$self}) {
		delete $self->{$_};
	}

	Gtk3->main_quit();

	return FALSE;
}

sub update_warning_text {
	my ($self, $warn_dialog) = @_;

	my $minutes = int((time - $self->{_start_time}) / 60);
	$minutes = 1 if $minutes == 0;

	my $txt = $self->{_d}->nget(
		"If you don't save the image, changes from the last minute will be lost",
		"If you don't save the image, changes from the last %d minutes will be lost",
		$minutes
	);

	$txt = sprintf($txt, $minutes) if $minutes > 1;

	$warn_dialog->set(
		'secondary-text' => "$txt."
	);

	return TRUE;
}

sub load_settings {
	my $self = shift;

	my $shutter_hfunct = Shutter::App::HelperFunctions->new($self->{_sc});

	#settings file
	my $settingsfile = "$ENV{ HOME }/.shutter/drawingtool.xml";

	my $settings_xml;
	if ($shutter_hfunct->file_exists($settingsfile)) {
		eval {
			$settings_xml = XMLin(IO::File->new($settingsfile));

			#restore window state when maximized
			if (exists $settings_xml->{'drawing'}->{'state'} && defined $settings_xml->{'drawing'}->{'state'} && $settings_xml->{'drawing'}->{'state'} eq 'maximized') {
				$self->{_drawing_window}->maximize;
			}

			#window size and position
			if ($settings_xml->{'drawing'}->{'x'} && $settings_xml->{'drawing'}->{'y'}) {
				$self->{_drawing_window}->move($settings_xml->{'drawing'}->{'x'}, $settings_xml->{'drawing'}->{'y'});
			}

			if ($settings_xml->{'drawing'}->{'width'} && $settings_xml->{'drawing'}->{'height'}) {
				$self->{_drawing_window}->resize($settings_xml->{'drawing'}->{'width'}, $settings_xml->{'drawing'}->{'height'});
			}

			#current mode
			if ($settings_xml->{'drawing'}->{'mode'}) {
				$self->{_current_mode} = $settings_xml->{'drawing'}->{'mode'};
			}

			#autoscroll
			my $autoscroll_toggle = $self->{_uimanager}->get_widget("/MenuBar/Edit/Autoscroll");
			$autoscroll_toggle->set_active($settings_xml->{'drawing'}->{'autoscroll'});

			#drawing colors
			$self->{_fill_color}         = Gtk3::Gdk::RGBA::parse($settings_xml->{'drawing'}->{'fill_color'}) // Gtk3::Gdk::RGBA::parse('black');
			$self->{_fill_color}->alpha($settings_xml->{'drawing'}->{'fill_color_alpha'});
			$self->{_stroke_color}       = Gtk3::Gdk::RGBA::parse($settings_xml->{'drawing'}->{'stroke_color'}) // Gtk3::Gdk::RGBA::parse('black');
			$self->{_stroke_color}->alpha($settings_xml->{'drawing'}->{'stroke_color_alpha'});

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

	#hash to store settings
	my %settings;

	#window size and position
	if (defined $self->{_drawing_window}->get_window) {
		if ($self->{_drawing_window}->get_window->get_state eq 'GDK_WINDOW_STATE_MAXIMIZED') {
			$settings{'drawing'}->{'state'} = 'maximized';
		}
	}

	my ($w, $h) = $self->{_drawing_window}->get_size;
	my ($x, $y) = $self->{_drawing_window}->get_position;
	$settings{'drawing'}->{'x'}      = $x;
	$settings{'drawing'}->{'y'}      = $y;
	$settings{'drawing'}->{'width'}  = $w;
	$settings{'drawing'}->{'height'} = $h;

	#current action
	#but don't save the crop tool as last action
	#as it would be confusing to open the drawing tool
	#with crop tool enabled
	if ($self->{_current_mode_descr} ne "crop") {
		$settings{'drawing'}->{'mode'} = $self->{_current_mode};
	} else {
		$settings{'drawing'}->{'mode'} = 10;
	}

	#autoscroll
	my $autoscroll_toggle = $self->{_uimanager}->get_widget("/MenuBar/Edit/Autoscroll");
	$settings{'drawing'}->{'autoscroll'} = $autoscroll_toggle->get_active();

	#drawing colors
	$settings{'drawing'}->{'fill_color'}         = sprintf("#%04x%04x%04x", $self->{_fill_color}->red * 65535, $self->{_fill_color}->green * 65535, $self->{_fill_color}->blue * 65535);
	$settings{'drawing'}->{'fill_color_alpha'}   = $self->{_fill_color}->alpha;
	$settings{'drawing'}->{'stroke_color'}       = sprintf("#%04x%04x%04x", $self->{_stroke_color}->red * 65535, $self->{_stroke_color}->green * 65535, $self->{_stroke_color}->blue * 65535);
	$settings{'drawing'}->{'stroke_color_alpha'} = $self->{_stroke_color}->alpha;

	#line_width
	$settings{'drawing'}->{'line_width'} = $self->{_line_width};

	#font
	$settings{'drawing'}->{'font'} = $self->{_font};

	eval {

		#save to file
		open(SETTFILE, ">$settingsfile") or die $!;
		print SETTFILE XMLout(\%settings);
		close(SETTFILE) or die $!;

	};
	if ($@) {
		warn "ERROR: Settings of DrawingTool could not be saved: $@ - ignoring\n";
	}

	return TRUE;
}

sub export_to_file {
	my $self      = shift;
	my $rfiletype = shift;

	my $fs = Gtk3::FileChooserDialog->new(
		$self->{_d}->get("Choose a location to save to"),
		$self->{_drawing_window}, 'save',
		'gtk-cancel' => 'reject',
		'gtk-save'   => 'accept'
	);

	my $shutter_hfunct = Shutter::App::HelperFunctions->new($self->{_sc});

	#parse filename
	my ($short, $folder, $ext) = fileparse($self->{_filename}, qr/\.[^.]*/);

	#go to recently used folder
	if (defined $self->{_sc}->get_rusf && $shutter_hfunct->folder_exists($self->{_sc}->get_rusf)) {
		$fs->set_current_folder($self->{_sc}->get_rusf);
		$fs->set_current_name($short . $ext);
	} elsif (defined $self->{_is_unsaved} && $self->{_is_unsaved}) {
		$fs->set_current_folder(Shutter::App::Directories::get_home_dir());
		$fs->set_current_name($short . $ext);
	} else {
		$fs->set_current_folder($folder);
		$fs->set_current_name($short . $ext);
	}

	#preview widget
	my $iprev = Gtk3::Image->new;
	$fs->set_preview_widget($iprev);

	$fs->signal_connect(
		'selection-changed' => sub {
			if (my $pfilename = $fs->get_preview_filename) {
				my $pixbuf = $self->{_lp_ne}->load($pfilename, 200, 200, TRUE, TRUE);
				unless ($pixbuf) {
					$fs->set_preview_widget_active(FALSE);
				} else {
					$fs->get_preview_widget->set_from_pixbuf($pixbuf);
					$fs->set_preview_widget_active(TRUE);
				}
			} else {
				$fs->set_preview_widget_active(FALSE);
			}
		});

	#change extension related to the requested filetype
	if (defined $rfiletype) {
		my ($short, $folder, $ext) = fileparse($self->{_filename}, qr/\.[^.]*/);
		$fs->set_current_name($short . "." . $rfiletype);
	}

	my $extra_hbox = Gtk3::HBox->new;

	my $label_save_as_type = Gtk3::Label->new($self->{_d}->get("Image format") . ":");

	my $combobox_save_as_type = Gtk3::ComboBoxText->new;

	#add supported formats to combobox
	my $counter     = 0;
	my $png_counter = undef;

	#add pdf support
	if (defined $rfiletype && $rfiletype eq 'pdf') {

		$combobox_save_as_type->insert_text($counter, "pdf - Portable Document Format");
		$combobox_save_as_type->set_active(0);

		#add ps support
	} elsif (defined $rfiletype && $rfiletype eq 'ps') {

		$combobox_save_as_type->insert_text($counter, "ps - PostScript");
		$combobox_save_as_type->set_active(0);

		#images
	} else {

		foreach my $format (Gtk3::Gdk::Pixbuf::get_formats()) {

			#we don't want svg here - this is a dedicated action in the DrawingTool
			next if !defined $rfiletype && $format->get_name =~ /svg/;

			#we have a requested filetype - nothing else will be offered
			next if defined $rfiletype && $format->get_name ne $rfiletype;

			#we want jpg not jpeg
			if ($format->get_name eq "jpeg" || $format->get_name eq "jpg") {
				$combobox_save_as_type->insert_text($counter, "jpg" . " - " . $format->get_description);
			} else {
				$combobox_save_as_type->insert_text($counter, $format->get_name . " - " . $format->get_description);
			}

			#set active when mime_type is matching
			#loop because multiple mime types are registered for fome file formats
			foreach my $mime (@{$format->get_mime_types}) {
				$combobox_save_as_type->set_active($counter)
					if $mime eq $self->{'_mimetype'} || defined $rfiletype;

				#save png_counter as well as fallback
				$png_counter = $counter if $mime eq 'image/png';
			}

			$counter++;

		}

	}

	#something went wrong here
	#filetype was not detected automatically
	#set to png as default
	unless ($combobox_save_as_type->get_active_text) {
		if (defined $png_counter) {
			$combobox_save_as_type->set_active($png_counter);
		}
	}

	$combobox_save_as_type->signal_connect(
		'changed' => sub {
			my $filename = $self->{_shf}->utf8_decode($fs->get_filename);

			my $choosen_format = $combobox_save_as_type->get_active_text;
			$choosen_format =~ s/ \-.*//;    #get png or jpeg (jpg) for example
											 #~ print $choosen_format . "\n";

			#parse filename
			my ($short, $folder, $ext) = fileparse($filename, qr/\.[^.]*/);

			$fs->set_current_name($short . "." . $choosen_format);
		});

	#emit the signal once in order to invoke the sub above
	#~ $combobox_save_as_type->signal_emit('changed');

	$extra_hbox->pack_start($label_save_as_type,    FALSE, FALSE, 5);
	$extra_hbox->pack_start($combobox_save_as_type, FALSE, FALSE, 5);

	my $align_save_as_type = Gtk3::Alignment->new(1, 0, 0, 0);

	$align_save_as_type->add($extra_hbox);
	$align_save_as_type->show_all;

	$fs->set_extra_widget($align_save_as_type);

	my $fs_resp = $fs->run;

	if ($fs_resp eq "accept") {
		my $filename = $self->{_shf}->utf8_decode($fs->get_filename);

		#parse filename
		my ($short, $folder, $ext) = fileparse($filename, qr/\.[^.]*/);

		#keep selected folder in mind
		$self->{_sc}->set_rusf($folder);

		#handle file format
		my $choosen_format = $combobox_save_as_type->get_active_text;
		$choosen_format =~ s/ \-.*//;    #get png or jpeg (jpg) for example

		$filename = $folder . $short . "." . $choosen_format;

		my $shutter_hfunct = Shutter::App::HelperFunctions->new($self->{_sc});

		unless ($shutter_hfunct->file_exists($filename)) {

			#save
			$self->save(FALSE, $filename, $choosen_format);

		} else {

			#ask the user to replace the image
			#replace button
			my $replace_btn = Gtk3::Button->new_with_mnemonic($self->{_d}->get("_Replace"));
			$replace_btn->set_image(Gtk3::Image->new_from_stock('gtk-save-as', 'button'));

			my $response = $self->{_dialogs}->dlg_warning_message(
				sprintf($self->{_d}->get("The image already exists in %s. Replacing it will overwrite its contents."), "'" . $folder . "'"),
				sprintf($self->{_d}->get("An image named %s already exists. Do you want to replace it?"),              "'" . $short . "." . $choosen_format . "'"),
				undef, undef, undef, $replace_btn, undef, undef
			);

			if ($response == 40) {

				#save
				$self->save(FALSE, $filename, $choosen_format);

			}

		}

	}

	$fs->destroy();

}

sub export_to_svg {
	my $self = shift;

	#here might be some more features in future releases of Shutter

	#just call the dialog
	$self->export_to_file('svg');

	return TRUE;
}

sub export_to_ps {
	my $self = shift;

	#here might be some more features in future releases of Shutter

	#just call the dialog
	$self->export_to_file('ps');

	return TRUE;
}

sub export_to_pdf {
	my $self = shift;

	#here might be some more features in future releases of Shutter

	#just call the dialog
	$self->export_to_file('pdf');

	return TRUE;
}

sub save {
	my $self        = shift;
	my $save_to_mem = shift;
	my $filename    = shift || $self->{_filename};
	my $filetype    = shift || $self->{_filetype};

	#make sure not to save the bounding rectangles
	$self->deactivate_all;

	#hide line and change background color, e.g. for saving
	$self->handle_bg_rects('hide');

	unless ($save_to_mem) {

		#image format supports transparency or not
		#we need to support more formats here I think
		if ($filetype eq 'jpeg' || $filetype eq 'jpg' || $filetype eq 'bmp') {
			$self->{_canvas_bg_rect}->set(
				'fill-color-gdk-rgba' => $self->{_canvas_bg_rect}{fill_color},
				'line-width'   => 0,
			);
		} elsif ($self->{_canvas_bg_rect}{fill_color}->equal(Gtk3::Gdk::RGBA::parse('gray'))) {
			$self->{_canvas_bg_rect}->set('visibility' => 'hidden');
		} else {

			#ask the user if he wants to save the background color
			my $bg_dialog = Gtk3::MessageDialog->new($self->{_drawing_window}, [qw/modal destroy-with-parent/], 'other', 'none', undef);

			#set attributes
			$bg_dialog->set('text'           => $self->{_d}->get("Do you want to save the changed background color?"));
			$bg_dialog->set('secondary-text' => $self->{_d}->get("The background is likely to be transparent if you decide to ignore the background color."));
			$bg_dialog->set('image'          => Gtk3::Image->new_from_stock('gtk-save', 'dialog'));
			$bg_dialog->set('title'          => $self->{_d}->get("Save Background Color"));

			#ignore bg button
			my $cancel_btn = Gtk3::Button->new_with_mnemonic($self->{_d}->get("_Ignore Background Color"));

			#save bg button
			my $bg_btn = Gtk3::Button->new_with_mnemonic($self->{_d}->get("_Save Background Color"));
			$bg_btn->set_can_default(TRUE);

			$bg_dialog->add_action_widget($cancel_btn, 10);
			$bg_dialog->add_action_widget($bg_btn,     20);

			$bg_dialog->set_default_response(20);

			$bg_dialog->get_child->show_all;

			my $response = $bg_dialog->run;
			if ($response == 10) {
				$self->{_canvas_bg_rect}->set('visibility' => 'hidden');
			} elsif ($response == 20) {
				$self->{_canvas_bg_rect}->set(
					'fill-color-gdk-rgba' => $self->{_canvas_bg_rect}{fill_color},
					'line-width'   => 0,
				);
			}

			$bg_dialog->destroy;

		}
	} else {
		$self->{_canvas_bg_rect}->set('visibility' => 'hidden');
	}

	if ($filetype eq 'svg') {

		#0.8? => 72 / 90 dpi
		my $surface = Cairo::SvgSurface->create($filename, $self->{_canvas_bg_rect}->get('width') * 0.8, $self->{_canvas_bg_rect}->get('height') * 0.8);
		my $cr      = Cairo::Context->create($surface);
		$cr->scale(0.8, 0.8);
		$self->{_canvas}->render($cr, $self->{_canvas_bg_rect}->get_bounds, 1);
		$cr->show_page;

	} elsif ($filetype eq 'ps') {

		#0.8? => 72 / 90 dpi
		my $surface = Cairo::PsSurface->create($filename, $self->{_canvas_bg_rect}->get('width') * 0.8, $self->{_canvas_bg_rect}->get('height') * 0.8);
		my $cr      = Cairo::Context->create($surface);
		$cr->scale(0.8, 0.8);
		$self->{_canvas}->render($cr, $self->{_canvas_bg_rect}->get_bounds, 1);
		$cr->show_page;

	} elsif ($filetype eq 'pdf') {

		#0.8? => 72 / 90 dpi
		my $surface = Cairo::PdfSurface->create($filename, $self->{_canvas_bg_rect}->get('width') * 0.8, $self->{_canvas_bg_rect}->get('height') * 0.8);
		my $cr      = Cairo::Context->create($surface);
		$cr->scale(0.8, 0.8);
		$self->{_canvas}->render($cr, $self->{_canvas_bg_rect}->get_bounds, 1);
		$cr->show_page;

	} else {

		my $surface = Cairo::ImageSurface->create('argb32', $self->{_canvas_bg_rect}->get('width'), $self->{_canvas_bg_rect}->get('height'));
		my $cr      = Cairo::Context->create($surface);
		$self->{_canvas}->render($cr, $self->{_canvas_bg_rect}->get_bounds, 1);

		my $loader = Gtk3::Gdk::PixbufLoader->new;
		$surface->write_to_png_stream(
			sub {
				my ($closure, $data) = @_;
				$loader->write([map ord, split //, $data]);
				return TRUE;
			});
		$loader->close;
		my $pixbuf = $loader->get_pixbuf;

		#just return pixbuf
		if ($save_to_mem) {

			#update the canvas_rect again
			$self->{_canvas_bg_rect}->set(
				'fill-color-gdk-rgba' => $self->{_canvas_bg_rect}{fill_color},
				'line-width'   => 1,
				'visibility'   => 'visible',

			);
			$self->handle_bg_rects('show');
			return $pixbuf;
		}

		#save pixbuf to file
		my $pixbuf_save = Shutter::Pixbuf::Save->new($self->{_sc}, $self->{_drawing_window});
		return $pixbuf_save->save_pixbuf_to_file($pixbuf, $filename, $filetype);

	}

}

#ITEM SIGNALS
sub setup_item_signals {
	my ($self, $item) = @_;

	$item->signal_connect(
		'motion_notify_event',
		sub {
			my ($item, $target, $ev) = @_;
			$self->event_item_on_motion_notify($item, $target, $ev);
		});
	$item->signal_connect(
		'key_press_event',
		sub {
			my ($item, $target, $ev) = @_;
			$self->event_item_on_key_press($item, $target, $ev);
		});
	$item->signal_connect(
		'button_press_event',
		sub {
			my ($item, $target, $ev) = @_;
			$self->event_item_on_button_press($item, $target, $ev);
		});
	$item->signal_connect(
		'button_release_event',
		sub {
			my ($item, $target, $ev) = @_;
			$self->event_item_on_button_release($item, $target, $ev);
		});

	return TRUE;
}

sub setup_item_signals_extra {
	my ($self, $item) = @_;

	$item->signal_connect(
		'enter_notify_event',
		sub {
			my ($item, $target, $ev) = @_;
			$self->event_item_on_enter_notify($item, $target, $ev);
		});

	$item->signal_connect(
		'leave_notify_event',
		sub {
			my ($item, $target, $ev) = @_;
			$self->event_item_on_leave_notify($item, $target, $ev);
		});

	return TRUE;
}

sub event_item_on_motion_notify {
	my ($self, $item, $target, $ev) = @_;

	$self->adjust_rulers($ev, $item);

	#autoscroll if enabled
	#as does not work when using the censor tool -> deactivate it
	if ($self->{_current_mode_descr} ne "censor" && $self->{_autoscroll} && ($ev->state >= 'button1-mask' || $ev->state >= 'button2-mask')) {

		my ($x, $y, $width, $height, $depth) = $self->{_canvas}->get_window->get_geometry;
		my $s  = $self->{_canvas}->get_scale;
		my $ha = $self->{_scrolled_window}->get_hadjustment->get_value;
		my $va = $self->{_scrolled_window}->get_vadjustment->get_value;

		#autoscroll
		if (   $ev->x > ($ha / $s + $width / $s - 100 / $s)
			&& $ev->y > ($va / $s + $height / $s - 100 / $s))
		{
			$self->{_canvas}->scroll_to($ha / $s + 10 / $s, $va / $s + 10 / $s);
		} elsif ($ev->x > ($ha / $s + $width / $s - 100 / $s)) {
			$self->{_canvas}->scroll_to($ha / $s + 10 / $s, $va / $s);
		} elsif ($ev->y > ($va / $s + $height / $s - 100 / $s)) {
			$self->{_canvas}->scroll_to($ha / $s, $va / $s + 10 / $s);
		} elsif ($ev->x < ($ha / $s + 100 / $s) && $ev->y < ($va / $s + 100 / $s)) {
			$self->{_canvas}->scroll_to($ha / $s - 10 / $s, $va / $s - 10 / $s);
		} elsif ($ev->x < ($ha / $s + 100 / $s)) {
			$self->{_canvas}->scroll_to($ha / $s - 10 / $s, $va / $s);
		} elsif ($ev->y < ($va / $s + 100 / $s)) {
			$self->{_canvas}->scroll_to($ha / $s, $va / $s - 10 / $s);
		}
	}

	#move
	if ($item->{dragging} && ($ev->state >= 'button1-mask' || $ev->state >= 'button2-mask')) {

		if ($item->isa('GooCanvas2::CanvasRect')) {

			my $new_x = $self->{_items}{$item}->get('x') + $ev->x - $item->{drag_x};
			my $new_y = $self->{_items}{$item}->get('y') + $ev->y - $item->{drag_y};

			$self->{_items}{$item}->set(
				'x' => $new_x,
				'y' => $new_y,
			);

			$item->{drag_x} = $ev->x;
			$item->{drag_y} = $ev->y;

			$self->handle_rects('update', $item);
			$self->handle_embedded('update', $item);

		} else {

			$item->translate($ev->x - $item->{drag_x}, $ev->y - $item->{drag_y});

		}

		#add to undo stack
		if ($item->{dragging_start}) {
			$self->store_to_xdo_stack($item, 'modify', 'undo');
			$item->{dragging_start} = FALSE;
		}

		#freehand line
	} elsif (($self->{_current_mode_descr} eq "freehand" || $self->{_current_mode_descr} eq "highlighter" || $self->{_current_mode_descr} eq "censor") && $ev->state >= 'button1-mask') {

		#mark as active item
		my $item = undef;
		if ($self->{_current_new_item}) {
			$item                      = $self->{_current_new_item};
			$self->{_current_new_item} = undef;
			$self->{_current_item}     = $item;

			#add to undo stack
			$self->store_to_xdo_stack($self->{_current_item}, 'create', 'undo');

		} else {
			$item = $self->{_current_item};
		}

		if ($ev->state >= 'control-mask') {

			my $last_point = pop @{$self->{_items}{$item}{'points'}};
			$last_point = $ev->y unless $last_point;
			push @{$self->{_items}{$item}{'points'}}, $last_point, $ev->x, $last_point;

		} elsif ($ev->state >= 'shift-mask') {

			my $last_point_y = pop @{$self->{_items}{$item}{'points'}};
			my $last_point_x = pop @{$self->{_items}{$item}{'points'}};
			$last_point_x = $ev->x unless $last_point_x;
			$last_point_y = $ev->y unless $last_point_y;
			push @{$self->{_items}{$item}{'points'}}, $last_point_x, $last_point_y, $last_point_x, $ev->y;

		} else {

			push @{$self->{_items}{$item}{'points'}}, $ev->x, $ev->y;

		}

		$self->{_items}{$item}->set('points' => Shutter::Draw::Utils::points_to_canvas_points(@{$self->{_items}{$item}{'points'}}));

		#new item is already on the canvas with small initial size
		#drawing is like resizing, so set up for resizing
	} elsif ((
			   $self->{_current_mode_descr} eq "rect"
			|| $self->{_current_mode_descr} eq "line"
			|| $self->{_current_mode_descr} eq "arrow"
			|| $self->{_current_mode_descr} eq "ellipse"
			|| $self->{_current_mode_descr} eq "text"
			|| $self->{_current_mode_descr} eq "image"
			|| $self->{_current_mode_descr} eq "pixelize"
			|| $self->{_current_mode_descr} eq "number"
		)
		&& $ev->state >= 'button1-mask'
		&& !$item->{resizing}    #if item is not in resize mode already
		)
	{

		#~ print "start resizing\n";

		my $item = $self->{_current_new_item};

		return FALSE unless $item;

		$self->deactivate_all($item);

		#mark as active item
		$self->{_current_item} = $item;

		$self->{_items}{$item}{'bottom-right-corner'}->{res_x}    = $ev->x;
		$self->{_items}{$item}{'bottom-right-corner'}->{res_y}    = $ev->y;
		$self->{_items}{$item}{'bottom-right-corner'}->{resizing} = TRUE;
		eval {
			$self->{_canvas}->pointer_grab($self->{_items}{$item}{'bottom-right-corner'}, ['pointer-motion-mask', 'button-release-mask'], undef, $ev->time);
		};
		if ($@) {
			# workaround for https://gitlab.gnome.org/GNOME/goocanvas/-/merge_requests/8
			$self->{_canvas}->pointer_grab($self->{_items}{$item}{'bottom-right-corner'}, ['pointer-motion-mask', 'button-release-mask'], Gtk3::Gdk::Cursor->new('left-ptr'), $ev->time);
		}

		#add to undo stack
		$self->store_to_xdo_stack($item, 'create', 'undo');

		#item is resizing mode already
	} elsif ($item->{resizing} && $ev->state >= 'button1-mask') {

		#~ print "resizing\n";

		$self->{_current_mode_descr} = "resize";

		#canvas resizing shape
		if ($self->{_canvas_bg_rect}{'right-side'} == $item) {

			my $new_width = $self->{_canvas_bg_rect}->get('width') + ($ev->x - $item->{res_x});

			unless ($new_width < 0) {

				$self->{_canvas_bg_rect}->set('width' => $new_width,);

				$self->handle_bg_rects('update');

			}

		} elsif ($self->{_canvas_bg_rect}{'bottom-side'} == $item) {

			my $new_height = $self->{_canvas_bg_rect}->get('height') + ($ev->y - $item->{res_y});

			unless ($new_height < 0) {

				$self->{_canvas_bg_rect}->set('height' => $new_height,);

				$self->handle_bg_rects('update');

			}

		} elsif ($self->{_canvas_bg_rect}{'bottom-right-corner'} == $item) {

			my $new_width  = $self->{_canvas_bg_rect}->get('width') + ($ev->x - $item->{res_x});
			my $new_height = $self->{_canvas_bg_rect}->get('height') + ($ev->y - $item->{res_y});

			unless ($new_width < 0 || $new_height < 0) {

				$self->{_canvas_bg_rect}->set(
					'width'  => $new_width,
					'height' => $new_height,
				);

				$self->handle_bg_rects('update');

			}

			#item resizing shape
		} else {

			my $curr_item = $self->{_current_item};

			#~ my $cursor = undef;

			return FALSE unless $curr_item;

			#calculate aspect ratio (resizing when control is pressed)
			my $ratio = 1;
			$ratio = $self->{_items}{$curr_item}->get('width') / $self->{_items}{$curr_item}->get('height') if $self->{_items}{$curr_item}->get('height') != 0;

			my $new_x      = 0;
			my $new_y      = 0;
			my $new_width  = 0;
			my $new_height = 0;

			foreach (keys %{$self->{_items}{$curr_item}}) {

				next unless $_ =~ m/(corner|side)/;

				#fancy resizing using our little resize boxes
				if ($item == $self->{_items}{$curr_item}{$_}) {

					#~ $cursor = $_;

					if ($_ eq 'bottom-side') {

						$new_x = $self->{_items}{$curr_item}->get('x');
						$new_y = $self->{_items}{$curr_item}->get('y');

						$new_width  = $self->{_items}{$curr_item}->get('width');
						$new_height = $self->{_items}{$curr_item}->get('height') + ($ev->y - $item->{res_y});

						last;

					} elsif ($_ eq 'bottom-right-corner') {

						$new_x = $self->{_items}{$curr_item}->get('x');
						$new_y = $self->{_items}{$curr_item}->get('y');

						if ($ev->state >= 'control-mask') {
							$new_width  = $self->{_items}{$curr_item}->get('width') + ($ev->y - $item->{res_y}) * $ratio;
							$new_height = $self->{_items}{$curr_item}->get('height') + ($ev->y - $item->{res_y});
						} else {
							$new_width  = $self->{_items}{$curr_item}->get('width') + ($ev->x - $item->{res_x});
							$new_height = $self->{_items}{$curr_item}->get('height') + ($ev->y - $item->{res_y});
						}

						last;

					} elsif ($_ eq 'top-left-corner') {

						if ($ev->state >= 'control-mask') {
							$new_x      = $self->{_items}{$curr_item}->get('x') + ($ev->y - $item->{res_y}) * $ratio;
							$new_y      = $self->{_items}{$curr_item}->get('y') + ($ev->y - $item->{res_y});
							$new_width  = $self->{_items}{$curr_item}->get('width') + ($self->{_items}{$curr_item}->get('x') - $new_x);
							$new_height = $self->{_items}{$curr_item}->get('height') + ($self->{_items}{$curr_item}->get('y') - $new_y);
						} else {
							$new_x      = $self->{_items}{$curr_item}->get('x') + $ev->x - $item->{res_x};
							$new_y      = $self->{_items}{$curr_item}->get('y') + $ev->y - $item->{res_y};
							$new_width  = $self->{_items}{$curr_item}->get('width') + ($self->{_items}{$curr_item}->get('x') - $new_x);
							$new_height = $self->{_items}{$curr_item}->get('height') + ($self->{_items}{$curr_item}->get('y') - $new_y);
						}

						last;

					} elsif ($_ eq 'top-side') {

						$new_x = $self->{_items}{$curr_item}->get('x');
						$new_y = $self->{_items}{$curr_item}->get('y') + $ev->y - $item->{res_y};

						$new_width  = $self->{_items}{$curr_item}->get('width');
						$new_height = $self->{_items}{$curr_item}->get('height') + ($self->{_items}{$curr_item}->get('y') - $new_y);

						last;

					} elsif ($_ eq 'top-right-corner') {

						$new_x = $self->{_items}{$curr_item}->get('x');
						$new_y = $self->{_items}{$curr_item}->get('y') + $ev->y - $item->{res_y};

						if ($ev->state >= 'control-mask') {
							$new_width  = $self->{_items}{$curr_item}->get('width') - ($ev->y - $item->{res_y}) * $ratio;
							$new_height = $self->{_items}{$curr_item}->get('height') + ($self->{_items}{$curr_item}->get('y') - $new_y);
						} else {
							$new_width  = $self->{_items}{$curr_item}->get('width') + ($ev->x - $item->{res_x});
							$new_height = $self->{_items}{$curr_item}->get('height') + ($self->{_items}{$curr_item}->get('y') - $new_y);
						}

						last;

					} elsif ($_ eq 'left-side') {

						$new_x = $self->{_items}{$curr_item}->get('x') + $ev->x - $item->{res_x};
						$new_y = $self->{_items}{$curr_item}->get('y');

						$new_width  = $self->{_items}{$curr_item}->get('width') + ($self->{_items}{$curr_item}->get('x') - $new_x);
						$new_height = $self->{_items}{$curr_item}->get('height');

						last;

					} elsif ($_ eq 'right-side') {

						$new_x = $self->{_items}{$curr_item}->get('x');
						$new_y = $self->{_items}{$curr_item}->get('y');

						$new_width  = $self->{_items}{$curr_item}->get('width') + ($ev->x - $item->{res_x});
						$new_height = $self->{_items}{$curr_item}->get('height');

						last;

					} elsif ($_ eq 'bottom-left-corner') {

						if ($ev->state >= 'control-mask') {
							$new_x = $self->{_items}{$curr_item}->get('x') - $ev->y + $item->{res_y};
							$new_y = $self->{_items}{$curr_item}->get('y');

							$new_width  = $self->{_items}{$curr_item}->get('width') + ($self->{_items}{$curr_item}->get('x') - $new_x);
							$new_height = $self->{_items}{$curr_item}->get('height') + ($ev->y - $item->{res_y}) / $ratio;
						} else {
							$new_x = $self->{_items}{$curr_item}->get('x') + $ev->x - $item->{res_x};
							$new_y = $self->{_items}{$curr_item}->get('y');

							$new_width  = $self->{_items}{$curr_item}->get('width') + ($self->{_items}{$curr_item}->get('x') - $new_x);
							$new_height = $self->{_items}{$curr_item}->get('height') + ($ev->y - $item->{res_y});
						}

						last;

					}
				}
			}

			#set cursor

			#~ $self->{_canvas}->window->set_cursor( Gtk3::Gdk::Cursor->new($cursor) );

			#when width or height are too small we switch to opposite rectangle and do the resizing in this way
			if ($ev->state >= 'control-mask' && $new_width < 1 && $new_height < 1) {

				$new_x      = $self->{_items}{$curr_item}->get('x');
				$new_y      = $self->{_items}{$curr_item}->get('y');
				$new_width  = $self->{_items}{$curr_item}->get('width');
				$new_height = $self->{_items}{$curr_item}->get('height');

			} elsif ($new_width < 0 || $new_height < 0) {

				$self->{_canvas}->pointer_ungrab($item, $ev->time);
				$self->{_canvas}->keyboard_ungrab($item, $ev->time);

				my $oppo = $self->get_opposite_rect($item, $curr_item, $new_width, $new_height);

				$self->{_items}{$curr_item}{$oppo}->{res_x}    = $ev->x;
				$self->{_items}{$curr_item}{$oppo}->{res_y}    = $ev->y;
				$self->{_items}{$curr_item}{$oppo}->{resizing} = TRUE;

				#~ #don'change cursor if this item was just started
				#~ if($self->{_last_item} && $self->{_current_item} && $self->{_last_item} == $self->{_current_item}){
				#~ $self->{_canvas}->pointer_grab( $self->{_items}{$curr_item}{$oppo}, [ 'pointer-motion-mask', 'button-release-mask' ], undef, $ev->time );
				#~ }else{
				#~ $self->{_canvas}->pointer_grab( $self->{_items}{$curr_item}{$oppo}, [ 'pointer-motion-mask', 'button-release-mask' ], Gtk3::Gdk::Cursor->new($oppo), $ev->time );
				#~ }

				eval {
					$self->{_canvas}->pointer_grab($self->{_items}{$curr_item}{$oppo}, ['pointer-motion-mask', 'button-release-mask'], undef, $ev->time);
				};
				if ($@) {
					# workaround for https://gitlab.gnome.org/GNOME/goocanvas/-/merge_requests/8
					$self->{_canvas}->pointer_grab($self->{_items}{$curr_item}{$oppo}, ['pointer-motion-mask', 'button-release-mask'], Gtk3::Gdk::Cursor->new('left-ptr'), $ev->time);
				}

				$self->handle_embedded('mirror', $curr_item, $new_width, $new_height);

				#adjust new values
				if ($new_width < 0) {
					$new_x += $new_width;
					$new_width = abs($new_width);
				}
				if ($new_height < 0) {
					$new_y += $new_height;
					$new_height = abs($new_height);
				}

			}

			#apply new values...
			$self->{_items}{$curr_item}->set(
				'x'      => $new_x,
				'y'      => $new_y,
				'width'  => $new_width,
				'height' => $new_height,
			);

			#and update rectangles and embedded items
			$self->handle_rects('update', $curr_item);
			$self->handle_embedded('update', $curr_item);

		}

		$item->{res_x} = $ev->x;
		$item->{res_y} = $ev->y;

	} else {

		if ($item->isa('GooCanvas2::CanvasRect')) {

			#embedded item?
			my $parent = $self->get_parent_item($item);
			$item = $parent if $parent;

			#shape or canvas background (resizeable rectangle)
			if (exists $self->{_items}{$item} or $item == $self->{_canvas_bg_rect}) {
				$self->push_tool_help_to_statusbar(int($ev->x), int($ev->y));

				#canvas resizing shape
			} elsif ($self->{_canvas_bg_rect}{'right-side'} == $item
				|| $self->{_canvas_bg_rect}{'bottom-side'} == $item
				|| $self->{_canvas_bg_rect}{'bottom-right-corner'} == $item)
			{
				$self->push_tool_help_to_statusbar(int($ev->x), int($ev->y), 'canvas_resize');

				#resizing shape
			} else {

				$self->push_tool_help_to_statusbar(int($ev->x), int($ev->y), 'resize');
			}
		} else {
			$self->push_tool_help_to_statusbar(int($ev->x), int($ev->y));
		}

	}

	return TRUE;
}

sub get_opposite_rect {
	my $self   = shift;
	my $rect   = shift;
	my $item   = shift;
	my $width  = shift;
	my $height = shift;

	foreach (keys %{$self->{_items}{$item}}) {

		#fancy resizing using our little resize boxes
		if ($rect eq $self->{_items}{$item}{$_}) {

			if ($_ eq 'top-left-corner') {

				return 'bottom-right-corner' if $width < 0 && $height < 0;
				return 'top-right-corner'    if $width < 0;
				return 'bottom-left-corner'  if $height < 0;

			} elsif ($_ eq 'top-side') {

				return 'bottom-side';

			} elsif ($_ eq 'top-right-corner') {

				return 'bottom-left-corner'  if $width < 0 && $height < 0;
				return 'top-left-corner'     if $width < 0;
				return 'bottom-right-corner' if $height < 0;

			} elsif ($_ eq 'left-side') {

				return 'right-side';

			} elsif ($_ eq 'right-side') {

				return 'left-side';

			} elsif ($_ eq 'bottom-left-corner') {

				return 'top-right-corner'    if $width < 0 && $height < 0;
				return 'bottom-right-corner' if $width < 0;
				return 'top-left-corner'     if $height < 0;

			} elsif ($_ eq 'bottom-side') {

				return 'top-side';

			} elsif ($_ eq 'bottom-right-corner') {

				return 'top-left-corner'    if $width < 0 && $height < 0;
				return 'bottom-left-corner' if $width < 0;
				return 'top-right-corner'   if $height < 0;

			}
		}
	}

	return FALSE;
}

sub get_parent_item {
	my ($self, $item) = @_;

	return FALSE unless $item;

	my $parent = undef;
	foreach (keys %{$self->{_items}}) {
		$parent = $self->{_items}{$_} if exists $self->{_items}{$_}{ellipse}  && $self->{_items}{$_}{ellipse} == $item;
		$parent = $self->{_items}{$_} if exists $self->{_items}{$_}{text}     && $self->{_items}{$_}{text} == $item;
		$parent = $self->{_items}{$_} if exists $self->{_items}{$_}{image}    && $self->{_items}{$_}{image} == $item;
		$parent = $self->{_items}{$_} if exists $self->{_items}{$_}{pixelize} && $self->{_items}{$_}{pixelize} == $item;
		$parent = $self->{_items}{$_} if exists $self->{_items}{$_}{line}     && $self->{_items}{$_}{line} == $item;
		if (defined $parent) {
			last;
		}
	}

	#~ #debug
	#~ if($parent){
	#~ print "parent: $parent queried for item: $item\n";
	#~ }else{
	#~ print "no parent found for item: $item\n";
	#~ }

	return $parent;
}

sub get_highest_auto_digit {
	my ($self) = @_;

	my $number = 0;
	foreach (keys %{$self->{_items}}) {

		my $item = $self->{_items}{$_};

		#numbered shape
		if (   exists $self->{_items}{$item}
			&& exists $self->{_items}{$item}{type}
			&& $self->{_items}{$item}{type} eq 'number'
			&& $self->{_items}{$item}{text}->get('visibility') ne 'hidden')
		{
			$number = $self->{_items}{$item}{text}{digit} if $self->{_items}{$item}{text}{digit} > $number;
		}

	}

	return $number;
}

sub get_pixelated_pixbuf_from_canvas {
	my ($self, $item) = @_;

	my $bounds = $item->get_bounds;
	my $sw     = $item->get('width');
	my $sh     = $item->get('height');

	#create surface and cairo context
	my $surface = Cairo::ImageSurface->create('rgb24', $bounds->x1 + $sw, $bounds->y1 + $sh);
	my $cr      = Cairo::Context->create($surface);

	#hide rects and image
	$self->handle_rects('hide', $item);
	$self->handle_embedded('hide', $item);

	#render the content and load it via Gtk3::Gdk::PixbufLoader
	$self->{_canvas}->render($cr, $bounds, 1);

	#show rects again
	$self->handle_rects('update', $item);

	#~ print "start loader\n";
	my $loader = Gtk3::Gdk::PixbufLoader->new;
	$surface->write_to_png_stream(
		sub {
			my ($closure, $data) = @_;
			$loader->write([map ord, split //, $data]);
			return TRUE;
		});
	$loader->close;

	#create vars
	my ($pixbuf, $target) = (undef, undef);

	#error icon
	my $error = Gtk3::Widget::render_icon(Gtk3::Invisible->new, "gtk-dialog-error", 'menu');

	eval {

		$pixbuf = $loader->get_pixbuf;

		#create target pixbuf
		$target = Gtk3::Gdk::Pixbuf->new($pixbuf->get_colorspace, TRUE, 8, $sw, $sh);

	};
	unless ($@) {

		#maybe rect is only partially on canvas
		my ($sx, $sy) = ($bounds->x1, $bounds->y1);
		my ($dx, $dy) = (0, 0);
		if ($bounds->x1 < 0) {
			$sx = 0;
			$dx = abs $bounds->x1;
			$sw += $bounds->x1;
		}
		if ($bounds->y1 < 0) {
			$sy = 0;
			$dy = abs $bounds->y1;
			$sh += $bounds->y1;
		}

		#valid pixbuf?
		if ($pixbuf) {

			#copy area
			$pixbuf->copy_area($sx, $sy, $sw, $sh, $target, $dx, $dy);

			if ($target->get_width > 10 && $target->get_height > 10) {

				eval {

					#pixelate the pixbuf - simply scale it down and scale it up afterwards
					$target = $target->scale_simple($target->get_width * 0.1, $target->get_height * 0.1, 'tiles');
					$target = $target->scale_simple($item->get('width'),      $item->get('height'),      'tiles');

				};
				unless ($@) {

					return $target;

				}

			} elsif ($target->get_width > 5 && $target->get_height > 5) {

				eval {

					#pixelate the pixbuf - simply scale it down and scale it up afterwards
					$target = $target->scale_simple($target->get_width * 0.2, $target->get_height * 0.2, 'tiles');
					$target = $target->scale_simple($item->get('width'),      $item->get('height'),      'tiles');

				};
				unless ($@) {

					return $target;

				}

			}

		}

	}

	return $error;

}

sub get_child_item {
	my ($self, $item) = @_;

	return FALSE unless $item;

	my $child = undef;

	#notice (special shapes like numbered ellipse do deliver ellipse here => NOT text!)
	#therefore the order matters
	if (defined $item && exists $self->{_items}{$item}) {
		$child = $self->{_items}{$item}{text}     if exists $self->{_items}{$item}{text};
		$child = $self->{_items}{$item}{ellipse}  if exists $self->{_items}{$item}{ellipse};
		$child = $self->{_items}{$item}{image}    if exists $self->{_items}{$item}{image};
		$child = $self->{_items}{$item}{pixelize} if exists $self->{_items}{$item}{pixelize};
		$child = $self->{_items}{$item}{line}     if exists $self->{_items}{$item}{line};
	}

	#~ #debug
	#~ if($child){
	#~ print "child: $child queried for item: $item\n";
	#~ }else{
	#~ print "no child found for item: $item\n";
	#~ }

	return $child;
}

sub abort_current_mode {
	my ($self) = @_;

	if ($self->{_current_item}) {
		$self->{_canvas}->pointer_ungrab($self->{_current_item}, Gtk3::get_current_event_time());
		$self->{_canvas}->keyboard_ungrab($self->{_current_item}, Gtk3::get_current_event_time());
	}

	#~ print "abort_current_mode\n";

	$self->set_drawing_action(1);

	return TRUE;
}

sub clear_item_from_canvas {
	my ($self, $item) = @_;

	#~ print "clear_item_from_canvas\n";

	$self->{_current_item}     = undef;
	$self->{_current_new_item} = undef;

	if ($item) {

		#maybe there is a parent item to delete?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#get child
		my $child = $self->get_child_item($item);

		#only delete if not already deleted (hidden)
		return FALSE if ($child && $child->get('visibility') eq 'hidden');

		#~ print "1st passed\n";
		return FALSE if (!$child && $item->get('visibility') eq 'hidden');

		#~ print "2nd passed\n";

		$self->store_to_xdo_stack($item, 'delete', 'undo');
		$item->set('visibility' => 'hidden');
		$self->handle_rects('hide', $item);
		$self->handle_embedded('hide', $item);

	}

	return TRUE;
}

sub store_to_xdo_stack {

	#opt1 is currently only used when cropping the image
	#it stores the selection
	my ($self, $item, $action, $xdo, $opt1, $source) = @_;

	return FALSE unless $item;

	#~ print "xdo - $item\n";

	my %do_info = ();

	#general properties for ellipse, rectangle, image, text
	if ($item->isa('GooCanvas2::CanvasRect') && $item != $self->{_canvas_bg_rect}) {

		my $stroke_color = $self->{_items}{$item}{stroke_color};
		my $fill_color   = $self->{_items}{$item}{fill_color};
		my $line_width     = $self->{_items}{$item}->get('line-width');

		#line
		my $mirrored_w   = undef;
		my $mirrored_h   = undef;
		my $end_arrow    = undef;
		my $start_arrow  = undef;
		my $arrow_width  = undef;
		my $arrow_length = undef;
		my $tip_length   = undef;

		#text
		my $text = undef;

		#numbered ellipse
		my $digit = undef;

		if (exists $self->{_items}{$item}{ellipse}) {

			$line_width = $self->{_items}{$item}{ellipse}->get('line-width');

			#numbered ellipse
			if (exists $self->{_items}{$item}{text}) {
				$text  = $self->{_items}{$item}{text}->get('text');
				$digit = $self->{_items}{$item}{text}{digit};
			}

		} elsif (exists $self->{_items}{$item}{text}) {

			$text = $self->{_items}{$item}{text}->get('text');

		} elsif (exists $self->{_items}{$item}{image}) {

		} elsif (exists $self->{_items}{$item}{line}) {

			#line width
			$line_width = $self->{_items}{$item}{line}->get('line-width');

			#arrow properties
			$end_arrow    = $self->{_items}{$item}{line}->get('end-arrow');
			$start_arrow  = $self->{_items}{$item}{line}->get('start-arrow');
			$arrow_width  = $self->{_items}{$item}{line}->get('arrow-width');
			$arrow_length = $self->{_items}{$item}{line}->get('arrow-length');
			$tip_length   = $self->{_items}{$item}{line}->get('arrow-tip-length');

			#mirror flag
			$mirrored_w = $self->{_items}{$item}{mirrored_w};
			$mirrored_h = $self->{_items}{$item}{mirrored_h};

		}

		#item props
		%do_info = (
			'item'               => $self->{_items}{$item},
			'action'             => $action,
			'x'                  => $self->{_items}{$item}->get('x'),
			'y'                  => $self->{_items}{$item}->get('y'),
			'width'              => $self->{_items}{$item}->get('width'),
			'height'             => $self->{_items}{$item}->get('height'),
			'stroke_color'       => $self->{_items}{$item}{stroke_color},
			'fill_color'         => $self->{_items}{$item}{fill_color},
			'line-width'         => $line_width,
			'mirrored_w'         => $mirrored_w,
			'mirrored_h'         => $mirrored_h,
			'end-arrow'          => $end_arrow,
			'start-arrow'        => $start_arrow,
			'arrow-length'       => $arrow_length,
			'arrow-width'        => $arrow_width,
			'arrow-tip-length'   => $tip_length,
			'text'               => $text,
			'digit'              => $digit,
			'opt1'               => $opt1,
		);

	} elsif ($item->isa('GooCanvas2::CanvasImage') && $item == $self->{_canvas_bg}) {

		#canvas_bg_image and bg_rect properties
		%do_info = (
			'item'           => $self->{_canvas_bg},
			'action'         => $action,
			'drawing_pixbuf' => $self->{_drawing_pixbuf},
			'x'              => $self->{_canvas_bg_rect}->get('x'),
			'y'              => $self->{_canvas_bg_rect}->get('y'),
			'width'          => $self->{_canvas_bg_rect}->get('width'),
			'height'         => $self->{_canvas_bg_rect}->get('height'),
			'opt1'           => $opt1,
		);

	} elsif ($item->isa('GooCanvas2::CanvasRect') && $item == $self->{_canvas_bg_rect}) {

		#canvas_bg_rect properties
		%do_info = (
			'item'   => $self->{_canvas_bg_rect},
			'action' => $action,
			'x'      => $self->{_canvas_bg_rect}->get('x'),
			'y'      => $self->{_canvas_bg_rect}->get('y'),
			'width'  => $self->{_canvas_bg_rect}->get('width'),
			'height' => $self->{_canvas_bg_rect}->get('height'),
			'opt1'   => $opt1,
		);

		#polyline specific properties to hash
	} elsif ($item->isa('GooCanvas2::CanvasPolyline')) {

		my $transform      = $self->{_items}{$item}->get('transform');
		my $line_width     = $self->{_items}{$item}->get('line-width');
		my $points         = $self->{_items}{$item}->get('points');

		%do_info = (
			'item'           => $self->{_items}{$item},
			'action'         => $action,
			'points'         => $points,
			'stroke_color'   => $self->{_items}{$item}{stroke_color},
			'line-width'     => $line_width,
			'transform'      => $transform,
			'opt1'           => $opt1,
		);

	}

	#reset redo
	if (defined $source && $source eq 'ui') {

		#~ print "no clear\n";
	} else {
		while (defined $self->{_redo} && scalar @{$self->{_redo}} > 0) {
			shift @{$self->{_redo}};
		}
	}

	if ($xdo eq 'undo') {
		push @{$self->{_undo}}, \%do_info;
	} elsif ($xdo eq 'redo') {
		push @{$self->{_redo}}, \%do_info;
	}

	#disable undo/redo actions
	$self->{_uimanager}->get_widget("/MenuBar/Edit/Undo")->set_sensitive(scalar @{$self->{_undo}}) if defined $self->{_undo};
	$self->{_uimanager}->get_widget("/MenuBar/Edit/Redo")->set_sensitive(scalar @{$self->{_redo}}) if defined $self->{_redo};

	$self->{_uimanager}->get_widget("/ToolBar/Undo")->set_sensitive(scalar @{$self->{_undo}}) if defined $self->{_undo};
	$self->{_uimanager}->get_widget("/ToolBar/Redo")->set_sensitive(scalar @{$self->{_redo}}) if defined $self->{_redo};

	return TRUE;
}

sub xdo_remove {
	my $self = shift;
	my $xdo  = shift;
	my $item = shift;

	my @indices;
	my $counter = 0;
	if ($xdo eq 'undo') {
		foreach my $do (@{$self->{_undo}}) {
			push @indices, $counter if $item == $do->{'item'};
			$counter++;
		}

		#delete from array
		foreach my $index (@indices) {
			splice(@{$self->{_undo}}, $index, 1);
		}
	} elsif ($xdo eq 'redo') {
		foreach my $do (@{$self->{_redo}}) {
			push @indices, $counter if $item == $do->{'item'};
			$counter++;
		}

		#delete from array
		foreach my $index (@indices) {
			splice(@{$self->{_redo}}, $index, 1);
		}
	}

	#disable undo/redo actions
	$self->{_uimanager}->get_widget("/MenuBar/Edit/Undo")->set_sensitive(scalar @{$self->{_undo}}) if defined $self->{_undo};
	$self->{_uimanager}->get_widget("/MenuBar/Edit/Redo")->set_sensitive(scalar @{$self->{_redo}}) if defined $self->{_redo};

	$self->{_uimanager}->get_widget("/ToolBar/Undo")->set_sensitive(scalar @{$self->{_undo}}) if defined $self->{_undo};
	$self->{_uimanager}->get_widget("/ToolBar/Redo")->set_sensitive(scalar @{$self->{_redo}}) if defined $self->{_redo};

	return TRUE;
}

sub xdo {
	my $self          = shift;
	my $xdo           = shift;
	my $source        = shift;
	my $block_reverse = shift;

	my $do = undef;
	if ($xdo eq 'undo') {
		$do = pop @{$self->{_undo}};
	} elsif ($xdo eq 'redo') {
		$do = pop @{$self->{_redo}};
	}

	my $item   = $do->{'item'};
	my $action = $do->{'action'};
	my $opt1   = $do->{'opt1'};

	return FALSE unless $item;
	return FALSE unless $action;

	if ($item->isa('GooCanvas2::CanvasImage') && $item == $self->{_canvas_bg}) {
		$opt1->{x} = $do->{'opt1'}->{x} * -1;
		$opt1->{y} = $do->{'opt1'}->{y} * -1;
	}

	#create reverse action
	my $reverse_action = 'modify';
	if ($action eq 'raise') {
		$reverse_action = 'lower_xdo';
	} elsif ($action eq 'raise_xdo') {
		$reverse_action = 'lower_xdo';
	} elsif ($action eq 'lower') {
		$reverse_action = 'raise_xdo';
	} elsif ($action eq 'lower_xdo') {
		$reverse_action = 'raise_xdo';
	} elsif ($action eq 'create') {
		$reverse_action = 'delete_xdo';
	} elsif ($action eq 'delete') {
		$reverse_action = 'create_xdo';
	} elsif ($action eq 'create_xdo') {
		$reverse_action = 'delete_xdo';
	} elsif ($action eq 'delete_xdo') {
		$reverse_action = 'create_xdo';
	}

	#undo or redo?
	unless ($block_reverse) {
		if ($xdo eq 'undo') {

			#store to redo stack
			$self->store_to_xdo_stack($item, $reverse_action, 'redo', $opt1, $source);
		} elsif ($xdo eq 'redo') {

			#store to undo stack
			$self->store_to_xdo_stack($item, $reverse_action, 'undo', $opt1, $source);
		}
	}

	#finally undo the last event
	if ($action eq 'modify') {

		if ($item->isa('GooCanvas2::CanvasRect') && $item != $self->{_canvas_bg_rect}) {

			$self->{_items}{$item}->set(
				'x'      => $do->{'x'},
				'y'      => $do->{'y'},
				'width'  => $do->{'width'},
				'height' => $do->{'height'},
			);

			if (exists $self->{_items}{$item}{ellipse}) {

				$self->{_items}{$item}{ellipse}->set(
					'fill-color-gdk-rgba'   => $do->{'fill_color'},
					'stroke-color-gdk-rgba' => $do->{'stroke_color'},
					'line-width'     => $do->{'line-width'},
				);

				#numbered ellipse
				if (exists $self->{_items}{$item}{text}) {
					$self->{_items}{$item}{text}->set(
						'text'         => $do->{'text'},
						'fill-color-gdk-rgba' => $do->{'stroke_color'},
					);
					$self->{_items}{$item}{text}{digit} = $do->{'digit'};
				}

				#restore color and opacity as well
				$self->{_items}{$item}{fill_color}         = $do->{'fill_color'};
				$self->{_items}{$item}{stroke_color}       = $do->{'stroke_color'};

			} elsif (exists $self->{_items}{$item}{text}) {

				$self->{_items}{$item}{text}->set(
					'text'         => $do->{'text'},
					'fill-color-gdk-rgba' => $do->{'stroke_color'},
				);

				#restore color and opacity as well
				$self->{_items}{$item}{stroke_color}       = $do->{'stroke_color'};

			} elsif (exists $self->{_items}{$item}{pixelize}) {

				$self->{_items}{$item}{pixelize}->set(
					'x'      => int $self->{_items}{$item}->get('x'),
					'y'      => int $self->{_items}{$item}->get('y'),
					'width'  => $self->{_items}{$item}->get('width'),
					'height' => $self->{_items}{$item}->get('height'),
					'pixbuf' => $self->get_pixelated_pixbuf_from_canvas($self->{_items}{$item}),
				);

			} elsif (exists $self->{_items}{$item}{image}) {

				#~ print "xdo image\n";

				my $copy = $self->{_lp}->load($self->{_items}{$item}{orig_pixbuf_filename}, $self->{_items}{$item}->get('width'), $self->{_items}{$item}->get('height'), FALSE, TRUE);
				if ($copy) {
					$self->{_items}{$item}{image}->set(
						'x'      => int $self->{_items}{$item}->get('x'),
						'y'      => int $self->{_items}{$item}->get('y'),
						'width'  => $self->{_items}{$item}->get('width'),
						'height' => $self->{_items}{$item}->get('height'),
						'pixbuf' => $copy
					);
				}

			} elsif (exists $self->{_items}{$item}{line}) {

				#save arrow specific properties
				$self->{_items}{$item}{end_arrow}        = $do->{'end-arrow'};
				$self->{_items}{$item}{start_arrow}      = $do->{'start-arrow'};
				$self->{_items}{$item}{arrow_width}      = $do->{'arrow-width'};
				$self->{_items}{$item}{arrow_length}     = $do->{'arrow-length'};
				$self->{_items}{$item}{arrow_tip_length} = $do->{'arrow-tip-length'};

				$self->{_items}{$item}{line}->set(
					'fill-color-gdk-rgba'   => $do->{'fill_color'},
					'stroke-color-gdk-rgba' => $do->{'stroke_color'},
					'line-width'       => $do->{'line-width'},
					'end-arrow'        => $self->{_items}{$item}{end_arrow},
					'start-arrow'      => $self->{_items}{$item}{start_arrow},
					'arrow-length'     => $self->{_items}{$item}{arrow_length},
					'arrow-width'      => $self->{_items}{$item}{arrow_width},
					'arrow-tip-length' => $self->{_items}{$item}{arrow_tip_length},
				);

				$self->{_items}{$item}{mirrored_w} = $do->{'mirrored_w'} if exists $do->{'mirrored_w'};
				$self->{_items}{$item}{mirrored_h} = $do->{'mirrored_h'} if exists $do->{'mirrored_h'};

				#restore color and opacity as well
				$self->{_items}{$item}{stroke_color}       = $do->{'stroke_color'};

			} else {

				$self->{_items}{$item}->set(
					'fill-color-gdk-rgba'   => $do->{'fill_color'},
					'stroke-color-gdk-rgba' => $do->{'stroke_color'},
					'line-width'     => $do->{'line-width'},
				);

				#restore color and opacity as well
				$self->{_items}{$item}{fill_color}         = $do->{'fill_color'};
				$self->{_items}{$item}{stroke_color}       = $do->{'stroke_color'};

			}

		} elsif ($item->isa('GooCanvas2::CanvasImage') && $item == $self->{_canvas_bg}) {

			#~ print "xdo canvas_bg\n";

			my $new_w = $do->{'drawing_pixbuf'}->get_width;
			my $new_h = $do->{'drawing_pixbuf'}->get_height;

			#update canvas and show the new pixbuf
			$self->{_canvas_bg}->set('pixbuf' => $do->{'drawing_pixbuf'});

			#save new pixbuf in var
			$self->{_drawing_pixbuf} = $do->{'drawing_pixbuf'}->copy;

			#update bounds and bg_rects
			$self->{_canvas_bg_rect}->set(
				'x'      => $do->{'x'},
				'y'      => $do->{'y'},
				'width'  => $do->{'width'},
				'height' => $do->{'height'},
			);

			#we need to move the shapes
			$self->move_all($opt1->{x}, $opt1->{y});

		} elsif ($item->isa('GooCanvas2::CanvasRect') && $item == $self->{_canvas_bg_rect}) {

			#~ print "xdo canvas_bg_rect\n";

			$self->{_canvas_bg_rect}->set(
				'x'      => $do->{'x'},
				'y'      => $do->{'y'},
				'width'  => $do->{'width'},
				'height' => $do->{'height'},
			);

			#polyline specific properties
		} elsif ($item->isa('GooCanvas2::CanvasPolyline')) {

			#if pattern exists
			#e.g. censor tool does not have a pattern
			if ($do->{'stroke-pattern'}) {

				$self->{_items}{$item}->set(
					'stroke-color-gdk-rgba' => $do->{'stroke_color'},
					'line-width'     => $do->{'line-width'},
					'points'         => $do->{'points'},
					'transform'      => $do->{'transform'},
				);

				$self->{_items}{$item}{stroke_color}       = $do->{'stroke_color'};

			} else {

				$self->{_items}{$item}->set(
					'line-width' => $do->{'line-width'},
					'points'     => $do->{'points'},
					'transform'  => $do->{'transform'},
				);
			}

		}

		#handle resize rectangles and embedded objects
		if ($item == $self->{_canvas_bg}) {

			$self->handle_bg_rects('update', $self->{_canvas_bg_rect});

		} elsif ($item == $self->{_canvas_bg_rect}) {

			$self->handle_bg_rects('update', $self->{_canvas_bg_rect});

		} else {

			$self->handle_rects('update', $self->{_items}{$item});
			$self->handle_embedded('update', $self->{_items}{$item}, undef, undef, TRUE);

			#apply item properties to widgets
			#line width, fill color, stroke color etc.
			$self->set_and_save_drawing_properties($self->{_current_item}, FALSE);

		}

		#adjust stack order
		$self->{_canvas_bg}->lower;
		$self->{_canvas_bg_rect}->lower;
		$self->handle_bg_rects('raise');

	} elsif ($action eq 'raise' || $action eq 'raise_xdo') {

		my $child = $self->get_child_item($item);
		if ($child) {
			$self->handle_rects('lower', $item);
			$child->lower;
			$item->lower;
		} else {
			$self->handle_rects('lower', $item);
			$item->lower;
		}
		$self->{_canvas_bg}->lower;
		$self->{_canvas_bg_rect}->lower;

	} elsif ($action eq 'lower' || $action eq 'lower_xdo') {

		my $child = $self->get_child_item($item);
		if ($child) {
			$child->raise;
			$item->raise;
			$self->handle_rects('raise', $item);
		} else {
			$item->raise;
			$self->handle_rects('raise', $item);
		}

	} elsif ($action eq 'delete' || $action eq 'delete_xdo') {

		#mark as current
		$self->{_current_item}     = $item;
		$self->{_current_new_item} = undef;

		$self->{_items}{$item}->set('visibility' => 'visible');
		$self->handle_rects('update', $self->{_items}{$item});
		$self->handle_embedded('update', $self->{_items}{$item}, undef, undef, TRUE);

	} elsif ($action eq 'create' || $action eq 'create_xdo') {

		$self->{_items}{$item}->set('visibility' => 'hidden');
		$self->handle_rects('hide', $self->{_items}{$item});
		$self->handle_embedded('hide', $self->{_items}{$item});

	}

	#disable undo/redo actions
	$self->{_uimanager}->get_widget("/MenuBar/Edit/Undo")->set_sensitive(scalar @{$self->{_undo}}) if defined $self->{_undo};
	$self->{_uimanager}->get_widget("/MenuBar/Edit/Redo")->set_sensitive(scalar @{$self->{_redo}}) if defined $self->{_redo};

	$self->{_uimanager}->get_widget("/ToolBar/Undo")->set_sensitive(scalar @{$self->{_undo}}) if defined $self->{_undo};
	$self->{_uimanager}->get_widget("/ToolBar/Redo")->set_sensitive(scalar @{$self->{_redo}}) if defined $self->{_redo};

	$self->deactivate_all;

	return TRUE;
}

sub set_and_save_drawing_properties {
	my $self      = shift;
	my $item      = shift;
	my $save_only = shift;

	return FALSE unless $item;

	#~ print "set_and_save_drawing_properties1\n";

	#determine key for item hash
	if (my $child = $self->get_child_item($item)) {
		$item = $child;
	}
	my $parent = $self->get_parent_item($item);
	my $key    = $self->get_item_key($item, $parent);

	return FALSE unless $key;

	#~ print "set_and_save_drawing_properties2\n";

	#we do not remember the properties for some tools
	#and don't remember them when just selecting items with the cursor
	if (   $self->{_items}{$key}{type} ne "highlighter"
		&& $self->{_items}{$key}{type} ne "censor"
		&& $self->{_items}{$key}{type} ne "image"
		&& $self->{_items}{$key}{type} ne "pixelize"
		&& $self->{_current_mode} != 10)
	{

		#remember drawing colors, line width and font settings
		#maybe we have to restore them
		$self->{_last_fill_color}         = $self->{_fill_color_w}->get_rgba;
		$self->{_last_stroke_color}       = $self->{_stroke_color_w}->get_rgba;
		$self->{_last_line_width}         = $self->{_line_spin_w}->get_value;
		$self->{_last_font}               = $self->{_font_btn_w}->get_font_name;

		#remember the last mode as well
		$self->{_last_mode} = $self->{_current_mode};

	}

	return TRUE if $save_only;

	#block 'value-change' handlers for widgets
	#so we do not apply the changes twice
	$self->{_line_spin_w}->signal_handler_block($self->{_line_spin_wh});
	$self->{_stroke_color_w}->signal_handler_block($self->{_stroke_color_wh});
	$self->{_fill_color_w}->signal_handler_block($self->{_fill_color_wh});
	$self->{_font_btn_w}->signal_handler_block($self->{_font_btn_wh});

	#~ print "set_and_save_drawing_properties3\n";

	if (   $item->isa('GooCanvas2::CanvasRect')
		|| $item->isa('GooCanvas2::CanvasEllipse')
		|| $item->isa('GooCanvas2::CanvasPolyline'))
	{

		#line width
		$self->{_line_spin_w}->set_value($item->get('line-width'));

		#stroke color
		#some items, e.g. censor tool, do not have a color - skip them
		if ($self->{_items}{$key}{stroke_color}) {

			#~ print $self->{_items}{$key}{stroke_color}->to_string, "\n";

			$self->{_stroke_color_w}->set_rgba($self->{_items}{$key}{stroke_color});
		}

		if ($item->isa('GooCanvas2::CanvasRect') || $item->isa('GooCanvas2::CanvasEllipse')) {

			#fill color
			$self->{_fill_color_w}->set_rgba($self->{_items}{$key}{fill_color});

			#numbered shapes
			if (exists($self->{_items}{$key}{text})) {

				#determine font description from string
				my ($attr_list, $text_raw, $accel_char) = Pango->parse_markup($self->{_items}{$key}{text}->get('text'));
				my $font_desc = $attr_list->get_iterator->get_font;

				#apply current font settings to button
				$self->{_font_btn_w}->set_font_name($font_desc ? $font_desc->to_string : $self->{_font});

			}
		}

	} elsif ($item->isa('GooCanvas2::CanvasText')) {

		#determine font description from string
		my ($attr_list, $text_raw, $accel_char) = Pango->parse_markup($item->get('text'));
		my $font_desc = $attr_list->get_iterator->get_font;

		#font color
		$self->{_stroke_color_w}->set_rgba($self->{_items}{$key}{stroke_color});

		#apply current font settings to button
		$self->{_font_btn_w}->set_font_name($font_desc ? $font_desc->to_string : $self->{_font});

	}

	#update global values
	$self->{_line_width}         = $self->{_line_spin_w}->get_value;
	$self->{_stroke_color}       = $self->{_stroke_color_w}->get_rgba;
	$self->{_fill_color}         = $self->{_fill_color_w}->get_rgba;
	my $font_descr = Pango::FontDescription->from_string($self->{_font_btn_w}->get_font_name);
	$self->{_font} = $self->{_font_btn_w}->get_font_name;

	#unblock 'value-change' handlers for widgets
	$self->{_line_spin_w}->signal_handler_unblock($self->{_line_spin_wh});
	$self->{_stroke_color_w}->signal_handler_unblock($self->{_stroke_color_wh});
	$self->{_fill_color_w}->signal_handler_unblock($self->{_fill_color_wh});
	$self->{_font_btn_w}->signal_handler_unblock($self->{_font_btn_wh});

}

sub restore_fixed_properties {
	my $self = shift;
	my $mode = shift;

	#~ print "restore_highlighter_properties\n";

	#block 'value-change' handlers for widgets
	#so we do not apply the changes twice
	$self->{_line_spin_w}->signal_handler_block($self->{_line_spin_wh});
	$self->{_stroke_color_w}->signal_handler_block($self->{_stroke_color_wh});
	$self->{_fill_color_w}->signal_handler_block($self->{_fill_color_wh});
	$self->{_font_btn_w}->signal_handler_block($self->{_font_btn_wh});

	if ($mode eq "highlighter") {

		#highlighter
		my $fill_color = Gtk3::Gdk::RGBA::parse('#00000000ffff');
		$fill_color->alpha(0.234683756771191);
		$self->{_fill_color_w}->set_rgba($fill_color);
		my $stroke_color = Gtk3::Gdk::RGBA::parse('#ffffffff0000');
		$stroke_color->alpha(0.499992370489052);
		$self->{_stroke_color_w}->set_rgba($stroke_color);
		$self->{_line_spin_w}->set_value(18);
	} elsif ($mode eq "censor") {

		#censor
		$self->{_line_spin_w}->set_value(14);
	}

	#update global values
	$self->{_line_width}         = $self->{_line_spin_w}->get_value;
	$self->{_stroke_color}       = $self->{_stroke_color_w}->get_rgba;
	$self->{_fill_color}         = $self->{_fill_color_w}->get_rgba;

	#unblock 'value-change' handlers for widgets
	$self->{_line_spin_w}->signal_handler_unblock($self->{_line_spin_wh});
	$self->{_stroke_color_w}->signal_handler_unblock($self->{_stroke_color_wh});
	$self->{_fill_color_w}->signal_handler_unblock($self->{_fill_color_wh});
	$self->{_font_btn_w}->signal_handler_unblock($self->{_font_btn_wh});

}

sub restore_drawing_properties {
	my $self = shift;

	#saved properties available?
	return FALSE unless defined $self->{_last_fill_color};

	#anything done until now?
	return FALSE unless defined $self->{_last_mode};

	#~ print "restore_drawing_properties\n";

	#block 'value-change' handlers for widgets
	#so we do not apply the changes twice
	$self->{_line_spin_w}->signal_handler_block($self->{_line_spin_wh});
	$self->{_stroke_color_w}->signal_handler_block($self->{_stroke_color_wh});
	$self->{_fill_color_w}->signal_handler_block($self->{_fill_color_wh});
	$self->{_font_btn_w}->signal_handler_block($self->{_font_btn_wh});

	#restore them
	$self->{_fill_color_w}->set_rgba($self->{_last_fill_color});
	$self->{_stroke_color_w}->set_rgba($self->{_last_stroke_color});
	$self->{_line_spin_w}->set_value($self->{_last_line_width});
	$self->{_font_btn_w}->set_font_name($self->{_last_font});

	#update global values
	$self->{_line_width}         = $self->{_line_spin_w}->get_value;
	$self->{_stroke_color}       = $self->{_stroke_color_w}->get_rgba;
	$self->{_fill_color}         = $self->{_fill_color_w}->get_rgba;
	my $font_descr = Pango::FontDescription->from_string($self->{_font_btn_w}->get_font_name);
	$self->{_font} = $self->{_font_btn_w}->get_font_name;

	#unblock 'value-change' handlers for widgets
	$self->{_line_spin_w}->signal_handler_unblock($self->{_line_spin_wh});
	$self->{_stroke_color_w}->signal_handler_unblock($self->{_stroke_color_wh});
	$self->{_fill_color_w}->signal_handler_unblock($self->{_fill_color_wh});
	$self->{_font_btn_w}->signal_handler_unblock($self->{_font_btn_wh});

}

sub event_item_on_key_press {
	my ($self, $item, $target, $ev) = @_;

	if ($self->{_current_item}) {

		#current item
		my $curr_item = $self->{_current_item};

		if (exists $self->{_items}{$curr_item}) {

			#construct an motion-notify event
			my $mevent = Gtk3::Gdk::Event->new('motion-notify');
			$mevent->state('button2-mask');
			$mevent->time(Gtk3::get_current_event_time());
			$mevent->window($self->{_drawing_window}->get_window);

			#get current x, y values
			my $old_x = $self->{_items}{$curr_item}->get('x');
			my $old_y = $self->{_items}{$curr_item}->get('y');

			#set item flags
			$curr_item->{drag_x}         = $old_x;
			$curr_item->{drag_y}         = $old_y;
			$curr_item->{dragging}       = TRUE;
			$curr_item->{dragging_start} = TRUE;

			#move with arrow keys
			if ($ev->keyval == Gtk3::Gdk::keyval_from_name('Up')) {

				#~ print $ev->keyval," $old_x,$old_y-up\n";
				$mevent->x($old_x);
				$mevent->y($old_y - 1);
			} elsif ($ev->keyval == Gtk3::Gdk::keyval_from_name('Down')) {

				#~ print $ev->keyval," $old_x,$old_y-down\n";
				$mevent->x($old_x);
				$mevent->y($old_y + 1);
			} elsif ($ev->keyval == Gtk3::Gdk::keyval_from_name('Left')) {

				#~ print $ev->keyval," $old_x,$old_y-left\n";
				$mevent->x($old_x - 1);
				$mevent->y($old_y);
			} elsif ($ev->keyval == Gtk3::Gdk::keyval_from_name('Right')) {

				#~ print $ev->keyval," $old_x,$old_y-right\n";
				$mevent->x($old_x + 1);
				$mevent->y($old_y);
			} else {
				return FALSE;
			}

			#finally call motion-notify handler
			$self->event_item_on_motion_notify($curr_item, $target, $mevent);

		}

	}

	return TRUE;
}

sub event_item_on_button_press {
	my ($self, $item, $target, $ev, $select) = @_;

	#~ print "button-press\n";

	#canvas is busy now...
	$self->{_busy} = TRUE;

	my $cursor = Gtk3::Gdk::Cursor->new('left-ptr');

	#activate item
	#if it is not activated yet
	# => single click
	if ($ev->type eq 'button-press' && ($self->{_current_mode_descr} eq "select" || $select || $ev->button == 2 || $ev->button == 3)) {

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if (exists $self->{_items}{$item}) {

			unless (defined $self->{_current_item} && $item == $self->{_current_item}) {

				unless ($self->{_current_mode_descr} eq "number" || $self->{_current_mode_descr} eq "text") {

					unless ($self->{_items}{$item}{locked}) {

						#deactivate last item
						my $last_item = $self->{_current_item};
						if (defined $last_item) {

							#~ print "deactivated item: $last_item\n";
							$self->{_canvas}->pointer_ungrab($last_item, $ev->time);
							$self->{_canvas}->keyboard_ungrab($last_item, $ev->time);
							$self->handle_rects('hide', $last_item);
						}

						#mark as active item
						$self->{_current_item}     = $item;
						$self->{_current_new_item} = undef;

						$self->handle_rects('update', $self->{_current_item});

						#apply item properties to widgets
						#line width, fill color, stroke color etc.
						$self->set_and_save_drawing_properties($self->{_current_item}, FALSE);

						#~ print "activated item: $item\n";

					} else {

						$self->deactivate_all;

						#~ print "deactivate because $item is locked\n";

					}

				} else {

					$self->deactivate_all($self->{_current_item});

					#~ print "deactivate because $item is text or number\n";

				}

			} else {

				#~ print "no activate because $item is already current item\n";

			}

			#no item selected, deactivate all items
		} elsif ($item == $self->{_canvas_bg_rect}) {

			$self->deactivate_all;

			#~ print "deactivate because $item is background rectangle\n";

		} else {

			#~ print "no activate because $item does not exist\n";

		}
	} else {

		#~ print "no activate action\n";

	}

	#left mouse click to drag, resize, create or delelte items
	if ($ev->type eq 'button-press' && ($ev->button == 1 || $ev->button == 2)) {

		#MOVE
		if ($self->{_current_mode_descr} eq "select" || $ev->button == 2) {

			#don't_move the bounding rectangle or the bg_image
			return TRUE if $item == $self->{_canvas_bg_rect};

			#don't move locked item
			return TRUE if (exists $self->{_items}{$item} && $self->{_items}{$item}{locked});

			if ($item->isa('GooCanvas2::CanvasRect')) {

				#real shape => move
				if (exists $self->{_items}{$item}) {
					$item->{drag_x}         = $ev->x;
					$item->{drag_y}         = $ev->y;
					$item->{dragging}       = TRUE;
					$item->{dragging_start} = TRUE;

					$cursor = Gtk3::Gdk::Cursor->new('fleur');

					#resizing shape => resize
				} else {
					$item->{res_x}    = $ev->x;
					$item->{res_y}    = $ev->y;
					$item->{resizing} = TRUE;

					$cursor = undef;

					#resizing the canvas_bg_rect
					if (   $self->{_canvas_bg_rect}{'right-side'} == $item
						|| $self->{_canvas_bg_rect}{'bottom-side'} == $item
						|| $self->{_canvas_bg_rect}{'bottom-right-corner'} == $item)
					{

						#add to undo stack
						$self->store_to_xdo_stack($self->{_canvas_bg_rect}, 'modify', 'undo');

						#other resizing rectangles
					} else {

						#add to undo stack
						$self->store_to_xdo_stack($self->{_current_item}, 'modify', 'undo');

					}

					#restore style pattern
					$item->set('fill-color-gdk-rgba' => $self->{_style_bg});

				}

				#no rectangle, e.g. polyline
			} else {

				#no rect, just move it ...
				$item->{drag_x}         = $ev->x;
				$item->{drag_y}         = $ev->y;
				$item->{dragging}       = TRUE;
				$item->{dragging_start} = TRUE;

				#add to undo stack
				#~ $self->store_to_xdo_stack($self->{_current_item} , 'modify', 'undo');

				$cursor = undef;

			}

			#~ print "grab keyboard and pointer focus for $item\n";

			#grab keyboard and pointer focus
			eval {
				$self->{_canvas}->pointer_grab($item, ['pointer-motion-mask', 'button-release-mask'], $cursor, $ev->time);
			};
			if ($@) {
				# workaround for https://gitlab.gnome.org/GNOME/goocanvas/-/merge_requests/8
				$self->{_canvas}->pointer_grab($item, ['pointer-motion-mask', 'button-release-mask'], Gtk3::Gdk::Cursor->new('left-ptr'), $ev->time);
			}
			$self->{_canvas}->grab_focus($item);

			#current mode not equal 'select' and no polyline
		} elsif ($ev->button == 1) {

			#resizing shape => resize (no real shape)
			#no polyline modes
			if (   $item->isa('GooCanvas2::CanvasRect')
				&& !exists $self->{_items}{$item}
				&& $item != $self->{_canvas_bg_rect}
				&& $self->{_current_mode_descr} ne "freehand"
				&& $self->{_current_mode_descr} ne "highlighter"
				&& $self->{_current_mode_descr} ne "censor")
			{

				$item->{res_x}    = $ev->x;
				$item->{res_y}    = $ev->y;
				$item->{resizing} = TRUE;

				$cursor = undef;

				#resizing the canvas_bg_rect
				if (   $self->{_canvas_bg_rect}{'right-side'} == $item
					|| $self->{_canvas_bg_rect}{'bottom-side'} == $item
					|| $self->{_canvas_bg_rect}{'bottom-right-corner'} == $item)
				{

					#add to undo stack
					$self->store_to_xdo_stack($self->{_canvas_bg_rect}, 'modify', 'undo');

					#other resizing rectangles
				} else {

					#add to undo stack
					$self->store_to_xdo_stack($self->{_current_item}, 'modify', 'undo');

				}

				#restore style pattern
				$item->set('fill-color-gdk-rgba' => $self->{_style_bg});

				#~ print "grab keyboard and pointer focus for $item\n";

				#grab keyboard and pointer focus
				eval {
					$self->{_canvas}->pointer_grab($item, ['pointer-motion-mask', 'button-release-mask'], $cursor, $ev->time);
				};
				if ($@) {
					# workaround for https://gitlab.gnome.org/GNOME/goocanvas/-/merge_requests/8
					$self->{_canvas}->pointer_grab($item, ['pointer-motion-mask', 'button-release-mask'], Gtk3::Gdk::Cursor->new('left-ptr'), $ev->time);
				}
				$self->{_canvas}->grab_focus($item);

				#create new item
			} else {

				#freehand
				if ($self->{_current_mode_descr} eq "freehand") {

					$self->deactivate_all;

					$self->create_polyline($ev, undef, FALSE);

					#highlighter
				} elsif ($self->{_current_mode_descr} eq "highlighter") {

					$self->deactivate_all;

					$self->create_polyline($ev, undef, TRUE);

					#Line
				} elsif ($self->{_current_mode_descr} eq "line") {

					$self->create_line($ev, undef);

					#Arrow
				} elsif ($self->{_current_mode_descr} eq "arrow") {

					$self->create_line($ev, undef, TRUE, FALSE);

					#Censor
				} elsif ($self->{_current_mode_descr} eq "censor") {

					$self->deactivate_all;

					$self->create_censor($ev, undef);

					#Number
				} elsif ($self->{_current_mode_descr} eq "number") {

					$self->create_ellipse($ev, undef, TRUE);

					#RECTANGLES
				} elsif ($self->{_current_mode_descr} eq "rect") {

					$self->create_rectangle($ev, undef);

					#ELLIPSE
				} elsif ($self->{_current_mode_descr} eq "ellipse") {

					$self->create_ellipse($ev, undef);

					#TEXT
				} elsif ($self->{_current_mode_descr} eq "text") {

					$self->create_text($ev, undef);

					#IMAGE
				} elsif ($self->{_current_mode_descr} eq "image") {

					$self->create_image($ev, undef);

					#PIXELIZE
				} elsif ($self->{_current_mode_descr} eq "pixelize") {

					$self->create_pixel_image($ev, undef);

				}

				#grab keyboard focus
				if (my $nitem = $self->{_current_new_item}) {

					#~ print "grab keyboard focus for new item $nitem\n";
					$self->{_canvas}->grab_focus($nitem);
				}

			}

		}

		#right click => show context menu, double-click => show properties directly
	} elsif ($ev->type eq '2button-press' || $ev->button == 3) {

		$self->{_canvas}->pointer_ungrab($item, $ev->time);
		$self->{_canvas}->keyboard_ungrab($item, $ev->time);

		#determine key for item hash
		if (my $child = $self->get_child_item($item)) {
			$item = $child;
		}
		my $parent = $self->get_parent_item($item);
		my $key    = $self->get_item_key($item, $parent);

		#real shape
		if (defined $key && exists $self->{_items}{$key}) {
			if (   $ev->type eq '2button-press'
				&& $ev->button == 1
				&& $self->{_current_mode_descr} ne "text"
				&& $self->{_current_mode_descr} ne "number"
				&& $self->{_current_mode_descr} ne "freehand"
				&& $self->{_current_mode_descr} ne "highlighter"
				&& $self->{_current_mode_descr} ne "censor")
			{

				#some items do not have properties, e.g. images or censor
				return FALSE if $item->isa('GooCanvas2::CanvasImage') || !exists($self->{_items}{$key}{stroke_color});

				#~ print $item, $parent, $key, "\n";

				$self->show_item_properties($item, $parent, $key);

			} elsif ($ev->type eq 'button-press' && $ev->button == 3) {

				my $item_menu = $self->ret_item_menu($item, $parent, $key);

				$item_menu->popup(
					undef,    # parent menu shell
					undef,    # parent menu item
					undef,    # menu pos func
					undef,    # data
					$ev->button,
					$ev->time
				);
			}

		} else {

			#background rectangle
			if ($item == $self->{_canvas_bg_rect}) {
				my $bg_menu = $self->ret_background_menu($item);

				$bg_menu->popup(
					undef,    # parent menu shell
					undef,    # parent menu item
					undef,    # menu pos func
					undef,    # data
					$ev->button,
					$ev->time
				);
			}
		}

		#canvas idle now
		$self->{_busy} = FALSE;

	}

	return TRUE;
}

sub ret_background_menu {
	my $self = shift;
	my $item = shift;

	my $menu_bg = Gtk3::Menu->new;

	#properties
	my $prop_item = Gtk3::ImageMenuItem->new($self->{_d}->get("Change Background Color..."));
	$prop_item->set_image(Gtk3::Image->new_from_stock('gtk-select-color', 'menu'));
	$prop_item->signal_connect(
		'activate' => sub {
			my $color_dialog = Gtk3::ColorChooserDialog->new($self->{_d}->get("Choose fill color"));

			#add reset button
			my $reset_btn = Gtk3::Button->new_with_mnemonic($self->{_d}->get("_Reset to Default"));
			$color_dialog->add_action_widget($reset_btn, 'reject');

			$color_dialog->set_rgba($self->{_canvas_bg_rect}{fill_color});

			$color_dialog->show_all;

			#run dialog
			my $response = 'reject';
			while ($response eq 'reject') {
				$response = $color_dialog->run;
				if ($response eq 'ok') {

					#apply new color
					$self->{_canvas_bg_rect}{fill_color} = $color_dialog->get_rgba;
					$self->{_canvas_bg_rect}{fill_color}->alpha(1);
					$self->{_canvas_bg_rect}->set('fill-color-gdk-rgba', $self->{_canvas_bg_rect}{fill_color});
					last;
				} elsif ($response eq 'reject') {
					$color_dialog->set_rgba(Gtk3::Gdk::RGBA::parse('gray'));
				} else {
					last;
				}
			}

			$color_dialog->destroy;

		});

	$menu_bg->append($prop_item);

	$menu_bg->show_all;

	return $menu_bg;
}

sub ret_item_menu {
	my $self   = shift;
	my $item   = shift;
	my $parent = shift;
	my $key    = shift;

	#~ print "ret_item_menu\n";

	my $menu_item = Gtk3::Menu->new;

	#raise
	my $raise_item = Gtk3::ImageMenuItem->new($self->{_d}->get("Raise"));
	$raise_item->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size($self->{_dicons} . '/draw-raise.png', Gtk3::IconSize->lookup('menu'))));
	$raise_item->signal_connect(
		'activate' => sub {
			if ($parent) {

				#add to undo stack
				$self->store_to_xdo_stack($parent, 'raise', 'undo');
				$parent->raise;
				$item->raise;
				$self->handle_rects('raise', $parent);
			} else {

				#add to undo stack
				$self->store_to_xdo_stack($item, 'raise', 'undo');
				$item->raise;
				$self->handle_rects('raise', $item);
			}
		});

	$menu_item->append($raise_item);

	#lower
	my $lower_item = Gtk3::ImageMenuItem->new($self->{_d}->get("Lower"));
	$lower_item->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size($self->{_dicons} . '/draw-lower.png', Gtk3::IconSize->lookup('menu'))));

	$lower_item->signal_connect(
		'activate' => sub {
			if ($parent) {

				#add to undo stack
				$self->store_to_xdo_stack($parent, 'lower', 'undo');
				$self->handle_rects('lower', $parent);
				$item->lower;
				$parent->lower;
			} else {

				#add to undo stack
				$self->store_to_xdo_stack($item, 'lower', 'undo');
				$self->handle_rects('lower', $item);
				$item->lower;
			}
			$self->{_canvas_bg}->lower;
			$self->{_canvas_bg_rect}->lower;
		});

	$menu_item->append($lower_item);

	$menu_item->append(Gtk3::SeparatorMenuItem->new);

	#copy item
	my $copy_item = Gtk3::ImageMenuItem->new_from_stock('gtk-copy');

	$copy_item->signal_connect(
		'activate' => sub {

			#clear clipboard
			$self->{_clipboard}->set_text("");
			$self->{_cut}               = FALSE;
			$self->{_current_copy_item} = $self->{_current_item};
		});

	$menu_item->append($copy_item);

	#cut item
	my $cut_item = Gtk3::ImageMenuItem->new_from_stock('gtk-cut');

	$cut_item->signal_connect(
		'activate' => sub {

			#clear clipboard
			$self->{_clipboard}->set_text("");
			$self->{_cut}               = TRUE;
			$self->{_current_copy_item} = $self->{_current_item};
			$self->clear_item_from_canvas($self->{_current_copy_item});
		});

	$menu_item->append($cut_item);

	#paste item
	my $paste_item = Gtk3::ImageMenuItem->new_from_stock('gtk-paste');

	$paste_item->signal_connect(
		'activate' => sub {
			$self->paste_item($self->{_current_copy_item}, $self->{_cut});
			$self->{_cut} = FALSE;
		});

	$menu_item->append($paste_item);

	#delete item
	my $remove_item = Gtk3::ImageMenuItem->new_from_stock('gtk-delete');

	$remove_item->signal_connect(
		'activate' => sub {
			$self->clear_item_from_canvas($item);
		});

	$menu_item->append($remove_item);

	$menu_item->append(Gtk3::SeparatorMenuItem->new);

	#add lock/unlock entry if item == background image
	if ($item == $self->{_canvas_bg}) {

		my $lock_item = undef;
		if (exists $self->{_items}{$key} && $self->{_items}{$key}{locked} == TRUE) {
			$lock_item = Gtk3::ImageMenuItem->new_with_label($self->{_d}->get("Unlock"));
			$lock_item->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size($self->{_dicons} . '/draw-unlocked.png', Gtk3::IconSize->lookup('menu'))));
		} elsif (exists $self->{_items}{$key} && $self->{_items}{$key}{locked} == FALSE) {
			$lock_item = Gtk3::ImageMenuItem->new_with_label($self->{_d}->get("Lock"));
			$lock_item->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size($self->{_dicons} . '/draw-locked.png', Gtk3::IconSize->lookup('menu'))));
		}

		#handler
		$lock_item->signal_connect(
			'activate' => sub {

				if (exists $self->{_items}{$key} && $self->{_items}{$key}{locked} == FALSE) {
					$self->{_items}{$key}{locked} = TRUE;
					$self->deactivate_all;
				} elsif (exists $self->{_items}{$key} && $self->{_items}{$key}{locked} == TRUE) {
					$self->{_items}{$key}{locked} = FALSE;
				}

			});

		$menu_item->append($lock_item);

		$menu_item->append(Gtk3::SeparatorMenuItem->new);
	}

	#properties
	my $prop_item = Gtk3::ImageMenuItem->new($self->{_d}->get("Edit Preferences..."));
	$prop_item->set_image(Gtk3::Image->new_from_stock('gtk-properties', 'menu'));

	#some items do not have properties, e.g. images or censor
	$prop_item->set_sensitive(FALSE) if $item->isa('GooCanvas2::CanvasImage') || !exists($self->{_items}{$key}{stroke_color});

	$prop_item->signal_connect(
		'activate' => sub {

			$self->show_item_properties($item, $parent, $key);

		});

	$menu_item->append($prop_item);

	$menu_item->show_all;

	return $menu_item;
}

sub get_item_key {
	my ($self, $item, $parent) = @_;
	if (exists $self->{_items}{$item}) {
		return $item;
	} else {
		return $parent;
	}
}

sub show_item_properties {
	my ($self, $item, $parent, $key) = @_;

	#~ print "show_item_properties\n";

	#create dialog
	my $prop_dialog = Gtk3::Dialog->new(
		$self->{_d}->get("Preferences"),
		$self->{_drawing_window},
		[qw/modal destroy-with-parent/],
		'gtk-cancel' => 'cancel',
		'gtk-ok'     => 'ok'
	);
	$prop_dialog->set_default_response('ok');

	#RECT OR ELLIPSE OR POLYLINE
	my $line_spin    = undef;
	my $fill_color   = undef;
	my $stroke_color = undef;

	#NUMBERED ELLIPSE
	my $number_spin = undef;

	#ARROW
	my $end_arrow   = undef;
	my $start_arrow = undef;
	my $arrow_spin  = undef;
	my $arrowl_spin = undef;
	my $arrowt_spin = undef;

	#TEXT
	my $font_btn;
	my $text;
	my $textview;
	my $font_color;

	#RECT OR ELLIPSE OR NUMBER OR POLYLINE
	#GENERAL SETTINGS
	if (   $item->isa('GooCanvas2::CanvasRect')
		|| $item->isa('GooCanvas2::CanvasEllipse')
		|| $item->isa('GooCanvas2::CanvasPolyline')
		|| ($item->isa('GooCanvas2::CanvasText') && defined $self->{_items}{$key}{ellipse}))
	{

		my $general_vbox = Gtk3::VBox->new(FALSE, 5);

		my $label_general = Gtk3::Label->new;
		$label_general->set_markup("<b>" . $self->{_d}->get("Main") . "</b>");
		my $frame_general = Gtk3::Frame->new();
		$frame_general->set_label_widget($label_general);
		$frame_general->set_shadow_type('none');
		$frame_general->set_border_width(5);
		$prop_dialog->get_child->add($frame_general);

		#line_width
		my $line_hbox = Gtk3::HBox->new(FALSE, 5);
		$line_hbox->set_border_width(5);
		my $linew_label = Gtk3::Label->new($self->{_d}->get("Line width") . ":");
		$line_spin = Gtk3::SpinButton->new_with_range(0.5, 20, 0.1);

		$line_spin->set_value($item->get('line-width'));

		$line_hbox->pack_start($linew_label, FALSE, TRUE, 12);
		$line_hbox->pack_start($line_spin,   TRUE,  TRUE, 0);
		$general_vbox->pack_start($line_hbox, FALSE, FALSE, 0);

		if ($item->isa('GooCanvas2::CanvasRect') || $item->isa('GooCanvas2::CanvasEllipse')) {

			#fill color
			my $fill_color_hbox = Gtk3::HBox->new(FALSE, 5);
			$fill_color_hbox->set_border_width(5);
			my $fill_color_label = Gtk3::Label->new($self->{_d}->get("Fill color") . ":");
			$fill_color = Gtk3::ColorButton->new();

			$fill_color->set_rgba($self->{_items}{$key}{fill_color});
			$fill_color->set_use_alpha(TRUE);
			$fill_color->set_title($self->{_d}->get("Choose fill color"));

			$fill_color_hbox->pack_start($fill_color_label, FALSE, TRUE, 12);
			$fill_color_hbox->pack_start($fill_color,       TRUE,  TRUE, 0);
			$general_vbox->pack_start($fill_color_hbox, FALSE, FALSE, 0);

		}

		#some items, e.g. censor tool, do not have a color - skip them
		if ($self->{_items}{$key}{stroke_color}) {

			#stroke color
			my $stroke_color_hbox = Gtk3::HBox->new(FALSE, 5);
			$stroke_color_hbox->set_border_width(5);
			my $stroke_color_label = Gtk3::Label->new($self->{_d}->get("Stroke color") . ":");
			$stroke_color = Gtk3::ColorButton->new();

			$stroke_color->set_rgba($self->{_items}{$key}{stroke_color});
			$stroke_color->set_use_alpha(TRUE);
			$stroke_color->set_title($self->{_d}->get("Choose stroke color"));

			$stroke_color_hbox->pack_start($stroke_color_label, FALSE, TRUE, 12);
			$stroke_color_hbox->pack_start($stroke_color,       TRUE,  TRUE, 0);
			$general_vbox->pack_start($stroke_color_hbox, FALSE, FALSE, 0);
		}

		$frame_general->add($general_vbox);

		#special shapes like numbered ellipse
		if (defined $self->{_items}{$key}{text}) {

			my $numbered_vbox = Gtk3::VBox->new(FALSE, 5);

			my $label_numbered = Gtk3::Label->new;
			$label_numbered->set_markup("<b>" . $self->{_d}->get("Numbering") . "</b>");
			my $frame_numbered = Gtk3::Frame->new();
			$frame_numbered->set_label_widget($label_numbered);
			$frame_numbered->set_shadow_type('none');
			$frame_numbered->set_border_width(5);
			$prop_dialog->get_child->add($frame_numbered);

			#current digit
			my $number_hbox = Gtk3::HBox->new(FALSE, 5);
			$number_hbox->set_border_width(5);
			my $numberw_label = Gtk3::Label->new($self->{_d}->get("Current value") . ":");
			$number_spin = Gtk3::SpinButton->new_with_range(0, 999, 1);

			$number_spin->set_value($self->{_items}{$key}{text}{digit});

			$number_hbox->pack_start($numberw_label, FALSE, TRUE, 12);
			$number_hbox->pack_start($number_spin,   TRUE,  TRUE, 0);
			$numbered_vbox->pack_start($number_hbox, FALSE, FALSE, 0);

			#font button
			my $font_hbox = Gtk3::HBox->new(FALSE, 5);
			$font_hbox->set_border_width(5);
			my $font_label = Gtk3::Label->new($self->{_d}->get("Font") . ":");
			$font_btn = Gtk3::FontButton->new();

			#determine font description from string
			my ($attr_list, $text_raw, $accel_char) = Pango->parse_markup($self->{_items}{$key}{text}->get('text'));
			my ($font_desc) = $attr_list->get_iterator->get_font;

			#apply current font settings to button
			$font_btn->set_font_name($font_desc ? $font_desc->to_string : $self->{_font});

			$font_hbox->pack_start($font_label, FALSE, TRUE, 12);
			$font_hbox->pack_start($font_btn,   TRUE,  TRUE, 0);
			$numbered_vbox->pack_start($font_hbox, FALSE, FALSE, 0);

			$frame_numbered->add($numbered_vbox);

		}

	}

	#ARROW item
	if (   $item->isa('GooCanvas2::CanvasPolyline')
		&& defined $self->{_items}{$key}{end_arrow}
		&& defined $self->{_items}{$key}{start_arrow})
	{
		my $arrow_vbox = Gtk3::VBox->new(FALSE, 5);

		my $label_arrow = Gtk3::Label->new;
		$label_arrow->set_markup("<b>" . $self->{_d}->get("Arrow") . "</b>");
		my $frame_arrow = Gtk3::Frame->new();
		$frame_arrow->set_label_widget($label_arrow);
		$frame_arrow->set_shadow_type('none');
		$frame_arrow->set_border_width(5);
		$prop_dialog->get_child->add($frame_arrow);

		#arrow_width
		my $arrow_hbox = Gtk3::HBox->new(FALSE, 5);
		$arrow_hbox->set_border_width(5);
		my $arroww_label = Gtk3::Label->new($self->{_d}->get("Width") . ":");
		$arrow_spin = Gtk3::SpinButton->new_with_range(0.5, 10, 0.1);

		$arrow_spin->set_value($item->get('arrow-width'));

		$arrow_hbox->pack_start($arroww_label, FALSE, TRUE,  12);
		$arrow_hbox->pack_start($arrow_spin,   TRUE,  TRUE,  0);
		$arrow_vbox->pack_start($arrow_hbox,   FALSE, FALSE, 0);

		#arrow_length
		my $arrowl_hbox = Gtk3::HBox->new(FALSE, 5);
		$arrowl_hbox->set_border_width(5);
		my $arrowl_label = Gtk3::Label->new($self->{_d}->get("Length") . ":");
		$arrowl_spin = Gtk3::SpinButton->new_with_range(0.5, 10, 0.1);

		$arrowl_spin->set_value($item->get('arrow-length'));

		$arrowl_hbox->pack_start($arrowl_label, FALSE, TRUE, 12);
		$arrowl_hbox->pack_start($arrowl_spin,  TRUE,  TRUE, 0);
		$arrow_vbox->pack_start($arrowl_hbox, FALSE, FALSE, 0);

		#arrow_tip_length
		my $arrowt_hbox = Gtk3::HBox->new(FALSE, 5);
		$arrowt_hbox->set_border_width(5);
		my $arrowt_label = Gtk3::Label->new($self->{_d}->get("Tip length") . ":");
		$arrowt_spin = Gtk3::SpinButton->new_with_range(0.5, 10, 0.1);

		$arrowt_spin->set_value($item->get('arrow-tip-length'));

		$arrowt_hbox->pack_start($arrowt_label, FALSE, TRUE, 12);
		$arrowt_hbox->pack_start($arrowt_spin,  TRUE,  TRUE, 0);
		$arrow_vbox->pack_start($arrowt_hbox, FALSE, FALSE, 0);

		#checkboxes for start and end arrows
		$end_arrow = Gtk3::CheckButton->new($self->{_d}->get("Display an arrow at the end of the line"));
		$end_arrow->set_active($self->{_items}{$key}{end_arrow});
		$start_arrow = Gtk3::CheckButton->new($self->{_d}->get("Display an arrow at the start of the line"));
		$start_arrow->set_active($self->{_items}{$key}{start_arrow});

		my $end_arrow_hbox = Gtk3::HBox->new(FALSE, 5);
		$end_arrow_hbox->set_border_width(5);

		my $start_arrow_hbox = Gtk3::HBox->new(FALSE, 5);
		$start_arrow_hbox->set_border_width(5);

		$end_arrow_hbox->pack_start($end_arrow, FALSE, TRUE, 12);
		$start_arrow_hbox->pack_start($start_arrow, FALSE, TRUE, 12);

		$arrow_vbox->pack_start($start_arrow_hbox, FALSE, FALSE, 0);
		$arrow_vbox->pack_start($end_arrow_hbox,   FALSE, FALSE, 0);

		#final packing
		$frame_arrow->add($arrow_vbox);

		#simple TEXT item (no numbered ellipse)
	} elsif ($item->isa('GooCanvas2::CanvasText')
		&& !defined $self->{_items}{$key}{ellipse})
	{

		my $text_vbox = Gtk3::VBox->new(FALSE, 5);

		my $label_text = Gtk3::Label->new;
		$label_text->set_markup("<b>" . $self->{_d}->get("Text") . "</b>");
		my $frame_text = Gtk3::Frame->new();
		$frame_text->set_label_widget($label_text);
		$frame_text->set_shadow_type('none');
		$frame_text->set_border_width(5);
		$prop_dialog->get_child->add($frame_text);

		#font button
		my $font_hbox = Gtk3::HBox->new(FALSE, 5);
		$font_hbox->set_border_width(5);
		my $font_label = Gtk3::Label->new($self->{_d}->get("Font") . ":");
		$font_btn = Gtk3::FontButton->new();

		#determine font description from string
		my ($attr_list, $text_raw, $accel_char) = Pango->parse_markup($item->get('text'));
		my ($font_desc) = Pango::FontDescription->from_string($self->{_font});

		$font_hbox->pack_start($font_label, FALSE, TRUE,  12);
		$font_hbox->pack_start($font_btn,   TRUE,  TRUE,  0);
		$text_vbox->pack_start($font_hbox,  FALSE, FALSE, 0);

		#font color
		my $font_color_hbox = Gtk3::HBox->new(FALSE, 5);
		$font_color_hbox->set_border_width(5);
		my $font_color_label = Gtk3::Label->new($self->{_d}->get("Font color") . ":");
		$font_color = Gtk3::ColorButton->new();
		$font_color->set_use_alpha(TRUE);

		$font_color->set_rgba($self->{_items}{$key}{stroke_color});
		$font_color->set_title($self->{_d}->get("Choose font color"));

		$font_color_hbox->pack_start($font_color_label, FALSE, TRUE, 12);
		$font_color_hbox->pack_start($font_color,       TRUE,  TRUE, 0);

		$text_vbox->pack_start($font_color_hbox, FALSE, FALSE, 0);

		#initial buffer
		my $text = Gtk3::TextBuffer->new;
		$text->set_text($text_raw);

		#textview
		my $textview_hbox = Gtk3::HBox->new(FALSE, 5);
		$textview_hbox->set_border_width(5);
		$textview = Gtk3::TextView->new_with_buffer($text);
		$textview->set_can_focus(TRUE);
		$textview->set_size_request(150, 200);
		$textview_hbox->pack_start($textview, TRUE, TRUE, 0);

		$text_vbox->pack_start($textview_hbox, TRUE, TRUE, 0);

		#use font checkbox
		my $use_font = Gtk3::CheckButton->new_with_label($self->{_d}->get("Use selected font"));
		$use_font->set_active(FALSE);

		$text_vbox->pack_start($use_font, TRUE, TRUE, 0);

		#use font color checkbox
		my $use_font_color = Gtk3::CheckButton->new_with_label($self->{_d}->get("Use selected font color"));
		$use_font_color->set_active(FALSE);

		$text_vbox->pack_start($use_font_color, TRUE, TRUE, 0);

		#apply changes directly
		$use_font->signal_connect(
			'toggled' => sub {

				$self->modify_text_in_properties($font_btn, $textview, $font_color, $item, $use_font, $use_font_color);

			});

		$use_font_color->signal_connect(
			'toggled' => sub {

				$self->modify_text_in_properties($font_btn, $textview, $font_color, $item, $use_font, $use_font_color);

			});

		$font_btn->signal_connect(
			'font-set' => sub {

				$self->modify_text_in_properties($font_btn, $textview, $font_color, $item, $use_font, $use_font_color);

			});

		$font_color->signal_connect(
			'color-set' => sub {

				$self->modify_text_in_properties($font_btn, $textview, $font_color, $item, $use_font, $use_font_color);

			});

		#apply current font settings to button
		$font_btn->set_font_name($font_desc ? $font_desc->to_string : $self->{_font});

		#FIXME >> why do we have to invoke this manually??
		$font_btn->signal_emit('font-set');

		$frame_text->add($text_vbox);

	}

	#instant changes
	my $store_count = 0;
	if (defined $line_spin) {
		$line_spin->signal_connect(
			'value-changed' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $fill_color) {
		$fill_color->signal_connect(
			'color-set' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $stroke_color) {
		$stroke_color->signal_connect(
			'color-set' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $number_spin) {
		$number_spin->signal_connect(
			'value-changed' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $end_arrow) {
		$end_arrow->signal_connect(
			'toggled' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $start_arrow) {
		$start_arrow->signal_connect(
			'toggled' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $arrow_spin) {
		$arrow_spin->signal_connect(
			'value-changed' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $arrowl_spin) {
		$arrowl_spin->signal_connect(
			'value-changed' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $arrowt_spin) {
		$arrowt_spin->signal_connect(
			'value-changed' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $font_btn) {
		$font_btn->signal_connect(
			'font-set' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $font_color) {
		$font_color->signal_connect(
			'color-set' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);
				$store_count++;
			});
	}
	if (defined $textview) {
		$textview->signal_connect(
			'key-release-event' => sub {
				$self->apply_properties(
					$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
					$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
				);

				$store_count++;
			});
	}

	#layout adjustments
	my $sg_prop = Gtk3::SizeGroup->new('horizontal');
	foreach ($prop_dialog->get_children->get_children) {
		if ($_->can('get_children')) {
			foreach ($_->get_children) {
				if ($_->can('get_children')) {
					foreach ($_->get_children) {
						if ($_->can('get_children')) {
							foreach ($_->get_children) {
								if ($_ =~ /Gtk3::Label/) {

									#~ print $_->get_text, "\n";
									$_->set_alignment(0, 0.5);
									$sg_prop->add_widget($_);
								}
							}
						}
					}
				}
			}
		}
	}

	#run dialog
	$prop_dialog->show_all;

	#textview grab focus to be able to edit
	#immediately
	if (defined $textview) {
		$textview->grab_focus;
	}
	my $prop_dialog_res = $prop_dialog->run;
	if ($prop_dialog_res eq 'ok') {

		$self->apply_properties(
			$item,     $parent,    $key,         $fill_color, $stroke_color, $line_spin,   $font_color,  $font_btn,
			$textview, $end_arrow, $start_arrow, $arrow_spin, $arrowl_spin,  $arrowt_spin, $number_spin, $store_count
		);

		#apply item properties to widgets
		#line width, fill color, stroke color etc.
		$self->set_and_save_drawing_properties($self->{_current_item}, FALSE);

		#FIXME - we need to save the changed values in this case
		$self->set_and_save_drawing_properties($self->{_current_item}, TRUE);

		$prop_dialog->destroy;
		return TRUE;
	} else {

		if ($store_count) {
			$self->xdo('undo', undef, TRUE);
		}

		$prop_dialog->destroy;
		return FALSE;
	}

}

sub apply_properties {
	my (

		$self,

		#item related infos
		$item,
		$parent,
		$key,

		#general properties
		$fill_color,
		$stroke_color,
		$line_spin,

		#only text
		$font_color,
		$font_btn,
		$textview,

		#only arrow
		$end_arrow,
		$start_arrow,
		$arrow_spin,
		$arrowl_spin,
		$arrowt_spin,

		#only numbered shapes
		$number_spin,

		#DO NOT STORE THE CHANGES (UNDO/REDO)
		$dont_store

	) = @_;

	#~ print "apply_properties\n";

	#remember drawing colors, line width and font settings
	#maybe we have to restore them
	if (   $self->{_items}{$key}{type} ne "highlighter"
		&& $self->{_items}{$key}{type} ne "censor")
	{

		$self->{_last_fill_color}         = $self->{_fill_color_w}->get_rgba;
		$self->{_last_stroke_color}       = $self->{_stroke_color_w}->get_rgba;
		$self->{_last_line_width}         = $self->{_line_spin_w}->get_value;
		$self->{_last_font}               = $self->{_font_btn_w}->get_font_name;

		#remember the last mode as well
		$self->{_last_mode} = $self->{_current_mode};

	}

	#add to undo stack
	unless ($dont_store) {
		$self->store_to_xdo_stack($self->{_current_item}, 'modify', 'undo');
	}

	#apply rect or ellipse options
	if ($item->isa('GooCanvas2::CanvasRect') || $item->isa('GooCanvas2::CanvasEllipse')) {

		$item->set(
			'line-width'     => $line_spin->get_value,
			'fill-color-gdk-rgba' => $fill_color->get_rgba,
			'stroke-color-gdk-rgba' => $stroke_color->get_rgba,
		);

		#special shapes like numbered ellipse (digit changed)
		if (defined $self->{_items}{$key}{text}) {

			#determine new or current digit
			my $digit = undef;
			if (defined $number_spin) {
				$digit = $number_spin->get_value;
			} else {
				$digit = $self->{_items}{$key}{text}{digit};
			}

			my $fill_color = undef;
			if (defined $font_color) {
				$fill_color = $font_color->get_rgba;
			} elsif (defined $stroke_color) {
				$fill_color = $stroke_color->get_rgba;
			}

			my $font_descr = Pango::FontDescription->from_string($font_btn->get_font_name);
			$self->{_items}{$key}{text}->set(
				'text'         => "<span font_desc=' " . $font_btn->get_font_name . " ' >" . $digit . "</span>",
				'fill-color-gdk-rgba' => $fill_color,
			);

			#adjust parent rectangle
			my $tb = $self->{_items}{$key}{text}->get_bounds;

			#keep ratio = 1
			my $qs = abs($tb->x1 - $tb->x2);
			$qs = abs($tb->y1 - $tb->y2) if abs($tb->y1 - $tb->y2) > abs($tb->x1 - $tb->x2);

			#add line width of parent ellipse
			$qs += $self->{_items}{$key}{ellipse}->get('line-width') + 5;

			$parent->set(
				'width'  => $qs,
				'height' => $qs,
			);

			#save digit in hash as well (only item properties dialog)
			if (defined $number_spin) {
				$self->{_items}{$key}{text}{digit} = $digit;
			}

			$self->handle_rects('update', $parent);
			$self->handle_embedded('update', $parent);

		}

		#save color and opacity as well
		$self->{_items}{$key}{fill_color}         = $fill_color->get_rgba;
		$self->{_items}{$key}{stroke_color}       = $stroke_color->get_rgba;
	}

	#apply polyline options (arrow)
	if (   $item->isa('GooCanvas2::CanvasPolyline')
		&& defined $self->{_items}{$key}{end_arrow}
		&& defined $self->{_items}{$key}{start_arrow})
	{

		#these values are only available in the item menu
		if (   defined $arrowl_spin
			&& defined $arrow_spin
			&& defined $arrowt_spin
			&& defined $end_arrow
			&& defined $start_arrow)
		{
			$item->set(
				'line-width'       => $line_spin->get_value,
				'stroke-color-gdk-rgba'   => $stroke_color->get_rgba,
				'end-arrow'        => $end_arrow->get_active,
				'start-arrow'      => $start_arrow->get_active,
				'arrow-length'     => $arrowl_spin->get_value,
				'arrow-width'      => $arrow_spin->get_value,
				'arrow-tip-length' => $arrowt_spin->get_value,
			);

		} else {
			$item->set(
				'line-width'     => $line_spin->get_value,
				'stroke-color-gdk-rgba'   => $stroke_color->get_rgba,
				'end-arrow'      => $self->{_items}{$key}{line}->get('end-arrow'),
				'start-arrow'    => $self->{_items}{$key}{line}->get('start-arrow'),
			);
		}

		#save color and opacity as well
		$self->{_items}{$key}{stroke_color}       = $stroke_color->get_rgba;

		#save arrow specific properties
		$self->{_items}{$key}{end_arrow}        = $self->{_items}{$key}{line}->get('end-arrow');
		$self->{_items}{$key}{start_arrow}      = $self->{_items}{$key}{line}->get('start-arrow');
		$self->{_items}{$key}{arrow_width}      = $self->{_items}{$key}{line}->get('arrow-width');
		$self->{_items}{$key}{arrow_length}     = $self->{_items}{$key}{line}->get('arrow-length');
		$self->{_items}{$key}{arrow_tip_length} = $self->{_items}{$key}{line}->get('arrow-tip-length');

		#apply polyline options (freehand, highlighter)
	} elsif ($item->isa('GooCanvas2::CanvasPolyline')
		&& defined $self->{_items}{$key}{stroke_color})
	{
		$item->set(
			'line-width'     => $line_spin->get_value,
			'stroke-color-gdk-rgba'   => $stroke_color->get_rgba,
		);

		#save color and opacity as well
		$self->{_items}{$key}{stroke_color}       = $stroke_color->get_rgba;
	}

	#apply text options
	if ($item->isa('GooCanvas2::CanvasText')) {
		my $font_descr = Pango::FontDescription->from_string($font_btn->get_font_name);

		my $new_text = undef;
		if ($textview) {
			$new_text = $textview->get_buffer->get_text($textview->get_buffer->get_start_iter, $textview->get_buffer->get_end_iter, FALSE)
				|| " ";
		} else {

			#determine font description and text from string
			my ($attr_list, $text_raw, $accel_char) = Pango->parse_markup($item->get('text'));
			$new_text = $text_raw;
		}

		$item->set(
			'text'         => "<span font_desc=' " . $font_btn->get_font_name . " ' >" . Glib::Markup::escape_text($new_text) . "</span>",
			'width'        => -1,
			'use-markup'   => TRUE,
			'fill-color-gdk-rgba' => $font_color->get_rgba,
		);

		#adjust parent rectangle
		my $tb = $item->get_bounds;
		$parent->set(
			'width'  => abs($tb->x1 - $tb->x2),
			'height' => abs($tb->y1 - $tb->y2),
		);

		$self->handle_rects('update', $parent);
		$self->handle_embedded('update', $parent);

		#save color and opacity as well
		$self->{_items}{$key}{stroke_color}       = $font_color->get_rgba;

	}

}

sub modify_text_in_properties {
	my $self           = shift;
	my $font_btn       = shift;
	my $textview       = shift;
	my $font_color     = shift;
	my $item           = shift;
	my $use_font       = shift;
	my $use_font_color = shift;

	my $font_descr = Pango::FontDescription->from_string($font_btn->get_font_name);
	my $texttag    = Gtk3::TextTag->new;

	if ($use_font->get_active && $use_font_color->get_active) {
		$texttag->set('font-desc' => $font_descr, 'foreground-rgba' => $font_color->get_rgba);
	} elsif ($use_font->get_active) {
		$texttag->set('font-desc' => $font_descr);
	} elsif ($use_font_color->get_active) {
		$texttag->set('foreground-rgba' => $font_color->get_rgba);
	}

	my $texttagtable = Gtk3::TextTagTable->new;
	$texttagtable->add($texttag);
	my $text = Gtk3::TextBuffer->new($texttagtable);
	$text->signal_connect(
		'changed' => sub {
			$text->apply_tag($texttag, $text->get_start_iter, $text->get_end_iter);
		});

	$text->set_text($textview->get_buffer->get_text($textview->get_buffer->get_start_iter, $textview->get_buffer->get_end_iter, FALSE));
	$text->apply_tag($texttag, $text->get_start_iter, $text->get_end_iter);
	$textview->set_buffer($text);

	return TRUE;
}

sub move_all {
	my ($self, $x, $y) = @_;

	foreach (keys %{$self->{_items}}) {

		my $item = $self->{_items}{$_};

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if (exists $self->{_items}{$item}) {

			if ($item->isa('GooCanvas2::CanvasRect')) {

				$item->set(
					'x' => $item->get('x') - $x,
					'y' => $item->get('y') - $y,
				);

				my $child = $self->get_child_item($item);
				$child = $item unless $child;

				#it item is hidden, keep the status
				if ($child->get('visibility') eq 'hidden') {
					$self->handle_rects('hide', $item);
					$self->handle_embedded('hide', $item);
				} else {
					$self->handle_rects('update', $item);

					#pixelizer is treated differently
					if ($child && $child->isa('GooCanvas2::CanvasImage')) {
						my $parent = $self->get_parent_item($child);

						if (exists $self->{_items}{$parent}{pixelize}) {

							Glib::Idle->add(
								sub {
									$self->{_items}{$parent}{pixelize}->set(
										'x'      => int $self->{_items}{$parent}->get('x'),
										'y'      => int $self->{_items}{$parent}->get('y'),
										'width'  => $self->{_items}{$parent}->get('width'),
										'height' => $self->{_items}{$parent}->get('height'),
										'pixbuf' => $self->get_pixelated_pixbuf_from_canvas($self->{_items}{$parent}),
									);

									$self->handle_embedded('update', $parent, undef, undef, TRUE);

									#deactivate all after move
									$self->deactivate_all;

									return FALSE;
								});

						} else {

							$self->handle_embedded('update', $item);

						}

					} else {

						$self->handle_embedded('update', $item);

					}
				}

				#freehand line for example
			} else {

				$item->translate(-$x, -$y);

			}

		}
	}

	#deactivate all after move
	$self->deactivate_all;

	return TRUE;
}

sub deactivate_all {
	my $self    = shift;
	my $exclude = shift || 0;

	#~ print "deactivate_all\n";

	foreach (keys %{$self->{_items}}) {

		my $item = $self->{_items}{$_};

		next if $item == $exclude;

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if (exists $self->{_items}{$item}) {
			$self->handle_rects('hide', $item);
		}

	}

	$self->{_current_item}     = undef;
	$self->{_current_new_item} = undef;

	return TRUE;
}

sub handle_embedded {
	my ($self, $action, $item, $new_width, $new_height, $force_show) = @_;

	return FALSE unless ($item && exists $self->{_items}{$item});

	if ($action eq 'update') {

		my $visibility = 'visible';

		#embedded ellipse
		if (exists $self->{_items}{$item}{ellipse}) {

			$self->{_items}{$item}{ellipse}->set(
				'center-x' => $self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width') / 2,
				'center-y' => $self->{_items}{$item}->get('y') + $self->{_items}{$item}->get('height') / 2,
			);
			$self->{_items}{$item}{ellipse}->set(
				'radius-x'   => $self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width') - $self->{_items}{$item}{ellipse}->get('center-x'),
				'radius-y'   => $item->get('y') + $self->{_items}{$item}->get('height') - $self->{_items}{$item}{ellipse}->get('center-y'),
				'visibility' => $visibility,
			);

			#numbered ellipse
			if (exists $self->{_items}{$item}{text}) {
				$self->{_items}{$item}{text}->set(
					'x'          => $self->{_items}{$item}{ellipse}->get('center-x'),
					'y'          => $self->{_items}{$item}{ellipse}->get('center-y'),
					'visibility' => $visibility,
				);
			}

		} elsif (exists $self->{_items}{$item}{text}) {
			$self->{_items}{$item}{text}->set(
				'x'          => $self->{_items}{$item}->get('x'),
				'y'          => $self->{_items}{$item}->get('y'),
				'width'      => $self->{_items}{$item}->get('width'),
				'visibility' => $visibility,
			);
		} elsif (exists $self->{_items}{$item}{line}) {

			#handle possible arrows properly
			#arrow is always and end-arrow
			if ($self->{_items}{$item}{mirrored_w} < 0 && $self->{_items}{$item}{mirrored_h} < 0) {
				$self->{_items}{$item}{line}->set(
					'points' => Shutter::Draw::Utils::points_to_canvas_points(
							$self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width'), $self->{_items}{$item}->get('y') + $self->{_items}{$item}->get('height'),
							$self->{_items}{$item}->get('x'),                                        $self->{_items}{$item}->get('y')
					),
					'visibility' => $visibility
				);
			} elsif ($self->{_items}{$item}{mirrored_w} < 0) {
				$self->{_items}{$item}{line}->set(
					'points' => Shutter::Draw::Utils::points_to_canvas_points(
							$self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width'), $self->{_items}{$item}->get('y'),
							$self->{_items}{$item}->get('x'),                                        $self->{_items}{$item}->get('y') + $self->{_items}{$item}->get('height')
					),
					'visibility' => $visibility
				);
			} elsif ($self->{_items}{$item}{mirrored_h} < 0) {
				$self->{_items}{$item}{line}->set(
					'points' => Shutter::Draw::Utils::points_to_canvas_points(
							$self->{_items}{$item}->get('x'),                                        $self->{_items}{$item}->get('y') + $self->{_items}{$item}->get('height'),
							$self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width'), $self->{_items}{$item}->get('y')
					),
					'visibility' => $visibility
				);
			} else {
				$self->{_items}{$item}{line}->set(
					'points' => Shutter::Draw::Utils::points_to_canvas_points(
							$self->{_items}{$item}->get('x'),                                        $self->{_items}{$item}->get('y'),
							$self->{_items}{$item}->get('x') + $self->{_items}{$item}->get('width'), $self->{_items}{$item}->get('y') + $self->{_items}{$item}->get('height')
					),
					'visibility' => $visibility
				);
			}

		} elsif (exists $self->{_items}{$item}{pixelize}) {

			if ($force_show) {
				$self->{_items}{$item}{pixelize}->set('visibility' => $visibility,);
			} else {
				$self->{_items}{$item}{pixelize}->set('visibility' => 'hidden',);
			}

		} elsif (exists $self->{_items}{$item}{image}) {

			if ($self->{_items}{$item}->get('width') == $self->{_items}{$item}{image}->get('width') && $self->{_items}{$item}->get('height') == $self->{_items}{$item}{image}->get('height')) {

				$self->{_items}{$item}{image}->set(
					'x'          => int $self->{_items}{$item}->get('x'),
					'y'          => int $self->{_items}{$item}->get('y'),
					'visibility' => $visibility,
				);

			} else {

				#be careful when resizing images
				#don't do anything when width or height are too small
				if ($self->{_items}{$item}->get('width') > 5 && $self->{_items}{$item}->get('height') > 5) {
					$self->{_items}{$item}{image}->set(
						'x'          => int $self->{_items}{$item}->get('x'),
						'y'          => int $self->{_items}{$item}->get('y'),
						'width'      => $self->{_items}{$item}->get('width'),
						'height'     => $self->{_items}{$item}->get('height'),
						'pixbuf'     => $self->{_items}{$item}{orig_pixbuf}->scale_simple($self->{_items}{$item}->get('width'), $self->{_items}{$item}->get('height'), 'nearest'),
						'visibility' => $visibility,
					);
				} else {
					$self->{_items}{$item}{image}->set(
						'x'          => int $self->{_items}{$item}->get('x'),
						'y'          => int $self->{_items}{$item}->get('y'),
						'width'      => $self->{_items}{$item}->get('width'),
						'height'     => $self->{_items}{$item}->get('height'),
						'visibility' => $visibility,
					);
				}

			}

		}
	} elsif ($action eq 'delete') {

		#ellipse
		if (exists $self->{_items}{$item}{ellipse}) {
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{ellipse})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
		}

		#text
		if (exists $self->{_items}{$item}{text}) {
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{text})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
		}

		#pixelize
		if (exists $self->{_items}{$item}{pixelize}) {
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{pixelize})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
		}

		#image
		if (exists $self->{_items}{$item}{image}) {
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{image})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
		}

		#line
		if (exists $self->{_items}{$item}{line}) {
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{line})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
		}

	} elsif ($action eq 'hide') {

		my $visibility = 'hidden';

		#ellipse => hide rectangle as well
		if (exists $self->{_items}{$item}{ellipse}) {
			$self->{_items}{$item}{ellipse}->set('visibility' => $visibility);
		}

		#text => hide rectangle as well
		if (exists $self->{_items}{$item}{text}) {
			$self->{_items}{$item}{text}->set('visibility' => $visibility);
		}

		#pixelize => hide rectangle as well
		if (exists $self->{_items}{$item}{pixelize}) {
			$self->{_items}{$item}{pixelize}->set('visibility' => $visibility);
		}

		#image => hide rectangle as well
		if (exists $self->{_items}{$item}{image}) {
			$self->{_items}{$item}{image}->set('visibility' => $visibility);
		}

		#line => hide rectangle as well
		if (exists $self->{_items}{$item}{line}) {
			$self->{_items}{$item}{line}->set('visibility' => $visibility);
		}

	} elsif ($action eq 'mirror') {
		if (exists $self->{_items}{$item}{line}) {

			#width
			if ($new_width < 0 && $self->{_items}{$item}{mirrored_w} >= 0) {
				$self->{_items}{$item}{mirrored_w} = $new_width;
			} elsif ($new_width < 0 && $self->{_items}{$item}{mirrored_w} < 0) {
				$self->{_items}{$item}{mirrored_w} = 0;
			}

			#height
			if ($new_height < 0 && $self->{_items}{$item}{mirrored_h} >= 0) {
				$self->{_items}{$item}{mirrored_h} = $new_height;
			} elsif ($new_height < 0 && $self->{_items}{$item}{mirrored_h} < 0) {
				$self->{_items}{$item}{mirrored_h} = 0;
			}
		}
	}

	return TRUE;
}

sub handle_bg_rects {
	my ($self, $action) = @_;

	my $x      = $self->{_canvas_bg_rect}->get('x');
	my $y      = $self->{_canvas_bg_rect}->get('y');
	my $width  = $self->{_canvas_bg_rect}->get('width');
	my $height = $self->{_canvas_bg_rect}->get('height');

	my $middle_h = $x + $width / 2;
	my $middle_v = $y + $height / 2;
	my $bottom   = $y + $height;
	my $top      = $y;
	my $left     = $x;
	my $right    = $x + $width;

	if ($action eq 'create') {


		$self->{_canvas_bg_rect}{'bottom-side'} = GooCanvas2::CanvasRect->new(
			parent=>$self->{_canvas}->get_root_item, x=>$middle_h, y=>$bottom, width=>8, height=>8,
			'fill-color-gdk-rgba' => $self->{_style_bg},
			'line-width'   => 1,
		);

		$self->{_canvas_bg_rect}{'bottom-right-corner'} = GooCanvas2::CanvasRect->new(
			parent=>$self->{_canvas}->get_root_item, x=>$right, y=>$bottom, width=>8, height=>8,
			'fill-color-gdk-rgba' => $self->{_style_bg},
			'line-width'   => 1,
		);

		$self->{_canvas_bg_rect}{'right-side'} = GooCanvas2::CanvasRect->new(
			parent=>$self->{_canvas}->get_root_item, x=>$right, y=>$middle_v, width=>8, height=>8,
			'fill-color-gdk-rgba' => $self->{_style_bg},
			'line-width'   => 1,
		);

		$self->setup_item_signals($self->{_canvas_bg_rect}{'bottom-side'});
		$self->setup_item_signals($self->{_canvas_bg_rect}{'bottom-right-corner'});
		$self->setup_item_signals($self->{_canvas_bg_rect}{'right-side'});
		$self->setup_item_signals_extra($self->{_canvas_bg_rect}{'bottom-side'});
		$self->setup_item_signals_extra($self->{_canvas_bg_rect}{'bottom-right-corner'});
		$self->setup_item_signals_extra($self->{_canvas_bg_rect}{'right-side'});

	} elsif ($action eq 'hide' || $action eq 'show') {

		my $visibility = undef;
		if ($action eq 'hide') {
			$visibility = 'hidden';
		} elsif ($action eq 'show') {
			$visibility = 'visible';
		}

		foreach (keys %{$self->{_canvas_bg_rect}}) {
			if ($self->{_canvas_bg_rect}{$_}->can('set')) {
				$self->{_canvas_bg_rect}{$_}->set('visibility' => $visibility,);
			}
		}    #end determine rect

	} elsif ($action eq 'update') {

		#update the canvas bounds as well
		$self->{_canvas}->set_bounds(0, 0, $self->{_canvas_bg_rect}->get('width'), $self->{_canvas_bg_rect}->get('height'));

		$self->{_canvas_bg_rect}{'bottom-side'}->set(
			'x' => $middle_h - 8,
			'y' => $bottom - 8,
		);

		$self->{_canvas_bg_rect}{'bottom-right-corner'}->set(
			'x' => $right - 8,
			'y' => $bottom - 8,
		);

		$self->{_canvas_bg_rect}{'right-side'}->set(
			'x' => $right - 8,
			'y' => $middle_v - 8,
		);

		$self->handle_bg_rects('raise');

	} elsif ($action eq 'raise') {
		$self->{_canvas_bg_rect}{'bottom-side'}->raise;
		$self->{_canvas_bg_rect}{'bottom-right-corner'}->raise;
		$self->{_canvas_bg_rect}{'right-side'}->raise;
	}
}

sub handle_rects {
	my ($self, $action, $item) = @_;

	#~ print "entering handle_rects1\n";

	return FALSE unless $item;
	return FALSE unless exists $self->{_items}{$item};

	#~ print "entering handle_rects2\n";

	#get root item
	my $root = $self->{_canvas}->get_root_item;

	if ($self->{_items}{$item}->isa('GooCanvas2::CanvasRect')) {

		my $x      = $self->{_items}{$item}->get('x');
		my $y      = $self->{_items}{$item}->get('y');
		my $width  = $self->{_items}{$item}->get('width');
		my $height = $self->{_items}{$item}->get('height');

		my $middle_h = $x + $width / 2;
		my $middle_v = $y + $height / 2;
		my $bottom   = $y + $height;
		my $top      = $y;
		my $left     = $x;
		my $right    = $x + $width;

		if ($action eq 'create') {

			$self->{_items}{$item}{'top-side'} = GooCanvas2::CanvasRect->new(
				parent=>$root, x=>$middle_h, y=>$top, width=>8, height=>8,
				'fill-color-gdk-rgba' => $self->{_style_bg},
				'visibility'   => 'hidden',
				'line-width'   => 0.5,
			);

			$self->{_items}{$item}{'top-left-corner'} = GooCanvas2::CanvasRect->new(
				parent=>$root, x=>$left, y=>$top, width=>8, height=>8,
				'fill-color-gdk-rgba' => $self->{_style_bg},
				'visibility'   => 'hidden',
				'line-width'   => 0.5,
				'radius-x'     => 8,
				'radius-y'     => 8,
			);

			$self->{_items}{$item}{'top-right-corner'} = GooCanvas2::CanvasRect->new(
				parent=>$root, x=>$right, y=>$top, width=>8, height=>8,
				'fill-color-gdk-rgba' => $self->{_style_bg},
				'visibility'   => 'hidden',
				'line-width'   => 0.5,
				'radius-x'     => 8,
				'radius-y'     => 8,
			);

			$self->{_items}{$item}{'bottom-side'} = GooCanvas2::CanvasRect->new(
				parent=>$root, x=>$middle_h, y=>$bottom, width=>8, height=>8,
				'fill-color-gdk-rgba' => $self->{_style_bg},
				'visibility'   => 'hidden',
				'line-width'   => 0.5,
			);

			$self->{_items}{$item}{'bottom-left-corner'} = GooCanvas2::CanvasRect->new(
				parent=>$root, x=>$left, y=>$bottom, width=>8, height=>8,
				'fill-color-gdk-rgba' => $self->{_style_bg},
				'visibility'   => 'hidden',
				'line-width'   => 0.5,
				'radius-x'     => 8,
				'radius-y'     => 8,
			);

			$self->{_items}{$item}{'bottom-right-corner'} = GooCanvas2::CanvasRect->new(
				parent=>$root, x=>$right, y=>$bottom, width=>8, height=>8,
				'fill-color-gdk-rgba' => $self->{_style_bg},
				'visibility'   => 'hidden',
				'line-width'   => 0.5,
				'radius-x'     => 8,
				'radius-y'     => 8,
			);

			$self->{_items}{$item}{'left-side'} = GooCanvas2::CanvasRect->new(
				parent=>$root, x=>$left - 8, y=>$middle_v, width=>8, height=>8,
				'fill-color-gdk-rgba' => $self->{_style_bg},
				'visibility'   => 'hidden',
				'line-width'   => 0.5,
			);

			$self->{_items}{$item}{'right-side'} = GooCanvas2::CanvasRect->new(
				parent=>$root, x=>$right, y=>$middle_v, width=>8, height=>8,
				'fill-color-gdk-rgba' => $self->{_style_bg},
				'visibility'   => 'hidden',
				'line-width'   => 0.5,
			);

			$self->setup_item_signals($self->{_items}{$item}{'top-side'});
			$self->setup_item_signals($self->{_items}{$item}{'top-left-corner'});
			$self->setup_item_signals($self->{_items}{$item}{'top-right-corner'});
			$self->setup_item_signals($self->{_items}{$item}{'bottom-side'});
			$self->setup_item_signals($self->{_items}{$item}{'bottom-left-corner'});
			$self->setup_item_signals($self->{_items}{$item}{'bottom-right-corner'});
			$self->setup_item_signals($self->{_items}{$item}{'left-side'});
			$self->setup_item_signals($self->{_items}{$item}{'right-side'});
			$self->setup_item_signals_extra($self->{_items}{$item}{'top-side'});
			$self->setup_item_signals_extra($self->{_items}{$item}{'top-left-corner'});
			$self->setup_item_signals_extra($self->{_items}{$item}{'top-right-corner'});
			$self->setup_item_signals_extra($self->{_items}{$item}{'bottom-side'});
			$self->setup_item_signals_extra($self->{_items}{$item}{'bottom-left-corner'});
			$self->setup_item_signals_extra($self->{_items}{$item}{'bottom-right-corner'});
			$self->setup_item_signals_extra($self->{_items}{$item}{'left-side'});
			$self->setup_item_signals_extra($self->{_items}{$item}{'right-side'});

		} elsif ($action eq 'delete') {

			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{'top-side'})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{'top-left-corner'})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{'top-right-corner'})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{'bottom-side'})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{'bottom-left-corner'})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{'bottom-right-corner'})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{'left-side'})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}
			if (my $nint = $self->{_canvas}->get_root_item->find_child($self->{_items}{$item}{'right-side'})) {
				$self->{_canvas}->get_root_item->remove_child($nint);
			}

		} elsif ($action eq 'update' || $action eq 'hide') {

			my $visibility = 'visible';
			$visibility = 'hidden' if $action eq 'hide';

			my $lw = $item->get('line-width');

			#ellipse => hide rectangle as well
			if (exists $self->{_items}{$item}{ellipse}) {
				$self->{_items}{$item}->set('visibility' => $visibility);
			}

			#text => hide rectangle as well
			if (exists $self->{_items}{$item}{text}) {
				$self->{_items}{$item}->set('visibility' => $visibility);
			}

			#pixelize => hide rectangle as well
			if (exists $self->{_items}{$item}{pixelize}) {
				$self->{_items}{$item}->set('visibility' => $visibility);
			}

			#image => hide rectangle as well
			if (exists $self->{_items}{$item}{image}) {
				$self->{_items}{$item}->set('visibility' => $visibility);
			}

			#line => hide rectangle as well
			if (exists $self->{_items}{$item}{line}) {
				$self->{_items}{$item}->set('visibility' => $visibility);
			}

			#just to make sure the update routines are not
			#called in wrong order
			#we test the first value, if this is ok
			#we believe all other resize rects are ok as well
			return FALSE unless defined $self->{_items}{$item}{'top-side'};

			$self->{_items}{$item}{'top-side'}->set(
				'x'          => $middle_h - 4,
				'y'          => $top - 8,
				'visibility' => $visibility,
			);
			$self->{_items}{$item}{'top-left-corner'}->set(
				'x'          => $left - 8,
				'y'          => $top - 8,
				'visibility' => $visibility,
			);

			$self->{_items}{$item}{'top-right-corner'}->set(
				'x'          => $right,
				'y'          => $top - 8,
				'visibility' => $visibility,
			);

			$self->{_items}{$item}{'bottom-side'}->set(
				'x'          => $middle_h - 4,
				'y'          => $bottom,
				'visibility' => $visibility,
			);

			$self->{_items}{$item}{'bottom-left-corner'}->set(
				'x'          => $left - 8,
				'y'          => $bottom,
				'visibility' => $visibility,
			);

			$self->{_items}{$item}{'bottom-right-corner'}->set(
				'x'          => $right,
				'y'          => $bottom,
				'visibility' => $visibility,
			);

			$self->{_items}{$item}{'left-side'}->set(
				'x'          => $left - 8,
				'y'          => $middle_v - 4,
				'visibility' => $visibility,
			);
			$self->{_items}{$item}{'right-side'}->set(
				'x'          => $right,
				'y'          => $middle_v - 4,
				'visibility' => $visibility,
			);

			#~ $self->handle_bg_rects('raise');

		} elsif ($action eq 'raise') {

			$self->{_items}{$item}{'top-side'}->raise;
			$self->{_items}{$item}{'top-left-corner'}->raise;
			$self->{_items}{$item}{'top-right-corner'}->raise;
			$self->{_items}{$item}{'bottom-side'}->raise;
			$self->{_items}{$item}{'bottom-left-corner'}->raise;
			$self->{_items}{$item}{'bottom-right-corner'}->raise;
			$self->{_items}{$item}{'left-side'}->raise;
			$self->{_items}{$item}{'right-side'}->raise;

		} elsif ($action eq 'lower') {

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
	my ($self, $item, $target, $ev) = @_;

	$self->{_canvas}->pointer_ungrab($item, $ev->time);
	$self->{_canvas}->keyboard_ungrab($item, $ev->time);

	#canvas is idle now...
	$self->{_busy} = FALSE;

	#we handle some minimum sizes here if the new items are too small
	#maybe the user just wanted to place an rect or an object on the canvas
	#and clicked on it without describing an rectangular area
	my $nitem = $self->{_current_new_item};

	if ($nitem) {

		#apply item properties to widgets
		#line width, fill color, stroke color etc.
		$self->set_and_save_drawing_properties($nitem, FALSE);

		#flag if item has to be deleted directly
		my $deleted = FALSE;

		#set minimum sizes
		if ($nitem->isa('GooCanvas2::CanvasRect')) {

			#real shape
			if (exists $self->{_items}{$nitem}) {

				#images
				if (exists $self->{_items}{$nitem}{image}) {

					$self->{_items}{$nitem}->set(
						'x'      => $ev->x - int($self->{_items}{$nitem}{orig_pixbuf}->get_width / 2),
						'y'      => $ev->y - int($self->{_items}{$nitem}{orig_pixbuf}->get_height / 2),
						'width'  => $self->{_items}{$nitem}{orig_pixbuf}->get_width,
						'height' => $self->{_items}{$nitem}{orig_pixbuf}->get_height,
					);

					#texts
				} elsif (exists $self->{_items}{$nitem}{text}) {

					if ($self->{_items}{$nitem}{type} eq 'text') {

						#clear text
						$self->{_items}{$nitem}{text}->set('text' => "<span font_desc='" . $self->{_font} . "' ></span>");

						#adjust parent rectangle
						my $tb = $self->{_items}{$nitem}{text}->get_bounds;

						$nitem->set(
							'x'      => $ev->x,
							'y'      => $ev->y - int(abs($tb->y1 - $tb->y2) / 2),
							'width'  => abs($tb->x1 - $tb->x2),
							'height' => abs($tb->y1 - $tb->y2),
						);

						#show property dialog directly
						Glib::Idle->add(
							sub {
								unless ($self->show_item_properties($self->{_items}{$nitem}{text}, $nitem, $nitem)) {
									if (my $nint = $self->{_canvas}->get_root_item->find_child($nitem)) {

										#delete canvas objects
										$self->{_canvas}->get_root_item->remove_child($nint);
										$self->handle_rects('delete', $nitem);
										$self->handle_embedded('delete', $nitem);

										#delete from hash
										delete $self->{_items}{$nitem};

										#delete all xdo emtries for this object
										$self->xdo_remove('undo', $nitem);
										$self->xdo_remove('redo', $nitem);
										$self->deactivate_all;
									}
								}
								return FALSE;
							});

					} elsif ($self->{_items}{$nitem}{type} eq 'number') {

						$self->{_items}{$nitem}->set(
							'x'      => $ev->x - int($self->{_items}{$nitem}->get('width') / 2),
							'y'      => $ev->y - int($self->{_items}{$nitem}->get('height') / 2),
							'width'  => $self->{_items}{$nitem}->get('width'),
							'height' => $self->{_items}{$nitem}->get('height'),
						);

					}

					#all other objects
				} else {

					#delete
					if (my $nint = $self->{_canvas}->get_root_item->find_child($nitem)) {

						#delete from canvas
						$self->{_canvas}->get_root_item->remove_child($nint);

						#mark as deleted
						$deleted = TRUE;

						#~ print "item $nitem marked as deleted at ",$ev->x,", ",$ev->y,"\n";

					}

				}

				#~ print "new item created: $item\n";

			}

		}

		if ($deleted) {

			#delete child objects and resizing rectangles
			$self->handle_rects('delete', $nitem);
			$self->handle_embedded('delete', $nitem);

			#delete from hash
			delete $self->{_items}{$nitem};

			#~ print "item $nitem deleted at ",$ev->x,", ",$ev->y,"\n";

			#deactivate all
			$self->deactivate_all;

			if (my $oitem = $self->{_canvas}->get_item_at($ev->x_root, $ev->y_root, TRUE)) {

				#~ print "item $oitem found at ",$ev->x,", ",$ev->y,"\n";

				#turn into a button-press-event
				my $initevent = Gtk3::Gdk::Event->new('button-press');
				$initevent->time(Gtk3::get_current_event_time());
				$initevent->window($self->{_drawing_window}->get_window);
				$initevent->x($ev->x);
				$initevent->y($ev->y);
				$self->event_item_on_button_press($oitem, undef, $initevent, TRUE);
				$self->event_item_on_button_release($oitem, undef, $initevent);

				return FALSE;

			}
		} else {

			$self->deactivate_all($nitem);

			#mark as active item
			$self->{_current_item} = $nitem;

			$self->handle_rects('update', $nitem);
			$self->handle_embedded('update', $nitem);

			#add to undo stack
			$self->store_to_xdo_stack($nitem, 'create', 'undo');

		}

		#no new item
		#existing item selected
	} else {

		#cleanup
		#it may happen that items are created
		#but resize mode is not activated immediately
		#those items would not be visible on the canvas
		#we delete them  here
		my $citem = $self->{_current_item};
		if ($citem && $citem->isa('GooCanvas2::CanvasRect')) {
			if (exists $self->{_items}{$citem}) {
				if ($self->{_items}{$citem}->get('visibility') eq 'hidden') {
					if (my $nint = $self->{_canvas}->get_root_item->find_child($citem)) {

						$self->xdo('undo', undef, TRUE);

						#delete from canvas
						$self->{_canvas}->get_root_item->remove_child($nint);

						#delete child objects and resizing rectangles
						$self->handle_rects('delete', $citem);
						$self->handle_embedded('delete', $citem);

						#delete from hash
						delete $self->{_items}{$citem};

					}
				}
			}

		}

		#apply item properties to widgets
		#line width, fill color, stroke color etc.
		$self->set_and_save_drawing_properties($citem, FALSE);
	}

	#uncheck previous active item
	$self->{_current_new_item} = undef;

	#unset action flags
	$item->{dragging}       = FALSE if exists $item->{dragging};
	$item->{dragging_start} = FALSE if exists $item->{dragging_start};
	$item->{resizing}       = FALSE if exists $item->{resizing};

	#because of performance reason we load the current image new from file when
	#the current action is over => button-release
	#when resizing or moving the image we just scale the current image with low quality settings
	#see handle_embedded
	my $child = $self->get_child_item($self->{_current_item});

	if ($child && $child->isa('GooCanvas2::CanvasImage')) {
		my $parent = $self->get_parent_item($child);

		if (exists $self->{_items}{$parent}{pixelize}) {

			$self->{_items}{$parent}{pixelize}->set(
				'x'      => int $self->{_items}{$parent}->get('x'),
				'y'      => int $self->{_items}{$parent}->get('y'),
				'width'  => $self->{_items}{$parent}->get('width'),
				'height' => $self->{_items}{$parent}->get('height'),
				'pixbuf' => $self->get_pixelated_pixbuf_from_canvas($self->{_items}{$parent}),
			);

			$self->handle_embedded('update', $parent, undef, undef, TRUE);

		} else {

			my $copy = $self->{_lp}->load($self->{_items}{$parent}{orig_pixbuf_filename}, $self->{_items}{$parent}->get('width'), $self->{_items}{$parent}->get('height'), FALSE, TRUE);
			if ($copy) {
				$self->{_items}{$parent}{image}->set(
					'x'      => int $self->{_items}{$parent}->get('x'),
					'y'      => int $self->{_items}{$parent}->get('y'),
					'width'  => $self->{_items}{$parent}->get('width'),
					'height' => $self->{_items}{$parent}->get('height'),
					'pixbuf' => $copy,
				);

				$self->handle_embedded('update', $parent, undef, undef, TRUE);

			} else {

				#Try to load it with default width and height (Bug #975247)
				$self->{_items}{$parent}->set(
					'x'      => $ev->x - int($self->{_items}{$parent}{orig_pixbuf}->get_width / 2),
					'y'      => $ev->y - int($self->{_items}{$parent}{orig_pixbuf}->get_height / 2),
					'width'  => $self->{_items}{$parent}{orig_pixbuf}->get_width,
					'height' => $self->{_items}{$parent}{orig_pixbuf}->get_height,
				);

				#mark as active item
				$self->{_current_item} = $parent;

				$self->handle_rects('update', $parent);
				$self->handle_embedded('update', $parent, undef, undef, TRUE);

				#~ $self->abort_current_mode;
			}

		}

	}

	$self->set_drawing_action(int($self->{_current_mode} / 10));

	return TRUE;
}

sub event_item_on_enter_notify {
	my ($self, $item, $target, $ev) = @_;

	return TRUE if $self->{_busy};

	if (
		($item->isa('GooCanvas2::CanvasRect') || $item->isa('GooCanvas2::CanvasEllipse') || $item->isa('GooCanvas2::CanvasText') || $item->isa('GooCanvas2::CanvasImage') || $item->isa('GooCanvas2::CanvasPolyline'))
		&& (   $self->{_current_mode_descr} ne "freehand"
			&& $self->{_current_mode_descr} ne "highlighter"
			&& $self->{_current_mode_descr} ne "censor")

		)
	{

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if (exists $self->{_items}{$item}) {

			#nothing here yet

			#canvas resizing shape
		} elsif ($self->{_canvas_bg_rect}{'right-side'} == $item
			|| $self->{_canvas_bg_rect}{'bottom-side'} == $item
			|| $self->{_canvas_bg_rect}{'bottom-right-corner'} == $item)
		{

			$item->set('fill-color' => 'red');

			#resizing shape
		} else {

			$item->set('fill-color' => 'red');

		}
	}

	return TRUE;
}

sub event_item_on_leave_notify {
	my ($self, $item, $target, $ev) = @_;

	return TRUE if $self->{_busy};

	if (
		($item->isa('GooCanvas2::CanvasRect') || $item->isa('GooCanvas2::CanvasEllipse') || $item->isa('GooCanvas2::CanvasText') || $item->isa('GooCanvas2::CanvasImage') || $item->isa('GooCanvas2::CanvasPolyline'))
		&& (   $self->{_current_mode_descr} ne "freehand"
			&& $self->{_current_mode_descr} ne "highlighter"
			&& $self->{_current_mode_descr} ne "censor")

		)
	{

		#embedded item?
		my $parent = $self->get_parent_item($item);
		$item = $parent if $parent;

		#real shape
		if (exists $self->{_items}{$item}) {

			#nothing here yet

			#canvas resizing shape
		} elsif ($self->{_canvas_bg_rect}{'right-side'} == $item
			|| $self->{_canvas_bg_rect}{'bottom-side'} == $item
			|| $self->{_canvas_bg_rect}{'bottom-right-corner'} == $item)
		{

			$item->set('fill-color-gdk-rgba' => $self->{_style_bg});

			#resizing shape
		} else {

			$item->set('fill-color-gdk-rgba' => $self->{_style_bg});

		}
	}

	return TRUE;
}

#ui related stuff
sub setup_uimanager {
	my $self = shift;

	return Shutter::Draw::UIManager->new( app => $self )->setup;
}

sub import_from_dnd {
	my ($self, $widget, $context, $x, $y, $selection, $info, $time) = @_;
	my $type = $selection->get_target->name;
	return unless $type eq 'text/uri-list';
	my $data = $selection->get_data;
	$data = join('', map { chr } @$data);

	my @files = grep defined($_), split /[\r\n]+/, $data;

	my @valid_files;
	foreach my $file (@files) {
		my $giofile = Glib::IO::File::new_for_uri($file);
		my ($mime_type) = Glib::Object::Introspection->invoke('Gio', undef, 'content_type_guess', $giofile->get_path);
		$mime_type =~ s/image\/x\-apple\-ios\-png/image\/png/;    #FIXME
		if ($mime_type && $self->check_valid_mime_type($mime_type)) {
			push @valid_files, $file;
		}
	}

	#open all valid files
	if (@valid_files) {

		#backup current pixbuf and filename
		my $old_current  = $self->{_current_pixbuf};
		my $old_filename = $self->{_current_pixbuf_filename};

		foreach (@valid_files) {

			#transform uri to path
			my $new_uri  = Glib::IO::File::new_for_uri($_);
			my $new_file = $new_uri->get_path;

			$self->{_current_pixbuf} = $self->{_lp}->load($new_file, undef, undef, undef, TRUE);
			if ($self->{_current_pixbuf}) {
				$self->{_current_pixbuf_filename} = $new_file;

				#construct an event and create a new image object
				my $initevent = Gtk3::Gdk::Event->new('motion-notify');
				$initevent->time(Gtk3::get_current_event_time());
				$initevent->window($self->{_drawing_window}->get_window);
				$initevent->x($x);
				$initevent->y($y);

				#new item
				my $nitem = $self->create_image($initevent, undef, TRUE);

				#add to undo stack
				$self->store_to_xdo_stack($nitem, 'create', 'undo');

			} else {
				$self->abort_current_mode;
			}
		}

		#restore saved values
		$self->{_current_pixbuf}          = $old_current;
		$self->{_current_pixbuf_filename} = $old_filename;

		#uncheck previous active item
		$self->{_current_new_item} = undef;

	} else {
		Gtk3::drag_finish($context, 0, 0, $time);
		return FALSE;
	}

	Gtk3::drag_finish($context, 1, 0, $time);
	return TRUE;
}

sub utf8_decode {
	my $self   = shift;
	my $string = shift;

	#see https://bugs.launchpad.net/shutter/+bug/347821
	utf8::decode $string;

	return $string;
}

sub check_valid_mime_type {
	my $self      = shift;
	my $mime_type = shift;

	foreach my $format (Gtk3::Gdk::Pixbuf::get_formats()) {
		foreach my $mime (@{$format->get_mime_types}) {
			return TRUE if $mime_type eq $mime_type;
			last;
		}
	}

	return FALSE;
}

sub import_from_filesystem {
	my $self   = shift;
	my $button = shift;

	#used when called recursively
	my $parent    = shift;
	my $directory = shift;

	my $menu_objects = Gtk3::Menu->new;

	my $dobjects = $directory || $self->{_sc}->get_root . "/share/shutter/resources/icons/drawing_tool/objects";

	#first directory flag (see description above)
	my $fd = TRUE;
	my $ff = FALSE;

	my @objects = bsd_glob("$dobjects/*");
	foreach my $name (sort { -d $a <=> -d $b } @objects) {

		#parse filename
		my ($short, $folder, $type) = fileparse($name, qr/\.[^.]*/);

		#if current object is a directory we call the current sub
		#recursively
		if (-d $name) {

			#objects from each directory are sorted (files first)
			#we display a separator when the first directory is listed
			if ($fd && $ff) {
				$menu_objects->append(Gtk3::SeparatorMenuItem->new);
				$fd = FALSE;
			}

			#objects from directory $name
			my $subdir_item = Gtk3::ImageMenuItem->new_with_label($short);
			$subdir_item->set('always_show_image' => TRUE);
			$subdir_item->set_image(Gtk3::Image->new_from_stock('gtk-directory', 'menu'));

			#add empty menu first
			my $menu_empty = Gtk3::Menu->new;
			my $empty_item = Gtk3::MenuItem->new_with_label($self->{_d}->get("No icon was found"));
			$empty_item->set_sensitive(FALSE);
			$menu_empty->append($empty_item);
			$subdir_item->set_submenu($menu_empty);

			#and populate later (performance)
			$subdir_item->{'nid'} = $subdir_item->signal_connect(
				'activate' => sub {
					$subdir_item->set_image(Gtk3::Image->new_from_file($self->{_icons} . "/throbber_16x16.gif"));
					my $submenu = $self->import_from_filesystem($button, $subdir_item, $dobjects . "/$short");

					if ($submenu->get_children) {

						$subdir_item->set_submenu($submenu);

					} else {

						$subdir_item->set_image(Gtk3::Image->new_from_stock('gtk-directory', 'menu'));

					}

					return TRUE;
				});

			#diconnect handler when this event occurs
			$subdir_item->signal_connect(
				'leave-notify-event' => sub {
					if ($subdir_item->signal_handler_is_connected($subdir_item->{'nid'})) {
						$subdir_item->signal_handler_disconnect($subdir_item->{'nid'});
					}
				});
			$menu_objects->append($subdir_item);
			next;
		}

		#there is at least one single file
		#set the flag
		$ff = TRUE;

		#init item with filename first
		my $new_item = Gtk3::ImageMenuItem->new_with_label($short);
		$new_item->set('always_show_image' => TRUE);
		$menu_objects->append($new_item);

		#sfsdc
		$new_item->{'name'} = $name;

	}

	#do not do that when called recursively
	#top level call
	unless ($directory) {

		$menu_objects->append(Gtk3::SeparatorMenuItem->new);

		#~ #objects from icontheme
		#~ if ( Gtk3->CHECK_VERSION( 2, 12, 0 ) ) {
		#~ my $icontheme = Gtk3::IconTheme::get_default();
		#~
		#~ my $utheme_item = Gtk3::ImageMenuItem->new_with_label( $self->{_d}->get("Import from current theme...") );
		#~ $utheme_item->set( 'always_show_image' => TRUE ) if Gtk3->CHECK_VERSION( 2, 16, 0 );
		#~ if ( $icontheme->has_icon('preferences-desktop-theme') ) {
		#~ $utheme_item->set_image( Gtk3::Image->new_from_icon_name( 'preferences-desktop-theme', 'menu' ) );
		#~ }
		#~
		#~ $utheme_item->set_submenu( $self->import_from_utheme( $icontheme, $button ) );
		#~
		#~ $menu_objects->append($utheme_item);
		#~
		#~ $menu_objects->append( Gtk3::SeparatorMenuItem->new );
		#~ }

		#objects from session
		my $session_menu_item = Gtk3::ImageMenuItem->new_with_label($self->{_d}->get("Import from session..."));
		$session_menu_item->set('always_show_image' => TRUE);
		$session_menu_item->set_image(Gtk3::Image->new_from_stock('gtk-index', 'menu'));
		$session_menu_item->set_submenu($self->import_from_session($button));

		#gen thumbnails in an idle callback
		$self->gen_thumbnail_on_idle('gtk-index', $session_menu_item, $button, TRUE, $session_menu_item->get_submenu->get_children);

		$menu_objects->append($session_menu_item);

		#objects from filesystem
		my $filesystem_menu_item = Gtk3::ImageMenuItem->new_with_label($self->{_d}->get("Import from filesystem..."));
		$filesystem_menu_item->set('always_show_image' => TRUE);
		$filesystem_menu_item->set_image(Gtk3::Image->new_from_stock('gtk-open', 'menu'));
		$filesystem_menu_item->signal_connect(
			'activate' => sub {

				my $fs = Gtk3::FileChooserDialog->new(
					$self->{_d}->get("Choose file to open"), $self->{_drawing_window}, 'open',
					'gtk-cancel' => 'reject',
					'gtk-open'   => 'accept'
				);

				$fs->set_select_multiple(FALSE);

				#preview widget
				my $iprev = Gtk3::Image->new;
				$fs->set_preview_widget($iprev);

				$fs->signal_connect(
					'selection-changed' => sub {
						if (my $pfilename = $fs->get_preview_filename) {
							my $pixbuf = $self->{_lp_ne}->load($pfilename, 200, 200, TRUE, TRUE);
							unless ($pixbuf) {
								$fs->set_preview_widget_active(FALSE);
							} else {
								$fs->get_preview_widget->set_from_pixbuf($pixbuf);
								$fs->set_preview_widget_active(TRUE);
							}
						} else {
							$fs->set_preview_widget_active(FALSE);
						}
					});

				my $filter_all = Gtk3::FileFilter->new;
				$filter_all->set_name($self->{_d}->get("All compatible image formats"));
				$fs->add_filter($filter_all);

				foreach my $format (Gtk3::Gdk::Pixbuf::get_formats()) {
					my $filter = Gtk3::FileFilter->new;
					$filter->set_name($format->get_name . " - " . $format->get_description);
					foreach my $ext (@{$format->get_extensions}) {
						$filter->add_pattern("*." . uc $ext);
						$filter_all->add_pattern("*." . uc $ext);
						$filter->add_pattern("*." . $ext);
						$filter_all->add_pattern("*." . $ext);
					}
					$fs->add_filter($filter);
				}

				if ($ENV{'HOME'}) {
					$fs->set_current_folder($ENV{'HOME'});
				}
				my $fs_resp = $fs->run;

				my $new_file;
				if ($fs_resp eq "accept") {
					$new_file = $fs->get_filenames;

					$self->{_current_pixbuf} = $self->{_lp}->load($new_file, undef, undef, undef, TRUE);
					if ($self->{_current_pixbuf}) {
						$self->{_current_pixbuf_filename} = $new_file;
						$button->set_icon_widget(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size($self->{_dicons} . '/draw-image.svg', Gtk3::IconSize->lookup('menu'))));
						$button->show_all;
						$self->{_canvas}->get_window->set_cursor($self->change_cursor_to_current_pixbuf);
					} else {
						$self->abort_current_mode;
					}

					$fs->destroy();
				} else {
					$fs->destroy();
				}

			});

		$menu_objects->append($filesystem_menu_item);

	}

	$button->show_all;
	$menu_objects->show_all;

	#generate thumbnails in an idle callback
	$self->gen_thumbnail_on_idle('gtk-directory', $parent, $button, FALSE, $menu_objects->get_children);

	return $menu_objects;
}

sub import_from_utheme {
	my $self      = shift;
	my $icontheme = shift;
	my $button    = shift;

	my $menu_ctxt = Gtk3::Menu->new;

	foreach my $context (sort $icontheme->list_contexts) {

		#objects from current theme (contexts)
		my $utheme_ctxt = Gtk3::ImageMenuItem->new_with_label($context);
		$utheme_ctxt->set('always_show_image' => TRUE);
		$utheme_ctxt->set_image(Gtk3::Image->new_from_stock('gtk-directory', 'menu'));

		#add empty menu first
		my $menu_empty = Gtk3::Menu->new;
		my $empty_item = Gtk3::MenuItem->new_with_label($self->{_d}->get("No icon was found"));
		$empty_item->set_sensitive(FALSE);
		$menu_empty->append($empty_item);
		$utheme_ctxt->set_submenu($menu_empty);

		#and populate later (performance)
		my @menu_items;
		$utheme_ctxt->{'nid'} = $utheme_ctxt->signal_connect(
			'activate' => sub {

				$utheme_ctxt->set_image(Gtk3::Image->new_from_file($self->{_icons} . "/throbber_16x16.gif"));
				my $context_submenu = $self->import_from_utheme_ctxt($icontheme, $context, $button);

				if ($context_submenu->get_children) {

					$utheme_ctxt->set_submenu($context_submenu);

					#gen thumbnails in an idle callback
					$self->gen_thumbnail_on_idle('gtk-directory', $utheme_ctxt, $button, TRUE, $utheme_ctxt->get_submenu->get_children);

				} else {
					$utheme_ctxt->set_image(Gtk3::Image->new_from_stock('gtk-directory', 'menu'));
				}

				return TRUE;
			});

		#disconnect handler when this event occurs
		$utheme_ctxt->signal_connect(
			'leave-notify-event' => sub {
				if ($utheme_ctxt->signal_handler_is_connected($utheme_ctxt->{'nid'})) {
					$utheme_ctxt->signal_handler_disconnect($utheme_ctxt->{'nid'});
				}
			});

		$menu_ctxt->append($utheme_ctxt);

	}

	$menu_ctxt->show_all;

	return $menu_ctxt;
}

sub import_from_utheme_ctxt {
	my $self      = shift;
	my $icontheme = shift;
	my $context   = shift;
	my $button    = shift;

	my $menu_ctxt_items = Gtk3::Menu->new;

	my $size = Gtk3::IconSize->lookup('dialog');

	foreach my $icon (sort $icontheme->list_icons($context)) {

		#objects from current theme (icons for specific contexts)
		my $utheme_ctxt_item = Gtk3::ImageMenuItem->new_with_label($icon);
		$utheme_ctxt_item->set('always_show_image' => TRUE);
		my $iconinfo = $icontheme->lookup_icon($icon, $size, 'generic-fallback');

		#save filename and generate thumbnail later
		#idle callback
		$utheme_ctxt_item->{'name'} = $iconinfo->get_filename;

		$menu_ctxt_items->append($utheme_ctxt_item);
	}

	$menu_ctxt_items->show_all;

	return $menu_ctxt_items;
}

sub import_from_session {
	my $self   = shift;
	my $button = shift;

	my $menu_session_objects = Gtk3::Menu->new;

	my %import_hash = %{$self->{_import_hash}};

	foreach my $key (Sort::Naturally::nsort(keys %import_hash)) {

		next unless exists $import_hash{$key}->{'short'};
		next unless defined $import_hash{$key}->{'short'};

		#init item with filename
		my $screen_menu_item = Gtk3::ImageMenuItem->new_with_label($import_hash{$key}->{'short'});
		$screen_menu_item->set('always_show_image' => TRUE);

		#set sensitive == FALSE if image eq current file
		$screen_menu_item->set_sensitive(FALSE)
			if $import_hash{$key}->{'long'} eq $self->{_filename};

		#save filename and attributes
		$screen_menu_item->{'name'}         = $import_hash{$key}->{'long'};
		$screen_menu_item->{'mime_type'}    = $import_hash{$key}->{'mime_type'};
		$screen_menu_item->{'mtime'}        = $import_hash{$key}->{'mtime'};
		$screen_menu_item->{'giofile'}      = $import_hash{$key}->{'giofile'};
		$screen_menu_item->{'no_thumbnail'} = $import_hash{$key}->{'no_thumbnail'};

		$menu_session_objects->append($screen_menu_item);
	}

	$menu_session_objects->show_all;

	return $menu_session_objects;
}

sub gen_thumbnail_on_idle {
	my $self       = shift;
	my $stock      = shift;
	my $parent     = shift;
	my $button     = shift;
	my $no_init    = shift;
	my @menu_items = @_;

	my $shutter_hfunct = Shutter::App::HelperFunctions->new($self->{_sc});

	#generate thumbnails in an idle callback
	my $next_item = 0;
	Glib::Idle->add(
		sub {

			#get next item
			my $child = $menu_items[$next_item];

			#no valid item - stop the idle handler
			unless ($child) {
				$parent->set_image(Gtk3::Image->new_from_stock($stock, 'menu')) if $parent;
				return FALSE;
			}

			my $name = $child->{'name'};

			#no valid item - stop the idle handler
			unless ($name) {
				$parent->set_image(Gtk3::Image->new_from_stock($stock, 'menu')) if $parent;
				return FALSE;
			}

			#increment counter
			$next_item++;

			#create thumbnail
			my $small_image;
			eval {

				#if uri exists we generate a thumbnail
				#with Shutter::Pixbuf::Thumbnail
				if (exists $child->{'giofile'}) {
					my $thumb;
					unless ($child->{'no_thumbnail'}) {
						$thumb = $self->{_lp_ne}->load($shutter_hfunct->utf8_decode($child->{'giofile'}->get_path), Gtk3::IconSize->lookup('small-toolbar'));
					} else {
						$thumb = Gtk3::Gdk::Pixbuf->new('rgb', TRUE, 8, 5, 5);
						$thumb->fill(0x00000000);
					}

					$small_image = Gtk3::Image->new_from_pixbuf($thumb);
				} else {
					my $pixbuf = $self->{_lp_ne}->load($name, undef, undef, undef, TRUE);

					#16x16 is minimum size
					if ($pixbuf->get_width >= 16 && $pixbuf->get_height >= 16) {
						$small_image = Gtk3::Image->new_from_pixbuf($pixbuf->scale_simple(Gtk3::IconSize->lookup('menu'), 'bilinear'));
					}
				}
			};
			unless ($@) {
				if ($small_image) {
					$child->set_image($small_image);

					#init when toplevel
					unless ($no_init) {
						unless ($button->get_icon_widget) {
							$button->set_icon_widget(Gtk3::Image->new_from_pixbuf($small_image->get_pixbuf));
							$self->{_current_pixbuf_filename} = $name;
							$button->show_all;
						}
					}

					$child->signal_connect(
						'activate' => sub {
							$self->{_current_pixbuf_filename} = $name;
							$button->set_icon_widget(Gtk3::Image->new_from_pixbuf($small_image->get_pixbuf));
							$button->show_all;
							$self->{_canvas}->get_window->set_cursor($self->change_cursor_to_current_pixbuf);
						});
				} else {
					$child->destroy;
				}
			} else {
				$child->destroy;
			}

			return TRUE;
		});    #end idle callback

}

sub set_drawing_action {
	my $self  = shift;
	my $index = shift;

	#~ print "set_drawing_action\n";

	my $item_index = 0;
	my $toolbar    = $self->{_uimanager}->get_widget("/ToolBarDrawing");
	for (my $i = 0 ; $i < $toolbar->get_n_items ; $i++) {
		my $item = $toolbar->get_nth_item($i);

		#skip separators
		#we only want to activate tools
		next if $item->isa('Gtk3::SeparatorToolItem');

		#add 1 to item index
		$item_index++;

		if ($item_index == $index) {
			if ($item->get_active) {
				$self->change_drawing_tool_cb($item_index * 10);
			} else {
				$item->set_active(TRUE);
			}
			last;
		}
	}

}

sub change_cursor_to_current_pixbuf {
	my $self = shift;

	#~ print "change_cursor_to_current_pixbuf\n";

	$self->{_current_mode_descr} = "image";

	my $cursor = undef;

	#load file
	$self->{_current_pixbuf} = $self->{_lp}->load($self->{_current_pixbuf_filename}, undef, undef, undef, TRUE);
	unless ($self->{_current_pixbuf}) {
		$cursor = Gtk3::Gdk::Cursor->new_from_pixbuf(Gtk3::Gdk::Display::get_default(), Gtk3::Gdk::Pixbuf->new_from_file($self->{_dicons} . '/draw-image.svg'), Gtk3::IconSize->lookup('menu'));
	}

	#very big images usually don't work as a cursor (no error though??)
	my $pb_w = $self->{_current_pixbuf}->get_width;
	my $pb_h = $self->{_current_pixbuf}->get_height;

	if ($pb_w < 800 && $pb_h < 800) {
		eval {

			#maximum cursor size
			my ($cw, $ch) = Gtk3::Gdk::Display::get_default->get_maximal_cursor_size;

			#images smaller than max cursor size?
			# => don't scale to a bigger size
			if ($cw > $pb_w || $ch > $pb_w) {
				$cursor = Gtk3::Gdk::Cursor->new_from_pixbuf(Gtk3::Gdk::Display::get_default(), $self->{_current_pixbuf}, int($pb_w / 2), int($pb_h / 2));
			} else {
				my $cpixbuf = $self->{_lp}->load($self->{_current_pixbuf_filename}, $cw, $ch, TRUE, TRUE);
				$cursor = Gtk3::Gdk::Cursor->new_from_pixbuf(Gtk3::Gdk::Display::get_default(), $cpixbuf, int($cpixbuf->get_width / 2), int($cpixbuf->get_height / 2));
			}

		};
		if ($@) {
			my $response = $self->{_dialogs}->dlg_error_message(
				sprintf($self->{_d}->get("Error while opening image %s."), "'" . $self->{_current_pixbuf_filename} . "'"),
				$self->{_d}->get("There was an error opening the image."),
				undef, undef, undef, undef, undef, undef, $@
			);
			$self->abort_current_mode;
		}
	} else {
		$cursor = Gtk3::Gdk::Cursor->new_from_pixbuf(Gtk3::Gdk::Display::get_default(), Gtk3::Gdk::Pixbuf->new_from_file($self->{_dicons} . '/draw-image.svg'), Gtk3::IconSize->lookup('menu'));
	}

	return $cursor;
}

sub paste_item {
	my $self = shift;
	my $item = shift;

	#cut instead of copy
	my $delete_after = shift;

	#import from system's clipboard
	if (my $image = $self->{_clipboard}->wait_for_image) {

		#backup current pixbuf and filename
		my $old_current  = $self->{_current_pixbuf};
		my $old_filename = $self->{_current_pixbuf_filename};

		#create tempfile
		my ($tmpfh, $tmpfilename) = tempfile(UNLINK => 1);

		#save pixbuf to tempfile and integrate it
		my $pixbuf_save = Shutter::Pixbuf::Save->new($self->{_sc}, $self->{_drawing_window});
		if ($pixbuf_save->save_pixbuf_to_file($image, $tmpfilename, 'png')) {

			#set pixbuf vars
			$self->{_current_pixbuf}          = $image;
			$self->{_current_pixbuf_filename} = $tmpfilename;

			#construct an event and create a new image object
			my $initevent = Gtk3::Gdk::Event->new('motion-notify');
			$initevent->time(Gtk3::get_current_event_time());
			$initevent->window($self->{_drawing_window}->get_window);

			#calculate coordinates
			$initevent->x(int($self->{_canvas_bg_rect}->get('width') / 2));
			$initevent->y(int($self->{_canvas_bg_rect}->get('height') / 2));

			#new item
			my $nitem = $self->create_image($initevent, undef, TRUE);

			#add to undo stack
			$self->store_to_xdo_stack($nitem, 'create', 'undo');

			#restore saved values
			$self->{_current_pixbuf}          = $old_current;
			$self->{_current_pixbuf_filename} = $old_filename;

			#uncheck
			$self->{_current_new_item}  = undef;
			$self->{_current_item}      = undef;
			$self->{_current_copy_item} = undef;

		}

		#import from DrawingTool's clipboard
	} elsif (defined $item) {

		my $child = $self->get_child_item($item);

		my $new_item = undef;
		if ($item->isa('GooCanvas2::CanvasRect') && !$child) {

			#~ print "Creating Rectangle...\n";
			$new_item = $self->create_rectangle(undef, $item);
		} elsif ($item->isa('GooCanvas2::CanvasPolyline') && !$child) {

			#~ print "Creating Polyline...\n";
			$new_item = $self->create_polyline(undef, $item);
		} elsif ($child->isa('GooCanvas2::CanvasPolyline') && exists $self->{_items}{$item}{stroke_color}) {

			#~ print "Creating Line...\n";
			$new_item = $self->create_line(undef, $item);
		} elsif ($child->isa('GooCanvas2::CanvasPolyline')) {

			#~ print "Creating Censor...\n";
			$new_item = $self->create_censor(undef, $item);
		} elsif ($child->isa('GooCanvas2::CanvasEllipse')) {

			#~ print "Creating Ellipse...\n";
			$new_item = $self->create_ellipse(undef, $item);
		} elsif ($child->isa('GooCanvas2::CanvasText')) {

			#~ print "Creating Text...\n";
			$new_item = $self->create_text(undef, $item);
		} elsif ($child->isa('GooCanvas2::CanvasImage') && exists $self->{_items}{$item}{pixelize}) {

			#~ print "Creating Pixelize...\n";
			$new_item = $self->create_pixel_image(undef, $item);
		} elsif ($child->isa('GooCanvas2::CanvasImage')) {

			#~ print "Creating Image...\n";
			$new_item = $self->create_image(undef, $item);
		}

		#cut instead of copy
		if ($delete_after) {
			$self->clear_item_from_canvas($item);
			$self->{_current_item}      = undef;
			$self->{_current_copy_item} = undef;
		}

		#add to undo stack
		$self->store_to_xdo_stack($new_item, 'create', 'undo');

	}

	return TRUE;
}

sub create_polyline {
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;

	#this is a highlighter?
	#we need different default values in this case
	my $highlighter = shift;

	my @points         = ();
	my $stroke_color = $self->{_stroke_color};
	my $transform;
	my $line_width = $self->{_line_width};

	#use event coordinates
	if ($ev) {
		@points = ($ev->x, $ev->y, $ev->x, $ev->y);

		#use source item coordinates
	} elsif ($copy_item) {
		foreach (@{$self->{_items}{$copy_item}{points}}) {
			push @points, $_ + 20;
		}

		$stroke_color = $self->{_items}{$copy_item}{stroke_color};
		$transform      = $self->{_items}{$copy_item}->get('transform');
		$line_width     = $self->{_items}{$copy_item}->get('line_width');
	}

	my $item = undef;
	if ($highlighter) {
		$stroke_color = Gtk3::Gdk::RGBA::parse('#FFFF00');
		$stroke_color->alpha(0.5);
		$item = GooCanvas2::CanvasPolyline->new(
			parent=>$self->{_canvas}->get_root_item, close_path=>FALSE,
			'stroke-color-gdk-rgba' => $stroke_color,
			'line-width'     => 18,
			'fill-rule'      => 'CAIRO_FILL_RULE_EVEN_ODD',
			'line-cap'       => 'CAIRO_LINE_CAP_SQUARE',
			'line-join'      => 'CAIRO_LINE_JOIN_BEVEL',
		);
	} else {
		$item = GooCanvas2::CanvasPolyline->new(
			parent=>$self->{_canvas}->get_root_item, close_path=>FALSE,
			'stroke-color-gdk-rgba' => $stroke_color,
			'line-width'     => $line_width,
			'line-cap'       => 'CAIRO_LINE_CAP_ROUND',
			'line-join'      => 'CAIRO_LINE_JOIN_ROUND',
		);
	}

	$self->{_current_new_item} = $item unless ($copy_item);
	$self->{_items}{$item} = $item;

	#need at least 2 points
	push @{$self->{_items}{$item}{'points'}}, @points;
	$self->{_items}{$item}->set(points    => Shutter::Draw::Utils::points_to_canvas_points(@{$self->{_items}{$item}{'points'}}));
	$self->{_items}{$item}->set(transform => $transform) if $transform;

	if ($highlighter) {

		#set type flag
		$self->{_items}{$item}{type}               = 'highlighter';
		$self->{_items}{$item}{uid}                = $self->{_uid}++;
		$self->{_items}{$item}{stroke_color}       = Gtk3::Gdk::RGBA::parse('#FFFF00');
		$self->{_items}{$item}{stroke_color}->alpha(0.5);
	} else {

		#set type flag
		$self->{_items}{$item}{type}               = 'freehand';
		$self->{_items}{$item}{uid}                = $self->{_uid}++;
		$self->{_items}{$item}{stroke_color}       = $self->{_stroke_color};
	}

	$self->setup_item_signals($self->{_items}{$item});
	$self->setup_item_signals_extra($self->{_items}{$item});

	return $item;
}

sub create_censor {
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;

	my @points = ();
	my $transform;

	#use event coordinates
	if ($ev) {
		@points = ($ev->x, $ev->y, $ev->x, $ev->y);

		#use source item coordinates
	} elsif ($copy_item) {
		foreach (@{$self->{_items}{$copy_item}{points}}) {
			push @points, $_ + 20;
		}
		$transform = $self->{_items}{$copy_item}->get('transform');
	}

	my $item = GooCanvas2::CanvasPolyline->new(
		parent=>$self->{_canvas}->get_root_item, close_path=>FALSE,
		'stroke-pixbuf' => $self->{_stipple_pixbuf},
		'line-width'     => 14,
		'line-cap'       => 'CAIRO_LINE_CAP_ROUND',
		'line-join'      => 'CAIRO_LINE_JOIN_ROUND',
	);

	$self->{_current_new_item} = $item unless ($copy_item);
	$self->{_items}{$item} = $item;

	#set type flag
	$self->{_items}{$item}{type} = 'censor';
	$self->{_items}{$item}{uid}  = $self->{_uid}++;

	#need at least 2 points
	push @{$self->{_items}{$item}{'points'}}, @points;
	$self->{_items}{$item}->set(points    => Shutter::Draw::Utils::points_to_canvas_points(@{$self->{_items}{$item}{'points'}}));
	$self->{_items}{$item}->set(transform => $transform) if $transform;

	$self->setup_item_signals($self->{_items}{$item});
	$self->setup_item_signals_extra($self->{_items}{$item});

	return $item;
}

sub create_pixel_image {
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;

	my ($x, $y, $width, $height) = (0, 0, 0, 0);

	#use event coordinates and selected color
	if ($ev) {
		$x = $ev->x;
		$y = $ev->y;

		#use source item coordinates and item color
	} elsif ($copy_item) {
		$x = $copy_item->get('x') + 20;
		$y = $copy_item->get('y') + 20;
		$width = $copy_item->get('width');
		$height = $copy_item->get('height');
	}

	my $item    = GooCanvas2::CanvasRect->new(
		parent=>$self->{_canvas}->get_root_item, x=>$x, y=>$y, width=>$width, height=>$height,
		'fill-color-rgba' => 0,
		'line-dash'    => GooCanvas2::CanvasLineDash->newv([5, 5]),
		'line-width'   => 1,
		'stroke-color' => 'gray',
	);

	$self->{_current_new_item} = $item unless ($copy_item);
	$self->{_items}{$item} = $item;

	#blank pixbuf
	my $blank = Gtk3::Gdk::Pixbuf->new('rgb', TRUE, 8, 2, 2);

	#whole pixbuf is transparent
	$blank->fill(0x00000000);

	$self->{_items}{$item}{pixelize} = GooCanvas2::CanvasImage->new(
		parent=>$self->{_canvas}->get_root_item,
		pixbuf=>$blank,
		x=>$item->get('x'),
		y=>$item->get('y'),
		'width'  => 2,
		'height' => 2,
	);

	#set type flag
	$self->{_items}{$item}{type} = 'pixelize';
	$self->{_items}{$item}{uid}  = $self->{_uid}++;

	#create rectangles
	$self->handle_rects('create', $item);

	if ($copy_item) {
		$self->{_items}{$item}{pixelize}->set(
			'x'      => int $self->{_items}{$item}->get('x'),
			'y'      => int $self->{_items}{$item}->get('y'),
			'width'  => $self->{_items}{$item}->get('width'),
			'height' => $self->{_items}{$item}->get('height'),
			'pixbuf' => $self->get_pixelated_pixbuf_from_canvas($self->{_items}{$item}),
		);

		$self->handle_embedded('update', $item, undef, undef, TRUE);
	}

	$self->setup_item_signals($self->{_items}{$item}{pixelize});
	$self->setup_item_signals_extra($self->{_items}{$item}{pixelize});

	$self->setup_item_signals($self->{_items}{$item});
	$self->setup_item_signals_extra($self->{_items}{$item});

	return $item;
}

sub create_image {
	my $self                 = shift;
	my $ev                   = shift;
	my $copy_item            = shift;
	my $force_orig_size_init = shift;

	my ($x, $y, $width, $height) = (0, 0, 0, 0);

	#use event coordinates
	if ($ev) {

		#we create the new image item
		#and use the original image size
		#dnd for example
		if ($force_orig_size_init) {
			$x = $ev->x - int($self->{_current_pixbuf}->get_width / 2);
			$y = $ev->y - int($self->{_current_pixbuf}->get_height / 2);
			$width = $self->{_current_pixbuf}->get_width;
			$height = $self->{_current_pixbuf}->get_height;
		} else {
			$x = $ev->x;
			$y = $ev->y;
		}

		#use source item coordinates
	} elsif ($copy_item) {
		$x = $copy_item->get('x') + 20;
		$y = $copy_item->get('y') + 20;
		$width = $self->{_items}{$copy_item}->get('width');
		$height = $self->{_items}{$copy_item}->get('height');
	}

	my $item    = GooCanvas2::CanvasRect->new(
		parent=>$self->{_canvas}->get_root_item, x=>$x, y=>$y, width=>$width, height=>$height,
		'fill-color-rgba' => 0,
		'line-dash'    => GooCanvas2::CanvasLineDash->newv([5, 5]),
		'line-width'   => 1,
		'stroke-color' => 'gray',
	);

	$self->{_current_new_item} = $item unless ($copy_item);
	$self->{_items}{$item} = $item;

	if ($ev) {
		$self->{_items}{$item}{orig_pixbuf}          = $self->{_current_pixbuf}->copy;
		$self->{_items}{$item}{orig_pixbuf_filename} = $self->{_current_pixbuf_filename};
	} elsif ($copy_item) {
		$self->{_items}{$item}{orig_pixbuf}          = $self->{_items}{$copy_item}{orig_pixbuf}->copy;
		$self->{_items}{$item}{orig_pixbuf_filename} = $self->{_items}{$copy_item}{orig_pixbuf_filename};
	}

	$self->{_items}{$item}{image} = GooCanvas2::CanvasImage->new(
		parent=>$self->{_canvas}->get_root_item,
		pixbuf=>$self->{_items}{$item}{orig_pixbuf},
		x=>$item->get('x'),
		y=>$item->get('y'),
		'width'  => 2,
		'height' => 2,
	);

	#set type flag
	$self->{_items}{$item}{type} = 'image';
	$self->{_items}{$item}{uid}  = $self->{_uid}++;

	#create rectangles
	$self->handle_rects('create', $item);

	#show image directly when copy or dnd
	if ($copy_item || $force_orig_size_init) {
		$self->handle_embedded('update', $item);
	}

	$self->setup_item_signals($self->{_items}{$item}{image});
	$self->setup_item_signals_extra($self->{_items}{$item}{image});

	$self->setup_item_signals($self->{_items}{$item});
	$self->setup_item_signals_extra($self->{_items}{$item});

	if ($copy_item) {

		my $copy = $self->{_lp}->load($self->{_items}{$item}{orig_pixbuf_filename}, $self->{_items}{$item}->get('width'), $self->{_items}{$item}->get('height'), FALSE, TRUE);

		$self->{_items}{$item}{image}->set(
			'x'      => int $self->{_items}{$item}->get('x'),
			'y'      => int $self->{_items}{$item}->get('y'),
			'pixbuf' => $copy
		);

		$self->handle_rects('hide', $item);

	}

	return $item;
}

sub create_text {
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;

	my ($x, $y, $width, $height)     = (0, 0, 0, 0);
	my $stroke_color = $self->{_stroke_color};
	my $text           = $self->{_d}->get('New text...');
	my $line_width     = $self->{_line_width};

	#use event coordinates and selected color
	if ($ev) {
		$x = $ev->x;
		$y = $ev->y;

		#use source item coordinates and item color
	} elsif ($copy_item) {
		$x = $copy_item->get('x') + 20;
		$y = $copy_item->get('y') + 20;
		$width = $copy_item->get('width');
		$height = $copy_item->get('height');
		$stroke_color = $self->{_items}{$copy_item}{stroke_color};
		$text           = $self->{_items}{$copy_item}{text}->get('text');
		$line_width     = $self->{_items}{$copy_item}{text}->get('line-width');
	}

	my $item    = GooCanvas2::CanvasRect->new(
		parent=>$self->{_canvas}->get_root_item, x=>$x, y=>$y, width=>$width, height=>$height,
		'fill-color-rgba' => 0,
		'line-dash'    => GooCanvas2::CanvasLineDash->newv([5, 5]),
		'line-width'   => 1,
		'stroke-color' => 'gray',
	);

	$self->{_current_new_item} = $item unless ($copy_item);
	$self->{_items}{$item} = $item;

	$self->{_items}{$item}{text} = GooCanvas2::CanvasText->new(
		parent=>$self->{_canvas}->get_root_item, text=>"<span font_desc='" . $self->{_font} . "' >" . $text . "</span>",
		x=>$item->get('x'),
		y=>$item->get('y'),
		width=>-1,
		anchor=>'nw',
		'use-markup'   => TRUE,
		'fill-color-gdk-rgba' => $stroke_color,
		'line-width'   => $line_width,
	);

	#adjust parent rectangle
	my $tb = $self->{_items}{$item}{text}->get_bounds;
	my $w  = abs($tb->x1 - $tb->x2);
	my $h  = abs($tb->y1 - $tb->y2);

	if ($copy_item) {
		$self->{_items}{$item}->set(
			'x'          => $self->{_items}{$item}->get('x') + 20,
			'y'          => $self->{_items}{$item}->get('y') + 20,
			'width'      => $w,
			'height'     => $h,
			'visibility' => 'hidden',
		);
	} else {
		$self->{_items}{$item}->set(
			'x'          => $ev->x - $w,
			'y'          => $ev->y - $h,
			'width'      => $w,
			'height'     => $h,
			'visibility' => 'hidden',
		);
	}

	#update text
	$self->handle_embedded('hide', $item);

	#set type flag
	$self->{_items}{$item}{type} = 'text';
	$self->{_items}{$item}{uid}  = $self->{_uid}++;

	$self->{_items}{$item}{stroke_color}       = $self->{_stroke_color};

	#create rectangles
	$self->handle_rects('create', $item);
	if ($copy_item) {
		$self->handle_embedded('update', $item);
		$self->handle_rects('hide', $item);
	}

	$self->setup_item_signals($self->{_items}{$item}{text});
	$self->setup_item_signals_extra($self->{_items}{$item}{text});

	$self->setup_item_signals($self->{_items}{$item});
	$self->setup_item_signals_extra($self->{_items}{$item});

	return $item;
}

sub create_line {
	my $self        = shift;
	my $ev          = shift;
	my $copy_item   = shift;
	my $end_arrow   = shift;
	my $start_arrow = shift;

	my ($x, $y, $width, $height)     = (0, 0, 0, 0);
	my $stroke_color = $self->{_stroke_color};
	my $line_width     = $self->{_line_width};
	my $mirrored_w     = 0;
	my $mirrored_h     = 0;

	#default values
	my $arrow_width      = 4;
	my $arrow_length     = 5;
	my $arrow_tip_length = 4;

	#use event coordinates and selected color
	if ($ev) {
		$x = $ev->x;
		$y = $ev->y;

		#use source item coordinates and item color
	} elsif ($copy_item) {
		$x = $copy_item->get('x') + 20;
		$y = $copy_item->get('y') + 20;
		$width = $copy_item->get('width');
		$height = $copy_item->get('height');
		$stroke_color = $self->{_items}{$copy_item}{stroke_color};
		$line_width     = $self->{_items}{$copy_item}{line}->get('line-width');
		$mirrored_w     = $self->{_items}{$copy_item}{mirrored_w};
		$mirrored_h     = $self->{_items}{$copy_item}{mirrored_h};

		#arrow specific properties
		$end_arrow        = $self->{_items}{$copy_item}{end_arrow};
		$start_arrow      = $self->{_items}{$copy_item}{start_arrow};
		$arrow_width      = $self->{_items}{$copy_item}{arrow_width};
		$arrow_length     = $self->{_items}{$copy_item}{arrow_length};
		$arrow_tip_length = $self->{_items}{$copy_item}{arrow_tip_length};
	}

	my $item    = GooCanvas2::CanvasRect->new(
		parent=>$self->{_canvas}->get_root_item, x=>$x, y=>$y, width=>$width, height=>$height,
		'fill-color-rgba' => 0,
		'line-dash'    => GooCanvas2::CanvasLineDash->newv([5, 5]),
		'line-width'   => 1,
		'stroke-color' => 'gray',
	);

	$self->{_current_new_item} = $item unless ($copy_item);
	$self->{_items}{$item} = $item;

	$self->{_items}{$item}{line} = GooCanvas2::CanvasPolyline->new(
		parent=>$self->{_canvas}->get_root_item,
		close_path=>FALSE,
		points => Shutter::Draw::Utils::points_to_canvas_points(
			$item->get('x'),
			$item->get('y'),
			$item->get('x') + $item->get('width'),
			$item->get('y') + $item->get('height'),
		),
		'stroke-color-gdk-rgba'   => $stroke_color,
		'line-width'       => $line_width,
		'line-cap'         => 'CAIRO_LINE_CAP_ROUND',
		'line-join'        => 'CAIRO_LINE_JOIN_ROUND',
		'end-arrow'        => $end_arrow,
		'start-arrow'      => $start_arrow,
		'arrow-length'     => $arrow_length,
		'arrow-width'      => $arrow_width,
		'arrow-tip-length' => $arrow_tip_length,
		'visibility'       => 'hidden',
	);

	if (defined $end_arrow || defined $start_arrow) {

		#save arrow specific properties
		$self->{_items}{$item}{end_arrow}        = $self->{_items}{$item}{line}->get('end-arrow');
		$self->{_items}{$item}{start_arrow}      = $self->{_items}{$item}{line}->get('start-arrow');
		$self->{_items}{$item}{arrow_width}      = $self->{_items}{$item}{line}->get('arrow-width');
		$self->{_items}{$item}{arrow_length}     = $self->{_items}{$item}{line}->get('arrow-length');
		$self->{_items}{$item}{arrow_tip_length} = $self->{_items}{$item}{line}->get('arrow-tip-length');
	}

	#set type flag
	$self->{_items}{$item}{type} = 'line';
	$self->{_items}{$item}{uid}  = $self->{_uid}++;

	$self->{_items}{$item}{mirrored_w} = $mirrored_w;
	$self->{_items}{$item}{mirrored_h} = $mirrored_h;

	$self->{_items}{$item}{stroke_color}       = $self->{_stroke_color};

	#create rectangles
	$self->handle_rects('create', $item);
	if ($copy_item) {
		$self->handle_embedded('update', $item);
		$self->handle_rects('hide', $item);
	}

	$self->setup_item_signals($self->{_items}{$item}{line});
	$self->setup_item_signals_extra($self->{_items}{$item}{line});

	$self->setup_item_signals($self->{_items}{$item});
	$self->setup_item_signals_extra($self->{_items}{$item});

	return $item;
}

sub create_ellipse {
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;
	my $numbered  = shift;

	my ($x, $y, $width, $height)     = (0, 0, 0, 0);
	my $stroke_color = $self->{_stroke_color};
	my $fill_color   = $self->{_fill_color};
	my $line_width     = $self->{_line_width};

	#use event coordinates and selected color
	if ($ev) {
		$x = $ev->x;
		$y = $ev->y;

		#use source item coordinates and item color
	} elsif ($copy_item) {
		$x = $copy_item->get('x') + 20;
		$y = $copy_item->get('y') + 20;
		$width = $copy_item->get('width');
		$height = $copy_item->get('height');
		$stroke_color = $self->{_items}{$copy_item}{stroke_color};
		$fill_color   = $self->{_items}{$copy_item}{fill_color};
		$line_width     = $self->{_items}{$copy_item}{ellipse}->get('line-width');
		$numbered       = TRUE if exists $self->{_items}{$copy_item}{text};
	}

	my $item    = GooCanvas2::CanvasRect->new(
		parent=>$self->{_canvas}->get_root_item, x=>$x, y=>$y, width=>$width, height=>$height,
		'fill-color-rgba' => 0,
		'line-dash'    => GooCanvas2::CanvasLineDash->newv([5, 5]),
		'line-width'   => 1,
		'stroke-color' => 'gray',
	);

	$self->{_current_new_item} = $item unless ($copy_item);
	$self->{_items}{$item} = $item;

	$self->{_items}{$item}{ellipse} = GooCanvas2::CanvasEllipse->new(
		parent=>$self->{_canvas}->get_root_item, x=>$item->get('x'), y=>$item->get('y'), width=>$item->get('width'),
		height=>$item->get('height'),
		'fill-color-gdk-rgba'   => $fill_color,
		'stroke-color-gdk-rgba' => $stroke_color,
		'line-width'     => $line_width,
	);

	#numbered ellipse
	if ($numbered) {

		my $number = $self->get_highest_auto_digit();
		$number++;

		$self->{_items}{$item}{text} = GooCanvas2::CanvasText->new(
			parent=>$self->{_canvas}->get_root_item, text=>"<span font_desc='" . $self->{_font} . "' >" . $number . "</span>",
			x=>$self->{_items}{$item}{ellipse}->get('center-x'),
			y=>$self->{_items}{$item}{ellipse}->get('center-y'),
			width=>-1,
			anchor=> 'center',
			'use-markup'   => TRUE,
			'fill-color-gdk-rgba'   => $stroke_color,
			'line-width'   => $line_width,
		);

		#save used number
		$self->{_items}{$item}{text}{digit} = $number;

		#set type flag
		$self->{_items}{$item}{type} = 'number';
		$self->{_items}{$item}{uid}  = $self->{_uid}++;

		#adjust parent rectangle if numbered ellipse
		my $tb = $self->{_items}{$item}{text}->get_bounds;

		#keep ratio = 1
		my $qs = abs($tb->x1 - $tb->x2);
		$qs = abs($tb->y1 - $tb->y2) if abs($tb->y1 - $tb->y2) > abs($tb->x1 - $tb->x2);

		#add line width of parent ellipse
		$qs += $self->{_items}{$item}{ellipse}->get('line-width') + 5;

		if ($copy_item) {
			$self->{_items}{$item}->set(
				'x'          => $self->{_items}{$item}->get('x') + 20,
				'y'          => $self->{_items}{$item}->get('y') + 20,
				'width'      => $qs,
				'height'     => $qs,
				'visibility' => 'hidden',
			);
		} else {
			$self->{_items}{$item}->set(
				'x'          => $self->{_items}{$item}->get('x') - $qs,
				'y'          => $self->{_items}{$item}->get('y') - $qs,
				'width'      => $qs,
				'height'     => $qs,
				'visibility' => 'hidden',
			);
		}

		$self->handle_embedded('hide', $item);

	} else {

		#set type flag
		$self->{_items}{$item}{type} = 'ellipse';
		$self->{_items}{$item}{uid}  = $self->{_uid}++;
	}

	#save color and opacity as well
	$self->{_items}{$item}{fill_color}         = $self->{_fill_color};
	$self->{_items}{$item}{stroke_color}       = $self->{_stroke_color};

	#create rectangles
	$self->handle_rects('create', $item);
	if ($copy_item) {
		$self->handle_embedded('update', $item);
		$self->handle_rects('hide', $item);
	}

	if ($numbered) {
		$self->setup_item_signals($self->{_items}{$item}{text});
		$self->setup_item_signals_extra($self->{_items}{$item}{text});
	}

	$self->setup_item_signals($self->{_items}{$item}{ellipse});
	$self->setup_item_signals_extra($self->{_items}{$item}{ellipse});

	$self->setup_item_signals($self->{_items}{$item});
	$self->setup_item_signals_extra($self->{_items}{$item});

	return $item;
}

sub create_rectangle {
	my $self      = shift;
	my $ev        = shift;
	my $copy_item = shift;

	my ($x, $y, $width, $height)     = (0, 0, 0, 0);
	my $stroke_color = $self->{_stroke_color};
	my $fill_color   = $self->{_fill_color};
	my $line_width     = $self->{_line_width};

	#use event coordinates and selected color
	if ($ev) {
		$x = $ev->x;
		$y = $ev->y;

		#use source item coordinates and item color
	} elsif ($copy_item) {
		$x = $copy_item->get('x') + 20;
		$y = $copy_item->get('y') + 20;
		$width = $copy_item->get('width');
		$height = $copy_item->get('height');
		$stroke_color = $self->{_items}{$copy_item}{stroke_color};
		$fill_color   = $self->{_items}{$copy_item}{fill_color};
		$line_width     = $self->{_items}{$copy_item}->get('line-width');
	}

	my $item = GooCanvas2::CanvasRect->new(
		parent=>$self->{_canvas}->get_root_item, x=>$x, y=>$y, width=>$width, height=>$height,
		'fill-color-gdk-rgba'   => $fill_color,
		'stroke-color-gdk-rgba' => $stroke_color,
		'line-width'     => $line_width,
	);

	$self->{_current_new_item} = $item unless ($copy_item);
	$self->{_items}{$item} = $item;

	#set type flag
	$self->{_items}{$item}{type} = 'rectangle';
	$self->{_items}{$item}{uid}  = $self->{_uid}++;

	$self->{_items}{$item}{fill_color}         = $self->{_fill_color};
	$self->{_items}{$item}{stroke_color}       = $self->{_stroke_color};

	#create rectangles
	$self->handle_rects('create', $item);

	$self->setup_item_signals($self->{_items}{$item});
	$self->setup_item_signals_extra($self->{_items}{$item});

	return $item;
}


# getters and setters

sub gettext { shift->{_d} }
sub dicons { shift->{_dicons} }
sub icons { shift->{_icons} }
sub clipboard { shift->{_clipboard} }
sub items { shift->{_items} }
sub drawing_window { shift->{_drawing_window} }
sub canvas { shift->{_canvas} }

sub cut {
	my $self = shift;
	$self->{_cut} = shift if scalar @_;
	return $self->{_cut};
}
sub current_copy_item {
	my $self = shift;
	$self->{_current_copy_item} = shift if scalar @_;
	return $self->{_current_copy_item};
}

sub current_item {
	my $self = shift;
	$self->{_current_item} = shift if scalar @_;
	return $self->{_current_item};
}

sub current_new_item {
	my $self = shift;
	$self->{_current_new_item} = shift if scalar @_;
	return $self->{_current_new_item};
}

sub canvas_bg {
	my $self = shift;
	$self->{_canvas_bg} = shift if scalar @_;
	return $self->{_canvas_bg};
}

sub factory {
	my $self = shift;
	$self->{_factory} = shift if scalar @_;
	return $self->{_factory};
}

sub autoscroll {
	my $self = shift;
	$self->{_autoscroll} = shift if scalar @_;
	return $self->{_autoscroll};
}

sub stroke_color {
	my $self = shift;
	$self->{_stroke_color} = shift if scalar @_;
	return $self->{_stroke_color};
}

sub fill_color {
	my $self = shift;
	$self->{_fill_color} = shift if scalar @_;
	return $self->{_fill_color};
}

sub line_width {
	my $self = shift;
	$self->{_line_width} = shift if scalar @_;
	return $self->{_line_width};
}

sub font {
	my $self = shift;
	$self->{_font} = shift if scalar @_;
	return $self->{_font};
}

sub uid { shift->{_uid} }

sub increase_uid { shift->{_uid}++ }

sub uimanager { shift->{_uimanager} }

1;

