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

package Shutter::Upload::UbuntuPics;

use SelfLoader;
use utf8;
use strict;
use WWW::Mechanize;
use HTTP::Status;

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

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

	$self->{_mech} = WWW::Mechanize->new( agent => "$self->{_ua}", timeout => 20 );
	$self->{_http_status} = undef;

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

1;

__DATA__

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

		$self->{_mech}->get("http://www.ubuntu-pics.de/login.html");
		$self->{_http_status} = $self->{_mech}->status();
		unless ( is_success( $self->{_http_status} ) ) {
			$self->{_links}{'status'} = $self->{_http_status};
			return %{ $self->{_links} };
		}

		#already logged in?
		unless ($self->{_mech}->find_link( text_regex => qr/logout/i )){
			$self->{_mech}->form_number(2);
			$self->{_mech}->field( name     => $username );
			$self->{_mech}->field( passwort => $password );
			$self->{_mech}->click("login");

			$self->{_http_status} = $self->{_mech}->status();
			unless ( is_success( $self->{_http_status} ) ) {
				$self->{_links}{'status'} = $self->{_http_status};
				return %{ $self->{_links} };
			}
			if ( $self->{_mech}->content =~ /Diese Login Daten sind leider falsch/ ) {
				$self->{_links}{'status'} = 999;
				return %{ $self->{_links} };
			}
			$self->{_links}{status} = 'OK Login';	
		}
	}

	$self->{_mech}->get("http://www.ubuntu-pics.de/easy.html");
	$self->{_http_status} = $self->{_mech}->status();
	unless ( is_success( $self->{_http_status} ) ) {
		$self->{_links}{'status'} = $self->{_http_status};
		return %{ $self->{_links} };
	}
	$self->{_mech}->submit_form(
		form_name => 'upload_bild',
		fields    => { "datei[]" => $upload_filename, }
	);

	$self->{_http_status} = $self->{_mech}->status();
	if ( is_success( $self->{_http_status} ) ) {
		my $html_file = $self->{_mech}->content;
		
		#error??
		if ( $html_file =~ /Es wurde keine Datei hochgeladen/ ) {
			$self->{_links}{'status'} = 'unknown';
			return %{ $self->{_links} };
		}

		$html_file =~ /id="thumb1" value='(.*)' onclick/g;
		$self->{_links}{'thumb1'} = $self->switch_html_entities($1);

		$html_file =~ /id="thumb2" value='(.*)' onclick/g;
		$self->{_links}{'thumb2'} = $self->switch_html_entities($1);

		$html_file =~ /id="bbcode" value='(.*)' onclick/g;
		$self->{_links}{'bbcode'} = $self->switch_html_entities($1);

		$html_file =~ /id="ubuntucode" value='(.*)' onclick/g;
		$self->{_links}{'ubuntucode'} = $self->switch_html_entities($1);

		$html_file =~ /id="direct" value='(.*)' onclick/g;
		$self->{_links}{'direct'} = $self->switch_html_entities($1);

		if ( $self->{_debug} ) {
			print "The following links were returned by http://www.ubuntu-pics.de:\n";
			print "Thumbnail for websites (with Border)\n$self->{_links}{'thumb1'}\n";
			print "Thumbnail for websites (without Border)\n$self->{_links}{'thumb2'}\n";
			print "Thumbnail for forums \n$self->{_links}{'bbcode'}\n";
			print "Thumbnail for Ubuntuusers.de forum \n$self->{_links}{'ubuntucode'}\n";
			print "Direct link \n$self->{_links}{'direct'}\n";
		}

		$self->{_links}{'status'} = $self->{_http_status};
		return %{ $self->{_links} };

	} else {
		$self->{_links}{'status'} = $self->{_http_status};
		return %{ $self->{_links} };
	}
}

sub create_tab {
	my $self = shift;

	#Clipboard
	my $clipboard = Gtk2::Clipboard->get( Gtk2::Gdk->SELECTION_CLIPBOARD );

	#Tooltips
	my $tooltips = Gtk2::Tooltips->new;

	my $upload_hbox   = Gtk2::HBox->new( FALSE, 0 );
	my $upload_hbox1  = Gtk2::HBox->new( TRUE,  10 );
	my $upload_hbox2  = Gtk2::HBox->new( FALSE, 10 );
	my $upload_hbox3  = Gtk2::HBox->new( TRUE,  10 );
	my $upload_hbox4  = Gtk2::HBox->new( FALSE, 10 );
	my $upload_hbox5  = Gtk2::HBox->new( TRUE,  10 );
	my $upload_hbox6  = Gtk2::HBox->new( FALSE, 10 );
	my $upload_hbox7  = Gtk2::HBox->new( TRUE,  10 );
	my $upload_hbox8  = Gtk2::HBox->new( FALSE, 10 );
	my $upload_hbox9  = Gtk2::HBox->new( TRUE,  10 );
	my $upload_hbox10 = Gtk2::HBox->new( FALSE, 10 );
	my $upload_vbox   = Gtk2::VBox->new( FALSE, 0 );

	my $label_status = Gtk2::Label->new( $self->{_gettext_object}->get("Upload status:") . " "
			. status_message( $self->{_http_status} ) );

	$upload_hbox->pack_start(
		Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_scale(
				"$self->{_shutter_root}/share/shutter/resources/icons/logo-ubuntu-pics.png",
				100, 100, TRUE
			)
		),
		TRUE, TRUE, 0
	);
	$upload_hbox->pack_start( $label_status, TRUE, TRUE, 0 );
	my $entry_thumb1     = Gtk2::Entry->new();
	my $entry_thumb2     = Gtk2::Entry->new();
	my $entry_bbcode     = Gtk2::Entry->new();
	my $entry_ubuntucode = Gtk2::Entry->new();
	my $entry_direct     = Gtk2::Entry->new();
	my $label_thumb1
		= Gtk2::Label->new( $self->{_gettext_object}->get("Thumbnail for websites (with border)") );
	my $label_thumb2 = Gtk2::Label->new(
		$self->{_gettext_object}->get("Thumbnail for websites (without border)") );
	my $label_bbcode = Gtk2::Label->new( $self->{_gettext_object}->get("Thumbnail for forums") );
	my $label_ubuntucode
		= Gtk2::Label->new( $self->{_gettext_object}->get("Thumbnail for Ubuntuusers.de forum") );
	my $label_direct = Gtk2::Label->new( $self->{_gettext_object}->get("Direct link") );
	$entry_thumb1->set_text( $self->{_links}{'thumb1'} );
	$entry_thumb2->set_text( $self->{_links}{'thumb2'} );
	$entry_bbcode->set_text( $self->{_links}{'bbcode'} );
	$entry_ubuntucode->set_text( $self->{_links}{'ubuntucode'} );
	$entry_direct->set_text( $self->{_links}{'direct'} );

	my $upload_copy1 = Gtk2::Button->new;
	$tooltips->set_tip( $upload_copy1,
		$self->{_gettext_object}->get("Copy this code to clipboard") );
	$upload_copy1->set_image( Gtk2::Image->new_from_stock( 'gtk-copy', 'menu' ) );
	$upload_copy1->signal_connect(
		'clicked' => sub {
			my ( $widget, $entry ) = @_;
			$clipboard->set_text( $entry->get_text );
		},
		$entry_thumb1
	);

	my $upload_copy2 = Gtk2::Button->new;
	$tooltips->set_tip( $upload_copy2,
		$self->{_gettext_object}->get("Copy this code to clipboard") );
	$upload_copy2->set_image( Gtk2::Image->new_from_stock( 'gtk-copy', 'menu' ) );
	$upload_copy2->signal_connect(
		'clicked' => sub {
			my ( $widget, $entry ) = @_;
			$clipboard->set_text( $entry->get_text );
		},
		$entry_thumb2
	);

	my $upload_copy3 = Gtk2::Button->new;
	$tooltips->set_tip( $upload_copy3,
		$self->{_gettext_object}->get("Copy this code to clipboard") );
	$upload_copy3->set_image( Gtk2::Image->new_from_stock( 'gtk-copy', 'menu' ) );
	$upload_copy3->signal_connect(
		'clicked' => sub {
			my ( $widget, $entry ) = @_;
			$clipboard->set_text( $entry->get_text );
		},
		$entry_bbcode
	);
	my $upload_copy4 = Gtk2::Button->new;
	$tooltips->set_tip( $upload_copy4,
		$self->{_gettext_object}->get("Copy this code to clipboard") );
	$upload_copy4->set_image( Gtk2::Image->new_from_stock( 'gtk-copy', 'menu' ) );
	$upload_copy4->signal_connect(
		'clicked' => sub {
			my ( $widget, $entry ) = @_;
			$clipboard->set_text( $entry->get_text );
		},
		$entry_ubuntucode
	);
	my $upload_copy5 = Gtk2::Button->new;
	$tooltips->set_tip( $upload_copy5,
		$self->{_gettext_object}->get("Copy this code to clipboard") );
	$upload_copy5->set_image( Gtk2::Image->new_from_stock( 'gtk-copy', 'menu' ) );
	$upload_copy5->signal_connect(
		'clicked' => sub {
			my ( $widget, $entry ) = @_;
			$clipboard->set_text( $entry->get_text );
		},
		$entry_direct
	);

	$upload_hbox1->pack_start_defaults($label_thumb1);
	$upload_hbox1->pack_start_defaults($entry_thumb1);
	$upload_hbox2->pack_start_defaults($upload_hbox1);
	$upload_hbox2->pack_start( $upload_copy1, FALSE, TRUE, 10 );

	$upload_hbox3->pack_start_defaults($label_thumb2);
	$upload_hbox3->pack_start_defaults($entry_thumb2);
	$upload_hbox4->pack_start_defaults($upload_hbox3);
	$upload_hbox4->pack_start( $upload_copy2, FALSE, TRUE, 10 );

	$upload_hbox5->pack_start_defaults($label_bbcode);
	$upload_hbox5->pack_start_defaults($entry_bbcode);
	$upload_hbox6->pack_start_defaults($upload_hbox5);
	$upload_hbox6->pack_start( $upload_copy3, FALSE, TRUE, 10 );

	$upload_hbox7->pack_start_defaults($label_ubuntucode);
	$upload_hbox7->pack_start_defaults($entry_ubuntucode);
	$upload_hbox8->pack_start_defaults($upload_hbox7);
	$upload_hbox8->pack_start( $upload_copy4, FALSE, TRUE, 10 );

	$upload_hbox9->pack_start_defaults($label_direct);
	$upload_hbox9->pack_start_defaults($entry_direct);
	$upload_hbox10->pack_start_defaults($upload_hbox9);
	$upload_hbox10->pack_start( $upload_copy5, FALSE, TRUE, 10 );

	$upload_vbox->pack_start( $upload_hbox, TRUE, TRUE, 10 );
	$upload_vbox->pack_start_defaults($upload_hbox2);
	$upload_vbox->pack_start_defaults($upload_hbox4);
	$upload_vbox->pack_start_defaults($upload_hbox6);
	$upload_vbox->pack_start_defaults($upload_hbox8);
	$upload_vbox->pack_start_defaults($upload_hbox10);

	return $upload_vbox;
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
