###################################################
#
#  Copyright (C) Mario Kemper 2008 <mario.kemper@googlemail.com>
#
#  This file is part of GScrot.
#
#  GScrot is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  GScrot is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with GScrot; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
###################################################

package GScrot::Draw;

our(@ISA, @EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(&fct_start_drawing);

#modules
#--------------------------------------
use utf8;
use strict;
use Exporter;
use Gnome2::Canvas;
#--------------------------------------

#define constants
#--------------------------------------
use constant TRUE                => 1;
use constant FALSE               => 0;

#--------------------------------------

#modal drawing window
my $drawing_pixbuf = undef;
my $drawing_window = undef;
my $colbut1 = undef;
my $draw_flag = 0;
my %lines;   # way to store multiple continuous lines
my $count = 0;
my $root = undef;
my $canvas = undef;
my $adj_zoom = undef;
my $sb_width = undef;

##################public subs##################
sub fct_start_drawing
{
	my ($filename, $w, $h, $filetype, $d) = @_;

	$drawing_window = Gtk2::Window->new ('toplevel');
	$drawing_window->set_title ($filename);
	$drawing_window->set_modal(1);
	$drawing_window->signal_connect('destroy', \&event_close_modal_window);
	$drawing_window->signal_connect('delete_event', sub { $drawing_window->destroy() });
	$drawing_window->set_resizable(0);

	$drawing_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file($filename);
	
	#basic packing
	my $drawing_vbox = Gtk2::VBox->new (FALSE, 0);
	$drawing_window->add ($drawing_vbox);
	my $drawing_statusbar = Gtk2::Statusbar->new;
	$drawing_vbox->pack_end($drawing_statusbar, FALSE, FALSE, 0 );

	my $scrolled_drawing_window = Gtk2::ScrolledWindow->new;
	my $ha1  = $scrolled_drawing_window->get_hadjustment;
	my $va1  = $scrolled_drawing_window->get_vadjustment;

	if($w < 560 && $h < 400){
		$scrolled_drawing_window->set_policy ('never', 'never');		
	}else{
		$scrolled_drawing_window->set_policy ('automatic', 'automatic');		
	}

	my $sw_width = $w;
	my $sw_height = $h;
	if ($w > 800){
		$sw_width = 800;
	}
	if ($h > 600){
		$sw_height = 600;
	}

	my $fixed_container = Gtk2::Fixed->new;
	$scrolled_drawing_window->set_size_request ($sw_width, $sw_height);
	$fixed_container->put($scrolled_drawing_window, 0, 0);
	
	$canvas = Gnome2::Canvas->new();
	$canvas->signal_connect (event => \&event_drawing_handler);
	my $white = Gtk2::Gdk::Color->new (0xFFFF,0xFFFF,0xFFFF);
	$canvas->modify_bg('normal',$white);
	$scrolled_drawing_window->add($canvas);

	# Width
	my $width_label = Gtk2::Label->new($d->get("Width:"));
	$sb_width = Gtk2::SpinButton->new_with_range(1, 20, 1);
	$sb_width->set_value(3);

	# create a color button
	my $col_label = Gtk2::Label->new($d->get("Color:"));
	my $red = Gtk2::Gdk::Color->new (0xFFFF,0,0);
	$colbut1 = Gtk2::ColorButton->new();
	$colbut1->set_color($red);

	# a Zoom
	my $zoom_label = Gtk2::Label->new($d->get("Zoom:"));
	$adj_zoom = Gtk2::Adjustment->new(1, 1, 5, 0.05, 0.5, 0);
	my $sb_zoom = Gtk2::SpinButton->new($adj_zoom, 0, 2);
	$adj_zoom->signal_connect("value-changed", \&event_zoom_changed, $canvas);
	$sb_zoom->set_size_request(60, -1);

	# a save button
	my $save_button = Gtk2::Button->new_from_stock ('gtk-save');

	$save_button->signal_connect(clicked => sub {

	my ($width, $height) = $canvas->get_size;
	my ($x,$y,$width1, $height1,$depth) = $canvas->window->get_geometry;		

	if($w < 400 && $h < 320){
		# create blank pixbuf to hold the stitched image
		my $gdkpixbuf_l = Gtk2::Gdk::Pixbuf->new ('rgb', 0, 8, $width, $height);
		$gdkpixbuf_l->get_from_drawable ($canvas->window, undef, 0, 0, 0, 0, $width, $height);		
		$gdkpixbuf_l->save ($filename, $filetype) if defined($gdkpixbuf_l); 
		$drawing_statusbar->push (1, $d->get("Drawing saved"));		
	}else{

		# a hack to slide the viewport and grab each viewable area
		my $cols = int($width/$width1);
		my $cmod = $width % $width1;
		my $rows = int($height/$height1);
		my $rmod = $height % $height1;

		# create large blank pixbuf to hold the stitched image
		my $gdkpixbuf_l = Gtk2::Gdk::Pixbuf->new ('rgb', 0, 8, $width, $height);

		# get full rows and cols ##################################
		for my $c (0 .. $cols - 1 ){    
			#slide viewport along
			$ha1->set_value( $c * $width1  );    
			for my $r (0..$rows - 1 ){
				$va1->set_value( $r * $height1  );    

				# create blank pixbuf to hold the small image
				my $gdkpixbuf = Gtk2::Gdk::Pixbuf->new ('rgb',0, 8,$width1, $height1);

				$gdkpixbuf->get_from_drawable ($canvas->window, undef, 0, 0, 0, 0, $width1, $height1);

				$gdkpixbuf->copy_area (0, 0, $width1, $height1, $gdkpixbuf_l, $c*$width1, $r*$height1);
			} #end rows
		} #end cols
		########################################################################

		# get bottom odd row except lower right corner#######################
		for my $c (0 .. $cols - 1 ){    
			$ha1->set_value( $c * $width1  );    
			$va1->set_value( $rows * $height1  );    

			my $gdkpixbuf = Gtk2::Gdk::Pixbuf->new ('rgb', 0,8,$width1,$rmod);

			$gdkpixbuf->get_from_drawable ($canvas->window, undef, 0, 0, 0, 0, $width1, $rmod);

			$gdkpixbuf->copy_area (0, 0, $width1, $rmod, $gdkpixbuf_l, $c*$width1, $rows*$height1);

		} #end odd row
		########################################################################

		# get right odd col except lower right corner ##########################
		for my $r (0 .. $rows - 1 ){    
			$ha1->set_value( $cols * $width1  );    
			$va1->set_value( $r * $height1  );    

			# create blank pixbuf to hold the image
			my $gdkpixbuf = Gtk2::Gdk::Pixbuf->new ('rgb', 0,8,$cmod, $height1);

			$gdkpixbuf->get_from_drawable ($canvas->window, undef, 0, 0, 0, 0, $cmod, $height1);

			$gdkpixbuf->copy_area (0, 0, $cmod, $height1, $gdkpixbuf_l, $cols*$width1, $r*$height1);
		} #end odd col
		########################################################################

		# get  lower right corner ##########################
		$ha1->set_value( $cols * $width1  );    
		$va1->set_value( $rows * $height1  );    

		# create blank pixbuf to hold the image
		my $gdkpixbuf = Gtk2::Gdk::Pixbuf->new ('rgb', 0,8,$cmod,$rmod);
		$gdkpixbuf->get_from_drawable ($canvas->window, undef, 0, 0, 0, 0, $cmod, $rmod);
		$gdkpixbuf->copy_area (0, 0, $cmod, $rmod, $gdkpixbuf_l, $width - $cmod, $height - $rmod);

		########################################################################
		$gdkpixbuf_l->save ($filename, $filetype) if defined($gdkpixbuf_l); 
		$drawing_statusbar->push (1, $d->get("Drawing saved"));
		$ha1->set_value( 0 );    
		$va1->set_value( 0 );   		
		
	}	
 
	  
		}); 

	# .. And a quit button
	my $quit_button = Gtk2::Button->new_from_stock ('gtk-close');
	$quit_button->signal_connect(clicked => sub { $drawing_window->destroy() });

	$canvas->set_scroll_region( 0, 0, $w, $h);	
	$root = $canvas->root;

	my $canvas_pixbuf = Gnome2::Canvas::Item->new(
		$root, 'Gnome2::Canvas::Pixbuf',
		x => 0,
		y => 0,
		pixbuf => $drawing_pixbuf,
	);

	my $drawing_box_buttons = undef;
	my $drawing_box = undef;
	#start packing, we have a horizontal and a vertical mode	
	if($h >= $w){ #vertical mode
		$drawing_box_buttons = Gtk2::VBox->new (FALSE, 0);
		$drawing_box = Gtk2::HBox->new (FALSE, 0);
		$drawing_box_buttons->pack_start($width_label, FALSE, FALSE, 0 );
		$drawing_box_buttons->pack_start($sb_width, FALSE, FALSE, 5 );
		$drawing_box_buttons->pack_start($col_label, FALSE, FALSE, 0 );
		$drawing_box_buttons->pack_start($colbut1, FALSE, FALSE, 5 );
		$drawing_box_buttons->pack_start($zoom_label, FALSE, FALSE, 0 );
		$drawing_box_buttons->pack_start($sb_zoom, FALSE, FALSE, 5 );
		$drawing_box_buttons->pack_start($save_button, FALSE, FALSE, 5 );	
		$drawing_box_buttons->pack_start ($quit_button, FALSE, FALSE, 5);
		$drawing_box->pack_start($drawing_box_buttons, FALSE, FALSE, 5 );
		$drawing_box->pack_start ($fixed_container, FALSE, FALSE, 10);
		$drawing_vbox->pack_start($drawing_box, FALSE, FALSE, 5 );	

	}else{ #horizontal mode
		$drawing_box_buttons = Gtk2::HBox->new (FALSE, 0);
		$drawing_box = Gtk2::VBox->new (FALSE, 0);
		my $halign = Gtk2::Alignment->new (1, 0, 0, 0);
		$drawing_box_buttons->add($halign);
		$drawing_box_buttons->pack_start($width_label, FALSE, FALSE, 0 );
		$drawing_box_buttons->pack_start($sb_width, FALSE, FALSE, 5 );
		$drawing_box_buttons->pack_start($col_label, FALSE, FALSE, 0 );
		$drawing_box_buttons->pack_start($colbut1, FALSE, FALSE, 5 );
		$drawing_box_buttons->pack_start($zoom_label, FALSE, FALSE, 0 );
		$drawing_box_buttons->pack_start($sb_zoom, FALSE, FALSE, 5 );
		$drawing_box_buttons->pack_start($save_button, FALSE, FALSE, 5 );	
		$drawing_box_buttons->pack_start ($quit_button, FALSE, FALSE, 5);
		$drawing_box->pack_start ($fixed_container, FALSE, FALSE, 10);
		$drawing_box->pack_start($drawing_box_buttons, FALSE, FALSE, 5 );
		$drawing_vbox->pack_start($drawing_box, FALSE, FALSE, 5 );	
		
	}

	$drawing_window->show_all();
	Gtk2->main;
}

##############################



##################private subs##################
sub event_drawing_handler{
     my ( $widget, $event ) = @_;
     my $scale = $adj_zoom->get_value;
    if ( $event->type eq "button-press" ) {
        $draw_flag = 1;       
        #start a new line curve
        $count++;      
        my ($x,$y) = ($event->x,$event->y);
    
        $lines{$count}{'points'} = [$x/$scale,$y/$scale,$x/$scale,$y/$scale]; #need at least 2 points 
        $lines{$count}{'line'} = Gnome2::Canvas::Item->new ($root,
                'Gnome2::Canvas::Line',
                points => $lines{$count}{'points'},
                fill_color_gdk => $colbut1->get_color,
                width_units => $sb_width->get_value,
                cap_style => 'round',
                join_style => 'round',
            );
     }
    if ( $event->type eq "button-release" ) {
        $draw_flag = 0;
    }

    if ( $event->type eq "focus-change" ) {
        return 0;
    }
    
    if ( $event->type eq "expose" ) {
        return 0;
    }

  if($draw_flag){
    #left with motion-notify
    if ( $event->type eq "motion-notify"){
   	 my ($x,$y) = ($event->x,$event->y);
     push @{$lines{$count}{'points'}},$x/$scale,$y/$scale;   
     $lines{$count}{'line'}->set(points=>$lines{$count}{'points'});

    }
  }        
}

sub event_zoom_changed {
    my ($adj_zoom, $canvas) = @_;
    $canvas->set_pixels_per_unit($adj_zoom->get_value);
}

sub event_close_modal_window {
 my ($widget) = @_;
 Gtk2->main_quit();
}

1;
