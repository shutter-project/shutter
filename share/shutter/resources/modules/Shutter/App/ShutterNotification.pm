###################################################
#
#  Copyright (C) 2008, 2009, 2010 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package Shutter::App::ShutterNotification;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

#Glib
use Glib qw/TRUE FALSE/; 

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
	
		#~ $self->{_notifications_window}->double_buffered(FALSE);
	    $self->{_notifications_window}->set_app_paintable(TRUE);
	    $self->{_notifications_window}->set_decorated(FALSE);
		$self->{_notifications_window}->set_skip_taskbar_hint(TRUE);
		$self->{_notifications_window}->set_skip_pager_hint(TRUE);	    
	    $self->{_notifications_window}->set_keep_above(TRUE);
	    $self->{_notifications_window}->set_accept_focus(FALSE);
	    #~ $self->{_notifications_window}->set_sensitive(FALSE);		
		$self->{_notifications_window}->add_events('GDK_ENTER_NOTIFY_MASK');
		
		#obtain current colors and font_desc from the main window
	    my $style 		= $self->{_sc}->get_mainwindow->get_style;
		#~ my $sel_bg 		= $style->bg('selected');
		my $sel_bg 		= Gtk2::Gdk::Color->parse('#131313');
		#~ my $sel_tx 		= $style->text('selected');
		my $sel_tx 		= Gtk2::Gdk::Color->parse('white');
		my $font_fam 	= $style->font_desc->get_family;
		my $font_size 	= $style->font_desc->get_size;

		my $mon 	= $self->{_sc}->get_current_monitor;
		my $size 	= int( $mon->width * 0.007 );
		my $size2 	= int( $mon->width * 0.006 );

		#shape the window
		my $pixbuf = Gtk2::Gdk::Pixbuf->new_from_file  ($self->{_sc}->get_root . "/share/shutter/resources/icons/notify.svg");
		my ($pixmap, $mask) = $pixbuf->render_pixmap_and_mask (1);
		$self->{_notifications_window}->shape_combine_mask($mask, 0, 0);
		
		#add a widget to control size of the window
		my $fixed = Gtk2::Fixed->new;
		$fixed->set_size_request(250, 100);
		$self->{_notifications_window}->add($fixed);
		
		#initial position
		$self->{_notifications_window}->move($mon->x + $mon->width - 265, $mon->y + $mon->height - 140);
		$self->{_notifications_window}->{'pos'} = 1;
		
		$self->{_notifications_window}->signal_connect('expose-event' => sub{
			
			return FALSE unless $self->{_notifications_window}->window;
			
			return FALSE unless $self->{_summary};
			
			#window size and position
			my ($w, $h) = $self->{_notifications_window}->get_size;
			my ($x, $y) = $self->{_notifications_window}->get_position;
			
			#create cairo context
			my $cr = Gtk2::Gdk::Cairo::Context->create ($self->{_notifications_window}->window);
	
			#pango layout
			my $layout = Gtk2::Pango::Cairo::create_layout($cr);
			$layout->set_width( ($w - $size * 3) * Gtk2::Pango->scale );
			$layout->set_alignment('left');
			$layout->set_wrap('word');
			
			#set text
			$layout->set_markup("<span font_desc=\"$font_fam $size\" weight=\"bold\" foreground=\"#FFFFFF\">".$self->{_summary}."</span><span font_desc=\"$font_fam $size2\" foreground=\"#FFFFFF\">\n".$self->{_body}."</span>");
			
			#fill window
			$cr->set_operator('source');
			
			if($self->{_sc}->get_mainwindow->get_screen->is_composited){
				
				$cr->set_source_rgba( $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255, 0.9 );
				$cr->paint;
				
			}else{
				
				$cr->set_source_rgb( $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255 );
				$cr->paint;
				
			}

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
			
			#~ $self->close(TRUE);
			if($self->{_notifications_window}->{'pos'} == 1){
				$self->{_notifications_window}->move($mon->x + $mon->width - 265, $mon->y + 40);
				$self->{_notifications_window}->{'pos'} = 0;
			}else{
				$self->{_notifications_window}->move($mon->x + $mon->width - 265, $mon->y + $mon->height - 140);
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
	my $self 			= shift;

	#remove old handler
	if(defined $self->{_notifications_timeout}){
		Glib::Source->remove($self->{_notifications_timeout});
	}
	
	#set body and summary
	$self->{_summary} 	= shift;
	$self->{_body}  	= shift;

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
		$self->{_summary} 	= undef;
		$self->{_body}  	= undef;
	}

	$self->{_notifications_window}->hide_all;
	
	return 0;
}

1;
