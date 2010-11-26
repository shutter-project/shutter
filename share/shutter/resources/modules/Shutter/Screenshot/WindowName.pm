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

package Shutter::Screenshot::WindowName;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Shutter::Screenshot::WindowXid;
use Data::Dumper;
our @ISA = qw(Shutter::Screenshot::WindowXid);

#Glib and Gtk2
use Gtk2;
use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;

	#call constructor of super class (shutter_common, include_cursor, delay, notify_timeout, include_border, windowresize_active, windowresize_w, windowresize_h, hide_time, mode)
	my $self = $class->SUPER::new( shift, shift, shift, shift, shift, shift, shift, shift, shift, shift );

	bless $self, $class;
	return $self;
}

#~ sub DESTROY {
    #~ my $self = shift;
    #~ print "$self dying at\n";
#~ } 
#~ 

sub window_find_by_name {
	my $self = shift;
	my $name_pattern = shift;
	
	my $active_workspace = $self->{_wnck_screen}->get_active_workspace;
	
	#cycle through all windows
	my $output = 7;
	foreach my $win ( $self->{_wnck_screen}->get_windows_stacked ) {
		if ( $active_workspace && $win->is_on_workspace( $active_workspace ) ) {
			if ( $win->get_name =~ m/$name_pattern/i ) {
				$output = $self->window_by_xid($win->get_xid);
				last;
			}
		}
	}	
		
	return $output;
}

1;
