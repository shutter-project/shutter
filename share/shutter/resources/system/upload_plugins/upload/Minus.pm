#! /usr/bin/env perl
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

package Minus;

use lib $ENV{'SHUTTER_ROOT'}.'/share/shutter/resources/modules';

use utf8;
use strict;
use POSIX qw/setlocale/;
use Locale::gettext;
use Glib qw/TRUE FALSE/;
use Data::Dumper;

use Shutter::Upload::Shared;
our @ISA = qw(Shutter::Upload::Shared);

my $d = Locale::gettext->domain("shutter-upload-plugins");
$d->dir( $ENV{'SHUTTER_INTL'} );

my %upload_plugin_info = (
    'module'        => "Minus",
	'url'           => "http://minus.com/",
	'registration'  => "http://minus.com/",
	'description'   => $d->get( "Minus is the simplest free file sharing platform online" ),
	'supports_anonymous_upload'	 => TRUE,
	'supports_authorized_upload' => TRUE,
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
	use JSON;
	use LWP::UserAgent;
	use HTTP::Request::Common;
	use HTTP::Cookies;
	use File::Basename qw(basename);
	
	return TRUE;	
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

	my $json_coder = JSON::XS->new;

	my $browser = LWP::UserAgent->new(
		'timeout'    => 20,
		'keep_alive' => 10,
		'env_proxy'  => 1,
	);

	#~ $browser->add_handler("request_send",  sub { shift->dump; return });
	#~ $browser->add_handler("response_done", sub { shift->dump; return });
	
	#create cookie jar
	my $cookie_jar = HTTP::Cookies->new(autosave => 1, ignore_discard => 1);

	if ( $username ne "" && $password ne "" ) {

		eval{

			#SignIn
			my $req_login = HTTP::Request->new(POST => "http://minus.com/api/SignIn");
			$req_login->content_type("application/x-www-form-urlencoded");
			$req_login->content("username=" . $username . "&password1=" . $password);

			my $res_login = $browser->request($req_login); #login
			my $login_json = $json_coder->decode($res_login->content);
			$login_json->{'success'} += 0; #see http://www.perlmonks.org/?node_id=773713
			
			unless(defined $login_json->{'success'} && $login_json->{'success'} == 1){
				$self->{_links}{'status'} = 999;
				return;
			}

		};
		if($@){
			$self->{_links}{'status'} = $@;
			return %{ $self->{_links} };
		}
		if($self->{_links}{'status'} == 999){
			return %{ $self->{_links} };
		}
		
	}
	
	eval{
		
		#CreateGallery
		my $req_gallery = HTTP::Request->new(POST => "http://minus.com/api/CreateGallery");
		my $res_gallery = $browser->request($req_gallery);
		
		# extract cookie from response header
		$cookie_jar->extract_cookies($res_gallery);
		
		my $gallery_json = $json_coder->decode($res_gallery->content);
		
		#upload if everything is fine
		if(defined $gallery_json->{'editor_id'}){

			my $url = "http://min.us/api/UploadItem?". "editor_id=" . $gallery_json->{'editor_id'} . "&key=OK&filename=" . basename($upload_filename);

			$HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
			
			#construct POST request (don't forget the cookie)
			my $req_upitem = POST(
				$url,
				Content_Type => 'multipart/form-data',
				Content => [ file => [$upload_filename] ],
				Cookie => $cookie_jar->as_string,
			);
			
			#execute upload request
			my $res = $browser->request($req_upitem);

			if ($res->status_line =~ m/^200/ ) {
				#construct link
				my $upload_json = $json_coder->decode($res->content);
				$self->{_links}->{'direct_link'} = "http://minus.com/l".$upload_json->{'id'};
				#debug
				if( $self->{_debug_cparam}) {
					foreach (keys %{$self->{_links}}){
						print $_.": ".$self->{_links}->{$_}, "\n";
					}
				}
				$self->{_links}{'status'} = 200;	
			} else { 
			   $self->{_links}{'status'} = $res->status_line;
			}

		#createGallery failed
		}else{
			$self->{_links}{'status'} = $@;
		}
		
	};
	if($@){
		$self->{_links}{'status'} = $@;
	}
	
	#and return links
	return %{ $self->{_links} };
}

1;
