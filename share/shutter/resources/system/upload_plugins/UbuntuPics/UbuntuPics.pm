#! /usr/bin/env perl
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

package UbuntuPics;

use utf8;
use strict;
use POSIX qw/setlocale/;
use Locale::gettext;
use Glib qw/TRUE FALSE/; 

my $d = Locale::gettext->domain("shutter-plugins");
$d->dir( $ENV{'SHUTTER_INTL'} );

my %upload_plugin_info = 	(
    'module'		=> $d->get( "UbuntuPics"),
	'url'			=> $d->get( "http://www.ubuntu-pics.de" ),
	'registration'  => $d->get( "http://www.ubuntu-pics.de/reg") ,
	'name'			=> $d->get( "Ubuntu-Pics.de" ),
	'description'	=> $d->get( "Upload screenshots to ubuntu-pics.de"),
	'supports_anonymous_upload'	 => FALSE,
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

	my $self = {
		_host            => shift,
		_debug_cparam    => shift,
		_shutter_root     => shift,
		_gettext_object  => shift,
		_main_gtk_window => shift,
		_ua              => shift
	};

	#received links are stored here
	$self->{_links} = undef;

	#credentials and filename
	$self->{_filename} = undef;
	$self->{_username} = undef;
	$self->{_password} = undef;

	$self->{_notebook} = Gtk2::Notebook->new;
	$self->{_notebook}->set( homogeneous => 1 );
	$self->{_notebook}->set_scrollable(TRUE);

	bless $self, $class;
	return $self;
}

###################################################

sub init {
	my $self = shift;

	#do custom stuff here	
	use JSON;
	use LWP::UserAgent;
	use HTTP::Request::Common;
	
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

	if ( $username ne "" && $password ne "" ) {

	##########FIXME

		my $client = LWP::UserAgent->new(
			'timeout'    => 20,
			'keep_alive' => 10,
			'env_proxy'  => 1,
		  );

		  eval{

			my %data = (
				auth => {
					clientName		=> "Shutter",
					clientVersion	=> "0.86.4",
					clientKey		=> "8430a2028f301ad05b9d24039bc63673",
					clientWeb		=> "http://shutter-project.org",
				},
				upload => {
					userName		=> "betatest",
					password		=> "betatest",
					description		=> "",	
					tags			=> "",
				},
			);

			my $json = JSON->new(); 
			my $json_text = $json->encode(\%data);

			my %params = (
				'upload' => [$self->{_filename}],
				'json'   => $json_text,
			);

			my @params = (
				"http://api.ubuntu-pics.de",
				'Content_Type' => 'multipart/form-data',
				'Content' => [%params]
			);
			
			my $req = HTTP::Request::Common::POST(@params);
			my $rsp = $client->request($req);

			$self->{_links} = $json->decode( $rsp->content ); 
			if(defined $self->{_links}->{'action'} && $self->{_links}->{'action'} eq 'success'){
				foreach (keys %{$self->{_links}}){
					next if $_ eq 'transferid';
					next if $_ eq 'action';
					print $_.": ".$self->{_links}->{$_}, "\n";
				}
			}else{
				print $self->{_links}->{'code'}, "\n";
			}
			
		  };

		  if($@){
			print "$@\n";
		  }


		}

	##########FIXME

	$self->{_links}{'status'} = 200;
	return %{ $self->{_links} };
}

sub create_tab {
	my $self = shift;

	my $upload_vbox = Gtk2::VBox->new( FALSE, 0 );
	my $upload_hbox = Gtk2::HBox->new( FALSE, 0 );
	
	my $label_status = Gtk2::Label->new( $self->{_gettext_object}->get("FIXME") );

	#~ $upload_hbox->pack_start(
		#~ Gtk2::Image->new_from_pixbuf(
			#~ Gtk2::Gdk::Pixbuf->new_from_file_at_scale(
				#~ "$self->{_shutter_root}/share/shutter/resources/icons/logo-ubuntu-pics.png",
				#~ 100, 100, TRUE
			#~ )
		#~ ),
		#~ TRUE, TRUE, 0
	#~ );
	#~ 
	$upload_hbox->pack_start( $label_status, TRUE, TRUE, 0 );	

	$upload_vbox->pack_start( $upload_hbox, TRUE, TRUE, 10 );

	#call class method - FIXME!!!
	foreach (keys %{$self->{_links}}){
		next if $_ eq 'transferid';
		next if $_ eq 'action';
		next if $_ eq 'status';
		my $box = $self->create_entry_for_notebook($_, $self->{_links}->{$_});
		$upload_vbox->pack_start_defaults($box);
	}
	
	
	return $upload_vbox;
}

sub create_entry_for_notebook {
	my ($self, $field, $value) = @_;

	#Clipboard
	my $clipboard = Gtk2::Clipboard->get( Gtk2::Gdk->SELECTION_CLIPBOARD );

	#Tooltips
	my $tooltips = Gtk2::Tooltips->new;
	
	my $upload_hbox1 = Gtk2::HBox->new( TRUE,  10 );
	my $upload_hbox2 = Gtk2::HBox->new( FALSE, 10 );
	my $entry = Gtk2::Entry->new();
	$entry->set_text($value);
	
	my $upload_copy = Gtk2::Button->new;
	$tooltips->set_tip( $upload_copy,
		$self->{_gettext_object}->get("Copy this code to clipboard") );
	
	$upload_copy->set_image( Gtk2::Image->new_from_stock( 'gtk-copy', 'menu' ) );
	$upload_copy->signal_connect(
		'clicked' => sub {
			my ( $widget, $entry ) = @_;
			$clipboard->set_text( $entry->get_text );
		},
		$entry
	);

	$upload_hbox1->pack_start_defaults(Gtk2::Label->new($field));
	$upload_hbox1->pack_start_defaults($entry);
	$upload_hbox2->pack_start_defaults($upload_hbox1);
	$upload_hbox2->pack_start( $upload_copy, FALSE, TRUE, 10 );
	
	return $upload_hbox2;
}


sub show_all {
	my $self = shift;

	#are there any uploaded files?
	return FALSE if $self->{_notebook}->get_n_pages < 1;

	my $dlg_header
		= $self->{_gettext_object}->get("Upload") . " - "
		. $self->{_host} . " - "
		. $self->{_username};
	my $upload_dialog = Gtk2::Dialog->new(
		$dlg_header,
		$self->{_main_gtk_window},
		[qw/modal destroy-with-parent/],
		'gtk-ok' => 'accept'
	);
	$upload_dialog->set_default_response('accept');

	$upload_dialog->vbox->add( $self->{_notebook} );
	$upload_dialog->show_all;
	my $upload_response = $upload_dialog->run;

	if ( $upload_response eq "accept" ) {
		$upload_dialog->destroy();
		return TRUE;
	} else {
		$upload_dialog->destroy();
		return FALSE;
	}
}

sub show {
	my $self = shift;

	$self->{_notebook}->append_page( $self->create_tab(), $self->{_filename} );

	return TRUE;
}

1;
