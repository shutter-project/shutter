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

package Shutter::Pixbuf::Save;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Gtk2;

#Gettext and filename parsing
use POSIX qw/setlocale strftime/;
use Locale::gettext;

#fileparse and tempfile
use File::Basename qw/ fileparse dirname basename /;
use File::Temp qw/ tempfile tempdir /;

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
	my $filetype = shift;
	my $quality = shift;

	print "Saving file $filename, $filetype, $quality\n" if $self->{_common}->get_debug;

	#gettext variable
	my $d = $self->{_common}->get_gettext;

	#we have two main ways of saving file
	#when possible we try to use all supported formats of the gdk-pixbuf libs
	#currently this is bmp, jpeg, png and ico (ico is not useful here)
	my $imagemagick_result = undef;
	if ( $filetype eq 'jpeg' ) {
		$quality = '100' unless $quality;
		eval{
			$pixbuf->save( $filename, $filetype, quality => $quality );
		};
	} elsif ( $filetype eq 'png' ) {
		$quality = '9' unless $quality;
		eval{
			$pixbuf->save( $filename, $filetype, "tEXt::Software" => "Shutter", compression => $quality );
		};
	} elsif ( $filetype eq 'bmp' ) {	
		eval{
			$pixbuf->save( $filename, $filetype );
		};
	} elsif ( $filetype eq 'pdf' ) {	
		
		#0.8? => 72 / 90 dpi		
    	my $surface = Cairo::PdfSurface->create($filename, $pixbuf->get_width * 0.8, $pixbuf->get_height * 0.8);
    	my $cr = Cairo::Context->create($surface);
		$cr->scale(0.8, 0.8);
		Gtk2::Gdk::Cairo::Context::set_source_pixbuf( $cr, $pixbuf, 0, 0 );
		$cr->paint;
		$cr->show_page;
				
		undef $surface;
		undef $cr;

	} elsif ( $filetype eq 'svg' ) {	
		
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

