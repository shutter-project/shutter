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

package Shutter::Pixbuf::Load;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Gtk2;

#fileparse and tempfile
use File::Basename qw/ fileparse dirname basename /;
use File::Temp qw/ tempfile tempdir /;

#Glib
use Glib qw/TRUE FALSE/; 

#--------------------------------------

##################public subs##################
sub new {
	my $class = shift;

	#constructor
	my $self = { _common => shift, _window => shift, _no_error_dialog => shift };

	bless $self, $class;
	return $self;
}

sub load {
	my $self 		= shift;
	my $filename 	= shift;
	my $width 		= shift;
	my $height 		= shift;
	my $sratio 		= shift;
	my $rotate		= shift;

	my $pixbuf = undef;
	eval{
		if(defined $width && defined $height && defined $sratio){
			$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_scale($filename, $width, $height, $sratio);			
		}elsif(defined $width && defined $height){
			$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size($filename, $width, $height);
		}else{
			$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file($filename);			
		}
	};
	#handle possible error messages
	if ($@) {
		
		unless(defined $self->{_no_error_dialog} && $self->{_no_error_dialog}){

			#import shutter dialogs
			my $current_window = $self->{_window} || $self->{_common}->get_mainwindow;
			my $sd = Shutter::App::SimpleDialogs->new( $current_window );

			#gettext variable
			my $d = $self->{_common}->get_gettext;
		
			#parse filename
			my ( $name, $folder, $type ) = fileparse( $filename, qr/\.[^.]*/ );		

			#nice error dialog, more detailed messages are shown with a gtk2 expander
			my $response = $sd->dlg_error_message( 
				sprintf( $d->get("Error while opening image %s."), "'" . $name.$type . "'"),
				$d->get("There was an error opening the image."),		
				undef, undef, undef,
				undef, undef, undef,
				$@->message
			);
		
		}
		
	}
	
	#read exif and rotate accordingly
	if($rotate && $pixbuf){
		$pixbuf = $self->auto_rotate($pixbuf);
	}
	
	return $pixbuf;
}

sub get_option {
	my $self = shift;
	my $pixbuf = shift;
	my $option = shift;

	return FALSE unless (defined $pixbuf && defined $option);

	return $pixbuf->get_option($option); 	
}

sub auto_rotate {
	my $self = shift;
	my $pixbuf = shift;

	my %orientation_flags = (
		1 => 'none,-1',
		2 => 'none,1',
		3 => 'upsidedown,-1',
		4 => 'none,0',
		5 => 'clockwise,1',
		6 => 'clockwise,-1',
		7 => 'clockwise,0',
		8 => 'counterclockwise,-1',
	);
	my $option = $self->get_option($pixbuf, 'orientation');
	if(defined $option && exists $orientation_flags{$option}){
		my ($rotate, $flip_horiz) = split ",", $orientation_flags{$option};
		#~ print $option, "\n";
		if(defined $rotate){
			$pixbuf = $pixbuf->rotate_simple($rotate);
		}
		if(defined $flip_horiz && $flip_horiz > -1){
			$pixbuf = $pixbuf->flip($flip_horiz);
		}
	}	

	return $pixbuf;
}

1;
