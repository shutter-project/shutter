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

package Shutter::Screenshot::Window;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

#File operations
use IO::File();

use Shutter::Screenshot::Main;
use Shutter::Screenshot::History;
use Data::Dumper;
our @ISA = qw(Shutter::Screenshot::Main);

#Glib
use Gtk2;
use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;

	#call constructor of super class (shutter_common, include_cursor, delay, notify_timeout)
	my $self = $class->SUPER::new( shift, shift, shift, shift );

	#get params
	$self->{_include_border}    = shift;
	$self->{_windowresize}      = shift;
	$self->{_windowresize_w}    = shift;
	$self->{_windowresize_h}    = shift;
	$self->{_hide_time}         = shift;   #a short timeout to give the server a chance to redraw the area that was obscured
	$self->{_mode}              = shift;
	$self->{_auto_shape}        = shift;   #shape the window without XShape support	
	$self->{_is_hidden}         = shift;
	$self->{_show_visible}      = shift;   #show user-visible windows only when selecting a window
	$self->{_ignore_type}       = shift;   #Ignore possibly wrong type hints

	#X11 protocol and XSHAPE ext
	require X11::Protocol;

	$self->{_x11} 				= X11::Protocol->new( $ENV{ 'DISPLAY' } );
	$self->{_x11}{ext_shape}	= $self->{_x11}->init_extension('SHAPE');

	#main window
	$self->{_main_gtk_window} 	= $self->{_sc}->get_mainwindow;

	#only used when selecting a window
	if(defined $self->{_mode} && $self->{_mode} =~ m/(window|section)/ig){
		
		#check if compositing is available
		my $compos = $self->{_main_gtk_window}->get_screen->is_composited;
		
		#higlighter (borderless gtk window)
		$self->{_highlighter} = Gtk2::Window->new('popup');
		if($compos){
			$self->{_highlighter}->set_colormap($self->{_main_gtk_window}->get_screen->get_rgba_colormap);
		}

		$self->{_highlighter}->set_app_paintable(TRUE);
		$self->{_highlighter}->set_decorated(FALSE);
		$self->{_highlighter}->set_skip_taskbar_hint(TRUE);
		$self->{_highlighter}->set_skip_pager_hint(TRUE);	    
		$self->{_highlighter}->set_keep_above(TRUE);
		$self->{_highlighter}->set_accept_focus(FALSE);

		#obtain current colors and font_desc from the main window
		my $style = $self->{_main_gtk_window}->get_style;
		my $sel_bg = $style->bg('selected');
		my $sel_tx = $style->text('selected');
		my $font_fam = $style->font_desc->get_family;
		my $font_size = $style->font_desc->get_size / Gtk2::Pango->scale;
		
		#get current monitor
		my $mon = $self->get_current_monitor;

		$self->{_highlighter_expose} = $self->{_highlighter}->signal_connect('expose-event' => sub{

			return FALSE unless $self->{_highlighter}->window;

			#Place window and resize it
			$self->{_highlighter}->window->move_resize($self->{_c}{'cw'}{'x'}-3, $self->{_c}{'cw'}{'y'}-3 ,$self->{_c}{'cw'}{'width'}+6, $self->{_c}{'cw'}{'height'}+6);			
			
			print $self->{_c}{'cw'}{'window'}->get_name, "\n" if $self->{_sc}->get_debug; 

			my $text = Glib::Markup::escape_text ($self->{_c}{'cw'}{'window'}->get_name);
			utf8::decode $text;
			
			my $sec_text =  "\n".$self->{_c}{'cw'}{'width'} . "x" . $self->{_c}{'cw'}{'height'};

			#window size and position
			my ($w, $h) = $self->{_highlighter}->get_size;
			my ($x, $y) = $self->{_highlighter}->get_position;

			#app icon
			my $icon = $self->{_c}{'cw'}{'window'}->get_icon;
			
			#create cairo context
			my $cr = Gtk2::Gdk::Cairo::Context->create ($self->{_highlighter}->window);
			
			#pango layout
			my $layout = Gtk2::Pango::Cairo::create_layout($cr);
			$layout->set_width( ($w - $icon->get_width - $font_size * 3) * Gtk2::Pango->scale );
			$layout->set_alignment('left');
			$layout->set_wrap('char');

			#warning if there are no subwindows
			#when we are in section mode and 
			#a toplevel window was already selected
			if($self->{_c}{'ws'}){
				my $xwindow = $self->{_c}{'ws'}->XWINDOW;				
				if (scalar @{$self->{_c}{'cw'}{$xwindow}} <= 1){
					#error icon
					$icon = Gtk2::Widget::render_icon (Gtk2::Invisible->new, "gtk-dialog-error", 'dialog');
					
					#error message
					my $d = $self->{_sc}->get_gettext;
					$text = $d->get("No subwindow detected");
					$sec_text = "\n".$d->get("Maybe this window is using client-side windows (or similar).\nShutter is not yet able to query the tree information of such windows.");
					
					#wrap nicely
					$layout->set_wrap('word-char');
				}
			}
			
			#set text
			$layout->set_markup("<span font_desc=\"$font_fam $font_size\" weight=\"bold\" foreground=\"#FFFFFF\">$text</span><span font_desc=\"$font_fam $font_size\" foreground=\"#FFFFFF\">$sec_text</span>");

			#get layout size
			my ( $lw, $lh ) = $layout->get_pixel_size;
			
			#adjust values
			$lw += $icon->get_width;
			$lh = $icon->get_height if $icon->get_height > $lh;
			
			#calculate values for rounded/shaped rectangle
			my $wi = $lw + $font_size * 3;
			my $hi = $lh + $font_size * 2;
			my $xi = int( ($w - $wi) / 2 );
			my $yi = int( ($h - $hi) / 2 );
			my $ri = 20;
			
			#two different ways - compositing or not
			if($compos){
				
				#fill window
				$cr->set_operator('source');
				$cr->set_source_rgba( $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255, 0.3 );
				$cr->paint;

				#Parent window with text and icon			
				if($self->{_c}{'cw'}{'is_parent'}){						
					
					$cr->set_operator('over');
																			
					#create small frame (window outlines)
					$cr->set_source_rgba( $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255, 0.75 );
					$cr->set_line_width(6);
					$cr->rectangle (0, 0, $w, $h);
					$cr->stroke;
					
					if($lw <= $w && $lh <= $h){
					
						#rounded rectangle to display the window name
						$cr->move_to( $xi + $ri, $yi );
						$cr->line_to( $xi + $wi - $ri, $yi );
						$cr->curve_to( $xi + $wi, $yi, $xi + $wi, $yi, $xi + $wi, $yi + $ri );
						$cr->line_to( $xi + $wi, $yi + $hi - $ri );
						$cr->curve_to( $xi + $wi, $yi + $hi, $xi + $wi, $yi + $hi, $xi + $wi - $ri, $yi + $hi );
						$cr->line_to( $xi + $ri, $yi + $hi );
						$cr->curve_to( $xi, $yi + $hi, $xi, $yi + $hi, $xi, $yi + $hi - $ri );
						$cr->line_to( $xi, $yi + $ri );
						$cr->curve_to( $xi, $yi, $xi, $yi, $xi + $ri, $yi );
						$cr->fill;	

						#app icon
						Gtk2::Gdk::Cairo::Context::set_source_pixbuf( $cr, $icon, $xi + $font_size, $yi + $font_size );
						$cr->paint;
						
						#draw the pango layout
						$cr->move_to( $xi + $font_size*2 + $icon->get_width, $yi + $font_size );
						Gtk2::Pango::Cairo::show_layout( $cr, $layout );	

					}

				}else{
					#create small frame
					$cr->set_source_rgba( $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255, 0.75 );
					$cr->set_line_width(6);
					$cr->rectangle (0, 0, $w, $h);
					$cr->stroke;	
				}

			#no compositing
			}else{

				#fill window
				$cr->set_operator('over');
				$cr->set_source_rgb( $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255 );
				$cr->paint;

				#Parent window with text and icon			
				if($self->{_c}{'cw'}{'is_parent'}){	
					
					if($lw <= $w && $lh <= $h){
						#app icon
						Gtk2::Gdk::Cairo::Context::set_source_pixbuf( $cr, $icon, $xi + $font_size, $yi + $font_size );
						$cr->paint;
						
						#draw the pango layout
						$cr->move_to( $xi + $font_size*2 + $icon->get_width, $yi + $font_size );
						Gtk2::Pango::Cairo::show_layout( $cr, $layout );
					}	
				
				}
								
				my $rectangle1 	 	= Gtk2::Gdk::Rectangle->new (0, 0, $w, $h);
				my $rectangle2 	 	= Gtk2::Gdk::Rectangle->new (3, 3, $w-6, $h-6);
				my $rectangle3 	 	= Gtk2::Gdk::Rectangle->new ($xi, $yi, $wi, $hi);
				my $shape_region1 	= Gtk2::Gdk::Region->rectangle ($rectangle1);
				my $shape_region2 	= Gtk2::Gdk::Region->rectangle ($rectangle2);
				my $shape_region3 	= Gtk2::Gdk::Region->rectangle ($rectangle3);
				
				#Parent window with text and icon			
				if($self->{_c}{'cw'}{'is_parent'}){	
					if($lw <= $w && $lh <= $h){
						$shape_region2->subtract($shape_region3);
					}
				}	

				$shape_region1->subtract($shape_region2);
				$self->{_highlighter}->window->shape_combine_region ($shape_region1, 0, 0);					
					
			}
			
			return TRUE;	
		});
		
	}
	
	bless $self, $class;
	return $self;
}

#~ sub DESTROY {
    #~ my $self = shift;
    #~ print "$self dying at\n";
#~ } 
#~ 

sub find_wm_window {
	my $self = shift;
	my $xid  = shift;

	do {
		my ( $qroot, $qparent, @qkids ) = $self->{_x11}->QueryTree($xid);
		return undef unless ( $qroot || $qparent );
		return $xid if ( $qroot == $qparent );
		$xid = $qparent;
	} while (TRUE);
}

sub get_shape {
	my $self        = shift;
	my $xid         = shift;
	my $orig        = shift;
	my $l_cropped   = shift;
	my $r_cropped   = shift;
	my $t_cropped   = shift;
	my $b_cropped   = shift;

	print "$l_cropped, $r_cropped, $t_cropped, $b_cropped cropped\n" if $self->{_sc}->get_debug;

	print "Calculating window shape\n" if $self->{_sc}->get_debug;

	#check if extenstion is available and use it
	my ($ordering, @r) = (undef, undef);
	if($self->{_x11}{ext_shape}){
		($ordering, @r) = $self->{_x11}->ShapeGetRectangles($self->find_wm_window($xid), 'Bounding');
	}
	
	my $manually_shaped = FALSE;
	#create shape manually when option is set and the shape was not detected automatically
	if (scalar @r <= 1 && defined $self->{_auto_shape} && $self->{_auto_shape}){
		
		my $shf = Shutter::App::HelperFunctions->new( $self->{_sc} );
		
		my $shape_path = undef;
		$shape_path = $self->{_sc}->get_root . "/share/shutter/resources/conf/shape.conf" if $shf->file_exists($self->{_sc}->get_root . "/share/shutter/resources/conf/shape.conf");
		$shape_path = "$ENV{'HOME'}/.shutter/shape.conf" if $shf->file_exists("$ENV{'HOME'}/.shutter/shape.conf");
		
		if(defined $shape_path && $shape_path){
			
			my @fregion;
			
			my $fh = new IO::File;
			if ($fh->open("< $shape_path")) {
				while( my $line = <$fh> ){
					#skip on comments
					next if $line =~ /^#/;
					chomp($line);
					push @fregion, $line;
				}
				$fh->close;
			}else{
				print "Unable to open file $shape_path" if $self->{_sc}->get_debug;
				return $orig;
			}
			
			print "Window shape not detected - using $shape_path\n" if $self->{_sc}->get_debug;
			
			#remove current entry
			pop @r;
			
			my $width = $orig->get_width;
			my $height = $orig->get_height;
						
			foreach my $line(@fregion){
				$line =~ s/width/$width/;
				$line =~ s/height/$height/;
				$line =~ s/(\d+)-(\d+)/$1-$2/eg;
				my @temp = split(' ', $line);
				push @r, \@temp;
			}
			
			$manually_shaped = TRUE;
			
		}else{
			
			print "Unable to locate shape.conf\n" if $self->{_sc}->get_debug;
			
		}
		
	#do nothing if there are no
	#shape rectangles (or only one)		
	}elsif(scalar @r <= 1){
		return $orig;
	}
							
	#create a region from the bounding rectangles
	my $bregion = Gtk2::Gdk::Region->new;					
	foreach my $r (@r){
		my @rect =  @{$r};
		
		next unless defined $rect[0];
		next unless defined $rect[1];
		next unless defined $rect[2];
		next unless defined $rect[3];
		
		unless($manually_shaped){
			#adjust rectangle if window is only partially visible
			if($l_cropped){
				$rect[2] -= $l_cropped - $rect[0]; 
				$rect[0] = 0;
			}
			if($t_cropped){
				$rect[3] -= $t_cropped - $rect[1]; 
				$rect[1] = 0;
			}
		}
		
		print "Current $rect[0],$rect[1],$rect[2],$rect[3]\n" if $self->{_sc}->get_debug;
		$bregion->union_with_rect(Gtk2::Gdk::Rectangle->new ($rect[0],$rect[1],$rect[2],$rect[3]));	
	}

	if(defined $orig){
		#create target pixbuf with dimensions if selected/current window
		my $target = Gtk2::Gdk::Pixbuf->new ($orig->get_colorspace, TRUE, 8, $orig->get_width, $orig->get_height);
		#whole pixbuf is transparent
		$target->fill(0x00000000);
		
		#copy all rectangles of bounding region to the target pixbuf
		foreach my $r($bregion->get_rectangles){
			print $r->x." ".$r->y." ".$r->width." ".$r->height."\n" if $self->{_sc}->get_debug;
			
			next if($r->x > $orig->get_width);
			next if($r->y > $orig->get_height);
	
			$r->width($orig->get_width - $r->x) if($r->x+$r->width > $orig->get_width);
			$r->height($orig->get_height - $r->y) if($r->y+$r->height > $orig->get_height);	
			
			if($r->x >= 0 && $r->x + $r->width <= $orig->get_width && $r->y >= 0 && $r->y + $r->height <= $orig->get_height){
				$orig->copy_area ($r->x, $r->y, $r->width, $r->height, $target, $r->x, $r->y);		
			}else{
				warn "WARNING: There was an error while calculating the window shape\n";
				return $orig;
			}
		}
		
		return $target;
	}else{
		return $bregion;	
	}
	
}	

sub get_window_size {
	my ( $self, $wnck_window, $gdk_window, $border, $no_resize ) = @_;

	#windowresize is active
	if($self->{_mode} eq "window" || $self->{_mode} eq "tray_window" || $self->{_mode} eq "awindow" || $self->{_mode} eq "tray_awindow"){
		unless($no_resize){
			if(defined $self->{_windowresize} && $self->{_windowresize}) {
				
				#windows can usually not be resized when maximized
				if($wnck_window->is_maximized){
					$wnck_window->unmaximize;
				}

				$self->quit_eventh_only;

				Glib::Timeout->add ($self->{_hide_time}, sub{		
					Gtk2->main_quit;
					return FALSE;	
				});	
				Gtk2->main();
				
				my ($xc, $yc, $wc, $hc) = $self->get_window_size($wnck_window, $gdk_window, $border, TRUE);
				
				if(defined $self->{_windowresize_w} && $self->{_windowresize} > 0){
					$wc = $self->{_windowresize_w};
				}
				
				if(defined $self->{_windowresize_h} && $self->{_windowresize_h} > 0){
					$hc = $self->{_windowresize_h};
				}
				
				if($border){
					$wnck_window->set_geometry ('current', [qw/width height/], $xc, $yc, $wc, $hc);		
				}else{
					$gdk_window->resize ($wc, $hc);
				}
					
				Glib::Timeout->add ($self->{_hide_time}, sub{		
					Gtk2->main_quit;
					return FALSE;	
				});	
				Gtk2->main();
			}
		}
	}

	#calculate size of the window
	my ( $xp, $yp, $wp, $hp ) = (0, 0, 0, 0);
	if ($border) {
		( $xp, $yp, $wp, $hp ) = $wnck_window->get_geometry;
	} else {
		( $xp, $yp, $wp, $hp ) = $gdk_window->get_geometry;
		( $xp, $yp ) = $gdk_window->get_origin;
	}

	return ( $xp, $yp, $wp, $hp );
}

sub update_highlighter {
	my $self 	= shift;

	if(defined $self->{_c}{'cw'}{'gdk_window'} && defined $self->{_c}{'cw'}{'window'}){

		#and show highlighter window at current cursor position		
		$self->{_highlighter}->show_all;
		$self->{_highlighter}->queue_draw;

		Gtk2::Gdk->keyboard_grab( $self->{_highlighter}->window, 0, Gtk2->get_current_event_time );
	
		#save last window objects
		$self->{_c}{'lw'}{'window'} 	= $self->{_c}{'cw'}{'window'};
		$self->{_c}{'lw'}{'gdk_window'} = $self->{_c}{'cw'}{'gdk_window'};
			
	}

}

sub find_current_parent_window {
	my $self 				= shift;
	my $event 				= shift;
	my $active_workspace 	= shift;

	#get all toplevel windows
	my @wnck_windows = $self->{_wnck_screen}->get_windows_stacked;
	
	#show user-visible windows only when selecting a window
	if(defined $self->{_show_visible} && $self->{_show_visible}){
		@wnck_windows = reverse @wnck_windows;	
	}
	
	foreach my $cwdow (@wnck_windows) {

		my $drawable = Gtk2::Gdk::Window->foreign_new( $cwdow->get_xid );
		if(defined $drawable){

			#do not detect shutter window when it is hidden
			if (   $self->{_main_gtk_window}->window && $self->{_is_hidden} ) {
				next if ( $cwdow->get_xid == $self->{_main_gtk_window}->window->get_xid );
			}
	
			my ( $xp, $yp, $wp, $hp ) = $self->get_window_size( $cwdow, $drawable, $self->{_include_border}, TRUE );
	
			my $wr = Gtk2::Gdk::Region->rectangle(
				Gtk2::Gdk::Rectangle->new( $xp, $yp, $wp, $hp ) );
	
			if ($cwdow->is_visible_on_workspace($active_workspace)
				&& $wr->point_in( $event->x, $event->y )
				&& $wp * $hp <= $self->{_min_size}) {
				
				$self->{_c}{'cw'}{'window'}     = $cwdow;
				$self->{_c}{'cw'}{'gdk_window'} = $drawable;
				$self->{_c}{'cw'}{'x'}          = $xp;
				$self->{_c}{'cw'}{'y'}          = $yp;
				$self->{_c}{'cw'}{'width'}      = $wp;
				$self->{_c}{'cw'}{'height'}     = $hp;
				$self->{_c}{'cw'}{'is_parent'} 	= TRUE;
				$self->{_min_size}				= $wp * $hp;
				
				#show user-visible windows only when selecting a window
				if(defined $self->{_show_visible} && $self->{_show_visible}){	
					last;
				}
	
			} #size and geometry check
			
		} #not defined gdk::window

	} #end if toplevel window loop	
			
	return TRUE;		
}

sub find_current_child_window {
	my ( $self, $event, $xwindow, $xparent, $depth, $limit, $type_hint ) = @_;
		
	#reparenting depth and recursion limit
	$depth = 0 unless defined $depth;
	$limit = 0 unless defined $limit;
	if ($depth > $limit){
		return TRUE;
	}
	
	my ( $qroot, $qparent, @qkids );
	unless(defined $self->{_c}{'cw'}{$xwindow} && scalar @{$self->{_c}{'cw'}{$xwindow}}){	
		
		#query all child windows of xwindow
		( $qroot, $qparent, @qkids ) = $self->{_x11}->QueryTree($xwindow);

		#and save them, so we don't have to query them again
		@{$self->{_c}{'cw'}{$xwindow}} = @qkids;

	}else{
		
		#we can use the cached children information
		@qkids = @{$self->{_c}{'cw'}{$xwindow}};
	
	}
	
	foreach my $kid (reverse @qkids) {

		my $gdk_window = Gtk2::Gdk::Window->foreign_new($kid);
			if ( defined $gdk_window ) {
	
			#window needs to be viewable and visible
			next unless $gdk_window->is_visible;
			next unless $gdk_window->is_viewable;	
	
			#check type_hint
			if(defined $type_hint){ 
				my $curr_type_hint = $gdk_window->get_type_hint;
				next unless $curr_type_hint =~ /$type_hint/;
			}
			
			#~ print $curr_type_hint, " - passed \n";
						
			#min size
			my ( $xp, $yp, $wp, $hp, $depthp ) = $gdk_window->get_geometry;
			( $xp, $yp ) = $gdk_window->get_origin;
			next if ( $wp * $hp < 4 );
	
			my $sr = Gtk2::Gdk::Region->rectangle(
				Gtk2::Gdk::Rectangle->new(
					$xp, $yp, $wp, $hp
				)
			);
			
			if ( $sr->point_in( $event->x, $event->y ) && $wp * $hp <= $self->{_min_size} ) {
				
				$self->{_c}{'cw'}{'gdk_window'} = $gdk_window;
				$self->{_c}{'cw'}{'x'} 			= $xp;
				$self->{_c}{'cw'}{'y'} 			= $yp;
				$self->{_c}{'cw'}{'width'} 		= $wp;
				$self->{_c}{'cw'}{'height'} 	= $hp;
				$self->{_c}{'cw'}{'is_parent'} 	= FALSE;
				$self->{_min_size} = $wp * $hp;
	
				#~ print $self->{_c}{'cw'}{'x'}, " - ",			 			
					  #~ $self->{_c}{'cw'}{'y'}, " - ", 			
					  #~ $self->{_c}{'cw'}{'width'}, " - ", 		
					  #~ $self->{_c}{'cw'}{'height'}, " \n " if $self->{_sc}->get_debug; 	
	
				#check next depth
				unless($gdk_window->XWINDOW == $xwindow){
					$self->find_current_child_window( $event, $gdk_window->XWINDOW, $xparent, $depth++, $limit, $type_hint );
				}else{
					last;	
				}
				#~ last;
				
			}
		}
	}
	
	return TRUE;	
}

sub find_active_window {
	my $self = shift;

	my $gdk_window = $self->{_gdk_screen}->get_active_window;

	if ( defined $gdk_window ) {
		my $wnck_window = Gnome2::Wnck::Window->get( $gdk_window->get_xid );
		if ( defined $wnck_window ) {
			return ($wnck_window, $gdk_window);
		}		  				
	}
	
	return FALSE;	
}

sub find_region_for_window_type {
	my ( $self, $xwindow, $type_hint) = @_;

	#XQueryTree - query window tree information
	my ( $qroot, $qparent, @qkids ) = $self->{_x11}->QueryTree($xwindow);
	
	foreach my $kid (reverse @qkids) {
				
		my $gdk_window = Gtk2::Gdk::Window->foreign_new($kid);

		if ( defined $gdk_window ) {

			#check type_hint
			my $curr_type_hint = $gdk_window->get_type_hint;
			if(defined $type_hint){ 
				next unless $curr_type_hint =~ /$type_hint/;
			}

			#XGetWindowAttributes, XGetGeometry, XWindowAttributes - get current
			#window attribute or geometry and current window attributes structure
			my @atts = $self->{_x11}->GetWindowAttributes($kid);
			return unless @atts;
			
			#window needs to be viewable
			return FALSE unless $atts[19] eq 'Viewable';
							
			#min size
			my ( $xp, $yp, $wp, $hp, $depthp ) = $gdk_window->get_geometry;
			( $xp, $yp ) = $gdk_window->get_origin;

			#~ print $xp, " - ", $yp, " - ", $wp, " - ", $hp, "\n";
			
			#create region
			my $sr = Gtk2::Gdk::Region->rectangle(
				Gtk2::Gdk::Rectangle->new(
					$xp, $yp, $wp, $hp
				)
			);
			
			#init region
			unless(defined $self->{_c}{'cw'}{'window_region'}){
				$self->{_c}{'cw'}{'window_region'} = Gtk2::Gdk::Region->new;
				$self->{_c}{'cw'}{'window_region'}->union($sr);
			}else{
				$self->{_c}{'cw'}{'window_region'}->union($sr);				
			}
			
			#store clipbox geometry
			#~ my $cbox = $self->{_c}{'cw'}{'window_region'}->get_clipbox;
			my $cbox = $self->get_clipbox($self->{_c}{'cw'}{'window_region'});
			
			$self->{_c}{'cw'}{'gdk_window'} = $gdk_window;
			$self->{_c}{'cw'}{'x'} 			= $cbox->x;
			$self->{_c}{'cw'}{'y'} 			= $cbox->y;
			$self->{_c}{'cw'}{'width'} 		= $cbox->width;
			$self->{_c}{'cw'}{'height'} 	= $cbox->height;
			$self->{_c}{'cw'}{'is_parent'} 	= FALSE;

			#~ print $self->{_c}{'cw'}{'x'}, " - ",			 			
			#~ $self->{_c}{'cw'}{'y'}, " - ", 			
			#~ $self->{_c}{'cw'}{'width'}, " - ", 		
			#~ $self->{_c}{'cw'}{'height'}, " \n "; 				
		}
	}
	
	return TRUE;	
}

sub select_window {
	my $self = shift;
	my $event = shift;
	my $active_workspace = shift;

	#select child window
	my $depth = shift; 
	my $limit = shift;
	my $type_hint = shift;

	#root window size is minimum at startup
	$self->{_min_size} = $self->{_root}->{w} * $self->{_root}->{h};
			
	#if there is no window already selected
	unless ($self->{_c}{'ws'}) {

		$self->find_current_parent_window($event, $active_workspace);

	#parent window selected/no grab, search for children now
	}elsif ( 
		( $self->{_mode} eq "section" || $self->{_mode} eq "tray_section" ) && $self->{_c}{'ws'} ) {

		$self->find_current_child_window($event, 
			$self->{_c}{'ws'}->XWINDOW, 
			$self->{_c}{'ws'}->XWINDOW,
			$depth,
			$limit,
			$type_hint);				
	}

	#draw highlighter if needed
	if ( (Gtk2::Gdk->pointer_is_grabbed && ($self->{_c}{'lw'}{'gdk_window'} ne $self->{_c}{'cw'}{'gdk_window'})) || 
		 (Gtk2::Gdk->pointer_is_grabbed && $self->{_c}{'ws_init'}) ) {
			 
		$self->update_highlighter();
		
		#reset flag
		$self->{_c}{'ws_init'} = FALSE;
	}
	
	return TRUE;
}

sub window {
	my $self = shift;

	#return value
	
	my $output = 5;
	
	#current workspace
	my $active_workspace = $self->{_wnck_screen}->get_active_workspace;

	#something went wrong here, no active workspace detected
	unless ( $active_workspace ) {
		$output = 0;
		return $output;
	}

	#grab pointer and keyboard
	#when mode is section or window 
	unless($self->{_mode} eq "menu" || $self->{_mode} eq "tray_menu" || $self->{_mode} eq "tooltip" || $self->{_mode} eq "tray_tooltip" || $self->{_mode} eq "awindow" || $self->{_mode} eq "tray_awindow"){
		
		$self->{_highlighter}->realize;
		
		my $grab_counter = 0;
		while ( !Gtk2::Gdk->pointer_is_grabbed && $grab_counter < 100 ) {
			Gtk2::Gdk->pointer_grab(
				$self->{_root}, FALSE,
				[qw/pointer-motion-mask button-press-mask button-release-mask/], undef,
				Gtk2::Gdk::Cursor->new('GDK_HAND2'),
				Gtk2->get_current_event_time
			);
			Gtk2::Gdk->keyboard_grab( $self->{_highlighter}->window, 0, Gtk2->get_current_event_time );
			$grab_counter++;
		}

	}

	#init
	$self->{_c} = ();
	$self->{_c}{'ws'} = undef;	
	$self->{_c}{'ws_init'} = FALSE;	
	$self->{_c}{'lw'}{'gdk_window'} = 0;

	#root window size is minimum at startup
	$self->{_min_size}              = $self->{_root}->{w} * $self->{_root}->{h};
	$self->{_c}{'cw'}{'gdk_window'} = $self->{_root};
	$self->{_c}{'cw'}{'x'}          = $self->{_root}->{x};
	$self->{_c}{'cw'}{'y'}          = $self->{_root}->{y};
	$self->{_c}{'cw'}{'width'}      = $self->{_root}->{w};
	$self->{_c}{'cw'}{'height'}     = $self->{_root}->{h};

	#get initial window under cursor
	my ( $window_at_pointer, $initx, $inity, $mask ) = $self->{_root}->get_pointer;		
	
	#create event for current coordinates
	my $initevent = Gtk2::Gdk::Event->new ('motion-notify');
	$initevent->set_time(Gtk2->get_current_event_time);
	$initevent->window($self->{_root});
	$initevent->x($initx);
	$initevent->y($inity);
		
	if ( Gtk2::Gdk->pointer_is_grabbed && !($self->{_mode} eq "menu" || $self->{_mode} eq "tray_menu" || $self->{_mode} eq "tooltip" || $self->{_mode} eq "tray_tooltip" || $self->{_mode} eq "awindow" || $self->{_mode} eq "tray_awindow") ) {

		#simulate mouse movement
		$self->select_window($initevent, $active_workspace);
		
		Gtk2::Gdk::Event->handler_set(
			sub {
				my ( $event, $data ) = @_;
				return FALSE unless defined $event;

				#KEY-PRESS
				if ( $event->type eq 'key-press' ) {
					next unless defined $event->keyval;
					
					if ( $event->keyval == Gtk2::Gdk->keyval_from_name('Escape') ) {

						#destroy highlighter window
						$self->{_highlighter}->destroy;

						$self->quit;

						$output = 5;
					}
				
				#BUTTON-PRESS	
				} elsif ( $event->type eq 'button-press' ) {
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_sc}->get_debug );			

					#user selects window or section
					$self->select_window($event, $active_workspace);
				
				#BUTTON-RELEASE				
				} elsif ( $event->type eq 'button-release' ) {
					print "Type: " . $event->type . "\n" if ( defined $event && $self->{_sc}->get_debug );

					my ( $xp, $yp, $wp, $hp, $xc, $yc, $wc, $hc ) = (0, 0, 0, 0, 0, 0, 0, 0);

					if ( defined $self->{_c}{'lw'} && $self->{_c}{'lw'}{'gdk_window'} ) {
						
						#size (we need to do this again because of autoresizing)
						if ( ( $self->{_mode} eq "window" || $self->{_mode} eq "tray_window" ||  $self->{_mode} eq "awindow"  || $self->{_mode} eq "tray_awindow" ) ) {
							( $xc, $yc, $wc, $hc ) = $self->get_window_size( $self->{_c}{'lw'}{'window'}, $self->{_c}{'lw'}{'gdk_window'}, $self->{_include_border}, TRUE );
							( $xp, $yp, $wp, $hp ) = $self->get_window_size( $self->{_c}{'lw'}{'window'}, $self->{_c}{'lw'}{'gdk_window'}, $self->{_include_border} );

							$self->{_c}{'cw'}{'x'} 			= $xp;
							$self->{_c}{'cw'}{'y'} 			= $yp;
							$self->{_c}{'cw'}{'width'} 		= $wp;
							$self->{_c}{'cw'}{'height'} 	= $hp;
						}
						
						#focus selected window (maybe it is hidden)
						$self->{_c}{'lw'}{'gdk_window'}->focus($event->time);
						Gtk2::Gdk->flush;						

					#something went wrong here, no window on screen detected	
					} else {
						
						$output = 0;
						$self->quit;
						return $output;
					
					}
					
					#looking for a section of a window?
					#keep current window in mind and search for children
					if ( ( $self->{_mode} eq "section" || $self->{_mode} eq "tray_section" )
						&& !$self->{_c}{'ws'} )
					{
																		
						#mark as selected parent window
						$self->{_c}{'ws'} = $self->{_c}{'cw'}{'gdk_window'};
						$self->{_c}{'ws_init'} = TRUE;	

						#and select current subwindow
						$self->select_window($event);
						
						#we don't take the screenshot yet
						return TRUE;
					}

					#stop event handler
					$self->quit_eventh_only;

					#destroy highlighter window
					$self->{_highlighter}->destroy;
					
					#A short timeout to give the server a chance to
					#redraw the area
					Glib::Timeout->add ($self->{_hide_time}, sub{		
						Gtk2->main_quit;
						return FALSE;	
					});	
					Gtk2->main();
					
					my ($output_new, $l_cropped, $r_cropped, $t_cropped, $b_cropped) = 
						$self->get_pixbuf_from_drawable(
							$self->{_root},
							$self->{_c}{'cw'}{'x'},
							$self->{_c}{'cw'}{'y'},
							$self->{_c}{'cw'}{'width'},
							$self->{_c}{'cw'}{'height'}
						);

					#save return value to current $output variable 
					#-> ugly but fastest and safest solution now
					$output = $output_new;
												
					#respect rounded corners of wm decorations (metacity for example - does not work with compiz currently)	
					if($self->{_include_border}){
						my $xid = $self->{_c}{ 'cw' }{ 'gdk_window' }->get_xid;
						#do not try this for child windows
						foreach my $win ($self->{_wnck_screen}->get_windows){
							if($win->get_xid == $xid){
								$output = $self->get_shape($xid, $output, $l_cropped, $r_cropped, $t_cropped, $b_cropped);				
								last;
							}
						}
					}

					#restore window size when autoresizing was used
					if($self->{_mode} eq "window" || $self->{_mode} eq "tray_window" || $self->{_mode} eq "awindow" || $self->{_mode} eq "tray_awindow"){
						if(defined $self->{_windowresize} && $self->{_windowresize}) {
							if($wc != $wp || $hc != $hp){
								if($self->{_include_border}){
									$self->{_c}{'lw'}{'window'}->set_geometry ('current', [qw/width height/], $xc, $yc, $wc, $hc);		
								}else{
									$self->{_c}{'lw'}{'gdk_window'}->resize ($wc, $hc);
								}
							}
						}
					}

					#set name of the captured window
					#e.g. for use in wildcards
					if($output =~ /Gtk2/ && defined $self->{_c}{'cw'}{'window'}){
						$self->{_action_name} = $self->{_c}{'cw'}{'window'}->get_name;
					}

					#set history object
					$self->{_history} = Shutter::Screenshot::History->new($self->{_sc}, 
							$self->{_root}, 
							$self->{_c}{'cw'}{'x'}, 
							$self->{_c}{'cw'}{'y'},
							$self->{_c}{'cw'}{'width'},
							$self->{_c}{'cw'}{'height'},
							undef,
							$self->{_c}{'cw'}{'window'}->get_xid,
							$self->{_c}{'cw'}{'gdk_window'}->get_xid
					);

					$self->quit;
															
				#MOTION-NOTIFY											
				} elsif ( $event->type eq 'motion-notify' ) {
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_sc}->get_debug );
					
					#user selects window or section
					$self->select_window($event, $active_workspace);

				} else {
					Gtk2->main_do_event($event);
				}
			}
		);
		
		Gtk2->main;
		
	#pointer not grabbed	
	} else {    
		
		$output = 0;

		my ( $xp, $yp, $wp, $hp, $xc, $yc, $wc, $hc ) = (0, 0, 0, 0, 0, 0, 0, 0);

		if ( ( $self->{_mode} eq "window" || $self->{_mode} eq "tray_window" ||  $self->{_mode} eq "awindow"  || $self->{_mode} eq "tray_awindow" ) ) {

			#and select current parent window
			my ($wnck_window, $gdk_window) = $self->find_active_window;
			
			if(defined $wnck_window && $wnck_window && defined $gdk_window && $gdk_window){

				#get_size of it
				( $xc, $yc, $wc, $hc ) = $self->get_window_size($wnck_window, $gdk_window, $self->{_include_border}, TRUE);
				( $xp, $yp, $wp, $hp ) = $self->get_window_size($wnck_window, $gdk_window, $self->{_include_border});
			
				$self->{_c}{'cw'}{'window'}     = $wnck_window;
				$self->{_c}{'cw'}{'gdk_window'} = $gdk_window;
				$self->{_c}{'cw'}{'x'}          = $xp;
				$self->{_c}{'cw'}{'y'}          = $yp;
				$self->{_c}{'cw'}{'width'}      = $wp;
				$self->{_c}{'cw'}{'height'}     = $hp;
				$self->{_c}{'cw'}{'is_parent'}  = TRUE;
			
			}

		}elsif ( ( $self->{_mode} eq "menu" || $self->{_mode} eq "tray_menu" ) ) {

			#and select current menu
			$self->find_region_for_window_type( $self->{_root}->XWINDOW, 'menu' );

			#no window with type_hint eq 'menu' detected
			unless (defined $self->{_c}{'cw'}{'window_region'}){
				if($self->{_ignore_type}){
					warn "WARNING: No window with type hint 'menu' detected -> window type hint will be ignored, because workaround is enabled\n";
					$self->find_region_for_window_type( $self->{_root}->XWINDOW );
				}else{
					return 2;
				}
			}

		}elsif ( ( $self->{_mode} eq "tooltip" || $self->{_mode} eq "tray_tooltip" ) ) {
			
			#and select current tooltip
			$self->find_region_for_window_type( $self->{_root}->XWINDOW, 'tooltip' );

			#no window with type_hint eq 'tooltip' detected
			unless (defined $self->{_c}{'cw'}{'window_region'}){
				if($self->{_ignore_type}){
					warn "WARNING: No window with type hint 'tooltip' detected -> window type hint will be ignored, because workaround is enabled\n";
					$self->find_region_for_window_type( $self->{_root}->XWINDOW );
				}else{
					return 2;
				}
			}

		#looking for a section of a window?
		#keep current window in mind and search for children
		}elsif ( ( $self->{_mode} eq "section" || $self->{_mode} eq "tray_section" ) ) {

			#mark as selected parent window
			$self->{_c}{'ws'} = $self->{_root};	

			#and select current subwindow
			$self->select_window($initevent);
		
		}	

		my ($output_new, $l_cropped, $r_cropped, $t_cropped, $b_cropped) = 
			$self->get_pixbuf_from_drawable(
				$self->{_root},
				$self->{_c}{'cw'}{'x'},
				$self->{_c}{'cw'}{'y'},
				$self->{_c}{'cw'}{'width'},
				$self->{_c}{'cw'}{'height'},
				$self->{_c}{'cw'}{'window_region'}
			);

		#save return value to current $output variable 
		#-> ugly but fastest and safest solution now
		$output = $output_new;

		#respect rounded corners of wm decorations 
		#(metacity for example - does not work with compiz currently)
		#only if toplevel window was selected
		if ( ( $self->{_mode} eq "window" || $self->{_mode} eq "tray_window" ||  $self->{_mode} eq "awindow"  || $self->{_mode} eq "tray_awindow" ) ) {
			if($self->{_include_border}){
				my $xid = $self->{_c}{ 'cw' }{ 'gdk_window' }->get_xid;
				#do not try this for child windows
				foreach my $win ($self->{_wnck_screen}->get_windows){
					if($win->get_xid == $xid){
						$output = $self->get_shape($xid, $output, $l_cropped, $r_cropped, $t_cropped, $b_cropped);				
						last;
					}
				}
			}
		}

		#restore window size when autoresizing was used
		if($self->{_mode} eq "window" || $self->{_mode} eq "tray_window" || $self->{_mode} eq "awindow" || $self->{_mode} eq "tray_awindow"){
			if(defined $self->{_windowresize} && $self->{_windowresize}) {
				if($wc != $wp || $hc != $hp){
					if($self->{_include_border}){
						$self->{_c}{'cw'}{'window'}->set_geometry ('current', [qw/width height/], $xc, $yc, $wc, $hc);		
					}else{
						$self->{_c}{'cw'}{'gdk_window'}->resize ($wc, $hc);
					}
				}
			}
		}

		#set name of the captured window
		#e.g. for use in wildcards
		my $d = $self->{_sc}->get_gettext;
		
		if ( ( $self->{_mode} eq "window" || $self->{_mode} eq "tray_window" ||  $self->{_mode} eq "awindow"  || $self->{_mode} eq "tray_awindow" ) ) {

			if($output =~ /Gtk2/ && defined $self->{_c}{'cw'}{'window'}){
				$self->{_action_name} = $self->{_c}{'cw'}{'window'}->get_name;
			}

		}elsif ( ( $self->{_mode} eq "section" || $self->{_mode} eq "tray_section" ) ) {

			if($output =~ /Gtk2/ && defined $self->{_c}{'cw'}{'window'}){
				$self->{_action_name} = $self->{_action_name} = $self->{_c}{'cw'}{'window'}->get_name;
			}

		}elsif ( ( $self->{_mode} eq "menu" || $self->{_mode} eq "tray_menu" ) ) {

			if($output =~ /Gtk2/){
				$self->{_action_name} = $d->get( "Menu" );
			}

		}elsif ( ( $self->{_mode} eq "tooltip" || $self->{_mode} eq "tray_tooltip" ) ) {

			if($output =~ /Gtk2/){
				$self->{_action_name} = $d->get( "Tooltip" );
			}
		
		}

		if(defined $self->{_c}{'cw'}{'window'} && $self->{_c}{'cw'}{'gdk_window'}){
	
			#set history object
			$self->{_history} = Shutter::Screenshot::History->new($self->{_sc}, 
				$self->{_root},
				$self->{_c}{'cw'}{'x'},
				$self->{_c}{'cw'}{'y'},
				$self->{_c}{'cw'}{'width'},
				$self->{_c}{'cw'}{'height'},
				$self->{_c}{'cw'}{'window_region'},
				$self->{_c}{'cw'}{'window'}->get_xid,
				$self->{_c}{'cw'}{'gdk_window'}->get_xid
			);
		
		}else{

			#set history object
			$self->{_history} = Shutter::Screenshot::History->new($self->{_sc}, 
				$self->{_root},
				$self->{_c}{'cw'}{'x'},
				$self->{_c}{'cw'}{'y'},
				$self->{_c}{'cw'}{'width'},
				$self->{_c}{'cw'}{'height'},
				$self->{_c}{'cw'}{'window_region'},
			);
			
		}
		
	}
	return $output;
}

sub get_mode {
	my $self = shift;
	return $self->{_mode};
}

sub redo_capture {
	my $self = shift;
	my $output = 3;
	
	if(defined $self->{_history}){
		my ($last_drawable, $lxp, $lyp, $lwp, $lhp, $lregion, $wxid, $gxid) = $self->{_history}->get_last_capture;
		
		if(defined $gxid && defined $wxid){
		
			#create windows
			my $gdk_window  = Gtk2::Gdk::Window->foreign_new( $gxid );
			my $wnck_window = Gnome2::Wnck::Window->get( $wxid );
			
			if(defined $gdk_window && defined $wnck_window){
	
				#store size
				my ( $xp, $yp, $wp, $hp, $xc, $yc, $wc, $hc ) = (0, 0, 0, 0, 0, 0, 0, 0);
	
				if($self->{_mode} eq "section" || $self->{_mode} eq "tray_section" ){
	
					( $xp, $yp, $wp, $hp ) = $gdk_window->get_geometry;
					( $xp, $yp ) = $gdk_window->get_origin;
					
					#find parent window
					my $pxid = $self->find_wm_window($gxid);
					my $parent = Gtk2::Gdk::Window->foreign_new( $pxid );
					if(defined $parent && $parent){
						#and focus parent window (maybe it is hidden)
						$parent->focus(Gtk2->get_current_event_time);
						Gtk2::Gdk->flush;
					}
									
				}elsif($self->{_mode} eq "window" || $self->{_mode} eq "tray_window" || $self->{_mode} eq "awindow" || $self->{_mode} eq "tray_awindow"){
	
					#get_size of it
					( $xc, $yc, $wc, $hc ) = $self->get_window_size($wnck_window, $gdk_window, $self->{_include_border}, TRUE);
					( $xp, $yp, $wp, $hp ) = $self->get_window_size($wnck_window, $gdk_window, $self->{_include_border});
								
				}
	
				#focus selected window (maybe it is hidden)
				$gdk_window->focus(Gtk2->get_current_event_time);
				Gtk2::Gdk->flush;	

				#A short timeout to give the server a chance to
				#redraw the area
				Glib::Timeout->add ($self->{_hide_time}, sub{		
					Gtk2->main_quit;
					return FALSE;	
				});	
				Gtk2->main();
		
				my ($output_new, $l_cropped, $r_cropped, $t_cropped, $b_cropped) = $self->get_pixbuf_from_drawable($self->{_root}, $xp, $yp, $wp, $hp);

				#save return value to current $output variable 
				#-> ugly but fastest and safest solution now				
				$output = $output_new;

				if($self->{_mode} eq "window" || $self->{_mode} eq "tray_window" || $self->{_mode} eq "awindow" || $self->{_mode} eq "tray_awindow"){
					if($self->{_include_border}){
						$output = $self->get_shape($gxid, $output, $l_cropped, $r_cropped, $t_cropped, $b_cropped);
					}
				}
				
				#restore window size when autoresizing was used
				if($self->{_mode} eq "window" || $self->{_mode} eq "tray_window" || $self->{_mode} eq "awindow" || $self->{_mode} eq "tray_awindow"){
					if(defined $self->{_windowresize} && $self->{_windowresize}) {
						if($wc != $wp || $hc != $hp){
							if($self->{_include_border}){
								$wnck_window->set_geometry ('current', [qw/width height/], $xc, $yc, $wc, $hc);		
							}else{
								$gdk_window->resize ($wc, $hc);
							}
						}
					}
				}

				$self->quit_eventh_only;
					
			}else{
				warn "WARNING: Could not get window with id $gxid\n";
				$output = 4;
			}
		
		#no xid
		}else{
			($output) = $self->get_pixbuf_from_drawable($self->{_history}->get_last_capture);
		}

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
	
	$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );
	Gtk2::Gdk->flush;

}

sub quit_eventh_only {
	my $self = shift;
	
	$self->ungrab_pointer_and_keyboard( FALSE, TRUE, FALSE );
	Gtk2::Gdk->flush;

}

1;
