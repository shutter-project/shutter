###################################################
#
#  Copyright (C) Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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
use utf8;
use strict;
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
	$self->{_x11} 				= shift;
	$self->{_include_border} 	= shift;
	$self->{_xid}  				= shift;    #only used by window_by_xid, undef this when selecting a window
	$self->{_mode} 				= shift;
	$self->{_is_in_tray}      	= shift;

	#main window
	$self->{_main_gtk_window} = $self->{_gc}->get_mainwindow;

	#only used by window_select
	$self->{_children} = {};

	bless $self, $class;
	return $self;
}

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

sub query_children {
	my ( $self,  $xwindow, $xparent ) = @_;
	my ( $qroot, $qparent, @qkids )   = $self->{_x11}->QueryTree($xwindow);
	foreach (@qkids) {

		my $gdk_window = Gtk2::Gdk::Window->foreign_new($_);
		if ( defined $gdk_window ) {

			#window needs to be viewable and visible
			next unless $gdk_window->is_visible;
			next unless $gdk_window->is_viewable;

			#min size
			my ( $xp, $yp, $widthp, $heightp, $depthp ) = $gdk_window->get_geometry;
			( $xp, $yp ) = $gdk_window->get_origin;
			next if ( $widthp * $heightp < 4 );

			#check if $gdk_window is already in hash
			my $dub = FALSE;
			foreach my $checkchild ( keys %{ $self->{_children}{$xparent} } ) {
				$dub = TRUE
					if $self->{_children}{$xparent}{$checkchild}{'gdk_window'} == $gdk_window;
			}
			unless ( $dub == TRUE ) {
				$self->{_children}{$xparent}{$_}{'gdk_window'} = $gdk_window;
				$self->{_children}{$xparent}{$_}{'x'}          = $xp;
				$self->{_children}{$xparent}{$_}{'y'}          = $yp;
				$self->{_children}{$xparent}{$_}{'width'}      = $widthp;
				$self->{_children}{$xparent}{$_}{'height'}     = $heightp;
				$self->{_children}{$xparent}{$_}{'size'}       = $widthp * $heightp;

				#check next depth
				$self->query_children( $gdk_window->XWINDOW, $xparent );
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

	print "$l_cropped, $r_cropped, $t_cropped, $b_cropped cropped\n" if $self->{_gc}->get_debug;

	print "Calculating window shape\n" if $self->{_gc}->get_debug;

	my ($ordering, @r) = $self->{_x11}->ShapeGetRectangles($self->find_wm_window($xid), 'Bounding');
	
	#do nothing if there are no
	#shape rectangles (or only one)
	return $orig if scalar @r <= 1;
							
	#create a region from the bounding rectangles
	my $bregion = Gtk2::Gdk::Region->new;					
	foreach my $r (@r){
		my @rect =  @{$r};
		
		#adjust rectanged if window is only partially visible
		if($l_cropped){
			$rect[2] -= $l_cropped - $rect[0]; 
			$rect[0] = 0;
		}
		
		print "Current $rect[0],$rect[1],$rect[2],$rect[3]\n" if $self->{_gc}->get_debug;
		$bregion->union_with_rect(Gtk2::Gdk::Rectangle->new ($rect[0],$rect[1],$rect[2],$rect[3]));	
	}

	#create target pixbuf with dimensions if selected/current window
	my $target = Gtk2::Gdk::Pixbuf->new ($orig->get_colorspace, TRUE, 8, $orig->get_width, $orig->get_height);
	#whole pixbuf is transparent
	$target->fill('0x00000000');
	
	#copy all rectangles of bounding region to the target pixbuf
	foreach my $r($bregion->get_rectangles){
		print $r->x." ".$r->y." ".$r->width." ".$r->height."\n" if $self->{_gc}->get_debug;
		
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

	my ( $xp, $yp, $widthp, $heightp ) = $wnck_window->get_geometry;
	if ($border) {

		#find wm_window
		my $wm_window
			= Gtk2::Gdk::Window->foreign_new( $self->find_wm_window( $wnck_window->get_xid ) );
		$gdk_window = $wm_window if $wm_window;

		#get_size of it
		my ( $xp2, $yp2, $widthp2, $heightp2 ) = $gdk_window->get_geometry;
		( $xp2, $yp2 ) = $gdk_window->get_origin;

		#check the correct rect
		if (   $xp2 + $widthp2 > $xp + $widthp
			&& $yp2 + $heightp2 > $yp + $heightp )
		{
			( $xp, $yp, $widthp, $heightp ) = ( $xp2, $yp2, $widthp2, $heightp2 );
		}

	} else {
		( $widthp, $heightp ) = $gdk_window->get_size;
		( $xp,     $yp )      = $gdk_window->get_origin;
	}

	return ( $xp, $yp, $widthp, $heightp );
}

sub window_by_xid {
	my $self = shift;

	my $gdk_window  = Gtk2::Gdk::Window->foreign_new( $self->{_xid} );
	my $wnck_window = Gnome2::Wnck::Window->get( $self->{_xid} );

	my ( $xp, $yp, $widthp, $heightp )
		= $self->get_window_size( $wnck_window, $gdk_window, $self->{_include_border} );

	#focus selected window (maybe it is hidden)
	$gdk_window->focus(time);
	Gtk2::Gdk->flush;
	sleep 1 if $self->{_delay} < 1;

	my ($output, $l_cropped, $r_cropped, $t_cropped, $b_cropped) = $self->get_pixbuf_from_drawable( $self->{_root}, $xp, $yp, $widthp, $heightp,
		$self->{_include_cursor},
		$self->{_delay} );

	#respect rounded corners of wm decorations (metacity for example - does not work with compiz currently)	
	if($self->{_x11}{ext_shape} && $self->{_include_border}){
		$output = $self->get_shape($self->{_xid}, $output, $l_cropped, $r_cropped, $t_cropped, $b_cropped);				
	}

	return $output;

}

sub window_select {
	my $self = shift;

	#return value
	my $output = 5;

	#get all the windows
	my @wnck_windows = $self->{_wnck_screen}->get_windows;

	#...and window "pick" cursor
	my $hand_cursor2 = Gtk2::Gdk::Cursor->new('GDK_HAND2');

	#define graphics context
	my $cr = undef;
	my $white = Gtk2::Gdk::Color->new( 65535, 65535, 65535 );
	my $black = Gtk2::Gdk::Color->new( 0,     0,     0 );
	my $gc = Gtk2::Gdk::GC->new( $self->{_root}, undef );
	$gc->set_line_attributes( 5, 'solid', 'round', 'round' );
	$gc->set_rgb_bg_color($black);
	$gc->set_rgb_fg_color($white);
	$gc->set_subwindow('include-inferiors');
	$gc->set_function('xor');

	my $grab_counter = 0;
	while ( !Gtk2::Gdk->pointer_is_grabbed && $grab_counter < 100 ) {
		Gtk2::Gdk->pointer_grab(
			$self->{_root},
			0,
			[   qw/
					pointer-motion-mask
					button-release-mask/
			],
			undef,
			$hand_cursor2,
			Gtk2->get_current_event_time
		);
		Gtk2::Gdk->keyboard_grab( $self->{_root}, 0, Gtk2->get_current_event_time );
		$grab_counter++;
	}

	if ( Gtk2::Gdk->pointer_is_grabbed ) {

		$self->{_children} = ();
		my $drawable        = undef;
		my $window_selected = FALSE;
		$self->{_children}{'last_win'}{'gdk_window'} = 0;
		my $active_workspace = $self->{_wnck_screen}->get_active_workspace;

		#something went wrong here, no active workspace detected
		unless ( $active_workspace ) {
			$self->ungrab_pointer_and_keyboard( FALSE, FALSE, FALSE );
			$output = 0;
			return $output;
		}

		Gtk2::Gdk::Event->handler_set(
			sub {
				my ( $event, $data ) = @_;
				return FALSE unless defined $event;

				#handle key events here
				if ( $event->type eq 'key-press' ) {
					next unless defined $event->keyval;
					if ( $event->keyval == $Gtk2::Gdk::Keysyms{Escape} ) {

						#clear the last rectangle
						if ( defined $self->{_children}{'last_win'} ) {
							$self->{_root}->draw_rectangle(
								$gc,
								0,
								$self->{_children}{'last_win'}{'x'},
								$self->{_children}{'last_win'}{'y'},
								$self->{_children}{'last_win'}{'width'},
								$self->{_children}{'last_win'}{'height'}
							);
							
						}

						$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );

						$output = 5;
					}
				} elsif ( $event->type eq 'button-release' ) {
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_gc}->get_debug );

					#looking for a section of a window?
					#keep current window in mind and search for children
					if ( ( $self->{_mode} eq "section" || $self->{_mode} eq "tray_section" )
						&& !$window_selected )
					{

						#something went wrong here, no window on screen detected
						unless ( $self->{_children}{'last_win'}{'gdk_window'} ) {
							$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );
							$output = "";
							return $output;
						}

						$self->query_children(
							$self->{_children}{'last_win'}{'gdk_window'}->XWINDOW,
							$self->{_children}{'last_win'}{'gdk_window'}->XWINDOW
						);

						#focus selected window (maybe it is hidden)
						$self->{_children}{'last_win'}{'gdk_window'}->focus(time);
						Gtk2::Gdk->flush;
						$window_selected
							= $self->{_children}{'curr_win'}{'gdk_window'};

						return TRUE;
					}

					$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );

					#clear the last rectangle
					if ( defined $self->{_children}{'last_win'}
						&& $self->{_children}{'last_win'}{'gdk_window'} )
					{
						$self->{_root}->draw_rectangle(
							$gc,
							0,
							$self->{_children}{'last_win'}{'x'},
							$self->{_children}{'last_win'}{'y'},
							$self->{_children}{'last_win'}{'width'},
							$self->{_children}{'last_win'}{'height'}
						);

						#focus selected window (maybe it is hidden)
						$self->{_children}{'last_win'}{'gdk_window'}->focus(time);
						Gtk2::Gdk->flush;
						sleep 1 if $self->{_delay} < 1;
						
						my ($output_new, $l_cropped, $r_cropped, $t_cropped, $b_cropped) = $self->get_pixbuf_from_drawable(
							$self->{_root},
							$self->{_children}{'curr_win'}{'x'},
							$self->{_children}{'curr_win'}{'y'},
							$self->{_children}{'curr_win'}{'width'},
							$self->{_children}{'curr_win'}{'height'},
							$self->{_include_cursor},
							$self->{_delay}
						);
						
						#save return value to current $output variable 
						#-> ugly but fastest and safest solution now
						$output = $output_new;						 
						
						#respect rounded corners of wm decorations (metacity for example - does not work with compiz currently)	
						if($self->{_x11}{ext_shape} && $self->{_include_border}){
							my $xid = $self->{_children}{ 'curr_win' }{ 'gdk_window' }->get_xid;
							#do not try this for child windows
							foreach my $win ($self->{_wnck_screen}->get_windows){
								if($win->get_xid == $xid){
									$output = $self->get_shape($xid, $output, $l_cropped, $r_cropped, $t_cropped, $b_cropped);				
								}
							}
						}

					} else {
						$output = 0;
					}
				} elsif ( $event->type eq 'motion-notify' ) {
					print "Type: " . $event->type . "\n"
						if ( defined $event && $self->{_gc}->get_debug );

					my $min_x = $self->{_root}->{w};
					my $min_y = $self->{_root}->{h};

					#if there is no window already selected
					unless ($window_selected) {
						print "Searching for window...\n"
							if $self->{_gc}->get_debug;
						foreach my $curr_window (@wnck_windows) {
							$drawable = Gtk2::Gdk::Window->foreign_new( $curr_window->get_xid );
							next unless defined $drawable;

							print "Do not detect gscrot main window...\n"
								if $self->{_gc}->get_debug;

							#do not detect gscrot window when it is hidden
							if (   $self->{_main_gtk_window}->window
								&& $self->{_is_in_tray} )
							{
								next
									if ( $curr_window->get_xid
									== $self->{_main_gtk_window}->window->get_xid );
							}

							my ( $xp, $yp, $widthp, $heightp )
								= $self->get_window_size( $curr_window, $drawable,
								$self->{_include_border} );

							print "Create region of window...\n"
								if $self->{_gc}->get_debug;
							my $window_region = Gtk2::Gdk::Region->rectangle(
								Gtk2::Gdk::Rectangle->new( $xp, $yp, $widthp, $heightp ) );

							print "determine if window fits on screen...\n"
								if $self->{_gc}->get_debug;
							if ($curr_window->is_visible_on_workspace(
									$active_workspace
								)
								&& $window_region->point_in( $event->x, $event->y )
								)
							{
								print "Parent X: $xp, Y: $yp, Width: $widthp, Height: $heightp\n"
									if $self->{_gc}->get_debug;
								$self->{_children}{'curr_win'}{'window'}     = $curr_window;
								$self->{_children}{'curr_win'}{'gdk_window'} = $drawable;
								$self->{_children}{'curr_win'}{'x'}          = $xp;
								$self->{_children}{'curr_win'}{'y'}          = $yp;
								$self->{_children}{'curr_win'}{'width'}      = $widthp;
								$self->{_children}{'curr_win'}{'height'}     = $heightp;
								$min_x                                       = $xp + $widthp;
								$min_y                                       = $yp + $heightp;

							}

						}    #end if toplevel window loop

						#something went wrong here, no window on screen detected
						unless ( $self->{_children}{'curr_win'}{'window'} ) {
							$self->ungrab_pointer_and_keyboard( FALSE, TRUE, TRUE );
							$output = "";
							return $output;
						}

						#window selected, search for children now
					} elsif ( ( $self->{_mode} eq "section" || $self->{_mode} eq "tray_section" )
						&& $window_selected )
					{
						print "Searching for children now...\n"
							if $self->{_gc}->get_debug;

						#selected window is parent
						my $curr_parent = $window_selected->XWINDOW;
						foreach my $curr_child ( keys %{ $self->{_children}{$curr_parent} } ) {
							next unless defined $curr_child;
							print "Child Current Event x: " . $event->x . ", y: " . $event->y . "\n"
								if $self->{_gc}->get_debug;

							my $section_region = Gtk2::Gdk::Region->rectangle(
								Gtk2::Gdk::Rectangle->new(
									$self->{_children}{$curr_parent}{$curr_child}{'x'},
									$self->{_children}{$curr_parent}{$curr_child}{'y'},
									$self->{_children}{$curr_parent}{$curr_child}{'width'},
									$self->{_children}{$curr_parent}{$curr_child}{'height'}
								)
							);

							if ($section_region->point_in( $event->x, $event->y )
								&&

								(   (     $self->{_children}{$curr_parent}{$curr_child}{'x'}
										+ $self->{_children}{$curr_parent}{$curr_child}{'width'}
									) * (
										$self->{_children}{$curr_parent}{$curr_child}{'y'}
											+ $self->{_children}{$curr_parent}{$curr_child}
											{'height'}
									) <= $min_x * $min_y
								)

								)
							{
								$self->{_children}{'curr_win'}{'gdk_window'}
									= $self->{_children}{$curr_parent}{$curr_child}{'gdk_window'};
								$self->{_children}{'curr_win'}{'x'}
									= $self->{_children}{$curr_parent}{$curr_child}{'x'};
								$self->{_children}{'curr_win'}{'y'}
									= $self->{_children}{$curr_parent}{$curr_child}{'y'};
								$self->{_children}{'curr_win'}{'width'}
									= $self->{_children}{$curr_parent}{$curr_child}{'width'};
								$self->{_children}{'curr_win'}{'height'}
									= $self->{_children}{$curr_parent}{$curr_child}{'height'};
								$min_x = $self->{_children}{$curr_parent}{$curr_child}{'x'}
									+ $self->{_children}{$curr_parent}{$curr_child}{'width'};
								$min_y = $self->{_children}{$curr_parent}{$curr_child}{'y'}
									+ $self->{_children}{$curr_parent}{$curr_child}{'height'};
							}
						}
					}    #endif search for children

					#draw rect if needed
					if ( $self->{_children}{'last_win'}{'gdk_window'} ne
						$self->{_children}{'curr_win'}{'gdk_window'} )
					{

						#clear last rectangle
						if ( $self->{_children}{'last_win'}{'gdk_window'} ) {
							$self->{_root}->draw_rectangle(
								$gc,
								0,
								$self->{_children}{'last_win'}{'x'},
								$self->{_children}{'last_win'}{'y'},
								$self->{_children}{'last_win'}{'width'},
								$self->{_children}{'last_win'}{'height'}
							);
							Gtk2::Gdk->flush;
						}

						#draw new rectangle for current window
						if ( $self->{_children}{'curr_win'}{'gdk_window'} ) {
							$self->{_root}->draw_rectangle(
								$gc,
								0,
								$self->{_children}{'curr_win'}{'x'} - 3,
								$self->{_children}{'curr_win'}{'y'} - 3,
								$self->{_children}{'curr_win'}{'width'} + 5,
								$self->{_children}{'curr_win'}{'height'} + 5
							);
						}

						$self->{_children}{'last_win'}{'window'}
							= $self->{_children}{'curr_win'}{'window'};
						$self->{_children}{'last_win'}{'gdk_window'}
							= $self->{_children}{'curr_win'}{'gdk_window'};
						$self->{_children}{'last_win'}{'x'}
							= $self->{_children}{'curr_win'}{'x'} - 3;
						$self->{_children}{'last_win'}{'y'}
							= $self->{_children}{'curr_win'}{'y'} - 3;
						$self->{_children}{'last_win'}{'width'}
							= $self->{_children}{'curr_win'}{'width'} + 5;
						$self->{_children}{'last_win'}{'height'}
							= $self->{_children}{'curr_win'}{'height'} + 5;

					}
				} else {
					Gtk2->main_do_event($event);
				}
			},
			'window'
		);
		Gtk2->main;
	} else {    #pointer not grabbed

		$self->ungrab_pointer_and_keyboard( FALSE, FALSE, FALSE );
		$output = 0;
	}
	return $output;
}

1;
