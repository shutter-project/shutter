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

package GScrot::Screenshot::Web;

#modules
#--------------------------------------
use utf8;
use strict;
use Image::Magick;

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

##################public subs##################
sub new {
	my $class = shift;
	
	my $self = {
				 _timeout => shift,
				 _format  => shift,
				 _quality  => shift,
				 _url  => shift,
				 _dest_filename => shift
			   };
	
	bless $self, $class;
	return $self;
}

sub web {
	my $self = shift;

	my $output = `gnome-web-photo --timeout=$self->{_timeout} --mode=photo --format=$self->{_format} -q $self->{_quality} '$self->{_url}' '$self->{_dest_filename}'`;
	
	return $self->get_imagemagick_object($self->{_dest_filename});
}

sub get_imagemagick_object {
	my $self = shift;
	my $filename = shift;
	 
	my $image = Image::Magick->new;
	$image->ReadImage( $filename );
	
	return $image;
}

1;
