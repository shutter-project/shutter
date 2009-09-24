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
	
	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	#button selection
	#--------------------------------------
	my $image_select;
	if($icontheme->has_icon('applications-accessories')){
		$image_select = Gtk2::Image->new_from_icon_name( 'applications-accessories', 'large-toolbar' );		
	}else{
		$image_select = Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size(
				"$shutter_root/share/shutter/resources/icons/selection.svg", Gtk2::IconSize->lookup('large-toolbar')
			)
		);
	}	
	$self->{_select} = Gtk2::MenuToolButton->new( $image_select, $d->get("Selection") );
	#The GtkToolButton class uses this property to determine whether 
	#to show or hide its label when the toolbar style is GTK_TOOLBAR_BOTH_HORIZ. 
	#The result is that only tool buttons with the 
	#"is_important" property set have labels, an effect known as "priority text"
	$self->{_select}->set_is_important (TRUE);

	$tooltips->set_tip( $self->{_select}, $d->get("Draw a rectangular capture area with your mouse\nto select a specified screen area"), '' );
	$self->{_select}->set_arrow_tooltip( $tooltips, $d->get("Choose selection tool"), '' );

	#--------------------------------------

	#button full screen
	#--------------------------------------
	my $image_raw = Gtk2::Image->new_from_stock('gtk-fullscreen', 'large-toolbar');
	$self->{_full} = Gtk2::MenuToolButton->new( $image_raw, $d->get("Full Screen") );
	$self->{_full}->set_is_important (TRUE);

	$tooltips->set_tip( $self->{_full}, $d->get("Take a screenshot of your whole desktop") );
	$self->{_full}->set_arrow_tooltip( $tooltips, $d->get("Capture a specific workspace"), '' );

	#--------------------------------------

	#button window
	#--------------------------------------
	my $image_window;
	if($icontheme->has_icon('preferences-system-windows')){
		$image_window = Gtk2::Image->new_from_icon_name( 'preferences-system-windows', 'large-toolbar' );		
	}else{
		$image_window = Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size(
				"$shutter_root/share/shutter/resources/icons/sel_window.svg",
				Gtk2::IconSize->lookup('large-toolbar')
			)
		);
	}
	$self->{_window} = Gtk2::MenuToolButton->new( $image_window, $d->get("Window") );
	$self->{_window}->set_is_important (TRUE);

	$tooltips->set_tip( $self->{_window}, $d->get("Select a window with your mouse") );
	$self->{_window}->set_arrow_tooltip( $tooltips, $d->get("Take a screenshot of a specific window"), '' );

	#--------------------------------------

	#button section
	#--------------------------------------
	my $image_window_sect;
	if($icontheme->has_icon('gdm-xnest')){
		$image_window_sect = Gtk2::Image->new_from_icon_name( 'gdm-xnest', 'large-toolbar' );		
	}else{
		$image_window_sect = Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size(
				"$shutter_root/share/shutter/resources/icons/sel_window_section.svg",
				Gtk2::IconSize->lookup('large-toolbar')
			)
		);
	}
	$self->{_section} = Gtk2::ToolButton->new( $image_window_sect, $d->get("Section") );

	$tooltips->set_tip( $self->{_section},
		$d->get( "Captures only a section of the window. You will be able to select any child window by moving the mouse over it" ) );

	#--------------------------------------

	#button menu
	#--------------------------------------
	my $image_window_menu;
	if($icontheme->has_icon('alacarte')){
		$image_window_menu = Gtk2::Image->new_from_icon_name( 'alacarte', 'large-toolbar' );		
	}else{
		$image_window_menu = Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size(
				"$shutter_root/share/shutter/resources/icons/sel_window_menu.svg",
				Gtk2::IconSize->lookup('large-toolbar')
			)
		);
	}
	$self->{_menu} = Gtk2::ToolButton->new( $image_window_menu, $d->get("Menu") );

	$tooltips->set_tip( $self->{_menu},
		$d->get( "Select a single menu or cascading menus from any application" ) );

	#--------------------------------------

	#button tooltip
	#--------------------------------------
	my $image_window_tooltip;
	#~ if($icontheme->has_icon('alacarte')){
		#~ $image_window_tooltip = Gtk2::Image->new_from_icon_name( 'alacarte', 'large-toolbar' );		
	#~ }else{
		$image_window_tooltip = Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size(
				"$shutter_root/share/shutter/resources/icons/sel_window_tooltip.svg",
				Gtk2::IconSize->lookup('large-toolbar')
			)
		);
	#~ }
	$self->{_tooltip} = Gtk2::ToolButton->new( $image_window_tooltip, $d->get("Tooltip") );

	$tooltips->set_tip( $self->{_tooltip},
		$d->get( "Capture a tooltip" ) );

	#--------------------------------------

	#button web
	#--------------------------------------
	my $image_web;
	if($icontheme->has_icon('applications-internet')){
		$image_web = Gtk2::Image->new_from_icon_name( 'applications-internet', 'large-toolbar' );		
	}else{
		$image_web = Gtk2::Image->new_from_pixbuf(
				Gtk2::Gdk::Pixbuf->new_from_file_at_size(
				"$shutter_root/share/shutter/resources/icons/web_image.svg", Gtk2::IconSize->lookup('large-toolbar')
			)
		);
	}
	$self->{_web} = Gtk2::MenuToolButton->new( $image_web, $d->get("Web") );

	$tooltips->set_tip( $self->{_web}, $d->get("Take a screenshot of a website") );
	$self->{_web}->set_arrow_tooltip( $tooltips, $d->get("The timeout in seconds, or 0 to disable timeout"), '' );

	#--------------------------------------

	#button edit
	#--------------------------------------
	my $image_edit;
	if($icontheme->has_icon('applications-graphics')){
		$image_edit = Gtk2::Image->new_from_icon_name( 'applications-graphics', 'large-toolbar' );		
	}else{
		$image_edit = Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size( 
			"$shutter_root/share/shutter/resources/icons/draw.svg", Gtk2::IconSize->lookup('large-toolbar') )
		);
	}	
	$self->{_edit} = Gtk2::ToolButton->new( $image_edit, $d->get("Edit") );
	$self->{_edit}->set_is_important (TRUE);

	$tooltips->set_tip( $self->{_edit}, $d->get("Use the built-in editor to highlight important fragments of your screenshot or crop it to a desired size") );

	#--------------------------------------	
	
	#button upload
	#--------------------------------------
	my $image_upload = Gtk2::Image->new_from_stock( 'gtk-network', 'large-toolbar' );
	$self->{_upload} = Gtk2::ToolButton->new( $image_upload, $d->get("Upload / Export") );

	$tooltips->set_tip( $self->{_upload}, $d->get("Upload your images to an image hosting service, FTP site or export them to an arbitrary folder") );

	#--------------------------------------	

	#create the toolbar
	$self->{_toolbar} = Gtk2::Toolbar->new;
	$self->{_toolbar}->set_show_arrow(FALSE);
	$self->{_toolbar}->insert( $self->{_select},             -1 );
	$self->{_toolbar}->insert( Gtk2::SeparatorToolItem->new, -1 );
	$self->{_toolbar}->insert( $self->{_full},               -1 );
	$self->{_toolbar}->insert( Gtk2::SeparatorToolItem->new, -1 );
	$self->{_toolbar}->insert( $self->{_window},             -1 );
	$self->{_toolbar}->insert( $self->{_section},            -1 );
	$self->{_toolbar}->insert( $self->{_menu},               -1 );
	$self->{_toolbar}->insert( $self->{_tooltip},            -1 );
	$self->{_toolbar}->insert( Gtk2::SeparatorToolItem->new, -1 );
	$self->{_toolbar}->insert( $self->{_web},                -1 );
	$self->{_toolbar}->insert( Gtk2::SeparatorToolItem->new, -1 );
	$self->{_toolbar}->insert( $self->{_edit},               -1 );
	$self->{_toolbar}->insert( $self->{_upload},             -1 );

	return $self->{_toolbar};
}

1;
