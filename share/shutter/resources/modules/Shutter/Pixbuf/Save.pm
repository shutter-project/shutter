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

package Shutter::Pixbuf::Save;

#modules
#--------------------------------------
use utf8;
use strict;
use Gtk2;

#Gettext and filename parsing
use POSIX qw/setlocale strftime/;
use Locale::gettext;

#Image operations
use Image::Magick();

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

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

sub save_pixbuf_to_file {
	my $self = shift;
	my $pixbuf = shift;
	my $filename = shift;
	my $old_filename = shift;
	my $filetype = shift;
	my $quality = shift;
	
	print "Saving file $filename, $filetype, $quality, $old_filename\n" if $self->{_common}->get_debug;

	#gettext variable
	my $d = $self->{_common}->get_gettext;

	#we have two main ways of saving file
	#when possible we try to use all supported formats of the gdk-pixbuf libs
	#currently this is bmp, jpeg, png and ico (ico is not useful here)
	my $imagemagick_result = 0;
	if ( $filetype eq 'jpeg' ) {
		$quality = '100' unless $quality;
		eval{
			$pixbuf->save( $filename, $filetype, quality => $quality );
		};
	} elsif ( $filetype eq 'png' ) {
		$quality = '9' unless $quality;
		eval{
			$pixbuf->save( $filename, $filetype, compression => $quality );
		};
	} elsif ( $filetype eq 'bmp' ) {	
		eval{
			$pixbuf->save( $filename, $filetype );
		};
	} else  {	
		$imagemagick_result = $self->use_imagemagick_to_save($old_filename, $filename );
	}
	
	#handle possible error messages
	#we use eval to test the pixbuf methods 
	#and error messages provided 
	#by the imagemagick libs
	if ($@ || $imagemagick_result) {

		#parse filename
		my ( $name, $folder, $type ) = fileparse( $filename, '\..*' );

		my $detailed_message = 'Unknown error';
		if($@){
			$detailed_message = $@->message;
		}elsif($imagemagick_result){
			$detailed_message = $imagemagick_result;
		}

		#nice error dialog, more detailed messages are shown with a gtk2 expander
		my $response = $self->{_dialog}->dlg_error_message( 
			$d->get( sprintf( "Error while saving the image %s.", "'" . $name.$type . "'" ) ),
			$d->get( sprintf( "There was an error saving the image to %s.", "'" . $folder . "'" ) ),		
			undef, undef, undef,
			undef, undef, undef,
			$detailed_message
		);
		return FALSE;

	}
	
	return TRUE;
	
}

#use imagemagick for all filetypes that are not
#supported by the gdk-pixbuf libs
#e.g. gif
sub use_imagemagick_to_save {
	my $self = shift;
	my $file = shift;
	my $new_file = shift;
	
	#create imagemagick object and result variable
	my $image 	= Image::Magick->new;
	my $result 	= undef;
	
	#read file and evaluate result
	$result = $image->ReadImage($file);
	warn "$result" if $result;      # print the error message
  	return $result if $result;

	#write file and evaluate result
	$result = $image->WriteImage( filename => $new_file );
	warn "$result" if $result;      # print the error message
  	return $result if $result;
	
	return FALSE;
}

1;
