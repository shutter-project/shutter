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

package Shutter::Screenshot::Window;

#modules
#--------------------------------------
use SelfLoader;
use utf8;
use strict;
use warnings;

use Shutter::Screenshot::Main;
use Data::Dumper;
our @ISA = qw(Shutter::Screenshot::Main);

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

sub new {
	my $class = shift;

	#call constructor of super class (shutter_common, include_cursor, delay)
	my $self = $class->SUPER::new( shift, shift, shift );

	#get params
	$self->{_include_border} 	= shift;
	$self->{_xid}  				= shift;    #only used by window_by_xid, undef this when selecting a window
	$self->{_mode} 				= shift;
	$self->{_is_hidden}      	= shift;

	#X11 protocol and XSHAPE ext
	require X11::Protocol;

	$self->{_x11} 				= X11::Protocol->new( $ENV{ 'DISPLAY' } );
	$self->{_x11}{ext_shape}	= $self->{_x11}->init_extension('SHAPE');

	#main window
	$self->{_main_gtk_window} 	= $self->{_sc}->get_mainwindow;

	#only used when selecting a window, undef this when selecting a window
	unless(defined $self->{_xid}){
		
		#higlighter (borderless gtk window)
		$self->{_highlighter} = Gtk2::Window->new('popup');
		$self->{_highlighter}->set_colormap($self->{_main_gtk_window}->get_screen->get_rgba_colormap);
	
		$self->{_highlighter}->double_buffered (FALSE);
	    $self->{_highlighter}->set_app_paintable(TRUE);
	    $self->{_highlighter}->set_decorated(FALSE);
		$self->{_highlighter}->set_skip_taskbar_hint(TRUE);
		$self->{_highlighter}->set_skip_pager_hint(TRUE);	    
	    $self->{_highlighter}->set_keep_above(TRUE);
	    $self->{_highlighter}->set_accept_focus(FALSE);
	    $self->{_highlighter}->set_sensitive(FALSE);
		$self->{_highlighter}->signal_connect('expose-event' => sub{
			if(defined $self->{_c}{'cw'}{'gdk_window'} && defined $self->{_c}{'cw'}{'window'}){
												
				#window size
				my ($w, $h) = $self->{_highlighter}->get_size;
				
				#create cairo context
				my $cr = Gtk2::Gdk::Cairo::Context->create ($self->{_highlighter}->window);
					
				#Parent window with text and icon
				my ( $lw, $lh ) = (0,0);			
				if($self->{_c}{'cw'}{'is_parent'}){

					my $layout = Gtk2::Pango::Cairo::create_layout($cr);
					$layout->set_width( $w * Gtk2::Pango->scale );
					$layout->set_alignment('center');
					$layout->set_wrap('word');
		
					#obtain current colors and font_desc from the main window
				    my $style 		= $self->{_main_gtk_window}->get_style;
					my $sel_bg 		= $style->bg('selected');
					my $sel_tx 		= $style->text('selected');
					my $font_fam 	= $style->font_desc->get_family;
					my $font_size 	= $style->font_desc->get_size;
		
					my $mon 	= $self->get_current_monitor;
					my $size 	= int( $mon->width * 0.007 );
					my $size2 	= int( $mon->width * 0.005 );
		
					my $text = $self->{_c}{'cw'}{'window'}->get_name;
					utf8::decode $text;
					
					my $sec_text =  $self->{_c}{'cw'}{'width'} . "x" . $self->{_c}{'cw'}{'height'};
		
					#white font-color	
					$layout->set_markup("<span font_desc=\"$font_fam $size\" weight=\"bold\" foreground=\"#FFFFFF\">$text</span><span font_desc=\"$font_fam $size2\" foreground=\"#FFFFFF\"> ($sec_text)</span>");
		
					#fill window
					$cr->set_operator('source');
					#~ my $lg = Cairo::LinearGradient->create (0, 50, 0, 0);
					#~ $lg->add_color_stop_rgba(0, $sel_tx->red / 257 / 255, $sel_tx->green / 257 / 255, $sel_tx->blue / 257 / 255, 0.85);
					#~ $lg->add_color_stop_rgba(1, $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255, 0.85);
					$cr->set_source_rgba( $sel_bg->red / 257 / 255, $sel_bg->green / 257 / 255, $sel_bg->blue / 257 / 255, 0.85 );
					#~ $cr->set_source($lg);
					$cr->paint;
					
					#app icon
					$cr->set_operator('over');
					my $pixbuf = $self->{_c}{'cw'}{'window'}->get_icon;
					Gtk2::Gdk::Cairo::Context::set_source_pixbuf( $cr, $pixbuf, 3, 2 );
					$cr->paint;

					#create small black frame
					$cr->set_source_rgb( 0, 0, 0 );
					#~ $cr->set_line_width(6);
					$cr->rectangle (0, 0, $w, $h);
					$cr->stroke;
	
					#draw the pango layout
					$cr->move_to( 0, 2 );
					Gtk2::Pango::Cairo::show_layout( $cr, $layout );	

					#get layout size
					( $lw, $lh ) = $layout->get_pixel_size;
					$lh = $pixbuf->get_height if $pixbuf->get_height > $lh;

				#child window with small black frame
				}else{
					#fill window black
					$cr->set_operator('source');
					$cr->set_source_rgb( 0, 0, 0 );
					$cr->paint;					
				}
				
				#shape the window						
				my $rectangle1 	 	= Gtk2::Gdk::Rectangle->new (0, 0, $w, $h);
				my $rectangle2 	 	= Gtk2::Gdk::Rectangle->new (3, $lh+3, $w-6, $h-$lh-6);
				my $shape_region1 	= Gtk2::Gdk::Region->rectangle ($rectangle1);
				my $shape_region2 	= Gtk2::Gdk::Region->rectangle ($rectangle2);
				$shape_region1->subtract($shape_region2);
				$self->{_highlighter}->window->shape_combine_region ($shape_region1, 0, 0);
						
				return FALSE;	
			}	
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

1;

__DATA__

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

sub query_c {
	my ( $self,  $xwindow, $xparent ) = @_;
	my ( $qroot, $qparent, @qkids )   = $self->{_x11}->QueryTree($xwindow);
	foreach (@qkids) {

		my $gdk_window = Gtk2::Gdk::Window->foreign_new($_);
		if ( defined $gdk_window ) {

			#window needs to be viewable and visible
			next unless $gdk_window->is_visible;
			next unless $gdk_window->is_viewable;

			#min size
			my ( $xp, $yp, $wp, $hp, $depthp ) = $gdk_window->get_geometry;
			( $xp, $yp ) = $gdk_window->get_origin;
			next if ( $wp * $hp < 4 );

			#check if $gdk_window is already in hash
			my $dub = FALSE;
			foreach my $checkchild ( keys %{ $self->{_c}{$xparent} } ) {
				$dub = TRUE
					if $self->{_c}{$xparent}{$checkchild}{'gdk_window'} == $gdk_window;
			}
			unless ( $dub == TRUE ) {
				$self->{_c}{$xparent}{$_}{'gdk_window'} = $gdk_window;
				$self->{_c}{$xparent}{$_}{'x'}          = $xp;
				$self->{_c}{$xparent}{$_}{'y'}          = $yp;
				$self->{_c}{$xparent}{$_}{'width'}      = $wp;
				$self->{_c}{$xparent}{$_}{'height'}     = $hp;
				$self->{_c}{$xparent}{$_}{'size'}       = $wp * $hp;

				#check next depth
				$self->query_c( $gdk_window->XWINDOW, $xparent );
			}
		}
	}
	return TRUE;
}

sub get_shape {
	my $self 		= shift;
	my $xid 		= shift;
	my $orig 		= shift;
	my $l_cropped 	= shift;
	my $r_cropped 	= shift;
	my $t_cropped 	= shift;
	my $b_cropped 	= shift;

	print "$l_cropped, $r_cropped, $t_cropped, $b_cropped cropped\n" if $self->{_sc}->get_debug;

	print "Calculating window shape\n" if $self->{_sc}->get_debug;

	my ($ordering, @r) = $self->{_x11}->ShapeGetRectangles($self->find_wm_window($xid), 'Bounding');
	
	#do nothing if there are no
	#shape rectangles (or only one)
	return $orig if scalar @r <= 1;
							
	#create a region from the bounding rectangles
	my $bregion = Gtk2::Gdk::Region->new;					
	foreach my $r (@r){
		my @rect =  @{$r};
		
		#adjust rectangle if window is only partially visible
		if($l_cropped){
			$rect[2] -= $l_cropped - $rect[0]; 
			$rect[0] = 0;
		}
		if($t_cropped){
			$rect[3] -= $t_cropped - $rect[1]; 
			$rect[1] = 0;
		}
		
		print "Current $rect[0],$rect[1],$rect[2],$rect[3]\n" if $self->{_sc}->get_debug;
		$bregion->union_with_rect(Gtk2::Gdk::Rectangle->new ($rect[0],$rect[1],$rect[2],$rect[3]));	
	}

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
		
		$orig->copy_area ($r->x, $r->y, $r->width, $r->height, $target, $r->x, $r->y);		
	}
	
	return $target;
}	

sub get_window_size {
	my ( $self, $wnck_window, $gdk_window, $border ) = @_;

	my ( $xp, $yp, $wp, $hp ) = $wnck_window->get_geometry;
	if ($border) {

		#~ #find wm_window
		#~ my $wm_window = Gtk2::Gdk::Window->foreign_new( $self->find_wm_window( $wnck_window->get_xid ) );
		#~ $gdk_window = $wm_window if $wm_window;

		#get_size of it
		my ( $xp2, $yp2, $wp2, $hp2 ) = $gdk_window->get_geometry;
		( $xp2, $yp2 ) = $gdk_window->get_origin;

		#check the correct rect
		if (   $xp2 + $wp2 > $xp + $wp && $yp2 + $hp2 > $yp + $hp ) {
			( $xp, $yp, $wp, $hp ) = ( $xp2, $yp2, $wp2, $hp2 );
		}

	} else {
		( $wp, $hp ) 	= $gdk_window->get_size;
		( $xp, $yp )	= $gdk_window->get_origin;
	}

	return ( $xp, $yp, $wp, $hp );
}

sub window_by_xid {
	my $self = shift;

	my $gdk_window  = Gtk2::Gdk::Window->foreign_new( $self->{_xid} );
	my $wnck_window = Gnome2::Wnck::Window->get( $self->{_xid} );

	my ( $xp, $yp, $wp, $hp ) = $self->get_window_size( $wnck_window, $gdk_window, $self->{_include_border} );

	#focus selected window (maybe it is hidden)
	$gdk_window->focus(time);
	Gtk2::Gdk->flush;

	my $output;
	#A short timeout to give the server a chance to
	#redraw the area
	Glib::Timeout->add (400, sub{
		
		my ($output_new, $l_cropped, $r_cropped, $t_cropped, $b_cropped) = $self->get_pixbuf_from_drawable( $self->{_root}, $xp, $yp, $wp, $hp);

		#save return value to current $output variable 
		#-> ugly but fastest and safest solution now
		$output = $output_new;	

		#respect rounded corners of wm decorations (metacity for example - does not work with compiz currently)	
		if($self->{_x11}{ext_shape} && $self->{_include_border}){
			$output = $self->get_shape($self->{_xid}, $output, $l_cropped, $r_cropped, $t_cropped, $b_cropped);				
		}

		#set name of the captured window
		#e.g. for use in wildcards
		$output->{'name'} = $wnck_window->get_name;
		$output->{'name'} =~ s/\//-/g;

		$self->quit;
		return FALSE;	
	});	

	Gtk2->main();

	return $output;
}

sub update_highlighter {
	my $self 	= shift;
	my $x		= shift;
	my $y		= shift;
	my $width	= shift;
	my $height	= shift;

	#Place window and resize it
	$self->{_highlighter}->move($x-3, $y-3);
	$self->{_highlighter}->resize($width+6, $height+6);

	#save last window objects
	$self->{_c}{'lw'}{'window'} 	= $self->{_c}{'cw'}{'window'};
	$self->{_c}{'lw'}{'gdk_window'} = $self->{_c}{'cw'}{'gdk_window'};

}

sub find_current_parent_window {
	my $self 				= shift;
	my $event 				= shift;
	my $active_workspace 	= shift;

	#get all the windows
	my @wnck_windows = $self->{_wnck_screen}->get_windows_stacked;
	
	print "Searching for window...\n" if $self->{_sc}->get_debug;
	
	foreach my $cwdow (@wnck_windows) {
		my $drawable = Gtk2::Gdk::Window->foreign_new( $cwdow->get_xid );
		next unless defined $drawable;

		print "Do not detect shutter main window...\n"
			if $self->{_sc}->get_debug;

		#do not detect shutter window when it is hidden
		if (   $self->{_main_gtk_window}->window
			&& $self->{_is_hidden} ) {
			next if ( $cwdow->get_xid == $self->{_main_gtk_window}->window->get_xid );
		}

		my ( $xp, $yp, $wp, $hp )
			= $self->get_window_size( $cwdow, $drawable,
			$self->{_include_border} );

		print "Create region of window...\n" if $self->{_sc}->get_debug;
		
		my $wr = Gtk2::Gdk::Region->rectangle(
			Gtk2::Gdk::Rectangle->new( $xp, $yp, $wp, $hp ) );

		print "Determine if window fits on screen... ".$event->x ." - ". $event->y."\n" if $self->{_sc}->get_debug;
		if ($cwdow->is_visible_on_workspace($active_workspace)
			&& $wr->point_in( $event->x, $event->y )
			&& $wp * $hp <= $self->{_min_size}) {
			
			print "Parent X: $xp, Y: $yp, Width: $wp, Height: $hp\n"
				if $self->{_sc}->get_debug;
			
			$self->{_c}{'cw'}{'window'}     = $cwdow;
			$self->{_c}{'cw'}{'gdk_window'} = $drawable;
			$self->{_c}{'cw'}{'x'}          = $xp;
			$self->{_c}{'cw'}{'y'}          = $yp;
			$self->{_c}{'cw'}{'width'}      = $wp;
			$self->{_c}{'cw'}{'height'}     = $hp;
			$self->{_c}{'cw'}{'is_parent'} 	= TRUE;
			$self->{_min_size}				= $wp * $hp;

		}

	}    #end if toplevel window loop	
			
}

sub find_current_child_window {
	my $self 	= shift;
	my $event 	= shift;

	print "Searching for children now...\n"
		if $self->{_sc}->get_debug;

	#selected window is parent
	my $cp = $self->{_c}{'ws'}->XWINDOW;
	
	foreach my $cc ( keys %{ $self->{_c}{$cp} } ) {
		next unless defined $cc;
		print "Child Current Event x: " . $event->x . ", y: " . $event->y . "\n"
			if $self->{_sc}->get_debug;

		my $sr = Gtk2::Gdk::Region->rectangle(
			Gtk2::Gdk::Rectangle->new(
				$self->{_c}{$cp}{$cc}{'x'},
				$self->{_c}{$cp}{$cc}{'y'},
				$self->{_c}{$cp}{$cc}{'width'},
				$self->{_c}{$cp}{$cc}{'height'}
			)
		);

		if ($sr->point_in( $event->x, $event->y )
			&&
			$self->{_c}{$cp}{$cc}{'width'} * 
			$self->{_c}{$cp}{$cc}{'height'} <= $self->{_min_size}

			)
		{
			$self->{_c}{'cw'}{'gdk_window'} = $self->{_c}{$cp}{$cc}{'gdk_window'};
			$self->{_c}{'cw'}{'x'} 			= $self->{_c}{$cp}{$cc}{'x'};
			$self->{_c}{'cw'}{'y'} 			= $self->{_c}{$cp}{$cc}{'y'};
			$self->{_c}{'cw'}{'width'} 		= $self->{_c}{$cp}{$cc}{'width'};
			$self->{_c}{'cw'}{'height'} 	= $self->{_c}{$cp}{$cc}{'height'};
			$self->{_c}{'cw'}{'is_parent'} 	= FALSE;
			$self->{_min_size} = $self->{_c}{$cp}{$cc}{'width'} * $self->{_c}{$cp}{$cc}{'height'};
				
		}
	}
}

sub select_window {
	my $self 				= shift;
	my $event				= shift;
	my $active_workspace	= shift;

	#root window size is minimum at startup
	$self->{_min_size} = $self->{_root}->{w} * $self->{_root}->{h};
			
	#if there is no window already selected
	unless ($self->{_c}{'ws'}) {

		$self->find_current_parent_window($event, $active_workspace);

	#parent window selected, search for children now
	}elsif ( 
		( $self->{_mode} eq "section" || $self->{_mode} eq "tray_section" ) 
		&& $self->{_c}{'ws'} ) {

		$self->find_current_child_window($event);				
	}

	#draw highlighter if needed
	if ( $self->{_c}{'lw'}{'gdk_window'} ne $self->{_c}{'cw'}{'gdk_window'} ) {

		$self->update_highlighter(
			$self->{_c}{'cw'}{'x'},
			$self->{_c}{'cw'}{'y'},
			$self->{_c}{'cw'}{'width'},
			$self->{_c}{'cw'}{'height'}
		);
	
	}
	
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

	my $grab_counter = 0;
	while ( !Gtk2::Gdk->pointer_is_grabbed && $grab_counter < 100 ) {
		Gtk2::Gdk->pointer_grab(
			$self->{_root},
			0,
			[   qw/
					pointer-motion-mask
					button-press-mask
					button-release-mask/
			],
			undef,
			Gtk2::Gdk::Cursor->new('GDK_HAND2'),
			Gtk2->get_current_event_time
		);
		Gtk2::Gdk->keyboard_grab( $self->{_root}, 0, Gtk2->get_current_event_time );
		$grab_counter++;
	}

	if ( Gtk2::Gdk->pointer_is_grabbed ) {

		#init
		$self->{_c} 					= ();
		$self->{_c}{'ws'} 				= undef;	
		$self->{_c}{'lw'}{'gdk_window'} = 0;

		#root window size is minimum at startup
		$self->{_min_size} 				= $self->{_root}->{w} * $self->{_root}->{h};
		$self->{_c}{'cw'}{'gdk_window'} = $self->{_root};
		$self->{_c}{'cw'}{'x'}          = $self->{_root}->{x};
		$self->{_c}{'cw'}{'y'}          = $self->{_root}->{y};
		$self->{_c}{'cw'}{'width'}      = $self->{_root}->{w};
		$self->{_c}{'cw'}{'height'}     = $self->{_root}->{h};

		#show highlighter window
		$self->{_highlighter}->show_all;
		
		Gtk2::Gdk::Event->handler_set(
			sub {
				my ( $event, $data ) = @_;
				return FALSE unless defined $event;

				#KEY-PRESS
				if ( $event->type eq 'key-press' ) {
					next unless defined $event->keyval;
					
					if ( $event->keyval == $Gtk2::Gdk::Keysyms{Escape} ) {

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
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_sc}->get_debug );

					if ( defined $self->{_c}{'lw'} && $self->{_c}{'lw'}{'gdk_window'} ) {

						#focus selected window (maybe it is hidden)
						$self->{_c}{'lw'}{'gdk_window'}->focus(time);
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
						
						#query all child windows
						$self->query_c(
							$self->{_c}{'lw'}{'gdk_window'}->XWINDOW,
							$self->{_c}{'lw'}{'gdk_window'}->XWINDOW
						);
												
						#mark as selected parent window
						$self->{_c}{'ws'} = $self->{_c}{'cw'}{'gdk_window'};	
						
						#we don't take the screenshot yet
						return TRUE;
					}

					#destroy highlighter window
					$self->{_highlighter}->destroy;

					#disable Event Handler
					$self->ungrab_pointer_and_keyboard( FALSE, TRUE, FALSE );
					
					#A short timeout to give the server a chance to
					#redraw the area
					Glib::Timeout->add (400, sub{
						
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
						if($self->{_x11}{ext_shape} && $self->{_include_border}){
							my $xid = $self->{_c}{ 'cw' }{ 'gdk_window' }->get_xid;
							#do not try this for child windows
							foreach my $win ($self->{_wnck_screen}->get_windows){
								if($win->get_xid == $xid){
									$output = $self->get_shape($xid, $output, $l_cropped, $r_cropped, $t_cropped, $b_cropped);				
									last;
								}
							}
						}

						#set name of the captured window
						#e.g. for use in wildcards
						$output->{'name'} = $self->{_c}{'cw'}{'window'}->get_name;	
						$output->{'name'} =~ s/\//-/g;

						$self->quit;
						return FALSE;	
					});	
															
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

		$self->ungrab_pointer_and_keyboard( FALSE, FALSE, FALSE );
		$output = 0;
	}
	return $output;
}

sub quit {
	my $self = shift;
	
	$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );
	Gtk2::Gdk->flush;

}

1;
