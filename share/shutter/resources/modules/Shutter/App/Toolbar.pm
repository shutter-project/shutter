###################################################
#
#  Copyright (C) 2008, 2009 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package Shutter::App::Toolbar;

#modules
#--------------------------------------
use utf8;
use strict;
use Gtk2;

#Gettext and filename parsing
use POSIX qw/setlocale strftime/;
use Locale::gettext;

#define constants
#--------------------------------------
use constant TRUE  => 1;
use constant FALSE => 0;

#--------------------------------------

##################public subs##################
sub new {
	my $class = shift;

	#constructor
	my $self = { _common => shift };

	bless $self, $class;
	return $self;
}

sub create_toolbar {
	my $self = shift;

	my $d           = $self->{_common}->get_gettext;
	my $window      = $self->{_common}->get_mainwindow;
	my $shutter_root = $self->{_common}->get_root;

	#Tooltips
	my $tooltips = $self->{_common}->get_tooltips;

	#button selection
	#--------------------------------------
	my $image_select = Gtk2::Image->new_from_pixbuf(
		Gtk2::Gdk::Pixbuf->new_from_file_at_size(
			"$shutter_root/share/shutter/resources/icons/selection.svg", Gtk2::IconSize->lookup('large-toolbar')
		)
	);
	$self->{_select} = Gtk2::MenuToolButton->new( $image_select, $d->get("Selection") );

	$tooltips->set_tip( $self->{_select}, $d->get("Draw a rectangular capture area with your mouse\nto select a specified screen area") );

	$self->{_select}->set_arrow_tooltip( $tooltips, $d->get("Choose selection tool"), 'arrow' );

	#--------------------------------------

	#button full screen
	#--------------------------------------
	my $image_raw = Gtk2::Image->new_from_pixbuf(
		Gtk2::Gdk::Pixbuf->new_from_file_at_size(
			"$shutter_root/share/shutter/resources/icons/fullscreen.svg",
			Gtk2::IconSize->lookup('large-toolbar')
		)
	);
	$self->{_full} = Gtk2::MenuToolButton->new( $image_raw, $d->get("Full Screen") );

	$tooltips->set_tip( $self->{_full}, $d->get("Take a screenshot of your whole desktop") );
	$self->{_full}->set_arrow_tooltip( $tooltips, $d->get("Capture a specific workspace"), 'arrow' );

	#--------------------------------------

	#button window
	#--------------------------------------
	my $image_window = Gtk2::Image->new_from_pixbuf(
		Gtk2::Gdk::Pixbuf->new_from_file_at_size(
			"$shutter_root/share/shutter/resources/icons/sel_window.svg",
			Gtk2::IconSize->lookup('large-toolbar')
		)
	);
	$self->{_window} = Gtk2::MenuToolButton->new( $image_window, $d->get("Window") );

	$tooltips->set_tip( $self->{_window}, $d->get("Select a window with your mouse") );
	$self->{_window}->set_arrow_tooltip( $tooltips, $d->get("Take a screenshot of a specific window"), 'arrow' );

	#--------------------------------------

	#button section
	#--------------------------------------
	my $image_window_sect = Gtk2::Image->new_from_pixbuf(
		Gtk2::Gdk::Pixbuf->new_from_file_at_size(
			"$shutter_root/share/shutter/resources/icons/sel_window_section.svg",
			Gtk2::IconSize->lookup('large-toolbar')
		)
	);
	$self->{_section} = Gtk2::ToolButton->new( $image_window_sect, $d->get("Section") );

	$tooltips->set_tip( $self->{_section},
		$d->get( "Captures only a section of the window. You will be able to select any child window by moving the mouse over it" ) );

	#--------------------------------------

	#button web
	#--------------------------------------
	my $image_web = Gtk2::Image->new_from_pixbuf(
		Gtk2::Gdk::Pixbuf->new_from_file_at_size(
			"$shutter_root/share/shutter/resources/icons/web_image.svg", Gtk2::IconSize->lookup('large-toolbar')
		)
	);
	$self->{_web} = Gtk2::MenuToolButton->new( $image_web, $d->get("Web") );

	#--------------------------------------

	#button edit
	#--------------------------------------
	my $image_edit = Gtk2::Image->new_from_pixbuf
		(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size( "$shutter_root/share/shutter/resources/icons/draw.svg", Gtk2::IconSize->lookup('large-toolbar') )
		);
	$self->{_edit} = Gtk2::ToolButton->new( $image_edit, $d->get("Edit") );

	#--------------------------------------	
	
	#button upload
	#--------------------------------------
	my $image_upload = Gtk2::Image->new_from_stock( 'gtk-network', 'large-toolbar' );
	$self->{_upload} = Gtk2::ToolButton->new( $image_upload, $d->get("Upload / Export") );

	#--------------------------------------	

	#create the toolbar
	$self->{_toolbar} = Gtk2::Toolbar->new;
	$self->{_toolbar}->set_show_arrow(TRUE);
	$self->{_toolbar}->set_style('both');
	$self->{_toolbar}->set_icon_size('large-toolbar');
	$self->{_toolbar}->insert( $self->{_select},             -1 );
	$self->{_toolbar}->insert( Gtk2::SeparatorToolItem->new, -1 );
	$self->{_toolbar}->insert( $self->{_full},               -1 );
	$self->{_toolbar}->insert( Gtk2::SeparatorToolItem->new, -1 );
	$self->{_toolbar}->insert( $self->{_window},             -1 );
	$self->{_toolbar}->insert( $self->{_section},            -1 );
	$self->{_toolbar}->insert( Gtk2::SeparatorToolItem->new, -1 );
	$self->{_toolbar}->insert( $self->{_web},                -1 );
	$self->{_toolbar}->insert( Gtk2::SeparatorToolItem->new, -1 );
	$self->{_toolbar}->insert( $self->{_edit},               -1 );
	$self->{_toolbar}->insert( $self->{_upload},             -1 );
	$self->{_toolbar}->set_size_request( 450, -1 );

	return $self->{_toolbar};
}

1;
