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
#
# Modified by Shlomi Fish ( http://www.shlomifish.org/ ), 2015 while disclaiming
# all rights to the modification.

package Gyazo;

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
    'module'        => "Gyazo",
	'url'           => "https://gyazo.com/",
	'registration'  => "https://gyazo.com/signup",
	'description'   => $d->get( "Gyazo is an open-source service for sharing screenshots." ),
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
    require WebService::Gyazo::B;

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

    my $client = WebService::Gyazo::B->new();

    eval {

        my $image = $client->uploadFile($upload_filename);

        if (!$client->isError) {
            my $url = $image->getImageUrl();
            $self->{_links} =
            +{
                status => 200,
                image_url => $url,
            };
            print "image_url: $url\n";
        }
        else {
            $self->{_links} =
            +{
                status => $client->error(),
            };
        }
    };

    if($@){
        $self->{_links}{'status'} = $@;
        #~ print "$@\n";
    }

    #and return links
    return %{ $self->{_links} };
}

1;