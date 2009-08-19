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
                               
package Shutter::Pixbuf::Thumbnail;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Gtk2;

#Gettext and filename parsing
use POSIX qw/setlocale strftime/;
use Locale::gettext;

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

##################public subs##################
sub new {
	my $class = shift;

	#constructor
	my $self = { _common => shift };

	bless $self, $class;
	return $self;
}

#~ sub DESTROY {
    #~ my $self = shift;
    #~ print "$self dying at\n";
#~ } 

sub get_thumbnail {
	my $self = shift;
	my $text_uri = shift;
	my $mime_type = shift;
	my $mtime = shift;
	my $rfactor = shift;
	
	my $pixbuf;
	my $factory = Gnome2::ThumbnailFactory->new ('normal');
	if($factory->can_thumbnail($text_uri, $mime_type, $mtime)){
		unless($factory->has_valid_failed_thumbnail ($text_uri, $mtime)){
			 if(my $existing_thumb = $factory->lookup ($text_uri, $mtime)){
				print "$text_uri thumbnail already exists\n" if $self->{_common}->get_debug;		
				$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file ($existing_thumb);	 
			 }else{
				print "$text_uri thumbnail created\n" if $self->{_common}->get_debug;
				$pixbuf = $factory->generate_thumbnail ($text_uri, $mtime);	 
				if($pixbuf){
					$factory->save_thumbnail ($pixbuf, $text_uri, $mtime);
				}
			 }
		}		
	}
	
	if($pixbuf){
		my $dest_width 	= $pixbuf->get_width*$rfactor; 
		my $dest_height = $pixbuf->get_height*$rfactor;
		$dest_width = 1 if $dest_width < 1;
		$dest_height = 1 if $dest_height < 1;

		return $pixbuf->scale_simple ($dest_width, $dest_height, 'tiles');	
	}else{
		my $blank = Gtk2::Gdk::Pixbuf->new ('rgb', TRUE, 8, 5, 5);	
		$blank->fill(0x00000000);
		
		return $blank; 
	}
	
}

1;
