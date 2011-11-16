#! /usr/bin/env perl
###################################################
#
#  Copyright (C) <year> <author> <<email>>
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

package PROVIDER;

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

my %upload_plugin_info = 	(
    'module'		=> $d->get( "PROVIDER" ),							#edit this
	'url'			=> $d->get( "http://provider.com/" ),				#edit this
	'registration'  => $d->get( "http://provider.com/" ),				#edit this
	'name'			=> $d->get( "PROVIDER" ),							#edit this
	'description'	=> $d->get( "Upload screenshots to PROVIDER" ),		#edit this
	'supports_anonymous_upload'	 => TRUE,								#
	'supports_authorized_upload' => TRUE,								#
);

binmode( STDOUT, ":utf8" );
if ( exists $upload_plugin_info{$ARGV[ 0 ]} ) {
	print $upload_plugin_info{$ARGV[ 0 ]};
	exit;
}


#don't touch this
sub new {
	my $class = shift;

	#call constructor of super class (host, debug_cparam, shutter_root, gettext_object, main_gtk_window, ua)
	my $self = $class->SUPER::new( shift, shift, shift, shift, shift, shift );

	bless $self, $class;
	return $self;
}

#load some custom modules here (or do other custom stuff)	
sub init {
	my $self = shift;

	use JSON;					#example1
	use LWP::UserAgent;			#example2
	use HTTP::Request::Common;	#example3
	
	return TRUE;	
}

#handle 
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

	if ( $username ne "" && $password ne "" ) {

		eval{

			#SignIn
			my $req_login = HTTP::Request->new(POST => "http://minus.com/api/SignIn");
			$req_login->content_type("application/x-www-form-urlencoded");
			$req_login->content("username=" . $self->{_username} . "&password1=" . $self->{_password});

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
		my $gallery_json = $json_coder->decode($res_gallery->content);
		
		#upload if everything is fine
		if(defined $gallery_json->{'editor_id'}){

			my $url = "http://min.us/api/UploadItem?". "editor_id=" . $gallery_json->{'editor_id'} . "&key=OK&filename=" . $self->{_filename};

			$HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;

			my $req_upitem = POST(
				$url,
				Content_Type => 'multipart/form-data',
				Content      => [ file => [$self->{_filename}] ],
			);

			my $res = $browser->request($req_upitem);
			#~ print Dumper $res->content;

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


#you are free to implement some custom subs here, but please make sure they don't interfere with Shutter's subs
#hence, please follow this naming convention: _<provider>_sub (e.g. _imageshack_convert_x_to_y)


1;
