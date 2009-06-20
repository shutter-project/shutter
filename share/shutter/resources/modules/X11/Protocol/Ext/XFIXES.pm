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

#http://freedesktop.org/wiki/Software/FixesExt
package X11::Protocol::Ext::XFIXES; 

use X11::Protocol qw(pad padding padded make_num_hash);
use Carp;

use strict;
use vars '$VERSION';

$VERSION = 0.01;

sub new
{
    my($pkg, $x, $request_num, $event_num, $error_num) = @_;
    my($self) = {};

    #Request
	#GetCursorImage
	# 
	#
	#x:					INT16
	#y:					INT16
	#width:				CARD16
	#height:			CARD16
	#x-hot:				CARD16
	#y-hot:				CARD16
	#cursor-serial:		CARD32
	#cursor-image:		LISTofCARD32

	#GetCursorImage returns the image of the current cursor.  X and y are
	#the current cursor position.  Width and height are the size of the
	#cursor image.  X-hot and y-hot mark the hotspot within the cursor
	#image.  Cursor-serial provides the number assigned to this cursor
	#image, this same serial number will be reported in a CursorNotify
	#event if this cursor image is redisplayed in the future.

	#The cursor image itself is returned as a single image at 32 bits per
	#pixel with 8 bits of alpha in the most significant 8 bits of the
	#pixel followed by 8 bits each of red, green and finally 8 bits of
	#blue in the least significant 8 bits.  The color components are
	#pre-multiplied with the alpha component.
    $x->{'ext_request'}{$request_num} = 
      [	  
		["XFixesQueryVersion", sub {
			my($self) = shift;
			return pack("LL", 1, 0); #we support/need only version 1.0
		}, sub {
	    	my($self) = shift;
	     	my($data) = @_;
	     	my($major,$minor) = unpack("xxxxxxxxLLxxxxxxxxxxxxxxxx",$data);
	     	return($major,$minor);
		}]
      ];
	  
    my($i);
    for $i (0 .. $#{$x->{'ext_request'}{$request_num}}) {
	$x->{'ext_request_num'}{$x->{'ext_request'}{$request_num}[$i][0]} =
	  [$request_num, $i];
    }
	($self->{'major'}, $self->{'minor'}) = $x->req('XFixesQueryVersion');
	
	print $self->{'major'}." - ".$self->{'minor'}."\n";
	
    return bless $self, $pkg;
}

1;
