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

package Shutter::Pixbuf::Save;

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


sub new {
	my $class = shift;

	#constructor
	my $self = { _common => shift, _window => shift };

	#import shutter dialogs
	my $current_window = $self->{_window} || $self->{_common}->get_mainwindow;
	$self->{_dialogs} = Shutter::App::SimpleDialogs->new( $current_window );
	$self->{_lp} = Shutter::Pixbuf::Load->new( $self->{_common}, $current_window );

	bless $self, $class;
	return $self;
}

sub save_pixbuf_to_file {
	my $self = shift;
	my $pixbuf = shift;
	my $filename = shift;
	my $filetype = shift;
	my $quality = shift;

	#gettext variable
	my $d = $self->{_common}->get_gettext;

	#check if we need to rotate the image or set the exif data accordingly
	my $option = $self->{_lp}->get_option($pixbuf, 'orientation');
	$option = 1 unless defined $option;

	#FIXME: NOT COVERED BY BINDINGS YET (we use Image::ExifTool instead)
	#we rotate the pixbuf when saving to any other format than jpeg (jpg)
	unless ( $filetype eq 'jpeg' || $filetype eq 'jpg') {
		if($option != 1){
			$pixbuf = $self->{_lp}->auto_rotate($pixbuf);
		}
	}

	#we have two main ways of saving file
	#when possible we try to use all supported formats of the gdk-pixbuf libs
	#currently this is bmp, jpeg (jpg), png and ico (ico is not useful here)
	my $imagemagick_result = undef;
	if ( $filetype eq 'jpeg' || $filetype eq 'jpg' ) {
		
		#get quality value from settings if not set
		if(my $settings = $self->{_common}->get_globalsettings_object){
			if(defined $settings->get_jpg_quality){
				$quality = $settings->get_jpg_quality;
			}else{
				$quality = 90;
			}
		}else{
			$quality = 90;
		}
		
		print "Saving file $filename, $filetype, $quality\n" if $self->{_common}->get_debug;
		
		eval{
			$pixbuf->save( $filename, 'jpeg', quality => $quality );
			
			#FIXME: NOT COVERED BY BINDINGS YET (we use Image::ExifTool instead)
			#~ $pixbuf->set_option( 'orientation' => $option );
			if(my $exif = Shutter::App::Optional::Exif->new()){
				#new Image::ExifTool instance 
				my $exiftool = $exif->get_exiftool;
				if($exiftool){
					#Set a new value for a tag
					$exiftool->SetNewValue('Orientation' => $option, Type => 'ValueConv');
					#Write new meta information to a file
					my $success = $exiftool->WriteInfo($filename);
				}
			}
		};
	} elsif ( $filetype eq 'png' ) {
		
		#get quality value from settings if not set
		if(my $settings = $self->{_common}->get_globalsettings_object){
			if(defined $settings->get_png_quality){
				$quality = $settings->get_png_quality;
			}else{
				$quality = 9;
			}
		}else{
			$quality = 9;
		}
		
		print "Saving file $filename, $filetype, $quality\n" if $self->{_common}->get_debug;
		
		eval{
			$pixbuf->save( $filename, $filetype, "tEXt::Software" => "Shutter", compression => $quality );
		};
	} elsif ( $filetype eq 'bmp' ) {	
		eval{
			$pixbuf->save( $filename, $filetype );
		};
	} elsif ( $filetype eq 'pdf' ) {	
		
		print "Saving file $filename, $filetype\n" if $self->{_common}->get_debug;
		
		#0.8? => 72 / 90 dpi		
    	my $surface = Cairo::PdfSurface->create($filename, $pixbuf->get_width * 0.8, $pixbuf->get_height * 0.8);
    	my $cr = Cairo::Context->create($surface);
		$cr->scale(0.8, 0.8);
		Gtk2::Gdk::Cairo::Context::set_source_pixbuf( $cr, $pixbuf, 0, 0 );
		$cr->paint;
		$cr->show_page;
				
		undef $surface;
		undef $cr;

	} elsif ( $filetype eq 'ps' ) {
		
		print "Saving file $filename, $filetype\n" if $self->{_common}->get_debug;
		
		#0.8? => 72 / 90 dpi		
    	my $surface = Cairo::PsSurface->create($filename, $pixbuf->get_width * 0.8, $pixbuf->get_height * 0.8);
    	my $cr = Cairo::Context->create($surface);
		$cr->scale(0.8, 0.8);
		Gtk2::Gdk::Cairo::Context::set_source_pixbuf( $cr, $pixbuf, 0, 0 );
		$cr->paint;
		$cr->show_page;
				
		undef $surface;
		undef $cr;

	} elsif ( $filetype eq 'svg' ) {
		
		print "Saving file $filename, $filetype\n" if $self->{_common}->get_debug;
		
		#0.8? => 72 / 90 dpi		
    	my $surface = Cairo::SvgSurface->create($filename, $pixbuf->get_width * 0.8, $pixbuf->get_height * 0.8);
    	my $cr = Cairo::Context->create($surface);
		$cr->scale(0.8, 0.8);
		Gtk2::Gdk::Cairo::Context::set_source_pixbuf( $cr, $pixbuf, 0, 0 );
		$cr->paint;
		$cr->show_page;
				
		undef $surface;
		undef $cr;
	
	} else  {
		
		print "Saving file $filename, $filetype, $quality (using fallback-mode)\n" if $self->{_common}->get_debug;
		
		#save pixbuf to tempfile
		my ( $tmpfh, $tmpfilename ) = tempfile();
		$tmpfilename .= '.png';
		if($pixbuf){
			$pixbuf->save( $tmpfilename, 'png', compression => '9' );
		}
		#and convert filetype with imagemagick
		$imagemagick_result = $self->use_imagemagick_to_save($tmpfilename, $filename);
		unlink $tmpfilename;
	}
	
	#handle possible error messages
	#we use eval to test the pixbuf methods 
	#and error messages provided 
	#by the imagemagick libs
	if ($@ || $imagemagick_result) {

		#parse filename
		my ( $name, $folder, $type ) = fileparse( $filename, qr/\.[^.]*/ );

		my $detailed_message = 'Unknown error';
		if($@){
			$detailed_message = $@->message;
		}elsif($imagemagick_result){
			$detailed_message = $imagemagick_result;
		}

		#nice error dialog, more detailed messages are shown with a gtk2 expander
		my $response = $self->{_dialogs}->dlg_error_message( 
			sprintf( $d->get("Error while saving the image %s."), "'" . $name.$type . "'"),
			sprintf( $d->get("There was an error saving the image to %s."), "'" . $folder . "'"),		
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

	#escape filename first
	$file = quotemeta $file;
	$new_file = quotemeta $new_file;
		
	my $result = `convert $file $new_file 2>&1`;
		
	return $result;
}

1;

