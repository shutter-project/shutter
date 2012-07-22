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

package Shutter::Screenshot::Main;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use File::Temp qw/ tempfile tempdir /;

#Glib
use Glib qw/TRUE FALSE/; 

#stringified perl data structures, suitable for both printing and eval
use Data::Dumper;

#--------------------------------------

sub new {
	my $class = shift;
	
	my $self = {
				 _sc  => shift,
				 _include_cursor => shift,
				 _delay          => shift,
				 _notify_timeout => shift,
			   };
			
	#root window
	$self->{ _root } = Gtk2::Gdk->get_default_root_window;
	( $self->{ _root }->{ x }, $self->{ _root }->{ y }, $self->{ _root }->{ w }, $self->{ _root }->{ h } ) = $self->{ _root }->get_geometry;
	( $self->{ _root }->{ x }, $self->{ _root }->{ y } ) = $self->{ _root }->get_origin;
	
	#import modules
	require lib;
	import lib $self->{_sc}->get_root."/share/shutter/resources/modules";

	#shutter region module
	require Shutter::Geometry::Region;

	#wnck screen
	$self->{_wnck_screen} = Gnome2::Wnck::Screen->get_default;
	$self->{_wnck_screen}->force_update();	

	#gdk screen
	$self->{_gdk_screen} = Gtk2::Gdk::Screen->get_default;	

	#gdk display
	$self->{_gdk_display} = $self->{_gdk_screen}->get_display;
	
	#we determine the wm name but on older
	#version of libwnck (or the bindings)
	#the needed method is not available
	#in this case we use gdk to do it
	#
	#this leads to a known problem when switching
	#the wm => wm_name will still remain the old one
	$self->{_wm_manager_name} = $self->{_gdk_screen}->get_window_manager_name;
	if($self->{_wnck_screen}->can('get_window_manager_name')){
		$self->{_wm_manager_name} = $self->{_wnck_screen}->get_window_manager_name;
	}

	#workspaces
	$self->{_workspaces} = ();
	for ( my $wcount = 0 ; $wcount < $self->{_wnck_screen}->get_workspace_count ; $wcount++ )
	{
		push( @{$self->{_workspaces}}, $self->{_wnck_screen}->get_workspace( $wcount ) );
	}	

	bless $self, $class;
	return $self;
}

sub get_clipbox {
	my $self 	= shift;
	my $region 	= shift;

	#create shutter region object
	my $sr = Shutter::Geometry::Region->new();
	
	return $sr->get_clipbox($region);
}	

sub update_workspaces {
	my $self = shift;
	for ( my $wcount = 0 ; $wcount < $self->{_wnck_screen}->get_workspace_count ; $wcount++ )
	{
		push( @{$self->{_workspaces}}, $self->{_wnck_screen}->get_workspace( $wcount ) );
	}
	return $self->{_wnck_screen}->get_workspace_count;		
}

sub get_root_and_geometry {
	my $self = shift;
	return ($self->{_root}, $self->{_root}->{x}, $self->{_root}->{y}, $self->{_root}->{w}, $self->{_root}->{h});
}

sub get_root_and_current_monitor_geometry {
	my $self = shift;
	my $mainwindow = $self->{_sc}->get_mainwindow->window || $self->{_root};
	my $mon1       = $self->{_gdk_screen}
		->get_monitor_geometry( $self->{_gdk_screen}->get_monitor_at_window($mainwindow) );
	return ($self->{_root}, $mon1->x, $mon1->y, $mon1->width, $mon1->height);
}

sub get_current_monitor {
	my $self = shift;
	my ( $window_at_pointer, $x, $y, $mask ) = $self->{_root}->get_pointer;
	my $mon = $self->{_gdk_screen}
		->get_monitor_geometry( $self->{_gdk_screen}->get_monitor_at_point ($x, $y));
	return ($mon);
}

sub get_monitor_region {
	my $self = shift;
	my $region = Gtk2::Gdk::Region->new;
	for(my $i = 0; $i < $self->{_gdk_screen}->get_n_monitors; $i++){
		$region->union_with_rect ($self->{_gdk_screen}->get_monitor_geometry ($i));
	}
	return $region;
}

sub ungrab_pointer_and_keyboard {
	my ( $self, $ungrab_server, $quit_event_handler, $quit_main ) = @_;

	#ungrab pointer and keyboard
	Gtk2::Gdk::X11->ungrab_server if $ungrab_server;
	Gtk2::Gdk->pointer_ungrab( Gtk2->get_current_event_time );
	Gtk2::Gdk->keyboard_ungrab( Gtk2->get_current_event_time );
	Gtk2::Gdk::Event->handler_set( undef, undef ) if $quit_event_handler;
	Gtk2->main_quit if $quit_main;

	return TRUE unless Gtk2::Gdk->pointer_is_grabbed;
	return FALSE;
}

#~ sub get_scrollable_from_drawable {
	#~ my ( $self, $drawable, $x, $y, $width, $height, $cursor, $sleep ) = @_;
#~ 
	#~ #save pixbuf to file
	#~ my $pixbuf_save = Shutter::Pixbuf::Save->new( $self->{_sc}, $self->{_sc}->get_mainwindow );
#~ 
	#~ my @steps;
	#~ while(1){
#~ 
		#~ #create tempfile
		#~ my ( $tmpfh, $tmpfilename ) = tempfile(UNLINK => 1);
		#~ 
		#~ my ($pixbuf, $l_cropped, $r_cropped, $t_cropped, $b_cropped) = $self->get_pixbuf_from_drawable($drawable, $x, $y, $width, $height, FALSE, 1);
		#~ $pixbuf_save->save_pixbuf_to_file($pixbuf, $tmpfilename, 'miff');
	#~ 
		#~ push @steps, $tmpfilename;		
		#~ 
		#~ my $curr_index = scalar @steps;
		#~ if($curr_index > 1){
#~ 
			#~ my $compare = `compare -metric PSNR $steps[$curr_index-2] $steps[$curr_index-1] null: 2>&1`;
			#~ if ($compare =~ /inf/){
				#~ print "Finish\n";
				#~ last; 
			#~ }
		#~ }else{
			#~ my $line_size = 67;
			#~ $y += $height - $line_size;
			#~ $height = $line_size;	
		#~ }
		#~ 
		#~ #cursor can only be on the first page
		#~ $self->{_include_cursor} = FALSE;
		#~ 
		#~ #next scroll step
		#~ my $xdo = `xdotool click 5`;
		#~ 
	#~ }
	#~ 
	#~ my $append_cmd = 'convert';
	#~ foreach(@steps){
		#~ $append_cmd	.= " $_";
	#~ }
#~ 
	#~ #create tempfile
	#~ my ( $tmpfh_fin, $tmpfilename_fin ) = tempfile(UNLINK => 1);
	#~ $append_cmd .= " -append $tmpfilename_fin";
	#~ 
	#~ print $append_cmd."\n";
	#~ 
	#~ my $append_res = `$append_cmd`;
	#~ 
	#~ my $app_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file($tmpfilename_fin);
	#~ print $app_pixbuf."\n";
	#~ return ($app_pixbuf, 0, 0, 0, 0);
		#~ 
#~ }	

sub get_pixbuf_from_drawable {
	my ( $self, $drawable, $x, $y, $width, $height, $region ) = @_;

	my ($pixbuf, $l_cropped, $r_cropped, $t_cropped, $b_cropped) = (0, 0, 0, 0, 0);

	#show notification messages displaying the countdown
	if($self->{_delay} && $self->{_notify_timeout}){
		my $notify 	= $self->{_sc}->get_notification_object;
		my $ttw 	= $self->{_delay};

		#gettext
		my $d = $self->{_sc}->get_gettext;

		#first notification immediately
		$notify->show( sprintf($d->nget("Screenshot will be taken in %s second", "Screenshot will be taken in %s seconds", $ttw) , $ttw), "" );
		$ttw--;
		
		#delay is only 1 second
		#do not show any further messages
		if($ttw >= 1){
			#then controlled via timeout
			Glib::Timeout->add (1000, sub{
				$notify->show( sprintf($d->nget("Screenshot will be taken in %s second", "Screenshot will be taken in %s seconds", $ttw) , $ttw), "" );
				$ttw--;
				if($ttw == 0){			
					
					#close last message with a short delay (less than a second)
					Glib::Timeout->add (500, sub{
						$notify->close;
						return FALSE;	
					});	
					
					return FALSE;
					
				}else{
					
					return TRUE;	
				
				}	
			});
		}else{
			#close last message with a short delay (less than a second)
			Glib::Timeout->add (500, sub{
				$notify->close;
				return FALSE;	
			});				
		}	
	
	}		

	#Add a timeout if there is any delay
	Glib::Timeout->add ($self->{_delay}*1000, sub{	

		#get the pixbuf from drawable and save the file
		#
		#maybe window is partially not on the screen
		
		#right
		if ( $x + $width > $self->{ _root }->{ w } ) {
			$r_cropped = $x + $width - $self->{ _root }->{ w };
			$width -= $x + $width - $self->{ _root }->{ w };
		}
		
		#bottom
		if ( $y + $height > $self->{ _root }->{ h } ) {
			$b_cropped = $y + $height - $self->{ _root }->{ h };
			$height -= $y + $height - $self->{ _root }->{ h };
		}
		
		#left
		if ( $x < $self->{ _root }->{ x } ) {
			$l_cropped = $self->{ _root }->{ x } - $x;
			$width = $width + $x;
			$x     = 0;
		}
		
		#top
		if ( $y < $self->{ _root }->{ y } ) {
			$t_cropped = $self->{ _root }->{ y } - $y;
			$height = $height + $y;
			$y      = 0;
		}

		#get the pixbuf from drawable and save the file
		eval{
			if($width > 0 && $height > 0){
				$pixbuf = Gtk2::Gdk::Pixbuf->get_from_drawable( $drawable, undef, $x, $y, 0, 0, $width, $height );
			}
		};
		if($@){
			$pixbuf = 5;
			return FALSE;
		}
		
		#include cursor
		if($self->{_include_cursor}){
			$pixbuf = $self->include_cursor( $x, $y, $width, $height, $drawable, $pixbuf );
		}

		#region is optional
		#it is used to handle multiple monitors (root window may not be rectangular)
		#or to cut out the screen contents when capturing menus
		if($region){
			#get clipbox
			#~ my $clipbox = $region->get_clipbox;
			my $clipbox = $self->get_clipbox($region);
			
			#~ print "Clipbox: ", $clipbox->width, " - ", $clipbox->height, "\n";
			
			#create target pixbuf with dimension of clipbox
			my $target = Gtk2::Gdk::Pixbuf->new ($pixbuf->get_colorspace, TRUE, 8, $clipbox->width, $clipbox->height);
			
			#whole pixbuf is transparent
			$target->fill(0x00000000);

			#determine low x and y
			my $small_x = $self->{ _root }->{ w };
			my $small_y = $self->{ _root }->{ h };
			foreach my $r ($region->get_rectangles){
				$small_x = $r->x if $r->x < $small_x; 
				$small_y = $r->y if $r->y < $small_y; 
			}
			
			#copy each rectangle
			foreach my $r ($region->get_rectangles){
				#~ print $r->x, " - ", $r->y, " - ", $r->width, " - ", $r->height, "\n";
				$pixbuf->copy_area ($r->x - $small_x, $r->y - $small_y, $r->width, $r->height, $target, $r->x - $small_x, $r->y - $small_y);
			}
			$pixbuf = $target->copy;			
		}

		Gtk2->main_quit;
		return FALSE;	
	});	

	Gtk2->main();

	return ($pixbuf, $l_cropped, $r_cropped, $t_cropped, $b_cropped);
}

#code ported and partially borrowed from gnome-screenshot and Gimp
sub include_cursor {

	my ( $self, $xp, $yp, $widthp, $heightp, $gdk_window, $pixbuf ) = @_;

	require lib;
	import lib $self->{_sc}->get_root."/share/shutter/resources/modules";
	
	require X11::Protocol;

	#X11 protocol and XFIXES ext
	$self->{_x11} 			  = X11::Protocol->new( $ENV{ 'DISPLAY' } );
	$self->{_x11}{ext_xfixes} = $self->{_x11}->init_extension('XFIXES');
	
	#pixbuf
	my $cursor_pixbuf = undef;
	
	#Cursor position (root window coordinates)
	my $cursor_pixbuf_xroot = undef;
	my $cursor_pixbuf_yroot = undef;
	
	#The "hotspot" position
	my $cursor_pixbuf_xhot = undef;
	my $cursor_pixbuf_yhot = undef;

	if($self->{_x11}{ext_xfixes}){
		
		my ($root_x, $root_y, $width, $height, $xhot, $yhot, $serial, $pixels) = $self->{_x11}->XFixesGetCursorImage;
		
		#packed data string
		my $data;
		my $pos = 0;
		foreach my $y (0 .. $height-1) {
			foreach my $x (0 .. $width-1) {		
				my $argb = unpack 'L', substr($pixels,$pos,4);
				my $a = ($argb >> 24) & 0xFF;
				my $r = ($argb >> 16) & 0xFF;
				my $g = ($argb >> 8)  & 0xFF;
				my $b = ($argb >> 0)  & 0xFF;
				$pos += 4;
				
				#~ print "r:$r,g:$g,b:$b,a:$a\n";
				
				$r = ($r * 255) / $a if($a);
				$g = ($g * 255) / $a if($a);
				$b = ($b * 255) / $a if($a);
				
				$data .= pack ('C*', $r, $g, $b, $a);
			}
		}

		if($width > 1 && $height > 1){
			$cursor_pixbuf = Gtk2::Gdk::Pixbuf->new_from_data($data,'rgb',1,8,$width,$height-1,4*$width);

			$cursor_pixbuf_xhot = $xhot;
			$cursor_pixbuf_yhot = $yhot;

			$cursor_pixbuf_xroot = $root_x;
			$cursor_pixbuf_yroot = $root_y;
		}else{
			warn "WARNING: There was an error while getting the cursor image (XFIXESGetCursorImage)\n";
		}
		
	}else{

		warn "WARNING: XFIXES extension not found - using a default cursor image\n";

		my ( $window_at_pointer, $root_x, $root_y, $mask ) = $gdk_window->get_pointer;

		my $cursor = Gtk2::Gdk::Cursor->new( 'GDK_LEFT_PTR' );
		$cursor_pixbuf = $cursor->get_image;
	
		#try to use default cursor if there was an error
		unless ( $cursor_pixbuf) {
			warn "WARNING: There was an error while getting the default cursor image - using one of our image files\n";
			my $icons_path = $self->{_sc}->get_root . "/share/shutter/resources/icons";
			eval{
				$cursor_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file($icons_path."/Normal.cur");
			};
			if($@){
				warn "ERROR: There was an error while loading the image file: $@\n";
			}
		}
		
		if( $cursor_pixbuf ){
			$cursor_pixbuf_xhot = $cursor_pixbuf->get_option('x_hot');
			$cursor_pixbuf_yhot = $cursor_pixbuf->get_option('y_hot');
			
			$cursor_pixbuf_xroot = $root_x;
			$cursor_pixbuf_yroot = $root_y;
		}
		
	}
	
	if ( $cursor_pixbuf ) {
	
		#x,y pos (cursor)
		my $x = $cursor_pixbuf_xroot;
		my $y = $cursor_pixbuf_yroot;
	
		#screenshot dimensions saved in a rect (global x, y)
		my $scshot  = Gtk2::Gdk::Rectangle->new( $xp, $yp, $widthp, $heightp );
		
		#see 'man xcursor' for a detailed description
		#of these values
		my $xhot = $cursor_pixbuf_xhot;
		my $yhot = $cursor_pixbuf_yhot;

		#cursor dimensions (global x, y and width and height of the pixbuf)
		my $cursor = Gtk2::Gdk::Rectangle->new( $x, $y, $cursor_pixbuf->get_width, $cursor_pixbuf->get_height );
		
		#is the cursor visible in the current screenshot?
		#(do the rects intersect?)
		if ( $cursor = $scshot->intersect( $cursor ) ) {
			
			#calculate dest_x, dest_y
			#be careful here when subtracting xhot and yhot,
			#because negative values are not allowed when 
			#using composite
			#
			#example: moving the cursor to the coords 0, 0
			#would lead to an error
			my $dest_x = $x - $xp - $xhot;
			my $dest_y = $y - $yp - $yhot;
			$dest_x = 0 if $dest_x < 0;
			$dest_y = 0 if $dest_y < 0;

			$cursor_pixbuf->composite(
									   $pixbuf, 
									   $dest_x,
									   $dest_y, 
									   $cursor->width,
									   $cursor->height, 
									   $x - $xp - $xhot,
									   $y - $yp - $yhot, 
									   1.0, 1.0, 'bilinear', 255
									 );
									 
		}
	}

	return $pixbuf;
}

1;
