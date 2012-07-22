#! /usr/bin/env perl
###################################################
#
#  Copyright (C) 2010-2011  Vadim Rutkovsky <roignac@gmail.com>, Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package ToileLibre;

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
    'module'        => "ToileLibre",
	'url'           => "http://pix.toile-libre.org/",
	'registration'  => "-",
	'description'   => $d->get( "Upload screenshots to pix.toile-libre.org" ),
	'supports_anonymous_upload'	 => TRUE,
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
	use WWW::Mechanize;
	use HTTP::Status;
	use HTTP::Request::Common 'POST';
	
	$self->{_mech} = WWW::Mechanize->new( agent => "$self->{_ua}", timeout => 20 );
	$self->{_http_status} = undef;
	
	return TRUE;
}

sub upload {
	my ( $self, $upload_filename, $username, $password ) = @_;
	
	#store as object vars
	$self->{_filename} = $upload_filename;
	$self->{_username} = $username;
	$self->{_password} = $password;

	my $filesize     = -s $upload_filename;
	my $max_filesize = 15360000;
	if ( $filesize > $max_filesize ) {
		$self->{_links}{'status'} = 998;
		$self->{_links}{'max_filesize'} = sprintf( "%.2f", $max_filesize / 1024 ) . " KB";
		return %{ $self->{_links} };
	}

	utf8::encode $upload_filename;
	utf8::encode $password;
	utf8::encode $username;

	eval{

		$self->{_mech}->get("http://pix.toile-libre.org");
		$self->{_http_status} = $self->{_mech}->status();

		if ( is_success( $self->{_http_status} ) ) {
		
			$self->{_mech}->request(POST "http://pix.toile-libre.org/?action=upload",
				Content_Type => 'form-data',
					Content      => [
						img =>  [ $upload_filename ],
					],
			);
			
			$self->{_http_status} = $self->{_mech}->status();
				
			if ( is_success( $self->{_http_status} ) ) {
				my $html_file = $self->{_mech}->content;
				
				my @links = $html_file =~ m{ <textarea>(.*)</textarea> }gx;

				$self->{_links}{'view_image'} = $links[0];
				$self->{_links}{'direct_link'} = $links[1];
				$self->{_links}{'thumbnail_forum'} = $links[2];
				$self->{_links}{'forum'} = $links[3];
				$self->{_links}{'thumbnail website'} = $links[4];
				$self->{_links}{'website'} = $links[5];

				if ( $self->{_debug} ) {
					print "The following links were returned by http://pix.toile-libre.org:\n";
					print $self->{_links}{'view_image'},"\n";
					print $self->{_links}{'direct_link'},"\n";
					print $self->{_links}{'thumbnail_forum'},"\n";
					print $self->{_links}{'forum'},"\n";
					print $self->{_links}{'thumbnail website'},"\n";
					print $self->{_links}{'website'},"\n";
				}

				$self->{_links}{'status'} = $self->{_http_status};
			} else {
				$self->{_links}{'status'} = $self->{_http_status};
			}
	
		}else{
			$self->{_links}{'status'} = $self->{_http_status};
		}
	
	};
	if($@){
		$self->{_links}{'status'} = $@;
	}

	return %{ $self->{_links} };

}

1;
