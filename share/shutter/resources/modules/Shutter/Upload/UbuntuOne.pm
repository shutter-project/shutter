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

package Shutter::Upload::UbuntuOne;

use utf8;
use strict;

#DBus message system
use Net::DBus::GLib;

#Glib
use Glib qw/TRUE FALSE/;

#--------------------------------------

sub new {
	my $class = shift;

	my $self = {
		_sc    => shift,
	};
	
	bless $self, $class;
	return $self;
}

#~ sub DESTROY {
    #~ my $self = shift;
    #~ print "$self dying at\n";
#~ } 

sub connect_to_bus {
	my $self = shift;
	
	eval{
		$self->{_bus} = Net::DBus::GLib->session();
		$self->{_service} = $self->{_bus}->get_service("com.ubuntuone.SyncDaemon");
	};
	if($@){
		print "Warning: $@", "\n";
		return ($@);
	}
	
	return ($self->{_service});
}

sub check_api {
	my $self = shift;
	return FALSE unless $self->is_connected;
	my $api = $self->{_service}->get_object("/", "org.freedesktop.DBus.Introspectable");
	my $node = $api->Introspect();
	if($node =~ /name=\"publicfiles\"/){
		return TRUE;
	}
	print "Warning: Node 'publicfiles' not found. Your Ubuntu One installation seems to be out of date.", "\n";	
	return FALSE;
}

sub get_syncdaemon {
	my $self = shift;
	return FALSE unless $self->is_connected;
	unless(defined $self->{_sd}){
		$self->{_sd} = $self->{_service}->get_object("/", "com.ubuntuone.SyncDaemon.SyncDaemon");
	}
	return $self->{_sd};
}

sub get_syncdaemon_fs {
	my $self = shift;
	return FALSE unless $self->is_connected;
	unless(defined $self->{_sd_fs}){
		$self->{_sd_fs} = $self->{_service}->get_object("/filesystem", "com.ubuntuone.SyncDaemon.FileSystem");
	}
	return $self->{_sd_fs};
}

sub get_syncdaemon_events {
	my $self = shift;
	return FALSE unless $self->is_connected;
	unless(defined $self->{_sd_ev}){
		$self->{_sd_ev} = $self->{_service}->get_object("/events", "com.ubuntuone.SyncDaemon.Events");
	}
	return $self->{_sd_ev};
}

sub get_syncdaemon_folders {
	my $self = shift;
	return FALSE unless $self->is_connected;
	unless(defined $self->{_sd_folders}){
		$self->{_sd_folders} = $self->{_service}->get_object("/folders", "com.ubuntuone.SyncDaemon.Folders");
	}
	return $self->{_sd_folders};
}

sub get_syncdaemon_config {
	my $self = shift;
	return FALSE unless $self->is_connected;
	
	#the following does not exist in all versions of U1
	my $api = $self->{_service}->get_object("/", "org.freedesktop.DBus.Introspectable");
	my $node = $api->Introspect();
	if($node =~ /name=\"config\"/){
		unless(defined $self->{_sd_config}){
			$self->{_sd_config} = $self->{_service}->get_object("/config", "com.ubuntuone.SyncDaemon.Config");
		}
		return $self->{_sd_config};
	}
	print "Warning: Node 'config' not found. Your Ubuntu One installation seems to be out of date. Unable to check for configuration.", "\n";	
	return FALSE;
}

sub get_syncdaemon_shares {
	my $self = shift;
	return FALSE unless $self->is_connected;
	unless(defined $self->{_sd_shares}){
		$self->{_sd_shares} = $self->{_service}->get_object("/shares", "com.ubuntuone.SyncDaemon.Shares");
	}
	return $self->{_sd_shares};
}

sub get_syncdaemon_status {
	my $self = shift;
	return FALSE unless $self->is_connected;
	unless(defined $self->{_sd_status}){
		$self->{_sd_status} = $self->{_service}->get_object("/status", "com.ubuntuone.SyncDaemon.Status");
	}
	return $self->{_sd_status};
}

sub get_syncdaemon_public {
	my $self = shift;
	return FALSE unless $self->is_connected;
	unless(defined $self->{_sd_public}){
		$self->{_sd_public} = $self->{_service}->get_object("/publicfiles", "com.ubuntuone.SyncDaemon.PublicFiles");
	}
	return $self->{_sd_public};
}

sub is_connected {
	my $self = shift;
	return TRUE if defined $self->{_bus} && defined $self->{_service};
	print "Warning: Not connected to bus, you need to call 'connect_to_bus' first", "\n";
	return FALSE;
}

sub is_online {
	my $self = shift;
	return FALSE unless $self->is_connected;
	my ($is_connected, $is_online, $text) = $self->get_current_status;
	return TRUE if $is_connected && $is_online;
	print "Warning: Not online, maybe your computer is not connected to a network", "\n";
	return FALSE;
}

sub get_current_status {
	my $self = shift;
	my $status_ref = shift;

	return FALSE unless $self->is_connected;

	my %status;
	if(defined $status_ref){
		%status = %{$status_ref};
	}else{
		%status = %{$self->get_syncdaemon_status->current_status};
	}
	
	#create human readable messages
	my $d = $self->{_sc}->get_gettext;
	my $text = $d->get("Disconnected");
	if($status{is_connected}){
		if($status{name} eq 'QUEUE_MANAGER' && $status{queues} eq 'IDLE'){
			$text = $d->get("Synchronization complete");
		}else{
			$text = $d->get("Synchronization in progress...");
		}
	}
	
	return ($status{is_connected}, $status{is_online}, $text);
}

sub is_synced_folder {
	my $self = shift;
	my $folder = shift;
	
	return FALSE unless defined $folder;
	return FALSE unless $self->is_connected;

	my $sd_fs = $self->get_syncdaemon_fs($folder);
	
	my %meta;
	eval{
		%meta = %{$sd_fs->get_metadata($folder)};
		print Dumper %meta;	
	};
	if($@){
		return FALSE;
	}
	return $meta{is_dir};
}

sub is_notifications_enabled {
	my $self = shift;
	
	return FALSE unless $self->is_connected;

	my $sd_cf = $self->get_syncdaemon_config;
	
	#does not exist in all version of U1
	return FALSE unless $sd_cf;
	
	my $is_enabled = TRUE;
	eval{
		$is_enabled = $sd_cf->show_all_notifications_enabled;
	};
	if($@){
		return FALSE;
	}
	return $is_enabled;
}

1;
