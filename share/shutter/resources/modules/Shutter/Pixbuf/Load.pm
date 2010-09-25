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
	my $self = { _common => shift, _window => shift };

	#import shutter dialogs
	my $current_window = $self->{_window} || $self->{_common}->get_mainwindow;
	$self->{_dialogs} = Shutter::App::SimpleDialogs->new( $current_window );

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

	print "Loading file $filename\n" if $self->{_common}->get_debug;

	#gettext variable
	my $d = $self->{_common}->get_gettext;

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
		
		#parse filename
		my ( $name, $folder, $type ) = fileparse( $filename, qr/\.[^.]*/ );		

		#nice error dialog, more detailed messages are shown with a gtk2 expander
		my $response = $self->{_dialogs}->dlg_error_message( 
			sprintf( $d->get("Error while opening image %s."), "'" . $name.$type . "'"),
			$d->get("There was an error opening the image."),		
			undef, undef, undef,
			undef, undef, undef,
			$@->message
		);
		
	}
	
	#load meta-data
	if($rotate && $pixbuf){
		my %orientation_flags = (
			1 => 'none',
			8 => 'clockwise',
			3 => 'upsidedown',
			6 => 'counterclockwise',
		);
		my $flag = $pixbuf->get_option('orientation'); 
		if(defined $flag && exists $orientation_flags{$flag}){
			$pixbuf = $pixbuf->rotate_simple($orientation_flags{$flag});
		}
	}
	
	return $pixbuf;
}

1;
