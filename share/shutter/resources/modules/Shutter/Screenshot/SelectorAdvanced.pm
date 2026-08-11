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

	#call constructor of super class (shutter_common, include_cursor, delay, notify_timeout)
	my $self = $class->SUPER::new(shift, shift, shift, shift);

	$self->{_zoom_active} = shift;
	$self->{_hide_time}   = shift;    #a short timeout to give the server a chance to redraw the area that was obscured
	$self->{_show_help}   = shift;    #hide help text?

	#initial selection size
	$self->{_init_x} = shift;
	$self->{_init_y} = shift;
	$self->{_init_w} = shift;
	$self->{_init_h} = shift;
	$self->{_confirmation_necessary} = shift;

	my $scale = 1;
	eval {
		$scale = $self->{_select_window}->get_scale_factor if $self->{_select_window};
	};
	$self->{_dpi_scale} = $scale || 1;

	$self->{_zoom_window} = Gtk3::Window->new('popup');
	$self->{_zoom_window}->set_decorated(0);
	$self->{_zoom_window}->set_keep_above(1);
	$self->{_zoom_window}->set_modal(0);

	$self->{_select_window} = Gtk3::Window->new('popup');
	$self->{_select_window}->set_decorated(0);
	$self->{_select_window}->set_keep_above(1);
	$self->{_select_window}->set_modal(1);

	my $zoom_vbox = Gtk3::VBox->new(0, 4);
	$self->{_zoom_window}->add($zoom_vbox);

	my $scwin = Gtk3::ScrolledWindow->new;
	$scwin->set_policy('never', 'never');
	$zoom_vbox->pack_start($scwin, 1, 1, 0);
	
	$self->{_x_label} = Gtk3::Label->new("X: 0");
	$self->{_y_label} = Gtk3::Label->new("Y: 0");
	$self->{_size_label} = Gtk3::Label->new("0 x 0");

	$zoom_vbox->pack_start($self->{_x_label}, 0, 0, 0);
	$zoom_vbox->pack_start($self->{_y_label}, 0, 0, 0);
	$zoom_vbox->pack_start($self->{_size_label}, 0, 0, 0);


	$self->{_zoom_area} = Gtk3::DrawingArea->new;
	$self->{_zoom_area}->set_size_request(100, 100);
	$scwin->add($self->{_zoom_area});

	$self->{_canvas} = Gtk3::DrawingArea->new;

	my $overlay = Gtk3::Overlay->new();
	$overlay->add($self->{_canvas});
	
	$self->{_prop_window} = $self->select_dialog();
	$overlay->add_overlay($self->{_prop_window});
	
	$self->{_prop_window}->set_halign('end');
	$self->{_prop_window}->set_valign('end');
	
	$self->{_prop_window}->set_margin_right(20);
	$self->{_prop_window}->set_margin_bottom(20);
	
	$self->{_prop_window}->hide();
	$self->{_prop_active} = 0;

	$self->{_select_window}->add($overlay);

	$self->{_selector_handler} = $self->{_canvas}->signal_connect(draw => sub {
		my ($widget, $cr) = @_;
		
		if (defined $self->{_screenshot_pixbuf}) {
			Gtk3::Gdk::cairo_set_source_pixbuf($cr, $self->{_screenshot_pixbuf}, 0, 0);
			$cr->paint;
		}

		if (defined $self->{_state} && defined $self->{_state}->{sel}) {
			my $s = $self->{_state}->{sel};
			
			my ($r, $g, $b)  = (0.5, 0.5, 0.5);

			eval {
				my $context = $widget->get_style_context();
				
				$context->save();
				$context->add_class('rubberband');
				
				my $rgba = $context->get_background_color('normal');
				
				if (defined $rgba) {
					$r = $rgba->red;
					$g = $rgba->green;
					$b = $rgba->blue;
				}
				$context->restore();
			};

			$cr->set_source_rgba($r, $g, $b, 1.0); 
			$cr->set_line_width(2.0);
			$cr->rectangle($s->{x}, $s->{y}, $s->{width}, $s->{height});
			$cr->stroke;

			$cr->set_source_rgba($r, $g, $b, 0.15); 
			$cr->rectangle($s->{x}, $s->{y}, $s->{width}, $s->{height});
			$cr->fill;
		}

		return 0;
	});

	return $self;
}


#~ sub DESTROY {
#~ my $self = shift;
#~ print "$self dying at\n";
#~ }

sub select_advanced {
	my $self = shift;

	my $output = 5;
	my $d = $self->{_sc}->get_gettext;

	my $clean_pixbuf = Gtk3::Gdk::pixbuf_get_from_window(
		$self->{_root}, 0, 0, $self->{_root}->{w}, $self->{_root}->{h}
	);

	$self->{_screenshot_pixbuf} = $clean_pixbuf;

	$self->{_state} = {
		pixbuf   => $clean_pixbuf,
		zoom     => 5,
		cursor_x => 0,
		cursor_y => 0,
		sel      => undef,
		dclick   => undef,
	};
	my $state = $self->{_state};


	my ($window_at_pointer, $xinit, $yinit, $mask) = $self->{_root}->get_pointer;
	$state->{cursor_x} = $xinit;
	$state->{cursor_y} = $yinit;

	my $scwin = Gtk3::ScrolledWindow->new();
	$scwin->set_policy('never', 'never');

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


	# zoom preview
	my $xlabel = $self->{_x_label};
	my $ylabel = $self->{_y_label};
	my $rlabel = $self->{_size_label};

	my $zoom_vbox = Gtk3::VBox->new(FALSE, 0);

	$self->{_zoom_window}->set_type_hint('splashscreen');
	$self->{_zoom_window}->set_can_focus(TRUE);
	$self->{_zoom_window}->set_accept_focus(TRUE);
	$self->{_zoom_window}->set_skip_taskbar_hint(TRUE);
	$self->{_zoom_window}->set_skip_pager_hint(TRUE);
	$self->{_zoom_window}->set_keep_above(TRUE);
	$self->{_zoom_window}->move($self->{_root}->{x}, $self->{_root}->{y});

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
	
	if (defined $self->{_prop_window}) {
		$self->{_prop_window}->hide;
		$self->{_prop_active} = 0;
	}

	$self->{_canvas}->set_can_focus(TRUE);
	$self->{_canvas}->add_events([
		qw(
			button-press-mask
			button-release-mask
			pointer-motion-mask
			key-press-mask
			scroll-mask
		)
	]);

	# usage hint
	$self->{_help_label} = undef;

	if (($self->{_init_w} < 1 || $self->{_init_h} < 1) && $self->{_show_help}) {
		my $mon1 = $self->get_current_monitor;
		
		my $text1 = $d->get("Draw a rectangular area using the mouse.");
		my $text2 = $d->get("To take a screenshot, double-click or press the Enter key.\nPress Esc to abort.");
		my $text3 =
			  $d->get("<b>shift/right-click</b> → selection dialog on/off") . "\n"
			. $d->get("<b>scrollwheel</b> → zoom in/out") . "\n"
			. $d->get("<b>space</b> → zoom window on/off") . "\n"
			. $d->get("<b>cursor keys</b> → move cursor") . "\n"
			. $d->get("<b>cursor keys + alt</b> → move selection") . "\n"
			. $d->get("<b>cursor keys + ctrl</b> → resize selection");

		my $help_lbl = Gtk3::Label->new();
		$help_lbl->set_use_markup(TRUE);
		$help_lbl->set_justify('left');
		$help_lbl->set_line_wrap(TRUE);
		$help_lbl->set_max_width_chars(60);
		$help_lbl->set_markup(
			"<span foreground='#FFFFFF' size='xx-large' weight='bold'>$text1</span>\n" .
			"<span foreground='#E0E0E0' size='large'>$text2</span>\n\n" .
			"<span foreground='#CCCCCC' size='medium'>$text3</span>"
		);

		my $help_frame = Gtk3::Frame->new();
		$help_frame->set_shadow_type('none'); # Alten Standard-Rahmen abschalten
		$help_frame->add($help_lbl);

		my $help_box = Gtk3::EventBox->new();
		$help_box->set_visible_window(TRUE); 
		$help_box->add($help_frame);

		my $context = $help_frame->get_style_context();
		$context->add_class('shutter-help-frame');

		my $css_provider = Gtk3::CssProvider->new();
		$css_provider->load_from_data(
			".shutter-help-frame { " .
			"  background-color: rgba(19, 19, 19, 0.85); " .
			"  border-radius: 20px; " .
			"  padding: 30px; " .
			"}"
		);
		$context->add_provider($css_provider, 600);

		my $box_context = $help_box->get_style_context();
		$box_context->add_class('shutter-transparent-box');
		my $box_css = Gtk3::CssProvider->new();
		$box_css->load_from_data(".shutter-transparent-box { background-color: transparent; }");
		$box_context->add_provider($box_css, 600);

		$help_box->set_halign('center');
		$help_box->set_valign('center');

		if (defined $self->{_canvas}) {
			my $overlay_parent = $self->{_canvas}->get_parent();
			if (defined $overlay_parent && $overlay_parent->isa('Gtk3::Overlay')) {
				$overlay_parent->add_overlay($help_box);
			}
		}

		$self->{_help_label} = $help_box;
	}

	$self->{_select_window}->show_all;
	
	$self->{_prop_window}->hide if defined $self->{_prop_window};
	$self->{_prop_active} = 0;

	$self->{_select_window}->present;

	if (defined $self->{_canvas}->get_window()) {
		my $gdk_win = $self->{_canvas}->get_window();
		my $cur = Gtk3::Gdk::Cursor->new_from_name($gdk_win->get_display(), 'crosshair');
		$gdk_win->set_cursor($cur) if defined $cur;
	}

	# helper for redraws
	my $queue_redraw = sub {
		if (defined $self->{_canvas}) {
			$self->{_canvas}->queue_draw;
		}
		if (defined $self->{_zoom_area}) {
			$self->{_zoom_area}->queue_draw;
		}
	};

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

			$cr->save;
			$cr->scale($zoom, $zoom);
			Gtk3::Gdk::cairo_set_source_pixbuf($cr, $crop, 0, 0);
			$cr->paint;
			$cr->restore;

			my $mid_x = int($allocated_w / 2);
			my $mid_y = int($allocated_h / 2);

			if (($zoom % 2) != 0) {
				$mid_x += 0.5;
				$mid_y += 0.5;
			}

			$cr->set_source_rgba(1.0, 0.0, 0.0, 0.8); 
			$cr->set_line_width($zoom); 

			my $half_pixel = $zoom / 2;

			$cr->move_to(0, $mid_y);
			$cr->line_to($mid_x - $half_pixel, $mid_y);
			
			$cr->move_to($mid_x + $half_pixel, $mid_y);
			$cr->line_to($allocated_w, $mid_y);

			$cr->move_to($mid_x, 0);
			$cr->line_to($mid_x, $mid_y - $half_pixel);
			
			$cr->move_to($mid_x, $mid_y + $half_pixel);
			$cr->line_to($mid_x, $allocated_h);

			$cr->stroke;

			return FALSE;
		}
	);

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

		Glib::Timeout->add($self->{_hide_time}, sub {
			Gtk3->main_quit;
			return FALSE;
		});

		Gtk3->main();
		$output = $self->take_screenshot($s, $clean_pixbuf);
		$self->quit;
	};


	# initial help-state
	$self->{_selector_init} = $self->{_show_help} ? TRUE : FALSE;
	$self->{_selector_init_zoom} = 0;

	my $is_dragging     = 0;
	my $is_moving_rect  = 0;
	my $is_resizing     = ''; # directions can be as follows: 'n', 's', 'w', 'e', 'nw', 'ne', 'sw', 'se'
	
	my ($start_x, $start_y) = (0, 0);
	my ($offset_x, $offset_y) = (0, 0);
	
	my $handle_size = 6 * ($self->{_dpi_scale} // 1);

	# helper to get which edge or corner is targeted by the mouse pointer
	my $get_resize_edge = sub {
		my ($mx, $my) = @_;
		my $s = $self->{_state}->{sel};
		return '' unless (defined $s && $s->{width} > 0 && $s->{height} > 0);

		my $x1 = $s->{x};
		my $y1 = $s->{y};
		my $x2 = $s->{x} + $s->{width};
		my $y2 = $s->{y} + $s->{height};

		return '' if ($mx < $x1 - $handle_size || $mx > $x2 + $handle_size ||
		              $my < $y1 - $handle_size || $my > $y2 + $handle_size);

		my $near_n = (abs($my - $y1) <= $handle_size);
		my $near_s = (abs($my - $y2) <= $handle_size);
		my $near_w = (abs($mx - $x1) <= $handle_size);
		my $near_e = (abs($mx - $x2) <= $handle_size);

		return 'nw' if ($near_n && $near_w);
		return 'ne' if ($near_n && $near_e);
		return 'sw' if ($near_s && $near_w);
		return 'se' if ($near_s && $near_e);
		return 'n'  if ($near_n && $mx >= $x1 && $mx <= $x2);
		return 's'  if ($near_s && $mx >= $x1 && $mx <= $x2);
		return 'w'  if ($near_w && $my >= $y1 && $my <= $y2);
		return 'e'  if ($near_e && $my >= $y1 && $my <= $y2);

		return '';
	};

	$self->{_view_button_handler} = $self->{_canvas}->signal_connect('button-press-event' => sub {
		my ($widget, $event) = @_;
		return FALSE unless defined $event;

		if ($event->button == 1) { 
			my $mx = int($event->x);
			my $my = int($event->y);
			my $s = $self->{_state}->{sel};

			my $edge = $get_resize_edge->($mx, $my);

			if ($edge ne '') {
				$is_resizing = $edge;
				$start_x = $mx;
				$start_y = $my;
			} elsif (defined $s && $s->{width} > 0 && $s->{height} > 0 &&
				$mx >= $s->{x} && $mx <= ($s->{x} + $s->{width}) &&
				$my >= $s->{y} && $my <= ($s->{y} + $s->{height})) {
				
				$is_moving_rect = 1;
				$offset_x = $mx - $s->{x};
				$offset_y = $my - $s->{y};
			} else {
				$is_dragging = 1;
				$start_x = $mx;
				$start_y = $my;

				if (defined $self->{_help_label}) {
					$self->{_help_label}->hide;
				}

				$self->{_state}->{sel} = { x => $start_x, y => $start_y, width => 0, height => 0 };
			}
			$queue_redraw->();
		}
		return TRUE;
	});

	$self->{_view_event_handler} = $self->{_canvas}->signal_connect('motion-notify-event' => sub {
		my ($widget, $event) = @_;
		return FALSE unless defined $event;

		my $mx = int($event->x);
		my $my = int($event->y);

		$self->{_state}->{cursor_x} = $mx;
		$self->{_state}->{cursor_y} = $my;
		$set_cursor_text->($mx, $my) if defined $set_cursor_text;

		if (defined $self->{_zoom_window} && $self->{_zoom_window}->get_visible && $self->can('zoom_check_pos')) {
			$self->zoom_check_pos();
		}

		if (defined $widget->get_window()) {
			my $gdk_window = $widget->get_window();
			my $display    = $gdk_window->get_display();
			my $s = $self->{_state}->{sel};
			
			my $cursor_type = 'crosshair';

			my $active_edge = $is_resizing ne '' ? $is_resizing : $get_resize_edge->($mx, $my);

			if ($active_edge ne '') {
				my %cursors = (
					n  => 'n-resize',  s  => 's-resize',  w  => 'w-resize',  e  => 'e-resize',
					nw => 'nw-resize', ne => 'ne-resize', sw => 'sw-resize', se => 'se-resize'
				);
				$cursor_type = $cursors{$active_edge};
			} elsif ($is_moving_rect) {
				$cursor_type = 'grabbing';
			} elsif (defined $s && $s->{width} > 0 && $s->{height} > 0) {
				if ($mx >= $s->{x} && $mx <= ($s->{x} + $s->{width}) &&
					$my >= $s->{y} && $my <= ($s->{y} + $s->{height})) {
					$cursor_type = 'grab';
				}
			}

			my $new_cursor = Gtk3::Gdk::Cursor->new_from_name($display, $cursor_type);
			$gdk_window->set_cursor($new_cursor) if defined $new_cursor;
		}

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
				my $new_x = $mx - $offset_x;
				my $new_y = $my - $offset_y;

				$new_x = 0 if $new_x < 0;
				$new_y = 0 if $new_y < 0;
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

				$s->{x} = $x1;
				$s->{y} = $y1;
				$s->{width}  = $x2 - $x1;
				$s->{height} = $y2 - $y1;
				$update_size_text->() if defined $update_size_text;
			}
		}

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

	$self->{_view_release_handler} = $self->{_canvas}->signal_connect('button-release-event' => sub {
		my ($widget, $event) = @_;
		return FALSE unless defined $event;
		if ($event->button == 3) {
			if (defined $self->{_prop_window}) {
				if ($self->{_prop_active}) {
					$self->{_prop_window}->hide;
					$self->{_prop_active} = 0;
				} else {
					my $mx = int($event->x);
					my $my = int($event->y);

					if (defined $self->{_state} && defined $self->{_state}->{sel}) {
						my $s = $self->{_state}->{sel};
						$self->{_x_spin_w}->set_value(int($s->{x}))      if defined $self->{_x_spin_w};
						$self->{_y_spin_w}->set_value(int($s->{y}))      if defined $self->{_y_spin_w};
						$self->{_width_spin_w}->set_value(int($s->{width}))   if defined $self->{_width_spin_w};
						$self->{_height_spin_w}->set_value(int($s->{height})) if defined $self->{_height_spin_w};
					} else {
						$self->{_x_spin_w}->set_value($mx) if defined $self->{_x_spin_w};
						$self->{_y_spin_w}->set_value($my) if defined $self->{_y_spin_w};
						$self->{_width_spin_w}->set_value(0)  if defined $self->{_width_spin_w};
						$self->{_height_spin_w}->set_value(0) if defined $self->{_height_spin_w};
					}
					
					$self->{_prop_window}->show_all;
					$self->{_prop_active} = 1;
					
					if (defined $self->{_x_spin_w}) {
						$self->{_x_spin_w}->grab_focus;
					}
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



	# --- keyboard ---
	$self->{_key_handler} = $self->{_select_window}->signal_connect('key-press-event' => sub {
		my ($window, $event) = @_;
		return FALSE unless defined $event;

		my $state = $self->{_state};
		my $s = $state->{sel};
		my ($window_at_pointer, $x, $y, $mask) = $self->{_root}->get_pointer;

		my $keyname = Gtk3::Gdk::keyval_name($event->keyval);

		if ($keyname eq 'Shift_L' || $keyname eq 'Shift_R') {
			if (defined $self->{_prop_window}) {
				if ($self->{_prop_active}) {
					$self->{_prop_window}->hide;
					$self->{_prop_active} = 0;
				} else {
					if (defined $s) {
						$self->{_x_spin_w}->set_value(int($s->{x}))      if defined $self->{_x_spin_w};
						$self->{_y_spin_w}->set_value(int($s->{y}))      if defined $self->{_y_spin_w};
						$self->{_width_spin_w}->set_value(int($s->{width}))   if defined $self->{_width_spin_w};
						$self->{_height_spin_w}->set_value(int($s->{height})) if defined $self->{_height_spin_w};
					}
					$self->{_prop_window}->show_all;
					$self->{_prop_active} = 1;
					
					if (defined $self->{_x_spin_w}) {
						$self->{_x_spin_w}->grab_focus;
					}
				}
				$queue_redraw->() if defined $queue_redraw;
				return TRUE;
			}
		}

		my $has_ctrl = $event->state & 'control-mask';
		my $has_alt  = $event->state & 'mod1-mask';

		my $kv_space    = Gtk3::Gdk::keyval_from_name('space');
		my $kv_escape   = Gtk3::Gdk::keyval_from_name('Escape');
		my $kv_up       = Gtk3::Gdk::keyval_from_name('Up');
		my $kv_down     = Gtk3::Gdk::keyval_from_name('Down');
		my $kv_left     = Gtk3::Gdk::keyval_from_name('Left');
		my $kv_right    = Gtk3::Gdk::keyval_from_name('Right');
		my $kv_add      = Gtk3::Gdk::keyval_from_name('KP_Add');
		my $kv_plus     = Gtk3::Gdk::keyval_from_name('plus');
		my $kv_equal    = Gtk3::Gdk::keyval_from_name('equal');
		my $kv_sub      = Gtk3::Gdk::keyval_from_name('KP_Subtract');
		my $kv_minus    = Gtk3::Gdk::keyval_from_name('minus');
		my $kv_zero     = Gtk3::Gdk::keyval_from_name('0');
		my $kv_return   = Gtk3::Gdk::keyval_from_name('Return');
		my $kv_kp_enter = Gtk3::Gdk::keyval_from_name('KP_Enter');

		if ($event->keyval == $kv_space) {
			if (defined $self->{_zoom_window} && $self->{_zoom_window}->get_visible) {
				$self->{_zoom_window}->hide;
				$self->{_zoom_active} = FALSE;
			} else {
				$self->{_zoom_active} = TRUE;
				$self->zoom_check_pos() if $self->can('zoom_check_pos');
				$self->{_zoom_window}->show_all if defined $self->{_zoom_window};
			}
			$queue_redraw->() if defined $queue_redraw;
			return TRUE;

		} elsif ($event->keyval == $kv_escape) {
			$self->quit;

		} elsif ($event->keyval == $kv_up) {
			if ($has_ctrl && $s) {
				$s->{height} -= 1;
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->{width} + $s->{x}, $s->{height} + $s->{y});
			} elsif ($has_alt && $s) {
				$s->{y} -= 1;
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->{x}, $s->{y});
			} else {
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x, $y - 1);
			}

		} elsif ($event->keyval == $kv_down) {
			if ($has_ctrl && $s) {
				$s->{height} += 1;
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->{width} + $s->{x}, $s->{height} + $s->{y});
			} elsif ($has_ctrl) {
				$state->{sel} = { x => $x, y => $y, width => 1, height => 2 };
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x + 1, $y + 2);
			} elsif ($has_alt && $s) {
				$s->{y} += 1;
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->{x}, $s->{y});
			} else {
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x, $y + 1);
			}

		} elsif ($event->keyval == $kv_left) {
			if ($has_ctrl && $s) {
				$s->{width} -= 1;
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->{width} + $s->{x}, $s->{height} + $s->{y});
			} elsif ($has_alt && $s) {
				$s->{x} -= 1;
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->{x}, $s->{y});
			} else {
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x - 1, $y);
			}

		} elsif ($event->keyval == $kv_right) {
			if ($has_ctrl && $s) {
				$s->{width} += 1;
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->{width} + $s->{x}, $s->{height} + $s->{y});
			} elsif ($has_ctrl) {
				$state->{sel} = { x => $x, y => $y, width => 2, height => 1 };
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x + 2, $y + 1);
			} elsif ($has_alt && $s) {
				$s->{x} += 1;
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $s->{x}, $s->{y});
			} else {
				$self->{_gdk_display}->warp_pointer($self->{_gdk_screen}, $x + 1, $y);
			}

		} elsif ($event->keyval == $kv_add || $event->keyval == $kv_plus || $event->keyval == $kv_equal) {
			$state->{zoom}++ if $has_ctrl;

		} elsif ($event->keyval == $kv_sub || $event->keyval == $kv_minus) {
			$state->{zoom}-- if $has_ctrl;
			$state->{zoom} = 1 if $state->{zoom} < 1;

		} elsif ($event->keyval == $kv_zero) {
			$state->{zoom} = 1 if $has_ctrl;

		} elsif ($event->keyval == $kv_return || $event->keyval == $kv_kp_enter) {
			if (defined $s) {
				$finish_capture->();
			}
		}

		$queue_redraw->() if defined $queue_redraw;
		return TRUE;
	});


	# initial selection
	Glib::Idle->add(sub {
		if ($self->{_init_w} && $self->{_init_h}) {
			$state->{sel} = {
				x => $self->{_init_x},
				y => $self->{_init_y},
				width => $self->{_init_w},
				height => $self->{_init_h},
			};
			$queue_redraw->();
		}
		return FALSE;
	});

	# grab keyboard
	my $status = Gtk3::Gdk::keyboard_grab($self->{_select_window}->get_window, 0, Gtk3::get_current_event_time());

	if ($self->{_zoom_active}) {
		$self->{_zoom_window}->show_all;
		$self->{_zoom_window}->get_window->set_override_redirect(TRUE);
		$self->zoom_check_pos();
		$self->{_zoom_window}->get_window->raise;
	}

	Gtk3->main();
	return $output;
}


sub zoom_check_pos {
	my $self = shift;

	return FALSE unless defined $self->{_zoom_window};
	return FALSE unless $self->{_zoom_window}->get_visible;

	my ($window_at_pointer, $ev_x, $ev_y, $mask) = $self->{_root}->get_pointer;

	my ($zw, $zh) = $self->{_zoom_window}->get_size;
	my ($zx, $zy) = $self->{_zoom_window}->get_position;

	my $distance = 50 * ($self->{_dpi_scale} // 1);
	
	my $box_x1 = $zx - $distance;
	my $box_y1 = $zy - $distance;
	my $box_x2 = $zx + $zw + $distance;
	my $box_y2 = $zy + $zh + $distance;

	if ($ev_x >= $box_x1 && $ev_x <= $box_x2 && $ev_y >= $box_y1 && $ev_y <= $box_y2) {
		
		my @pos = (
			{x => $self->{_root}->{x},       y => $self->{_root}->{y}},       # 1. Oben links
			{x => $self->{_root}->{x},       y => $self->{_root}->{h} - $zh}, # 2. Unten links
			{x => $self->{_root}->{w} - $zw, y => $self->{_root}->{h} - $zh}, # 3. Unten rechts
			{x => $self->{_root}->{w} - $zw, y => $self->{_root}->{y}},       # 4. Oben rechts
		);

		foreach my $p (@pos) {
			my $p_box_x1 = $p->{x} - $distance;
			my $p_box_y1 = $p->{y} - $distance;
			my $p_box_x2 = $p->{x} + $zw + $distance;
			my $p_box_y2 = $p->{y} + $zh + $distance;

			if (!($ev_x >= $p_box_x1 && $ev_x <= $p_box_x2 && $ev_y >= $p_box_y1 && $ev_y <= $p_box_y2)) {
				$self->{_zoom_window}->move($p->{x}, $p->{y});
				$self->{_zoom_window}->queue_draw;
				return TRUE;
			}
		}
	}

	return TRUE;
}


sub adjust_prop_values {
	my $self = shift;

	return unless defined $self->{_state};

	my $s = $self->{_state}->{sel};

	if (defined $s) {
		$self->{_x_spin_w}->signal_handler_block($self->{_x_spin_w_handler})           if defined $self->{_x_spin_w_handler};
		$self->{_y_spin_w}->signal_handler_block($self->{_y_spin_w_handler})           if defined $self->{_y_spin_w_handler};
		$self->{_width_spin_w}->signal_handler_block($self->{_width_spin_w_handler})   if defined $self->{_width_spin_w_handler};
		$self->{_height_spin_w}->signal_handler_block($self->{_height_spin_w_handler}) if defined $self->{_height_spin_w_handler};

		$self->{_x_spin_w}->set_value(int($s->{x})) if defined $self->{_x_spin_w};
		$self->{_x_spin_w}->set_range(0, int($self->{_root}->{w} - $s->{width})) if defined $self->{_x_spin_w};

		$self->{_y_spin_w}->set_value(int($s->{y})) if defined $self->{_y_spin_w};
		$self->{_y_spin_w}->set_range(0, int($self->{_root}->{h} - $s->{height})) if defined $self->{_y_spin_w};

		$self->{_width_spin_w}->set_value(int($s->{width})) if defined $self->{_width_spin_w};
		$self->{_width_spin_w}->set_range(0, int($self->{_root}->{w} - $s->{x})) if defined $self->{_width_spin_w};

		$self->{_height_spin_w}->set_value(int($s->{height})) if defined $self->{_height_spin_w};
		$self->{_height_spin_w}->set_range(0, int($self->{_root}->{h} - $s->{y})) if defined $self->{_height_spin_w};

		$self->{_x_spin_w}->signal_handler_unblock($self->{_x_spin_w_handler})           if defined $self->{_x_spin_w_handler};
		$self->{_y_spin_w}->signal_handler_unblock($self->{_y_spin_w_handler})           if defined $self->{_y_spin_w_handler};
		$self->{_width_spin_w}->signal_handler_unblock($self->{_width_spin_w_handler})   if defined $self->{_width_spin_w_handler};
		$self->{_height_spin_w}->signal_handler_unblock($self->{_height_spin_w_handler}) if defined $self->{_height_spin_w_handler};
	}
}


sub select_dialog {
	my $self = shift;

	my $d = $self->{_sc}->get_gettext;

	my $state = $self->{_state};
	my $s = defined $state ? $state->{sel} : undef;

	my $sx = 0;
	my $sy = 0;
	my $sw = 0;
	my $sh = 0;

	if (defined $s) {
		$sx = $s->{x};
		$sy = $s->{y};
		$sw = $s->{width};
		$sh = $s->{height};
	}

	my $value_callback = sub {
		if (defined $self->{_state}) {
			$self->{_state}->{sel} = {
				x      => int($self->{_x_spin_w}->get_value),
				y      => int($self->{_y_spin_w}->get_value),
				width  => int($self->{_width_spin_w}->get_value),
				height => int($self->{_height_spin_w}->get_value),
			};
			$self->{_canvas}->queue_draw if defined $self->{_canvas};
			$self->{_zoom_area}->queue_draw if defined $self->{_zoom_area};
		}
	};

	# x coordinate
	my $xw_label = Gtk3::Label->new($d->get("X") . ":");
	$self->{_x_spin_w} = Gtk3::SpinButton->new_with_range(0, $self->{_root}->{w}, 1);
	$self->{_x_spin_w}->set_value($sx);
	$self->{_x_spin_w_handler} = $self->{_x_spin_w}->signal_connect(
		'value-changed' => $value_callback);

	my $xw_hbox = Gtk3::HBox->new(FALSE, 5);
	$xw_hbox->pack_start($xw_label,          FALSE, FALSE, 5);
	$xw_hbox->pack_start($self->{_x_spin_w}, FALSE, FALSE, 5);

	# y coordinate
	my $yw_label = Gtk3::Label->new($d->get("Y") . ":");
	$self->{_y_spin_w} = Gtk3::SpinButton->new_with_range(0, $self->{_root}->{h}, 1);
	$self->{_y_spin_w}->set_value($sy);
	$self->{_y_spin_w_handler} = $self->{_y_spin_w}->signal_connect(
		'value-changed' => $value_callback);

	my $yw_hbox = Gtk3::HBox->new(FALSE, 5);
	$yw_hbox->pack_start($yw_label,          FALSE, FALSE, 5);
	$yw_hbox->pack_start($self->{_y_spin_w}, FALSE, FALSE, 5);

	# width
	my $widthw_label = Gtk3::Label->new($d->get("Width") . ":");
	$self->{_width_spin_w} = Gtk3::SpinButton->new_with_range(0, $self->{_root}->{w}, 1);
	$self->{_width_spin_w}->set_value($sw);
	$self->{_width_spin_w_handler} = $self->{_width_spin_w}->get_value_as_int; # Hilfswert
	$self->{_width_spin_w_handler} = $self->{_width_spin_w}->signal_connect(
		'value-changed' => $value_callback);

	my $ww_hbox = Gtk3::HBox->new(FALSE, 5);
	$ww_hbox->pack_start($widthw_label,          FALSE, FALSE, 5);
	$ww_hbox->pack_start($self->{_width_spin_w}, FALSE, FALSE, 5);

	# height
	my $heightw_label = Gtk3::Label->new($d->get("Height") . ":");
	$self->{_height_spin_w} = Gtk3::SpinButton->new_with_range(0, $self->{_root}->{h}, 1);
	$self->{_height_spin_w}->set_value($sh);
	$self->{_height_spin_w_handler} = $self->{_height_spin_w}->signal_connect(
		'value-changed' => $value_callback);

	my $hw_hbox = Gtk3::HBox->new(FALSE, 5);
	$hw_hbox->pack_start($heightw_label,          FALSE, FALSE, 5);
	$hw_hbox->pack_start($self->{_height_spin_w}, FALSE, FALSE, 5);

	my $prop_dialog = Gtk3::EventBox->new();

	# fixed size
	$prop_dialog->set_size_request(180, 160);
	
	$prop_dialog->override_background_color('normal', Gtk3::Gdk::RGBA->new(0.9, 0.9, 0.9, 1.0));
	$prop_dialog->set_focus_on_click(TRUE);

	my $hide_btn = Gtk3::Button->new_with_mnemonic($d->get("_Hide"));
	$hide_btn->set_image(Gtk3::Image->new_from_stock('gtk-close', 'button'));
	$hide_btn->set_can_default(TRUE);
	$hide_btn->signal_connect(
		'clicked' => sub {
			$prop_dialog->hide;
			$self->{_prop_active} = FALSE;
		});

	$xw_label->set_xalign(0);     $xw_label->set_yalign(0.5);
	$yw_label->set_xalign(0);     $yw_label->set_yalign(0.5);
	$widthw_label->set_xalign(0);  $widthw_label->set_yalign(0.5);
	$heightw_label->set_xalign(0); $heightw_label->set_yalign(0.5);

	my $sg_main = Gtk3::SizeGroup->new('horizontal');
	$sg_main->add_widget($xw_label);
	$sg_main->add_widget($yw_label);
	$sg_main->add_widget($widthw_label);
	$sg_main->add_widget($heightw_label);

	my $vbox = Gtk3::VBox->new(FALSE, 5);
	$vbox->pack_start($xw_hbox,  FALSE, FALSE, 3);
	$vbox->pack_start($yw_hbox,  FALSE, FALSE, 3);
	$vbox->pack_start($ww_hbox,  FALSE, FALSE, 3);
	$vbox->pack_start($hw_hbox,  FALSE, FALSE, 3);
	$vbox->pack_start($hide_btn, FALSE, FALSE, 3);

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


sub take_screenshot {
	my $self         = shift;
	my $s            = shift;
	my $clean_pixbuf = shift;

	my $d = $self->{_sc}->get_gettext;

	my $output;

	#no delay? then we take a subsection of the pixbuf in memory
	if ($s && $clean_pixbuf && $self->{_delay} == 0) {
		$output = $clean_pixbuf->new_subpixbuf($s->{x}, $s->{y}, $s->{width}, $s->{height});

		#include cursor
		if ($self->{_include_cursor}) {
			$output = $self->include_cursor($s->{x}, $s->{y}, $s->{width}, $s->{height}, $self->{_root}, $output);
		}

		#if there is a delay != 0 set, we have to wait and get a new pixbuf from the root window
	} elsif ($s && $self->{_delay} != 0) {
		($output) = $self->get_pixbuf_from_drawable($self->{_root}, $s->{x}, $s->{y}, $s->{width}, $s->{height});

		#section not valid
	} else {
		$output = 0;
	}

	#we don't have a useful string for wildcards (e.g. $name)
	if ($output =~ /Gtk3/) {
		$self->{_action_name} = $d->get("Selection");
	}

	#set history object
	if ($s) {
		$self->{_history} = Shutter::Screenshot::History->new($self->{_sc}, $self->{_root}, $s->{x}, $s->{y}, $s->{width}, $s->{height});
	}

	return $output;
}

sub redo_capture {
	my $self   = shift;
	my $output = 3;
	if (defined $self->{_history}) {
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

	eval { $self->ungrab_pointer_and_keyboard(FALSE, FALSE, TRUE); };
	$self->clean;
}

sub clean {
	my $self = shift;

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

	if (defined $self->{_zoom_area} && defined $self->{_view_zoom_handler} && $self->{_view_zoom_handler} > 0) {
		eval { $self->{_zoom_area}->signal_handler_disconnect($self->{_view_zoom_handler}); };
		$self->{_view_zoom_handler} = undef;
	}

	if (defined $self->{_select_window} && defined $self->{_key_handler} && $self->{_key_handler} > 0) {
		eval { $self->{_select_window}->signal_handler_disconnect($self->{_key_handler}); };
		$self->{_key_handler} = undef;
	}

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

	$self->{_canvas} = undef;
	$self->{_zoom_area} = undef;
}


1;
