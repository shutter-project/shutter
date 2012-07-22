#! /usr/bin/env perl
###################################################
#
#  Copyright (C) 2010-2012 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package ITmages;

use lib $ENV{'SHUTTER_ROOT'}.'/share/shutter/resources/modules';

use utf8;
use strict;
use POSIX qw/setlocale/;
use Locale::gettext;
use Glib qw/TRUE FALSE/;

use Shutter::Upload::Shared;
our @ISA = qw(Shutter::Upload::Shared);

my $d = Locale::gettext->domain("shutter-upload-plugins");
$d->dir( $ENV{'SHUTTER_INTL'} );

my %upload_plugin_info = (
    'module'        => "ITmages",
	'url'           => "http://itmages.com/",
	'registration'  => "http://itmages.com/user/register",
	'description'   => $d->get( "Upload screenshots to itmages.com" ),
	'supports_anonymous_upload'  => TRUE,
	'supports_authorized_upload' => FALSE,
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
	use LWP::UserAgent;
	use HTTP::Request::Common;
	use XML::Simple;
	
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

	#~ if ( $username ne "" && $password ne "" ) {

		my $client = LWP::UserAgent->new(
			'timeout'    => 20,
			'keep_alive' => 10,
			'env_proxy'  => 1,
		);

		eval{

			my @params = (
				'http://itmages.com/api/v2/add',
				'Content_Type' => 'form-data',
				'Content' => [
					"UFileManager[picture]" => "",
					"UFileManager[picture]" => [ $upload_filename, $upload_filename ],
					"yt0" => "Upload",
				]				
			);

			my $req = HTTP::Request::Common::POST(@params);
			push @{ $client->requests_redirectable }, 'POST';
			my $rsp = $client->request($req);

			#convert XML
			my $ref = XMLin($rsp->content);

			if(defined $ref->{'status'} && $ref->{'status'} eq 'ok'){			
				#construct links
				$self->{_links}->{'direct_link'} = "http://"
					. $ref->{'item'}->{'server'} . ".static.itmages.com/" . $ref->{'item'}->{'iuri'};
				$self->{_links}->{'thumbnail'} = "http://"
					. $ref->{'item'}->{'server'} . ".static.itmages.com/" . $ref->{'item'}->{'turi'};
				
				#debug
				if( $self->{_debug_cparam}) {
					foreach (keys %{$self->{_links}}){
						print $_.": ".$self->{_links}->{$_}, "\n";
					}
				}
				
				#set status (success)
				$self->{_links}{'status'} = 200;				
			}else{
				$self->{_links}{'status'} = $ref->{'err'}->{'msg'};
			}
    
		};
		if($@){
			$self->{_links}{'status'} = $@;
			#~ print "$@\n";
		}

	#~ }else{
		#~ 
	#~ }
	
	#and return links
	return %{ $self->{_links} };
}

1;
