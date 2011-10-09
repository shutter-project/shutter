#! /usr/bin/env perl
###################################################
#
#  Copyright (C) 2008-2011 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package Dropbox;

use lib $ENV{'SHUTTER_ROOT'}.'/share/shutter/resources/modules';

use utf8;
use strict;
use POSIX qw/setlocale/;
use Locale::gettext;
use Glib qw/TRUE FALSE/; 
use Data::Dumper;

use Shutter::Upload::Shared;
our @ISA = qw(Shutter::Upload::Shared);

my $d = Locale::gettext->domain("shutter-plugins");
$d->dir( $ENV{'SHUTTER_INTL'} );

my %upload_plugin_info = (
    'module'		=> $d->get( "Dropbox" ),
	'url'			=> $d->get( "https://www.dropbox.com/" ),
	'registration'  => $d->get( "https://www.dropbox.com/register" ),
	'name'			=> $d->get( "Dropbox" ),
	'description'	=> $d->get( "Upload screenshots into your Dropbox" ),
	'supports_anonymous_upload'	 => FALSE,
	'supports_authorized_upload' => FALSE,	
	'supports_oauth_upload' => TRUE,	
);

binmode( STDOUT, ":utf8" );
if ( exists $upload_plugin_info{$ARGV[ 0 ]} ) {
	print $upload_plugin_info{$ARGV[ 0 ]};
	exit;
}

###################################################

sub new {
	my $class = shift;

	#call constructor of super class (host, debug_cparam, shutter_root, gettext_object, main_gtk_window, ua)
	my $self = $class->SUPER::new( shift, shift, shift, shift, shift, shift );

	bless $self, $class;
	return $self;
}

sub init {
	my $self = shift;

	#do custom stuff here
	use Net::Dropbox::API;
	use JSON;
	use URI::Escape qw(uri_escape_utf8);
	use File::Basename qw(dirname basename);
	use File::Spec;

	$self->{_box} = undef;
	$self->{_config} = { };
	$self->{_config_file} = File::Spec->catfile( $ENV{'HOME'}, '.dropbox-api-config' );
	
	$self->connect;
}

sub connect {
	my $self = shift;
	
	eval{
		if(-f $self->{_config_file}){
			$self->{_config} = decode_json($self->{_config_file}->slurp);
			$self->{_config}->{key} = 'fwsv9z8slaw0c0q';
			$self->{_config}->{secret} = 'hsxflivocvav6ag';
			$self->{_config}->{callback_url} = '';						
			$self->{_box} = Net::Dropbox::API->new($self->{_config});
			$self->{_box}->context('dropbox');
		}else{
			$self->{_config}->{key} = 'fwsv9z8slaw0c0q';
			$self->{_config}->{secret} = 'hsxflivocvav6ag';
			$self->{_config}->{callback_url} = '';				
			return $self->setup;
		}
	};
	if($@){
		return FALSE;
	}
	
	return TRUE;
}

sub setup {
	my $self = shift;
	
	print "Setting up Dropbox...\n";
	
	#some helpers
	my $sd = Shutter::App::SimpleDialogs->new;
	my $d = $self->{_gettext_object};

    #Authentication
    $self->{_box} = Net::Dropbox::API->new($self->{_config});
    my $login_link = $self->{_box}->login;
    if($self->{_box}->error){
		$sd->dlg_error_message($self->{_box}->error, $d->get("There was an error receiving the authentication URL."));
		print "ERROR: There was an error while receiving the Dropbox-URL. ", $self->{_box}->error, "\n";
		return FALSE;	
	}else{
		my $response = $sd->dlg_info_message(
			"Please follow the URL ($login_link) below to authorize with Dropbox. Press 'Accept' when you are done.", 
			$d->get("Authorize with Dropbox"),
			'gtk-cancel',
			$d->get("I have authorized Shutter. Let's go ...")
		);
		print $response, "\n";
		if ( $response == 20 ) {
			
			print "Dropbox: Authorizing...\n";
			
			$self->{_box}->auth;
			if($self->{_box}->error){
				$sd->dlg_error_message($self->{_box}->error, $d->get("There was an error authenticating with Dropbox."));
				print "ERROR: There was an error while authenticating with Dropbox. ", $self->{_box}->error, "\n";
				return FALSE;
			}
			#get atoken and asecret
			$self->{_config}->{access_token} = $self->{_box}->access_token;
			$self->{_config}->{access_secret} = $self->{_box}->access_secret;
			$self->{_config}->{key} = 'fwsv9z8slaw0c0q';
			$self->{_config}->{secret} = 'hsxflivocvav6ag';
			$self->{_config}->{callback_url} = '';
			
			print $self->{_config}->{access_token}, "\n";
			print $self->{_config}->{access_secret}, "\n";
			
			$self->{_config_file}->openw->print(encode_json($self->{_config}));
			chmod 0600, $self->{_config_file};			
			
			#again
			$self->{_box} = Net::Dropbox::API->new($self->{_config});
			$self->{_box}->context('dropbox');
			
			return TRUE;
		} else {
			print "What is wrong here....dialog reponse\n";
			return FALSE;
		}
		
	}
}

sub get_uid {
	my $self = shift;
	my $info = $self->{_box}->account_info();
	return $info->{uid};
}

sub escape {
	my $self = shift;
    my $str = shift;
    my $escape = uri_escape_utf8($str, q{^a-zA-Z0-9_./-});
    return $escape;
}

sub upload {
	my ( $self, $upload_filename) = @_;

	#store as object vars
	$self->{_filename} = $upload_filename;
	utf8::encode $upload_filename;
	
	eval{
		my $res = $self->{_box}->putfile($upload_filename, "Public");
		if($res->{'http_response_code'} == 200){
			#set status (success)
			$self->{_links}{'status'} = 200;
			
			#...and filename
			$self->{_links}->{'direct_link'} = "http://dl.dropbox.com/u/".$self->get_uid."/".$self->escape(basename($upload_filename));
			
			#print all links (debug)
			if( $self->{_debug_cparam}) {
				foreach (keys %{$self->{_links}}){
					print $_.": ".$self->{_links}->{$_}, "\n";
				}
			}
		}else{
			$self->{_links}{'status'} = $res->{'error'};
		}
	};
	if($@){
		$self->{_links}{'status'} = $@;
	}
	
	return %{ $self->{_links} };
}

1;
