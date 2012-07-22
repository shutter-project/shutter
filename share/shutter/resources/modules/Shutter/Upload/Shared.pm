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
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
#
###################################################

package Shutter::Upload::Shared;

use utf8;
use strict;
use POSIX qw/setlocale/;
use Locale::gettext;
use Glib qw/TRUE FALSE/;
use Data::Dumper;

sub new {
	my $class = shift;

	my $self = {
		_host            => shift,
		_debug_cparam    => shift,
		_shutter_root    => shift,
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

sub create_tab {
	my $self = shift;

	my $upload_vbox = Gtk2::VBox->new( FALSE, 0 );

	#sizegroup for all labels
	my $sg = Gtk2::SizeGroup->new('horizontal');

	#create entry for each link
	foreach (keys %{$self->{_links}}){
		next if $_ eq 'status';
		my $box = $self->create_entry_for_notebook($_, $self->{_links}->{$_}, $sg);
		$upload_vbox->pack_start($box, FALSE, FALSE, 3);
	}
	
	return $upload_vbox;
}

sub create_entry_for_notebook {
	my ($self, $field, $value, $sg) = @_;

	#Clipboard
	my $clipboard = Gtk2::Clipboard->get( Gtk2::Gdk->SELECTION_CLIPBOARD );

	#Tooltips
	my $tooltips = Gtk2::Tooltips->new;
	
	my $upload_hbox1 = Gtk2::HBox->new(FALSE, 10);
	my $upload_hbox2 = Gtk2::HBox->new(FALSE, 10);
	
	#prepare $field
	$field =~ s/_/ /ig;
	$field = ucfirst $field;
	my $label = Gtk2::Label->new($field);
	$label->set_alignment( 0, 0.5 );
	$sg->add_widget($label);
	
	my $entry = Gtk2::Entry->new();
	$entry->set_text($value);
	$entry->signal_connect( 'button-release-event' => sub {
			my ($widget, $event) = @_;
			$widget->select_region(0, -1);
			return FALSE;
		}
	);
	
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
	
	$upload_hbox1->pack_start($label, FALSE, FALSE, 10);
	$upload_hbox1->pack_start($entry, TRUE, TRUE, 3);
	$upload_hbox2->pack_start($upload_hbox1, TRUE, TRUE, 0);
	$upload_hbox2->pack_start($upload_copy, FALSE, TRUE, 3);
	
	return $upload_hbox2;
}

sub show_all {
	my $self = shift;

	#are there any uploaded files?
	return FALSE if $self->{_notebook}->get_n_pages < 1;

	my $dlg_header = sprintf($self->{_gettext_object}->get("Upload - %s - %s"), $self->{_host}, $self->{_username});
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

	if($upload_response eq "accept") {
		$upload_dialog->destroy();
		return TRUE;
	} else {
		$upload_dialog->destroy();
		return FALSE;
	}
}

sub show {
	my $self = shift;

	#Tooltips
	my $tooltips = Gtk2::Tooltips->new;
	
	#Create label for each notebook page
	my $fnlabel = Gtk2::Label->new($self->{_filename});
	$fnlabel->set_ellipsize('middle');
	$fnlabel->set_width_chars(20);
	$tooltips->set_tip( $fnlabel, $self->{_filename} );

	$self->{_notebook}->append_page( $self->create_tab(), $fnlabel );

	return TRUE;
}

1;
