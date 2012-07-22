###################################################
#
#  Copyright (C) 2008-2012 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package Shutter::App::ShutterNotification;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

#Glib
use Glib qw/TRUE FALSE/; 

#Gtk2 and Pango
use Gtk2;
use Gtk2::Pango;

#--------------------------------------

sub new {
	my $class = shift;

	my $self = { _sc => shift };

	#Use notifications object
	eval{
		
		#notification window (borderless gtk window)
		$self->{_notifications_window} = Gtk2::Window->new('popup');
		if($self->{_sc}->get_mainwindow->get_screen->is_composited){
			$self->{_notifications_window}->set_colormap($self->{_sc}->get_mainwindow->get_screen->get_rgba_colormap);
		}
	
		$self->{_notifications_window}->set_app_paintable(TRUE);
		$self->{_notifications_window}->set_decorated(FALSE);
		$self->{_notifications_window}->set_skip_taskbar_hint(TRUE);
		$self->{_notifications_window}->set_skip_pager_hint(TRUE);	    
		$self->{_notifications_window}->set_keep_above(TRUE);
		$self->{_notifications_window}->set_accept_focus(FALSE);	
		$self->{_notifications_window}->add_events('GDK_ENTER_NOTIFY_MASK');
		
		#shape the window
		my $pixbuf = Gtk2::Gdk::Pixbuf->new_from_file  ($self->{_sc}->get_root . "/share/shutter/resources/icons/notify.svg");
		#~ my ($pixmap, $mask) = $pixbuf->render_pixmap_and_mask (1);
		#~ $self->{_notifications_window}->shape_combine_mask($mask, 0, 0);
		
		#add a widget to control size of the window
		my $fixed = Gtk2::Fixed->new;
		$fixed->set_size_request(300, 120);
		$self->{_notifications_window}->add($fixed);
				
		$self->{_notifications_window}->signal_connect('expose-event' => sub{
			
			return FALSE unless $self->{_notifications_window}->window;

			return FALSE unless $self->{_summary};

			#current monitor
			my $mon = $self->{_sc}->get_current_monitor;

			#initial position
			unless(defined $self->{_notifications_window}->{'pos'}){
				$self->{_notifications_window}->move($mon->x + $mon->width - 315, $mon->y + $mon->height - 140);
				$self->{_notifications_window}->{'pos'} = 1;
			}

			#window size and position
			my ($w, $h) = $self->{_notifications_window}->get_size;
			my ($x, $y) = $self->{_notifications_window}->get_position;

			#obtain current colors and font_desc from the main window
			my $style 		= $self->{_sc}->get_mainwindow->get_style;
			my $sel_bg 		= Gtk2::Gdk::Color->parse('#131313');
			my $sel_tx 		= Gtk2::Gdk::Color->parse('white');
			my $font_fam 	= $style->font_desc->get_family;
			my $font_size 	= $style->font_desc->get_size / Gtk2::Pango->scale;
				
			#create cairo context
			my $cr = Gtk2::Gdk::Cairo::Context->create ($self->{_notifications_window}->window);

			#pango layout
			my $layout = Gtk2::Pango::Cairo::create_layout($cr);
			$layout->set_width( ($w - 30) * Gtk2::Pango->scale );

			if ( Gtk2::Pango->CHECK_VERSION( 1, 20, 0 ) ) {
				$layout->set_height( ($h - 20) * Gtk2::Pango->scale );
			}else{
				warn "WARNING: \$layout->set_height is not available - outdated Pango version\n";
			}

			if ( Gtk2::Pango->CHECK_VERSION( 1, 6, 0 ) ) {
				$layout->set_ellipsize ('middle');
			}else{
				warn "WARNING: \$layout->set_ellipsize is not available - outdated Pango version\n";
			}

			$layout->set_alignment('left');
			$layout->set_wrap('word-char');

			#set text
			$layout->set_markup("<span font_desc=\"$font_fam $font_size\" weight=\"bold\" foreground=\"#FFFFFF\">" . Glib::Markup::escape_text( $self->{_summary} ) . "</span><span font_desc=\"$font_fam $font_size\" foreground=\"#FFFFFF\">\n" . Glib::Markup::escape_text( $self->{_body} ) . "</span>");

			$cr->set_operator('source');

			if($self->{_sc}->get_mainwindow->get_screen->is_composited){
				$cr->set_source_rgba( 1.0, 1.0, 1.0, 0 );
				Gtk2::Gdk::Cairo::Context::set_source_pixbuf( $cr, $pixbuf, 0, 0 );
				$cr->paint;
			}else{
				$cr->set_source_rgb( $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255 );
				$cr->paint;
			}

			$cr->set_operator('over');

			#get layout size
			my ( $lw, $lh ) = $layout->get_pixel_size;			
			$cr->move_to( ($w - $lw) / 2, ($h - $lh) / 2 );
			Gtk2::Pango::Cairo::show_layout( $cr, $layout );

			return TRUE;
		});	

		$self->{_notifications_window}->signal_connect('enter-notify-event' => sub{

			#remove old handler
			if(defined $self->{_enter_notify_timeout}){
				Glib::Source->remove($self->{_enter_notify_timeout});
			}

			#current monitor
			my $mon = $self->{_sc}->get_current_monitor;

			if(defined $self->{_notifications_window}->{'pos'} && $self->{_notifications_window}->{'pos'} == 1){
				$self->{_notifications_window}->move($mon->x + $mon->width - 315, $mon->y + 40);
				$self->{_notifications_window}->{'pos'} = 0;
			}else{
				$self->{_notifications_window}->move($mon->x + $mon->width - 315, $mon->y + $mon->height - 140);
				$self->{_notifications_window}->{'pos'} = 1;
			}

			$self->{_enter_notify_timeout} = Glib::Timeout->add (100, sub{
				$self->show($self->{_summary}, $self->{_body});
			});

			return FALSE;
		});	

	};
	if($@){
		print "Warning: $@", "\n";	
	}

	#last nid
	$self->{_nid} = 0;

	bless $self, $class;
	return $self;
}

sub show {
	my $self = shift;

	#remove old handler
	if(defined $self->{_notifications_timeout}){
		Glib::Source->remove($self->{_notifications_timeout});
	}

	#set body and summary
	$self->{_summary} 	= shift;
	$self->{_body}		= shift;

	$self->{_notifications_window}->show_all;

	$self->{_notifications_window}->queue_draw;

	$self->{_notifications_timeout} = Glib::Timeout->add (3000, sub{
		$self->close;
	});

	return 0;
}

sub close {
	my $self 		= shift;
	my $no_clear 	= shift;

	#clear body and summary
	unless($no_clear){
		$self->{_summary}	= undef;
		$self->{_body}		= undef;
	}

	$self->{_notifications_window}->hide_all;

	$self->{_notifications_window}->{'pos'} = undef;

	return 0;
}

1;
