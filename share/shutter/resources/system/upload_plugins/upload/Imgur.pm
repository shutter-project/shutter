#! /usr/bin/env perl
###################################################
#
#  Copyright (C) 2008-2013 Mario Kemper <mario.kemper@gmail.com>
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

package Imgur;

use lib $ENV{'SHUTTER_ROOT'}.'/share/shutter/resources/modules';

use utf8;
use strict;
use POSIX qw/setlocale/;
use Locale::gettext;
use Glib qw/TRUE FALSE/;
use MIME::Base64;

use Shutter::Upload::Shared;
our @ISA = qw(Shutter::Upload::Shared);

my $d = Locale::gettext->domain("shutter-upload-plugins");
$d->dir( $ENV{'SHUTTER_INTL'} );

my %upload_plugin_info = (
	'module'        => "Imgur",
	'url'           => "http://imgur.com/",
	'registration'  => "https://imgur.com/register",
	'description'   => $d->get( "Imgur is used to share photos with social networks and online communities, and has the funniest pictures from all over the Internet" ),
	'supports_anonymous_upload'	 => TRUE,
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
	my $username = shift;

	#do custom stuff here
	use JSON::MaybeXS;
	use LWP::UserAgent;
	use HTTP::Request::Common;
	use Path::Class;

	$self->{_config} = { };
	$self->{_config_file} = file( $ENV{'HOME'}, '.imgur-api-config' );

	$self->load_config;
	if ($username eq $d->get("OAuth"))
	{
		if (!$self->{_config}->{access_token}) 
		{
			return $self->connect;
		}
	}

	return TRUE;
}

sub load_config {
	my $self = shift;
	
	if (-f $self->{_config_file}) {
		eval {
			$self->{_config} = decode_json($self->{_config_file}->slurp);
		};
		if ($@) {
			$self->{_config}->{client_id} = '9490811e0906b6e';
			$self->{_config}->{client_secret} = '158b57f13e9a51f064276bd9e31529fb065f741e';
		}
	}
	else {
		$self->{_config}->{client_id} = '9490811e0906b6e';
		$self->{_config}->{client_secret} = '158b57f13e9a51f064276bd9e31529fb065f741e';
	}

	return TRUE;
}

sub connect {
	my $self = shift;
	return $self->setup;
}

sub setup {
	my $self = shift;
	
	if ($self->{_debug_cparam}) {
		print "Setting up Imgur...\n";
	}
	
	#some helpers
	my $sd = Shutter::App::SimpleDialogs->new;

	#Authentication
	my $login_link = 'https://api.imgur.com/oauth2/authorize?response_type=pin&client_id=' . $self->{_config}->{client_id};

	my $pin_entry = Gtk2::Entry->new();
	my $pin = '';
	$pin_entry->signal_connect(changed => sub {
		$pin = $pin_entry->get_text;
	});

	my $response = $sd->dlg_info_message(
		$d->get("Please click on the button below to authorize with Imgur. Input the PIN you receive and press 'Apply' when you are done."), 
		$d->get("Authorize with Imgur"),
		'gtk-cancel','gtk-apply', undef,
		undef, undef, undef, undef, undef,
		Gtk2::LinkButton->new ($login_link, $d->get("Authorize")),
		$pin_entry,
	);
	if ($response == 20) {
		
		if ($self->{_debug_cparam}) {
			print "Imgur: Authorizing...\n";
		}

		my %params = (
			'client_id' => $self->{_config}->{client_id},
			'client_secret' => $self->{_config}->{client_secret},
			'grant_type' => 'pin',
			'pin' => $pin,
		);

		my @params = (
			"https://api.imgur.com/oauth2/token",
			'Content' => [%params]
		);

		my $req = HTTP::Request::Common::POST(@params, 'Authorization' => 'Client-ID ' . $self->{_config}->{client_id});

		my $client = LWP::UserAgent->new(
			'timeout'    => 20,
			'keep_alive' => 10,
			'env_proxy'  => 1,
		);
		my $rsp = $client->request($req);

		my $json = JSON::MaybeXS->new(); 
		my $json_rsp = $json->decode($rsp->content);
		
		if ($self->{_debug_cparam}) {
			print $pin . ' ' . $rsp->content;
		}
		if (exists $json_rsp->{status} && $json_rsp->{status} ne 200) {
			return $self->setup;
		}

		$self->{_config}->{access_token} = $json_rsp->{access_token};
		$self->{_config}->{refresh_token} = $json_rsp->{refresh_token};
		$self->{_config}->{account_id} = $json_rsp->{account_id};
		$self->{_config}->{account_username} = $json_rsp->{account_username};

		$self->{_config_file}->openw->print(encode_json($self->{_config}));
		chmod 0600, $self->{_config_file};

		return TRUE;
	}
	else {
		return FALSE;
	}
}

sub upload {
	my ( $self, $upload_filename, $username, $password ) = @_;

	#store as object vars
	$self->{_filename} = $upload_filename;
	$self->{_username} = $username;
	$self->{_password} = $password;

	utf8::encode $upload_filename;
	utf8::encode $password;
	utf8::encode $username;

	my $client = LWP::UserAgent->new(
		'timeout'    => 20,
		'keep_alive' => 10,
		'env_proxy'  => 1,
	);

	eval {

		my $json = JSON::MaybeXS->new();

		open( IMAGE, $upload_filename ) or die "$!";
		my $binary_data = do { local $/ = undef; <IMAGE>; };
		close IMAGE;
		my $encoded_image = encode_base64($binary_data);

		my %params = (
			'image' => $encoded_image,
		);

		my @params = (
			"https://api.imgur.com/3/image",
			'Content' => [%params]
		);

		my $req;
		if ($username eq $d->get("OAuth") && $self->{_config}->{access_token}) {
			$req = HTTP::Request::Common::POST(@params, 'Authorization' => 'Bearer ' . $self->{_config}->{access_token});
		}
		else {
			$req = HTTP::Request::Common::POST(@params, 'Authorization' => 'Client-ID ' . $self->{_config}->{client_id});
		}
		my $rsp = $client->request($req);

		#~ print Dumper $json->decode( $rsp->content ); 

		my $json_rsp = $json->decode( $rsp->content );

		if ($json_rsp->{'status'} ne 200) {
			unlink $self->{_config_file};
			$self->{_links}{'status'} = '';
			if (exists $json_rsp->{'data'}->{'error'}) {
				$self->{_links}{'status'} .= $json_rsp->{'data'}->{'error'} . ': ';
			}
			$self->{_links}{'status'} .= $d->get("Maybe you or Imgur revoked or expired an access token. Please close this dialog and try again. Your account will be re-authenticated the next time you upload a file.");
			return %{ $self->{_links} };
		}

		$self->{_links}{'status'} = $json_rsp->{'status'};
		$self->{_links}->{'direct_link'} = $json_rsp->{'data'}->{'link'};
		$self->{_links}->{'deletion_link'} = 'https://imgur.com/delete/' . $json_rsp->{'data'}->{'deletehash'};
		$self->{_links}->{'post_link'} = $json_rsp->{'data'}->{'link'};
		$self->{_links}->{'post_link'} =~ s/i\.imgur/imgur/;
		$self->{_links}->{'post_link'} =~ s/\.[^.]+$//;

	};
	if ($@) {
		$self->{_links}{'status'} = $@;
		#~ print "$@\n";
	}

	#and return links
	return %{ $self->{_links} };
}

1;
