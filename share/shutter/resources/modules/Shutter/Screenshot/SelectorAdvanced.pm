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

package Shutter::Screenshot::SelectorAdvanced;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Gtk3::ImageView;
use GooCanvas2;
use GooCanvas2::CairoTypes;
use Shutter::Screenshot::Main;
use Shutter::Screenshot::History;

use Data::Dumper;
our @ISA = qw(Shutter::Screenshot::Main);

#Glib
use Glib qw/TRUE FALSE/;

#--------------------------------------

sub new {
	my $class = shift;

	# Call the constructor of the superclass (Shutter::Screenshot::Main)
	my $self = $class->SUPER::new(shift, shift, shift, shift);

	# Initialize interactive behavior and helper flags
	$self->{_zoom_active}            = shift; # Determines if magnifier tool is active at start
	$self->{_hide_time}              = shift; # Timeout allowing the server to redraw obscured screen portions
	$self->{_show_help}              = shift; # Toggle flag for the introductory shortcut guide panel

	# Set initial geometry constraints for the selection area
	$self->{_init_x}                 = shift;
	$self->{_init_y}                 = shift;
	$self->{_init_w}                 = shift;
	$self->{_init_h}                 = shift;
	$self->{_confirmation_necessary} = shift; # If true, user must confirm via Enter key

	# Query and calculate the system's monitor scale factor for HiDPI support
	my $scale = 1;
	eval {
		$scale = $self->{_select_window}->get_scale_factor if $self->{_select_window};
	};
	$self->{_dpi_scale} = $scale || 1;

	# Create the independent Popup window container for the magnifier lens preview
	$self->{_zoom_window} = Gtk3::Window->new('popup');
	$self->{_zoom_window}->set_decorated(0);
	$self->{_zoom_window}->set_keep_above(1);
	$self->{_zoom_window}->set_modal(0);

	# Setup the layout inside the magnifier popup
	my $zoom_vbox = Gtk3::VBox->new(0, 4);
	$self->{_zoom_window}->add($zoom_vbox);

	my $scwin = Gtk3::ScrolledWindow->new;
	$scwin->set_policy('never', 'never');
	$zoom_vbox->pack_start($scwin, 1, 1, 0);
	
	# Instantiate coordinate context descriptors
	$self->{_x_label}    = Gtk3::Label->new("X: 0");
	$self->{_y_label}    = Gtk3::Label->new("Y: 0");
	$self->{_size_label} = Gtk3::Label->new("0 x 0");

	$zoom_vbox->pack_start($self->{_x_label}, 0, 0, 0);
	$zoom_vbox->pack_start($self->{_y_label}, 0, 0, 0);
	$zoom_vbox->pack_start($self->{_size_label}, 0, 0, 0);

	# Create the drawing lens canvas area for pixel zooming
	$self->{_zoom_area} = Gtk3::DrawingArea->new;
	$self->{_zoom_area}->set_size_request(160, 160);
	$scwin->add($self->{_zoom_area});

	# Create the primary full-screen workspace window
	$self->{_select_window} = Gtk3::Window->new('popup');
	$self->{_select_window}->set_decorated(0);
	$self->{_select_window}->set_keep_above(1);
	$self->{_select_window}->set_modal(1);

	# Create the main full-screen interaction canvas
	$self->{_canvas} = Gtk3::DrawingArea->new;

	# Use a Gtk3::Overlay container to layer floating dialog elements on top of the canvas
	my $overlay = Gtk3::Overlay->new();
	$overlay->add($self->{_canvas});
	
	# Instantiate and append the dimension property dialog panel into the overlay
	$self->{_prop_window} = $self->select_dialog();
	$overlay->add_overlay($self->{_prop_window});
	
	# Lock the coordinate control panel statically to the bottom-right viewport corner
	$self->{_prop_window}->set_halign('end');
	$self->{_prop_window}->set_valign('end');
	$self->{_prop_window}->set_margin_right(20);
	$self->{_prop_window}->set_margin_bottom(20);
	
	# Start concealed until explicitly requested via Shift or Right-click
	$self->{_prop_window}->hide();
	$self->{_prop_active} = 0;

	# Bind the configured overlay workspace layout to the primary window shell
	$self->{_select_window}->add($overlay);

	# PRIMARY CANVAS DRAW SIGNAL: Renders base snapshot and rubberband marquee selection
	$self->{_selector_handler} = $self->{_canvas}->signal_connect(draw => sub {
		my ($widget, $cr) = @_;
		
		# 1. Render the captured raw desktop image layer
		if (defined $self->{_screenshot_pixbuf}) {
			Gtk3::Gdk::cairo_set_source_pixbuf($cr, $self->{_screenshot_pixbuf}, 0, 0);
			$cr->paint;
		}

		# 2. Render the selection geometry boundary pathing accents
		if (defined $self->{_state} && defined $self->{_state}->{sel}) {
			my $s = $self->{_state}->{sel};
			
			# Fallback gray accent rule parameters
			my ($r, $g, $b) = (0.5, 0.5, 0.5);

			# Safely tap into the current GTK theme context stylesheet parameters
			eval {
				my $context = $widget->get_style_context();
				$context->save();
				# Match the desktop's native selection indicator tint values (rubberband class)
				$context->add_class('rubberband');
				
				my $rgba = $context->get_background_color('normal');
				if (defined $rgba) {
					$r = $rgba->red;
					$g = $rgba->green;
					$b = $rgba->blue;
				}
				$context->restore();
			};

			# 3. Draw the solid rectangular bounding outline strokes
			$cr->set_source_rgba($r, $g, $b, 1.0); 
			$cr->set_line_width(2.0);
			$cr->rectangle($s->{x}, $s->{y}, $s->{width}, $s->{height});
			$cr->stroke;

			# 4. Fill the rectangle selection interior with a soft accent mask tint
			$cr->set_source_rgba($r, $g, $b, 0.15); 
			$cr->rectangle($s->{x}, $s->{y}, $s->{width}, $s->{height});
			$cr->fill;
		}

		# -------------------------------------------------------------------------
		# DRAW OVERLAY LAYER: Render dynamic native help instructions box on context
		# -------------------------------------------------------------------------
		if ($self->{_show_help_overlay}) {
			my $allocated_w = $widget->get_allocated_width;
			my $allocated_h = $widget->get_allocated_height;

			# Ensure gettext handle is locally accessible for translations
			my $d = $self->{_sc}->get_gettext;
			my $text1 = $d->get("Draw a rectangular area using the mouse.");
			my $text2 = $d->get("To take a screenshot, double-click or press the Enter key.\nPress Esc to abort.");
			my $text3 =
					$d->get("<b>shift/right-click</b> → selection dialog on/off") . "\n"
				. $d->get("<b>scrollwheel</b> → zoom in/out") . "\n"
				. $d->get("<b>space</b> → zoom window on/off") . "\n"
				. $d->get("<b>cursor keys</b> → move cursor") . "\n"
				. $d->get("<b>cursor keys + alt</b> → move selection") . "\n"
				. $d->get("<b>cursor keys + ctrl</b> → resize selection");

			# Create layout and assign structured markup blocks
			my $layout = $widget->create_pango_layout("");
			$layout->set_markup(
				"<span foreground='#FFFFFF' size='xx-large' weight='bold'>$text1</span>\n" .
				"<span foreground='#E0E0E0' size='large'>$text2</span>\n\n" .
				"<span foreground='#CCCCCC' size='medium'>$text3</span>"
			);
			
			# Restrict max text layout bounds width (e.g., 550px) to force wrapping
			my $max_text_width = 550;
			$layout->set_width($max_text_width * Pango::SCALE);
			$layout->set_wrap('word-char');

			# Query exact geometric dimensions parsed by the layout engine
			my ($text_w, $text_h) = $layout->get_pixel_size();

			# Configure bounding box dimensions with symmetrical 30px padding
			my $padding = 30;
			my $box_w   = $text_w + ($padding * 2);
			my $box_h   = $text_h + ($padding * 2);

			# Center the dynamic card based on current allocation bounds
			my $box_x = int(($allocated_w - $box_w) / 2);
			my $box_y = int(($allocated_h - $box_h) / 2);

			# Draw backdrop card using specific hex color structure (rgba: 19, 19, 19, 0.85)
			$cr->save();
			$cr->set_source_rgba(0.074, 0.074, 0.074, 0.85);
			my $radius = 20;
			$cr->new_sub_path();
			$cr->arc($box_x + $box_w - $radius, $box_y + $radius, $radius, -1.5708, 0);
			$cr->arc($box_x + $box_w - $radius, $box_y + $box_h - $radius, $radius, 0, 1.5708);
			$cr->arc($box_x + $radius, $box_y + $box_h - $radius, $radius, 1.5708, 3.1416);
			$cr->arc($box_x + $radius, $box_y + $radius, $radius, 3.1416, 4.7124);
			$cr->close_path();
			$cr->fill();
			$cr->restore();

			# Execute final surface text blitting inside the padded region
			$cr->save();
			$cr->move_to($box_x + $padding, $box_y + $padding);
			Pango::Cairo::show_layout($cr, $layout);
			$cr->restore();
			}


			# (Hier steht dein bereits existierendes 'return FALSE;')
			return FALSE;
		});

	return $self;
}



#~ sub DESTROY {
#~ my $self = shift;
#~ print "$self dying at\n";
#~ }


# =========================================================================
# MAIN ROUTINE: INTERACTIVE ADVANCED SELECTOR SCREENSHOT MODE
# =========================================================================
sub select_advanced {
	my $self = shift;

	my $output = 5;
	my $d = $self->{_sc}->get_gettext;

	# Freeze the desktop layout view by capturing the root window buffer maps
	my $clean_pixbuf = Gtk3::Gdk::pixbuf_get_from_window(
		$self->{_root}, 0, 0, $self->{_root}->{w}, $self->{_root}->{h}
	);

	$self->{_screenshot_pixbuf} = $clean_pixbuf;

	# Initialize global selector session data tracking context mappings
	$self->{_state} = {
		pixbuf   => $clean_pixbuf,
		zoom     => 5,
		cursor_x => 0,
		cursor_y => 0,
		sel      => undef,
		dclick   => undef,
	};
	my $state = $self->{_state};

	# Query the hardware pointing device vectors variables configurations on load
	my ($window_at_pointer, $xinit, $yinit, $mask) = $self->{_root}->get_pointer;
	$state->{cursor_x} = $xinit;
	$state->{cursor_y} = $yinit;

	# Configure primary workspace interaction canvas parameters
	my $canvas = $self->{_canvas};
	$canvas->set_can_focus(TRUE);
	$canvas->add_events([
		qw(
			button-press-mask
			button-release-mask
			pointer-motion-mask
			key-press-mask
			scroll-mask
		)
	]);

	# Retrieve shared zoom viewer layout labels references pointers
	my $xlabel = $self->{_x_label};
	my $ylabel = $self->{_y_label};
	my $rlabel = $self->{_size_label};

	# Configure magnifier window parameters layout rules
	$self->{_zoom_window}->set_type_hint('splashscreen');
	$self->{_zoom_window}->set_can_focus(TRUE);
	$self->{_zoom_window}->set_accept_focus(TRUE);
	$self->{_zoom_window}->set_skip_taskbar_hint(TRUE);
	$self->{_zoom_window}->set_skip_pager_hint(TRUE);
	$self->{_zoom_window}->set_keep_above(TRUE);
	$self->{_zoom_window}->move($self->{_root}->{x}, $self->{_root}->{y});

	# Configure primary workspace selection window behaviors
	$self->{_select_window}->set_type_hint('splashscreen');
	$self->{_select_window}->set_can_focus(TRUE);
	$self->{_select_window}->set_accept_focus(TRUE);
	$self->{_select_window}->set_modal(TRUE);
	$self->{_select_window}->set_skip_taskbar_hint(TRUE);
	$self->{_select_window}->set_skip_pager_hint(TRUE);
	$self->{_select_window}->set_keep_above(TRUE);
	$self->{_select_window}->set_default_size($self->{_root}->{w}, $self->{_root}->{h});
	$self->{_select_window}->resize($self->{_root}->{w}, $self->{_root}->{h});
	$self->{_select_window}->move($self->{_root}->{x}, $self->{_root}->{y});
	
	# Keep coordinate control properties widgets hidden initially
	if (defined $self->{_prop_window}) {
		$self->{_prop_window}->hide;
		$self->{_prop_active} = 0;
	}

	# -------------------------------------------------------------------------
	# INITIALIZE INTRODUCTION USER GUIDE OVERLAY (Cairo status flag configuration)
	# -------------------------------------------------------------------------
	$self->{_show_help_overlay} = 0;

	if (($self->{_init_w} < 1 || $self->{_init_h} < 1) && $self->{_show_help}) {
		$self->{_show_help_overlay} = 1;
	}

	# Realize window configurations pipelines
	$self->{_select_window}->show_all;
	
	$self->{_prop_window}->hide if defined $self->{_prop_window};
	$self->{_prop_active} = 0;

	$self->{_select_window}->present;

	# Set the initial targeting reticle layout cursor icon descriptor
	if (defined $self->{_canvas}->get_window()) {
		my $gdk_win = $self->{_canvas}->get_window();
		my $cur = Gtk3::Gdk::Cursor->new_from_name($gdk_win->get_display(), 'crosshair');
		$gdk_win->set_cursor($cur) if defined $cur;
	}

	# -------------------------------------------------------------------------
	# ANONYMOUS INTERACTION SCREEN REDRAW METHOD
	# -------------------------------------------------------------------------
	my $queue_redraw = sub {
		if (defined $self->{_canvas}) {
			$self->{_canvas}->queue_draw;
		}
		if (defined $self->{_zoom_area}) {
			$self->{_zoom_area}->queue_draw;
		}
	};

	# -------------------------------------------------------------------------
	# RENDERING SIGNAL: DETAIL PIPELINE MAGNIFIER (Zoom Area Draw Pipeline)
	# -------------------------------------------------------------------------
	$self->{_zoom_area}->signal_connect(
		'draw',
		sub {
			my ($widget, $cr) = @_;

			my $pixbuf = $self->{_screenshot_pixbuf};
			return FALSE unless $pixbuf;

			my $zoom = $self->{_state}->{zoom}     || 4;
			my $cx   = $self->{_state}->{cursor_x} // 0;
			my $cy   = $self->{_state}->{cursor_y} // 0;

			my $allocated_w = $widget->get_allocated_width;
			my $allocated_h = $widget->get_allocated_height;

			my $crop_w = int($allocated_w / $zoom);
			my $crop_h = int($allocated_h / $zoom);

			my $src_x = int($cx - $crop_w / 2);
			my $src_y = int($cy - $crop_h / 2);

			$src_x = 0 if $src_x < 0;
			$src_y = 0 if $src_y < 0;

			my $max_x = $pixbuf->get_width  - $crop_w;
			my $max_y = $pixbuf->get_height - $crop_h;

			$src_x = $max_x if $src_x > $max_x;
			$src_y = $max_y if $src_y > $max_y;

			my $crop = $pixbuf->new_subpixbuf($src_x, $src_y, $crop_w, $crop_h);

			# Scale cropped sub-image to draw a pixelated detail context layer
			$cr->save;
			$cr->scale($zoom, $zoom);
			Gtk3::Gdk::cairo_set_source_pixbuf($cr, $crop, 0, 0);
			$cr->paint;
			$cr->restore;

			# Render magnifier tactical grid target indicators hairs lines
			my $mid_x = int($allocated_w / 2);
			my $mid_y = int($allocated_h / 2);

			if (($zoom % 2) != 0) {
				$mid_x += 0.5;
				$mid_y += 0.5;
			}

			$cr->set_source_rgba(1.0, 0.0, 0.0, 0.8); 
			$cr->set_line_width($zoom); 

			my $half_pixel = $zoom / 2;

			# Render disconnected intersecting crosshairs lines targeting paths
			$cr->move_to(0, $mid_y);
			$cr->line_to($mid_x - $half_pixel, $mid_y);
			
			$cr->move_to($mid_x + $half_pixel, $mid_y);
			$cr->line_to($allocated_w, $mid_y);

			$cr->move_to($mid_x, 0);
			$cr->line_to($mid_x, $mid_y - $half_pixel);
			
			$cr->move_to($mid_x, $mid_y + $half_pixel);
			$cr->line_to($mid_x, $allocated_h);

			$cr->stroke;

			return FALSE; # Propagate draw state execution updates
		}
	);

	# -------------------------------------------------------------------------
	# ANONYMOUS INTERACTION TEXT HUD DISPLAY STRINGS REFRESH HANDLERS
	# -------------------------------------------------------------------------
	my $set_cursor_text = sub {
		my ($x, $y) = @_;
		$xlabel->set_text("X: " . (int($x) + 1));
		$ylabel->set_text("Y: " . (int($y) + 1));
	};

	my $update_size_text = sub {
		if (defined $self->{_state}) {
			my $s = $self->{_state}->{sel};
			if (defined $s) {
				my $w = int($s->{width}  // 0);
				my $h = int($s->{height} // 0);
				
				$rlabel->set_text($w . " x " . $h) if defined $rlabel;
				return;
			}
		}
		
		$rlabel->set_text("0 x 0") if defined $rlabel;
	};

	my $finish_capture = sub {
		my $s = $state->{sel};

		$self->{_select_window}->hide if defined $self->{_select_window};
		$self->{_zoom_window}->hide   if defined $self->{_zoom_window};
		$self->{_prop_window}->hide   if defined $self->{_prop_window};

		# Defer the main loop termination briefly to allow the display server to catch up
		Glib::Timeout->add($self->{_hide_time}, sub {
			Gtk3->main_quit;
			return FALSE;
		});

		Gtk3->main();
		$output = $self->take_screenshot($s, $clean_pixbuf);
		$self->quit;
	};

	# Setup initial helper constraints tracker states
	$self->{_selector_init} = $self->{_show_help} ? TRUE : FALSE;
	$self->{_selector_init_zoom} = 0;

	# -------------------------------------------------------------------------
	# INTERACTION EVENT STATE VARIABLES (Marquee Dragging, Moving & Resizing)
	# -------------------------------------------------------------------------
	my $is_dragging     = 0;
	my $is_moving_rect  = 0;
	my $is_resizing     = ''; # Holds direction strings: 'n', 's', 'w', 'e', 'nw', 'ne', 'sw', 'se'
	
	my ($start_x, $start_y)   = (0, 0);
	my ($offset_x, $offset_y) = (0, 0);
	
	# Proximity handle padding context (6 pixels scaled for HiDPI)
	my $handle_size = 6 * ($self->{_dpi_scale} // 1);

	# Helper sub to detect if the pointer sits near any edge or corner of the marquee
	my $get_resize_edge = sub {
		my ($mx, $my) = @_;
		my $s = $self->{_state}->{sel};
		return '' unless (defined $s && $s->{width} > 0 && $s->{height} > 0);

		my $x1 = $s->{x};          my $y1 = $s->{y};
		my $x2 = $s->{x} + $s->{width}; my $y2 = $s->{y} + $s->{height};

		# Discard checks if mouse is too far outside the marquee buffer zone
		return '' if ($mx < $x1 - $handle_size || $mx > $x2 + $handle_size ||
		              $my < $y1 - $handle_size || $my > $y2 + $handle_size);

		my $near_n = (abs($my - $y1) <= $handle_size);
		my $near_s = (abs($my - $y2) <= $handle_size);
		my $near_w = (abs($mx - $x1) <= $handle_size);
		my $near_e = (abs($mx - $x2) <= $handle_size);

		# Corner detection takes strict priority over line edge paths
		return 'nw' if ($near_n && $near_w);
		return 'ne' if ($near_n && $near_e);
		return 'sw' if ($near_s && $near_w);
		return 'se' if ($near_s && $near_e);
		return 'n'  if ($near_n && $mx >= $x1 && $mx <= $x2);
		return 's'  if ($near_s && $mx >= $x1 && $mx <= $x2);
		return 'w'  if ($near_w && $my >= $y1 && $my <= $y2);
		return 'e'  if ($near_e && $mx >= $x1 && $mx <= $x2);

		return '';
	};

	# =========================================================================
	# BUTTON PRESS EVENT: Mouse clicks initiate actions based on pointer location
	# =========================================================================
	$self->{_view_button_handler} = $self->{_canvas}->signal_connect('button-press-event' => sub {
		my ($widget, $event) = @_;
		return FALSE unless defined $event;

		if ($event->button == 1) { 
			my $mx = int($event->x);
			my $my = int($event->y);
			my $s  = $self->{_state}->{sel};

			# Check if clicking a resize handle edge
			my $edge = $get_resize_edge->($mx, $my);

			if ($edge ne '') {
				$is_resizing = $edge;
				$start_x = $mx; $start_y = $my;
			} elsif (defined $s && $s->{width} > 0 && $s->{height} > 0 &&
				$mx >= $s->{x} && $mx <= ($s->{x} + $s->{width}) &&
				$my >= $s->{y} && $my <= ($s->{y} + $s->{height})) {
				
				# Clicking inside marquee activates reposition/moving mode
				$is_moving_rect = 1;
				$offset_x = $mx - $s->{x};
				$offset_y = $my - $s->{y};
			} else {
				# Clicking empty background constructs a brand new marquee bounds area
				$is_dragging = 1;
				$start_x = $mx; $start_y = $my;

				# Clear the Cairo rendering flag to dim the help card instantly
				$self->{_show_help_overlay} = 0;
				$self->{_state}->{sel} = { x => $start_x, y => $start_y, width => 0, height => 0 };
			}

			$queue_redraw->();
		}
		return TRUE;
	});


	# =========================================================================
	# MOTION NOTIFY EVENT: Mouse movements recalculate geometric states and cursors
	# =========================================================================
	$self->{_view_event_handler} = $self->{_canvas}->signal_connect('motion-notify-event' => sub {
		my ($widget, $event) = @_;
		return FALSE unless defined $event;

		my $mx = int($event->x);
		my $my = int($event->y);

		$self->{_state}->{cursor_x} = $mx;
		$self->{_state}->{cursor_y} = $my;
		$set_cursor_text->($mx, $my) if defined $set_cursor_text;

		# Safely trigger magnifier displacement check pipeline
		$self->zoom_check_pos() if (defined $self->{_zoom_window} && $self->{_zoom_window}->get_visible && $self->can('zoom_check_pos'));

		# --- CONTEXTUAL MOUSE CURSOR SHAPE EVALUATION ---
		if (defined $widget->get_window()) {
			my $gdk_window = $widget->get_window();
			my $display    = $gdk_window->get_display();
			my $s          = $self->{_state}->{sel};
			
			my $cursor_type = 'crosshair'; # Target crosshair default

			my $active_edge = $is_resizing ne '' ? $is_resizing : $get_resize_edge->($mx, $my);

			if ($active_edge ne '') {
				my %cursors = (
					n  => 'n-resize',  s  => 's-resize',  w  => 'w-resize',  e  => 'e-resize',
					nw => 'nw-resize', ne => 'ne-resize', sw => 'sw-resize', se => 'se-resize'
				);
				$cursor_type = $cursors{$active_edge};
			} elsif ($is_moving_rect) {
				$cursor_type = 'grabbing'; # Hand grabs down tight while shifting positions
			} elsif (defined $s && $s->{width} > 0 && $s->{height} > 0) {
				if ($mx >= $s->{x} && $mx <= ($s->{x} + $s->{width}) &&
					$my >= $s->{y} && $my <= ($s->{y} + $s->{height})) {
					$cursor_type = 'grab'; # Hovering inside marquee presents open palm
				}
			}

			my $new_cursor = Gtk3::Gdk::Cursor->new_from_name($display, $cursor_type);
			$gdk_window->set_cursor($new_cursor) if defined $new_cursor;
		}

		# --- COMPUTE INTERACTIVE COORDINATE ADJUSTMENTS ---
		if ($is_dragging) { 
			my $x = $mx < $start_x ? $mx : $start_x;
			my $y = $my < $start_y ? $my : $start_y;
			my $w = abs($mx - $start_x);
			my $h = abs($my - $start_y);
			$self->{_state}->{sel} = { x => $x, y => $y, width => $w, height => $h };
			$update_size_text->() if defined $update_size_text;

		} elsif ($is_moving_rect) {
			my $s = $self->{_state}->{sel};
			if (defined $s) {
				my $new_x = $mx - $offset_x; my $new_y = $my - $offset_y;
				$new_x = 0 if $new_x < 0;   $new_y = 0 if $new_y < 0;
				
				my $max_x = $self->{_root}->{w} - $s->{width};
				my $max_y = $self->{_root}->{h} - $s->{height};
				$new_x = $max_x if $new_x > $max_x;
				$new_y = $max_y if $new_y > $max_y;

				$s->{x} = $new_x; $s->{y} = $new_y;
			}
		} elsif ($is_resizing ne '') {
			my $s = $self->{_state}->{sel};
			if (defined $s) {
				my $x1 = $s->{x}; my $y1 = $s->{y};
				my $x2 = $s->{x} + $s->{width}; my $y2 = $s->{y} + $s->{height};

				if ($is_resizing =~ /w/ && $mx < $x2) { $x1 = $mx; }
				if ($is_resizing =~ /e/ && $mx > $x1) { $x2 = $mx; }
				if ($is_resizing =~ /n/ && $my < $y2) { $y1 = $my; }
				if ($is_resizing =~ /s/ && $my > $y1) { $y2 = $my; }

				$s->{x} = $x1; $s->{y} = $y1;
				$s->{width}  = $x2 - $x1;
				$s->{height} = $y2 - $y1;
				$update_size_text->() if defined $update_size_text;
			}
		}

		# Feed numerical widget entry values live when sidebar panels are currently active
		if (($is_dragging || $is_moving_rect || $is_resizing ne '') && $self->{_prop_active}) {
			my $s = $self->{_state}->{sel};
			if (defined $s) {
				$self->{_x_spin_w}->signal_handler_block($self->{_x_spin_w_handler})           if defined $self->{_x_spin_w_handler};
				$self->{_y_spin_w}->signal_handler_block($self->{_y_spin_w_handler})           if defined $self->{_y_spin_w_handler};
				$self->{_width_spin_w}->signal_handler_block($self->{_width_spin_w_handler})   if defined $self->{_width_spin_w_handler};
				$self->{_height_spin_w}->signal_handler_block($self->{_height_spin_w_handler}) if defined $self->{_height_spin_w_handler};

				$self->{_x_spin_w}->set_value(int($s->{x}))      if defined $self->{_x_spin_w};
				$self->{_y_spin_w}->set_value(int($s->{y}))      if defined $self->{_y_spin_w};
				$self->{_width_spin_w}->set_value(int($s->{width}))   if defined $self->{_width_spin_w};
				$self->{_height_spin_w}->set_value(int($s->{height})) if defined $self->{_height_spin_w};

				$self->{_x_spin_w}->signal_handler_unblock($self->{_x_spin_w_handler})           if defined $self->{_x_spin_w_handler};
				$self->{_y_spin_w}->signal_handler_unblock($self->{_y_spin_w_handler})           if defined $self->{_y_spin_w_handler};
				$self->{_width_spin_w}->signal_handler_unblock($self->{_width_spin_w_handler})   if defined $self->{_width_spin_w_handler};
				$self->{_height_spin_w}->signal_handler_unblock($self->{_height_spin_w_handler}) if defined $self->{_height_spin_w_handler};
			}
		}

		$queue_redraw->();
		return TRUE;
	});


	# =========================================================================
	# BUTTON RELEASE EVENT: Mouse releases finalize drag operations
	# =========================================================================
	$self->{_view_release_handler} = $self->{_canvas}->signal_connect('button-release-event' => sub {
		my ($widget, $event) = @_;
		return FALSE unless defined $event;

		# Context Right click opens or closes parameters configuration settings
		if ($event->button == 3) {
			if (defined $self->{_prop_window}) {
				if ($self->{_prop_active}) {
					$self->{_prop_window}->hide;
					$self->{_prop_active} = 0;
				} else {
					my $mx = int($event->x); my $my = int($event->y);
					if (defined $self->{_state} && defined $self->{_state}->{sel}) {
						my $s = $self->{_state}->{sel};
						$self->{_x_spin_w}->set_value(int($s->{x}))      if defined $self->{_x_spin_w};
						$self->{_y_spin_w}->set_value(int($s->{y}))      if defined $self->{_y_spin_w};
						$self->{_width_spin_w}->set_value(int($s->{width}))   if defined $self->{_width_spin_w};
						$self->{_height_spin_w}->set_value(int($s->{height})) if defined $self->{_height_spin_w};
					} else {
						$self->{_x_spin_w}->set_value($mx) if defined $self->{_x_spin_w};
						$self->{_y_spin_w}->set_value($my) if defined $self->{_y_spin_w};
					}
					$self->{_prop_window}->show_all;
					$self->{_prop_active} = 1;
					$self->{_x_spin_w}->grab_focus if defined $self->{_x_spin_w};
				}
			}
		} elsif ($event->button == 1) { 
			my $was_modifying = ($is_moving_rect || $is_resizing ne '');
			$is_dragging    = 0;
			$is_moving_rect = 0;
			$is_resizing    = '';

			if (!$self->{_confirmation_necessary} && !$was_modifying) {
				$finish_capture->();
			}
		}
		return TRUE;
	});

	# =========================================================================
	# KEY PRESS EVENT: Full hardware layout keyboard input interceptor pipeline
	# =========================================================================
	$self->{_key_handler} = $self->{_select_window}->signal_connect('key-press-event' => sub {
		my ($window, $event) = @_;
		return FALSE unless defined $event;

		my $state_obj = $self->{_state};
		my $s = $state_obj->{sel};
		my ($window_at_pointer, $x, $y, $mask) = $self->{_root}->get_pointer;
		
		# Resolve text based representation mapping names for intercepted physical keypresses
		my $keyname = Gtk3::Gdk::keyval_name($event->keyval);

		# ---------------------------------------------------------------------
		# CRITICAL FIX: FREE TYPING PATH & VALUES UPDATE ON ENTER
		# ---------------------------------------------------------------------
		if ($self->{_prop_active}) {
			# Allow normal text typing, deletions and navigations to bypass interception
			if ($keyname =~ /^[0-9]$/ || $keyname eq 'BackSpace' || $keyname eq 'Delete' || 
			    $keyname eq 'Left'    || $keyname eq 'Right'     || $keyname eq 'period') {
				return FALSE; 
			}

			# Intercept Return/Enter while the dialog is active to commit values instead of shooting
			if ($keyname eq 'Return' || $keyname eq 'KP_Enter') {
				# Force all spin buttons to flush their current text buffers into numerical values
				$self->{_x_spin_w}->update()      if defined $self->{_x_spin_w};
				$self->{_y_spin_w}->update()      if defined $self->{_y_spin_w};
				$self->{_width_spin_w}->update()  if defined $self->{_width_spin_w};
				$self->{_height_spin_w}->update() if defined $self->{_height_spin_w};

				# Extract values safely beforehand to prevent inline syntax errors
				my $val_x = defined $self->{_x_spin_w} ? int($self->{_x_spin_w}->get_value) : 0;
				my $val_y = defined $self->{_y_spin_w} ? int($self->{_y_spin_w}->get_value) : 0;
				my $val_w = defined $self->{_width_spin_w} ? int($self->{_width_spin_w}->get_value) : 0;
				my $val_h = defined $self->{_height_spin_w} ? int($self->{_height_spin_w}->get_value) : 0;

				# Manually reshape the selection state with the fresh values
				$self->{_state}->{sel} = {
					x      => $val_x,
					y      => $val_y,
					width  => $val_w,
					height => $val_h,
				};

				# Force canvas updates to visualize the new geometry instantly
				$self->{_canvas}->queue_draw    if defined $self->{_canvas};
				$self->{_zoom_area}->queue_draw if defined $self->{_zoom_area};

				return TRUE; # Stop event propagation here to prevent taking the screenshot!
			}
		}
		# ---------------------------------------------------------------------

		# Shift action triggers settings viewport toggles
		if ($keyname eq 'Shift_L' || $keyname eq 'Shift_R') {
			if (defined $self->{_prop_window}) {
				if ($self->{_prop_active}) {
					$self->{_prop_window}->hide; $self->{_prop_active} = 0;
				} else {
					if (defined $s) {
						$self->{_x_spin_w}->set_value(int($s->{x}))      if defined $self->{_x_spin_w};
						$self->{_y_spin_w}->set_value(int($s->{y}))      if defined $self->{_y_spin_w};
						$self->{_width_spin_w}->set_value(int($s->{width}))   if defined $self->{_width_spin_w};
						$self->{_height_spin_w}->set_value(int($s->{height})) if defined $self->{_height_spin_w};
					}
					$self->{_prop_window}->show_all; $self->{_prop_active} = 1;
					$self->{_x_spin_w}->grab_focus if defined $self->{_x_spin_w};
				}
				$queue_redraw->() if defined $queue_redraw;
				return TRUE;
			}
		}

		my $has_ctrl = $event->state & 'control-mask';
		my $has_alt  = $event->state & 'mod1-mask';

		# Space toggles magnifier lens active visualization frames
		if ($keyname eq 'space' || $keyname eq 'Space') {
			if (defined $self->{_zoom_window} && $self->{_zoom_window}->get_visible) {
				$self->{_zoom_window}->hide; $self->{_zoom_active} = FALSE;
			} else {
				$self->{_zoom_active} = TRUE;
				$self->zoom_check_pos() if $self->can('zoom_check_pos');
				$self->{_zoom_window}->show_all if defined $self->{_zoom_window};
			}
			return TRUE;
		} elsif ($keyname eq 'Escape') {
			$self->quit;
			return TRUE;
		} elsif ($keyname eq 'Up') {
			if ($has_ctrl && $s) { $s->{height} -= 1; }
			elsif ($has_alt && $s) { $s->{y} -= 1; }
			else { $self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x, $y - 1); }
		} elsif ($keyname eq 'Down') {
			if ($has_ctrl && $s) { $s->{height} += 1; }
			elsif ($has_alt && $s) { $s->{y} += 1; }
			else { $self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x, $y + 1); }
		} elsif ($keyname eq 'Left') {
			if ($has_ctrl && $s) { $s->{width} -= 1; }
			elsif ($has_alt && $s) { $s->{x} -= 1; }
			else { $self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x - 1, $y); }
		} elsif ($keyname eq 'Right') {
			if ($has_ctrl && $s) { $s->{width} += 1; }
			elsif ($has_alt && $s) { $s->{x} += 1; }
			else { $self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x + 1, $y); }
		} elsif ($keyname eq 'KP_Add' || $keyname eq 'plus' || $keyname eq 'equal') {
			$state_obj->{zoom}++ if $has_ctrl;
		} elsif ($keyname eq 'KP_Subtract' || $keyname eq 'minus') {
			$state_obj->{zoom}-- if $has_ctrl; $state_obj->{zoom} = 1 if $state_obj->{zoom} < 1;
		} elsif ($keyname eq '0') {
			$state_obj->{zoom} = 1 if $has_ctrl;
		} elsif ($keyname eq 'Return' || $keyname eq 'KP_Enter') {
			$finish_capture->() if defined $s;
		}

		$self->{_canvas}->queue_draw if defined $self->{_canvas};
		return TRUE;
	});

	# Apply initial selection parameters asynchronously on main loop activation idle cycles
	Glib::Idle->add(sub {
		if ($self->{_init_w} && $self->{_init_h}) {
			$state->{sel} = {
				x      => $self->{_init_x},
				y      => $self->{_init_y},
				width  => $self->{_init_w},
				height => $self->{_init_h},
			};
			$queue_redraw->();
		}
		return FALSE;
	});

	# Intercept hardware layout keyboard inputs hooks strictly on the overlay viewport window node
	my $status = Gtk3::Gdk::keyboard_grab($self->{_select_window}->get_window, FALSE, Gtk3::get_current_event_time());

	# Synchronize magnifier initialization visibility states rules
	if ($self->{_zoom_active}) {
		$self->{_zoom_window}->show_all;
		$self->zoom_check_pos();
		$self->{_zoom_window}->get_window->raise;
	}

	Gtk3::main();
	return $output;
}


# =========================================================================
# LENS POSITIONING BOUNDS REGULATOR (Magnifier Window Collision Avoidance)
# =========================================================================
sub zoom_check_pos {
	my $self = shift;

	# Guard: Abort immediately if the magnifier window doesn't exist or is hidden
	return FALSE unless defined $self->{_zoom_window};
	return FALSE unless $self->{_zoom_window}->get_visible;

	# Query the real, absolute screen coordinates of the hardware mouse pointer
	my ($window_at_pointer, $ev_x, $ev_y, $mask) = $self->{_root}->get_pointer;

	# Retrieve the current screen dimensions and positioning of the magnifier window
	my ($zw, $zh) = $self->{_zoom_window}->get_size;
	my ($zx, $zy) = $self->{_zoom_window}->get_position;

	# Define a safety buffer padding context (50 pixels scaled for HiDPI support)
	my $distance = 50 * ($self->{_dpi_scale} // 1);
	
	# Construct an expanded safety collision box boundary around the current magnifier position
	my $box_x1 = $zx - $distance;
	my $box_y1 = $zy - $distance;
	my $box_x2 = $zx + $zw + $distance;
	my $box_y2 = $zy + $zh + $distance;

	# Collision Check: If the hardware cursor penetrates the expanded safety box
	if ($ev_x >= $box_x1 && $ev_x <= $box_x2 && $ev_y >= $box_y1 && $ev_y <= $box_y2) {
		
		# Define target layout screen corner positions (Strict Shutter clockwise order sequence)
		my @pos = (
			{x => $self->{_root}->{x},       y => $self->{_root}->{y}},       # 1. Top-Left
			{x => $self->{_root}->{x},       y => $self->{_root}->{h} - $zh}, # 2. Bottom-Left
			{x => $self->{_root}->{w} - $zw, y => $self->{_root}->{h} - $zh}, # 3. Bottom-Right
			{x => $self->{_root}->{w} - $zw, y => $self->{_root}->{y}},       # 4. Top-Right
		);

		# Iterate through available corners to discover the first non-colliding location
		foreach my $p (@pos) {
			my $p_box_x1 = $p->{x} - $distance;
			my $p_box_y1 = $p->{y} - $distance;
			my $p_box_x2 = $p->{x} + $zw + $distance;
			my $p_box_y2 = $p->{y} + $zh + $distance;

			# If the cursor does NOT collide with this specific corner's safety area
			if (!($ev_x >= $p_box_x1 && $ev_x <= $p_box_x2 && $ev_y >= $p_box_y1 && $ev_y <= $p_box_y2)) {
				# Instantly move the magnifier window to the safe screen corner location
				$self->{_zoom_window}->move($p->{x}, $p->{y});
				$self->{_zoom_window}->queue_draw;
				return TRUE; # Rotation successful, break routine pipeline
			}
		}
	}

	return TRUE; # Frame processing complete
}

# =========================================================================
# PROPERTY BOUNDS REGULATOR (Updates SpinButton limits and values safely)
# =========================================================================
sub adjust_prop_values {
	my $self = shift;

	# Guard: Abort immediately if session state tracking object is missing
	return unless defined $self->{_state};

	# Retrieve current active selection geometry coordinates and bounds map
	my $s = $self->{_state}->{sel};

	if (defined $s) {
		# Temporarily detach interactive widget event signals listeners channels
		# This prevents circular recursive updates loops while modifying values via code
		$self->{_x_spin_w}->signal_handler_block($self->{_x_spin_w_handler})           if defined $self->{_x_spin_w_handler};
		$self->{_y_spin_w}->signal_handler_block($self->{_y_spin_w_handler})           if defined $self->{_y_spin_w_handler};
		$self->{_width_spin_w}->signal_handler_block($self->{_width_spin_w_handler})   if defined $self->{_width_spin_w_handler};
		$self->{_height_spin_w}->signal_handler_block($self->{_height_spin_w_handler}) if defined $self->{_height_spin_w_handler};

		# 1. Update X coordinate positioning input and recalculate maximum slide range
		$self->{_x_spin_w}->set_value(int($s->{x})) if defined $self->{_x_spin_w};
		$self->{_x_spin_w}->set_range(0, int($self->{_root}->{w} - $s->{width})) if defined $self->{_x_spin_w};

		# 2. Update Y coordinate positioning input and recalculate maximum slide range
		$self->{_y_spin_w}->set_value(int($s->{y})) if defined $self->{_y_spin_w};
		$self->{_y_spin_w}->set_range(0, int($self->{_root}->{h} - $s->{height})) if defined $self->{_y_spin_w};

		# 3. Update width dimension input and constrain range to remaining space on the right
		$self->{_width_spin_w}->set_value(int($s->{width})) if defined $self->{_width_spin_w};
		$self->{_width_spin_w}->set_range(0, int($self->{_root}->{w} - $s->{x})) if defined $self->{_width_spin_w};

		# 4. Update height dimension input and constrain range to remaining space underneath
		$self->{_height_spin_w}->set_value(int($s->{height})) if defined $self->{_height_spin_w};
		$self->{_height_spin_w}->set_range(0, int($self->{_root}->{h} - $s->{y})) if defined $self->{_height_spin_w};

		# Re-attach the numerical spin entries alert listeners to unlock user input processing
		$self->{_x_spin_w}->signal_handler_unblock($self->{_x_spin_w_handler}) if defined $self->{_x_spin_w_handler};
		$self->{_y_spin_w}->signal_handler_unblock($self->{_y_spin_w_handler}) if defined $self->{_y_spin_w_handler};
		$self->{_width_spin_w}->signal_handler_unblock($self->{_width_spin_w_handler}) if defined $self->{_width_spin_w_handler};
		$self->{_height_spin_w}->signal_handler_unblock($self->{_height_spin_w_handler}) if defined $self->{_height_spin_w_handler};
	}
}


# =========================================================================
# CONTROL DIALOG CONFIGURATOR (Builds the inline floating numeric input overlay)
# =========================================================================
sub select_dialog {
	my $self = shift;

	# Retrieve the standard translation module handle for Shutter
	my $d = $self->{_sc}->get_gettext;

	# Check the active state context safely
	my $state = $self->{_state};
	my $s = defined $state ? $state->{sel} : undef;

	# Initialize geometry default buffers
	my $sx = 0; my $sy = 0;
	my $sw = 0; my $sh = 0;

	# Populate initialization dimensions if a marquee selection area is predefined
	if (defined $s) {
		$sx = $s->{x};     $sy = $s->{y};
		$sw = $s->{width}; $sh = $s->{height};
	}

	# Centralized entry callback triggered upon any spin button modifications
	my $value_callback;
	$value_callback = sub {
		if (defined $self->{_state}) {
			# 1. Read out currently requested integer values from the inputs
			my $current_x = int($self->{_x_spin_w}->get_value);
			my $current_y = int($self->{_y_spin_w}->get_value);
			my $current_w = int($self->{_width_spin_w}->get_value);
			my $current_h = int($self->{_height_spin_w}->get_value);

			# 2. Block recursion safely by temporarily turning off signal listeners
			$self->{_x_spin_w}->signal_handler_block($self->{_x_spin_w_handler});
			$self->{_y_spin_w}->signal_handler_block($self->{_y_spin_w_handler});
			$self->{_width_spin_w}->signal_handler_block($self->{_width_spin_w_handler});
			$self->{_height_spin_w}->signal_handler_block($self->{_height_spin_w_handler});

			# 3. Mathematically adjust maximum thresholds dynamically (Clamping)
			my $max_w = $self->{_root}->{w} - $current_x;
			my $max_h = $self->{_root}->{h} - $current_y;
			my $max_x = $self->{_root}->{w} - $current_w;
			my $max_y = $self->{_root}->{h} - $current_h;

			# 4. Enforce new ranges on the spin buttons on-the-fly
			$self->{_x_spin_w}->set_range(0, $max_x > 0 ? $max_x : 0);
			$self->{_y_spin_w}->set_range(0, $max_y > 0 ? $max_y : 0);
			$self->{_width_spin_w}->set_range(0, $max_w > 0 ? $max_w : 0);
			$self->{_height_spin_w}->set_range(0, $max_h > 0 ? $max_h : 0);

			# 5. Restore safe boundary configurations back inside internal state tracker
			$self->{_state}->{sel} = {
				x      => int($self->{_x_spin_w}->get_value),
				y      => int($self->{_y_spin_w}->get_value),
				width  => int($self->{_width_spin_w}->get_value),
				height => int($self->{_height_spin_w}->get_value),
			};

			# 6. Reactivate signal listeners to catch next modifications
			$self->{_x_spin_w}->signal_handler_unblock($self->{_x_spin_w_handler});
			$self->{_y_spin_w}->signal_handler_unblock($self->{_y_spin_w_handler});
			$self->{_width_spin_w}->signal_handler_unblock($self->{_width_spin_w_handler});
			$self->{_height_spin_w}->signal_handler_unblock($self->{_height_spin_w_handler});

			# Instantly enforce redraw operations across workspace components
			$self->{_canvas}->queue_draw    if defined $self->{_canvas};
			$self->{_zoom_area}->queue_draw if defined $self->{_zoom_area};
		}
	};

	# 1. Coordinate configuration inputs setup: X parameter row
	my $xw_label = Gtk3::Label->new($d->get("X") . ":");
	# Initialize with a safe dynamic ceiling right away
	my $init_max_x = $self->{_root}->{w} - $sw;
	$self->{_x_spin_w} = Gtk3::SpinButton->new_with_range(0, $init_max_x > 0 ? $init_max_x : $self->{_root}->{w}, 1);
	$self->{_x_spin_w}->set_value($sx);
	$self->{_x_spin_w_handler} = $self->{_x_spin_w}->signal_connect('value-changed' => $value_callback);

	my $xw_hbox = Gtk3::HBox->new(FALSE, 5);
	$xw_hbox->pack_start($xw_label,          FALSE, FALSE, 5);
	$xw_hbox->pack_start($self->{_x_spin_w}, FALSE, FALSE, 5);

	# 2. Coordinate configuration inputs setup: Y parameter row
	my $yw_label = Gtk3::Label->new($d->get("Y") . ":");
	my $init_max_y = $self->{_root}->{h} - $sh;
	$self->{_y_spin_w} = Gtk3::SpinButton->new_with_range(0, $init_max_y > 0 ? $init_max_y : $self->{_root}->{h}, 1);
	$self->{_y_spin_w}->set_value($sy);
	$self->{_y_spin_w_handler} = $self->{_y_spin_w}->signal_connect('value-changed' => $value_callback);

	my $yw_hbox = Gtk3::HBox->new(FALSE, 5);
	$yw_hbox->pack_start($yw_label,          FALSE, FALSE, 5);
	$yw_hbox->pack_start($self->{_y_spin_w}, FALSE, FALSE, 5);

	# 3. Coordinate configuration inputs setup: Width parameter row
	my $widthw_label = Gtk3::Label->new($d->get("Width") . ":");
	my $init_max_w = $self->{_root}->{w} - $sx;
	$self->{_width_spin_w} = Gtk3::SpinButton->new_with_range(0, $init_max_w > 0 ? $init_max_w : $self->{_root}->{w}, 1);
	$self->{_width_spin_w}->set_value($sw);
	$self->{_width_spin_w_handler} = $self->{_width_spin_w}->signal_connect('value-changed' => $value_callback);

	my $ww_hbox = Gtk3::HBox->new(FALSE, 5);
	$ww_hbox->pack_start($widthw_label,          FALSE, FALSE, 5);
	$ww_hbox->pack_start($self->{_width_spin_w}, FALSE, FALSE, 5);

	# 4. Coordinate configuration inputs setup: Height parameter row
	my $heightw_label = Gtk3::Label->new($d->get("Height") . ":");
	my $init_max_h = $self->{_root}->{h} - $sy;
	$self->{_height_spin_w} = Gtk3::SpinButton->new_with_range(0, $init_max_h > 0 ? $init_max_h : $self->{_root}->{h}, 1);
	$self->{_height_spin_w}->set_value($sh);
	$self->{_height_spin_w_handler} = $self->{_height_spin_w}->signal_connect('value-changed' => $value_callback);

	my $hw_hbox = Gtk3::HBox->new(FALSE, 5);
	$hw_hbox->pack_start($heightw_label,          FALSE, FALSE, 5);
	$hw_hbox->pack_start($self->{_height_spin_w}, FALSE, FALSE, 5);

	# Construct an EventBox as the core parent layer container to receive background styles safely
	my $prop_dialog = Gtk3::EventBox->new();
	$prop_dialog->set_size_request(180, 160); # Lock panel viewport dimensions to a fixed size bounding box
	$prop_dialog->override_background_color('normal', Gtk3::Gdk::RGBA->new(0.9, 0.9, 0.9, 1.0));
	$prop_dialog->set_focus_on_click(TRUE);

	# Initialize panel close/dismiss interface control
	my $hide_btn = Gtk3::Button->new_with_mnemonic($d->get("_Hide"));
	$hide_btn->set_image(Gtk3::Image->new_from_stock('gtk-close', 'button'));
	$hide_btn->set_can_default(TRUE);
	$hide_btn->signal_connect(
		'clicked' => sub {
			$prop_dialog->hide;
			$self->{_prop_active} = 0; # Set to integer 0 for full code state synchronization
		});

	# Equalize label text layouts settings fields alignments
	$xw_label->set_xalign(0);     $xw_label->set_yalign(0.5);
	$yw_label->set_xalign(0);     $yw_label->set_yalign(0.5);
	$widthw_label->set_xalign(0);  $widthw_label->set_yalign(0.5);
	$heightw_label->set_xalign(0); $heightw_label->set_yalign(0.5);

	# Group label widgets horizontally to align the starting inputs borders symmetrically
	my $sg_main = Gtk3::SizeGroup->new('horizontal');
	$sg_main->add_widget($xw_label);     $sg_main->add_widget($yw_label);
	$sg_main->add_widget($widthw_label); $sg_main->add_widget($heightw_label);

	# Construct structural packaging containers layout tree
	my $vbox = Gtk3::VBox->new(FALSE, 5);
	$vbox->pack_start($xw_hbox,  FALSE, FALSE, 3); $vbox->pack_start($yw_hbox,  FALSE, FALSE, 3);
	$vbox->pack_start($ww_hbox,  FALSE, FALSE, 3); $vbox->pack_start($hw_hbox,  FALSE, FALSE, 3);
	$vbox->pack_start($hide_btn, FALSE, FALSE, 3);

	# Embed layouts into an elegant localized layout frame element
	my $frame_label = Gtk3::Label->new;
	$frame_label->set_markup("<b>" . $d->get("Selection") . "</b>");

	my $frame = Gtk3::Frame->new();
	$frame->set_border_width(5);
	$frame->set_label_widget($frame_label);
	$frame->set_shadow_type('none');

	$frame->add($vbox);
	$prop_dialog->add($frame);

	return $prop_dialog;
}


# =========================================================================
# CAPTURE PIPELINE EVALUATOR (Extracts and processes the final cropped image)
# =========================================================================
sub take_screenshot {
	my $self         = shift;
	my $s            = shift; # Selection geometric coordinates map
	my $clean_pixbuf = shift; # Raw full screen desktop capture cache

	my $d = $self->{_sc}->get_gettext;
	my $output;

	# Scenario A: Immediate capture (No delay) -> crop the cached memory pixbuf
	if ($s && $clean_pixbuf && $self->{_delay} == 0) {
		$output = $clean_pixbuf->new_subpixbuf($s->{x}, $s->{y}, $s->{width}, $s->{height});

		# Layer the hardware mouse pointer cursor into the cropped region if requested
		if ($self->{_include_cursor}) {
			$output = $self->include_cursor($s->{x}, $s->{y}, $s->{width}, $s->{height}, $self->{_root}, $output);
		}

	# Scenario B: Delayed capture -> wait for timeout and fetch a fresh root drawable buffer
	} elsif ($s && $self->{_delay} != 0) {
		($output) = $self->get_pixbuf_from_drawable($self->{_root}, $s->{x}, $s->{y}, $s->{width}, $s->{height});

	# Scenario C: Aborted or invalid layout state parameters
	} else {
		$output = 0;
	}

	# Set localized human-readable component name descriptor fallback metadata
	if ($output =~ /Gtk3/) {
		$self->{_action_name} = $d->get("Selection");
	}

	# Push selection geometries snapshots states into Shutter's history tracking system
	if ($s) {
		$self->{_history} = Shutter::Screenshot::History->new(
			$self->{_sc}, $self->{_root}, $s->{x}, $s->{y}, $s->{width}, $s->{height}
		);
	}

	return $output; # Returns the ready-to-save Gtk3::Gdk::Pixbuf object
}


# =========================================================================
# HISTORY REPLAY INTERFACE (Re-runs the exact last coordinate capture clip)
# =========================================================================
sub redo_capture {
	my $self   = shift;
	my $output = 3; # Default error signal bit handler fallback
	
	# If a historical coordinates footprint map object is available
	if (defined $self->{_history}) {
		# Query a fresh drawable capture segment matching the exact cached boundary bounds
		($output) = $self->get_pixbuf_from_drawable($self->{_history}->get_last_capture);
	}
	return $output;
}

# =========================================================================
# GETTER ACCESS PIPELINES (Read-only metadata endpoints)
# =========================================================================
sub get_history {
	my $self = shift;
	return $self->{_history}; # Returns Shutter's active History tracking module instance
}

sub get_error_text {
	my $self = shift;
	# Safely returns the logged exception buffer string or an empty string for graceful escapes
	return $self->{_error_text} // "";
}

sub get_action_name {
	my $self = shift;
	return $self->{_action_name}; # Returns active localized user activity name tag
}

# =========================================================================
# DESTRUCTOR CLOSURE PIPELINES (Gracefully tears down server grabs and windows)
# =========================================================================
sub quit {
	my $self = shift;

	# Safely lift active input target lockups constraints on server device layers
	eval { $self->ungrab_pointer_and_keyboard(FALSE, FALSE, TRUE); };
	
	# Execute absolute memory purge routine
	$self->clean;
}


# =========================================================================
# MEMORY CLEANUP & DEALLOCATION ROUTINE (Prevents memory leaks in GTK3)
# =========================================================================
sub clean {
	my $self = shift;

	# 1. Safely disconnect active event handlers from the primary drawing canvas
	if (defined $self->{_canvas}) {
		if (defined $self->{_selector_handler} && $self->{_selector_handler} > 0) {
			eval { $self->{_canvas}->signal_handler_disconnect($self->{_selector_handler}); };
			$self->{_selector_handler} = undef;
		}

		if (defined $self->{_view_event_handler} && $self->{_view_event_handler} > 0) {
			eval { $self->{_canvas}->signal_handler_disconnect($self->{_view_event_handler}); };
			$self->{_view_event_handler} = undef;
		}

		if (defined $self->{_view_button_handler} && $self->{_view_button_handler} > 0) {
			eval { $self->{_canvas}->signal_handler_disconnect($self->{_view_button_handler}); };
			$self->{_view_button_handler} = undef;
		}

		if (defined $self->{_view_release_handler} && $self->{_view_release_handler} > 0) {
			eval { $self->{_canvas}->signal_handler_disconnect($self->{_view_release_handler}); };
			$self->{_view_release_handler} = undef;
		}
	}

	# 2. Disconnect render loop handler from the magnifier zoom area
	if (defined $self->{_zoom_area} && defined $self->{_view_zoom_handler} && $self->{_view_zoom_handler} > 0) {
		eval { $self->{_zoom_area}->signal_handler_disconnect($self->{_view_zoom_handler}); };
		$self->{_view_zoom_handler} = undef;
	}

	# 3. Disconnect global hardware hotkey interceptor from the primary window
	if (defined $self->{_select_window} && defined $self->{_key_handler} && $self->{_key_handler} > 0) {
		eval { $self->{_select_window}->signal_handler_disconnect($self->{_key_handler}); };
		$self->{_key_handler} = undef;
	}

	# 4. Destroy window architectures and drop references for garbage collection
	if (defined $self->{_select_window}) {
		$self->{_select_window}->destroy;
		$self->{_select_window} = undef;
	}

	if (defined $self->{_zoom_window}) {
		$self->{_zoom_window}->destroy;
		$self->{_zoom_window} = undef;
	}

	if (defined $self->{_prop_window}) {
		$self->{_prop_window}->destroy;
		$self->{_prop_window} = undef;
	}

	# 5. Clear remaining underlying widget handles completely
	$self->{_canvas}    = undef;
	$self->{_zoom_area} = undef;
}

1;
