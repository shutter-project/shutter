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

package Shutter::Upload::FTP;

use utf8;
use strict;
use Net::FTP;
use URI;
use URI::Split qw(uri_split);

#Glib
use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;

	my $self = {
		_debug_cparam    => shift,
		_shutter_root     => shift,
		_gettext_object  => shift,
		_main_gtk_window => shift,
		_mode            => shift    #active or passive
	};

	#connection settings
	$self->{_prot}  = "";
	$self->{_host}  = "";
	$self->{_port}  = "";
	$self->{_path}  = "";
	$self->{_auth}  = "";
	$self->{_query} = "";
	$self->{_frag}  = "";

	#credentials and filename
	$self->{_filename} = undef;
	$self->{_username} = undef;
	$self->{_password} = undef;

	bless $self, $class;
	return $self;
}

sub login {
	my ( $self, $uri, $username, $password ) = @_;

	#uri should start with ftp:// to parse it correctly
	$uri = "ftp://" . $uri unless ( $uri =~ /^ftp:\/\// );

	#split uri
	my $u = URI->new($uri);

	( $self->{_prot}, $self->{_auth}, $self->{_path}, $self->{_query}, $self->{_frage} )
		= uri_split($u);

	#get port and host
	$self->{_auth} =~ /(.*):?([0-9]?)/;
	$self->{_host} = $1 || "undefined.host";
	$self->{_port} = $2 || 21;

	#check uri and return if anything is missing
	unless ( $self->{_host} && $self->{_port} ) {
		return (
		$self->{_gettext_object}->get("Illegal URI."),
		"<<ftp://host:port/path>>",
		undef);
	}

	#store parms as object vars
	$self->{_username} = $username;
	$self->{_password} = $password;
	utf8::encode $self->{_host};
	utf8::encode $self->{_username} if $self->{_username};
	utf8::encode $self->{_password} if $self->{_password};

	#CONNECT TO FTP SERVER
	$self->{_ftp} = Net::FTP->new(
		$self->{_host},
		Passive => $self->{_mode},
		Port    => $self->{_port},
		Timeout => 10
		)
		or return (
			$self->{_gettext_object}->get("Connection error."),
			$self->{_gettext_object}->get("Please check your connectivity and try again."),
			$@);

	#TRY TO LOGIN WITH GIVEN CREDENTIALS
	$self->{_ftp}->login( $self->{_username}, $self->{_password} )
		or return (
			sprintf ($self->{_gettext_object}->get("Login with username %s failed."), "'".$self->{_username}."'"),
			$self->{_gettext_object}->get("Please check your credentials and try again."),
			$self->{_ftp}->message);

	#THERE ARE NO ERRORS WHEN ROUTINE RETURNS AT THIS POINT
	return (FALSE);
}

sub upload {
	my ( $self, $upload_filename ) = @_;

	#store parms as object vars
	$self->{_filename} = $upload_filename;

	utf8::encode $self->{_filename};

	#CHANGE WORKING DIRECTORY USING CWD COMMAND
	$self->{_ftp}->cwd( $self->{_path} )
		or return (
			$self->{_gettext_object}->get("Failed"),
			$self->{_gettext_object}->get("Cannot change working directory."),
			$self->{_ftp}->message
			);

	$self->{_ftp}->binary;

	#UPLOAD FILE
	$self->{_ftp}->put( $self->{_filename} )
		or return (
			$self->{_gettext_object}->get("Failed"),
			$self->{_gettext_object}->get("Command 'put' failed."), 
			$self->{_ftp}->message
		);

	#THERE ARE NO ERRORS WHEN ROUTINE RETURNS AT THIS POINT
	return (FALSE);
}

sub quit {
	my $self = shift;

	#QUIT CONNECTION
	$self->{_ftp}->quit;

	#THERE ARE NO ERRORS WHEN ROUTINE RETURNS AT THIS POINT
	return (FALSE);
}

1;
