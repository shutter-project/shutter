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

package Shutter::App::HelperFunctions;

#modules
#--------------------------------------
use utf8;
use strict;
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

sub xdg_open {
	my ( $self, $dialog, $link, $user_data ) = @_;
	system("xdg-open $link");
	return TRUE;
}

sub xdg_open_mail {
	my ( $self, $dialog, $mail, $user_data ) = @_;
	system("xdg-email $mail $user_data");
	return TRUE;
}

sub nautilus_sendto {
	my ( $self, $user_data ) = @_;
	system("nautilus-sendto $user_data &");
	return TRUE;
}

sub file_exists {
	my ( $self, $filename ) = @_;
	return FALSE unless $filename;
	$filename = $self->switch_home_in_file($filename);
	return TRUE if ( -f $filename && -r $filename );
	return FALSE;
}

sub folder_exists {
	my ( $self, $folder ) = @_;
	return FALSE unless $folder;
	$folder = $self->switch_home_in_file($folder);
	return TRUE if ( -d $folder && -r $folder );
	return FALSE;
}

sub uri_exists {
	my ( $self, $filename ) = @_;
	return FALSE unless $filename;
	$filename = $self->switch_home_in_file($filename);
	my $new_uri = Gnome2::VFS::URI->new($filename);
	return TRUE if $new_uri->exists;
	return FALSE;
}

sub file_executable {
	my ( $self, $filename ) = @_;
	return FALSE unless $filename;
	$filename = $self->switch_home_in_file($filename);
	return TRUE if ( -x $filename );
	return FALSE;
}

sub switch_home_in_file {
	my ( $self, $filename ) = @_;
	$filename =~ s/^~/$ENV{ HOME }/;    #switch ~ in path to /home/username
	return $filename;
}

sub utf8_decode {
	my $self 	= shift;
	my $string	= shift;
	
	#see https://bugs.launchpad.net/shutter/+bug/347821
	utf8::decode $string;
	
	return $string;
}

sub usage {
	my $self = shift;

	print "shutter [options]\n";
	print "Available options:\n\n"
		. "Capture:\n"
		. "--full (starts shutter and takes a full screen screenshot directly)\n"
		. "--selection (starts shutter in selection mode)\n"
		. "--window (starts shutter in window selection mode)\n"
		. "--section (starts shutter in section selection mode)\n\n"
		.

		"Application:\n"
		. "--min_at_startup (starts shutter minimized to tray)\n"
		. "--clear_cache (clears cache, e.g. installed plugins, at startup)\n"
		. "--debug (prints a lot of debugging information to STDOUT)\n"
		. "--disable_systray (disable systray icon)\n"
		. "--help (displays this help)\n";

	return TRUE;
}

1;
