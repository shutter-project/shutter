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

package Shutter::App::Notification;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Net::DBus;

#Glib
use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;

	my $self = { };

	#Use notifications object
	eval{
		$self->{_notifications_service} = Net::DBus->session->get_service('org.freedesktop.Notifications');
		$self->{_notifications_object} = $self->{_notifications_service}->get_object('/org/freedesktop/Notifications', 'org.freedesktop.Notifications');
	};
	if($@){
		print "Warning: $@", "\n";	
	}

	#last nid
	$self->{_nid} = 0;

	bless $self, $class;
	return $self;
}

sub show {
	my $self 	= shift;
	my $summary = shift;
	my $body 	= shift;
	my $nid		= shift || $self->{_nid};

	#notification
	eval{
		if(defined $self->{_notifications_object}){
			$self->{_nid} = $self->{_notifications_object}->Notify('Shutter', $nid, "gtk-dialog-info", $summary, $body, [], {}, -1);
		}
	};
	if($@){
		print "NotifyWarning: $@", "\n";		
	}
	
	return $self->{_nid};
}

sub close {
	my $self 	= shift;
	my $nid		= shift || $self->{_nid};
	
	#close notification
	if($nid){
		eval{
			if(defined $self->{_notifications_object}){
				$self->{_notifications_object}->CloseNotification($nid);
			}
		};
		if($@){
			print "CloseNotificationWarning: $@", "\n";		
		}
		return TRUE;	
	}

	return FALSE;
}

1;
