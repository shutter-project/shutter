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

package ImageBanana;

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
    'module'        => "ImageBanana",
	'url'           => "http://imagebanana.com",
	'registration'  => "http://www.imagebanana.com/myib/registrieren",
	'description'   => $d->get( "Upload screenshots to imagebanana.com" ),
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
	use WWW::Mechanize;
	use HTTP::Status;
	
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
	my $max_filesize = 2048000;
	if ( $filesize > $max_filesize ) {
		$self->{_links}{'status'} = 998;
		$self->{_links}{'max_filesize'} = sprintf( "%.2f", $max_filesize / 1024 ) . " KB";
		return %{ $self->{_links} };
	}

	utf8::encode $upload_filename;
	utf8::encode $password;
	utf8::encode $username;
	
	if ( $username ne "" && $password ne "" ) {
		
		eval{
			$self->{_mech}->get("http://www.imagebanana.com/member/");
		};
		if($@){
			$self->{_links}{'status'} = $@;
			return %{ $self->{_links} };			
		}
		$self->{_http_status} = $self->{_mech}->status();
		unless ( is_success( $self->{_http_status} ) ) {
			$self->{_links}{'status'} = $self->{_http_status};
			return %{ $self->{_links} };
		}

		#already logged in?
		unless ( $self->{_mech}->find_link( text_regex => qr/logout/i ) ) {
			$self->{_mech}->field( member_nick     => $username );
			$self->{_mech}->field( member_password => $password );
			$self->{_mech}->click_button( value => 'Anmelden' );

			$self->{_http_status} = $self->{_mech}->status();
			unless ( is_success( $self->{_http_status} ) ) {
				$self->{_links}{'status'} = $self->{_http_status};
				return %{ $self->{_links} };
			}
			if ( $self->{_mech}->content =~ /Login fehlgeschlagen/ ) {
				$self->{_links}{'status'} = 999;
				return %{ $self->{_links} };
			}
			$self->{_links}{status} = 'OK Login';
		}

	}

	eval{
		$self->{_mech}->get("http://www.imagebanana.com/");
	};
	if($@){
		$self->{_links}{'status'} = $@;
		return %{ $self->{_links} };			
	}
	
	$self->{_http_status} = $self->{_mech}->status();
	unless ( is_success( $self->{_http_status} ) ) {
		$self->{_links}{'status'} = $self->{_http_status};
		return %{ $self->{_links} };
	}
	
	$self->{_mech}->form_number(1);
	$self->{_mech}->field( 'upload[]' => $upload_filename );
	$self->{_mech}->click_button( value => 'Hochladen!' );

	$self->{_http_status} = $self->{_mech}->status();
	if ( is_success( $self->{_http_status} ) ) {
		
		my $html_file = $self->{_mech}->content;
		#~ print $html_file, "\n";

		#error??
		if ( $html_file =~ /Upload Error/ ) {
			$self->{_links}{'status'} = 'unknown';
			return %{ $self->{_links} };
		}
		
		#new extended view
		$self->{_mech}->follow_link( url_regex => qr/\?extended/i );

		$self->{_http_status} = $self->{_mech}->status();
		unless ( is_success( $self->{_http_status} ) ) {
			$self->{_links}{'status'} = $self->{_http_status};
			return %{ $self->{_links} };		
		}
		
		my $html_file = $self->{_mech}->content;
		#~ print $html_file, "\n";
		
		$html_file = $self->switch_html_entities($html_file);

		my @link_array;
		while ( $html_file =~ /type="text" value="(.*)"/g ) {
			push( @link_array, $1 );
		}

		$self->{_links}{'thumbnail for websites'} = $link_array[1];
		$self->{_links}{'thumbnail for forums'} = $link_array[2];
		$self->{_links}{'hotlink for websites'} = $link_array[3];
		$self->{_links}{'hotlink for forums'} = $link_array[4];
		$self->{_links}{'direct link'} = $link_array[5];

		if ( $self->{_debug_cparam} ) {
			print "The following links were returned by http://www.imagebanana.com:\n";
			print $self->{_links}{'thumbnail for websites'} . "\n";
			print $self->{_links}{'thumbnail for forums'} . "\n";
			print $self->{_links}{'hotlink for websites'} . "\n";
			print $self->{_links}{'hotlink for forums'} . "\n";
			print $self->{_links}{'direct link'} . "\n";
		}

		$self->{_links}{'status'} = $self->{_http_status};
		return %{ $self->{_links} };

	} else {
		$self->{_links}{'status'} = $self->{_http_status};
		return %{ $self->{_links} };
	}
}

sub switch_html_entities {
	my $self = shift;
	my ($code) = @_;
	$code =~ s/&amp;/\&/g;
	$code =~ s/&lt;/</g;
	$code =~ s/&gt;/>/g;
	$code =~ s/&quot;/\"/g;
	return $code;
}

1;
