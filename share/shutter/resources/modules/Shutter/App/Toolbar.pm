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

package Shutter::App::Toolbar;

#modules
#--------------------------------------
use utf8;
use strict;
use Gtk3;

#Glib
use Glib qw/TRUE FALSE/;

#--------------------------------------

sub new {
	my $class = shift;
	my $sc = shift;

	#constructor
	my $self = {
		_common => $sc,
		_shf => Shutter::App::HelperFunctions->new($sc),
	};

	bless $self, $class;
	return $self;
}

sub create_toolbar {
	my $self = shift;

	my $d            = $self->{_common}->get_gettext;
	my $window       = $self->{_common}->get_mainwindow;
	my $shutter_root = $self->{_common}->get_root;

	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	#button redoshot
	#--------------------------------------
	my $image_redoshot = Gtk3::Image->new_from_stock('gtk-refresh', 'large-toolbar');
	$self->{_redoshot} = Gtk3::ToolButton->new($image_redoshot, $d->get("Redo"));

	#~ $self->{_redoshot}->set_is_important (TRUE);

	$self->{_redoshot}->set_tooltip_text($d->get("Redo last screenshot"));

	#--------------------------------------

	#button selection
	#--------------------------------------
	my $image_select;
	eval {
		my $ccursor_pb = Gtk3::Gdk::Cursor->new('left_ptr')->get_image->scale_simple($self->{_shf}->icon_size('large-toolbar'), 'bilinear');
		$image_select = Gtk3::Image->new_from_pixbuf($ccursor_pb);
	};
	if ($@) {
		if ($icontheme->has_icon('applications-accessories')) {
			$image_select = Gtk3::Image->new_from_icon_name('applications-accessories', 'large-toolbar');
		} else {
			$image_select =
				Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/selection.svg", $self->{_shf}->icon_size('large-toolbar')));
		}
	}

	$self->{_select} = Gtk3::ToolButton->new($image_select, $d->get("Selection"));

	#The GtkToolButton class uses this property to determine whether
	#to show or hide its label when the toolbar style is GTK_TOOLBAR_BOTH_HORIZ.
	#The result is that only tool buttons with the
	#"is_important" property set have labels, an effect known as "priority text"
	$self->{_select}->set_is_important(TRUE);

	$self->{_select}->set_tooltip_text($d->get("Draw a rectangular capture area with your mouse\nto select a specified screen area"));

	#--------------------------------------

	#button full screen
	#--------------------------------------
	my $image_full;
	if ($icontheme->has_icon('user-desktop')) {
		$image_full = Gtk3::Image->new_from_icon_name('user-desktop', 'large-toolbar');
	} elsif ($icontheme->has_icon('desktop')) {
		$image_full = Gtk3::Image->new_from_icon_name('desktop', 'large-toolbar');
	} else {
		$image_full = Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/desktop.svg", $self->{_shf}->icon_size('large-toolbar')));
	}
	$self->{_full} = Gtk3::MenuToolButton->new($image_full, $d->get("Desktop"));
	$self->{_full}->set_is_important(TRUE);

	$self->{_full}->set_tooltip_text($d->get("Take a screenshot of your whole desktop"));
	$self->{_full}->set_arrow_tooltip_text($d->get("Capture a specific workspace"));

	#--------------------------------------

	#button active window
	#--------------------------------------
	#~ my $image_awindow;
	#~ if($icontheme->has_icon('preferences-system-windows')){
	#~ $image_awindow = Gtk3::Image->new_from_icon_name( 'preferences-system-windows', 'large-toolbar' );
	#~ }else{
	#~ $image_awindow = Gtk3::Image->new_from_pixbuf(
	#~ Gtk3::Gdk::Pixbuf->new_from_file_at_size(
	#~ "$shutter_root/share/shutter/resources/icons/sel_window_active.svg",
	#~ $self->{_shf}->icon_size('large-toolbar')
	#~ )
	#~ );
	#~ }
	#~ $self->{_awindow} = Gtk3::MenuToolButton->new( $image_awindow, $d->get("Window") );
	#~ $self->{_awindow}->set_is_important (TRUE);
	#~
	#~  $self->{_awindow}->set_tooltip_text($d->get("Capture active window") );
	#~ $self->{_awindow}->set_arrow_tooltip( $tooltips, $d->get("Take a screenshot of a specific window"), '' );

	#--------------------------------------

	#button window
	#--------------------------------------
	my $image_window;
	if ($icontheme->has_icon('preferences-system-windows')) {
		$image_window = Gtk3::Image->new_from_icon_name('preferences-system-windows', 'large-toolbar');
	} else {
		$image_window = Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/sel_window.svg", $self->{_shf}->icon_size('large-toolbar')));
	}
	$self->{_window} = Gtk3::MenuToolButton->new($image_window, $d->get("Window"));
	$self->{_window}->set_is_important(TRUE);

	$self->{_window}->set_tooltip_text($d->get("Select a window with your mouse"));
	$self->{_window}->set_arrow_tooltip_text($d->get("Take a screenshot of a specific window"));

	#button section
	#--------------------------------------
	my $image_window_sect;
	if ($icontheme->has_icon('gdm-xnest')) {
		$image_window_sect = Gtk3::Image->new_from_icon_name('gdm-xnest', 'large-toolbar');
	} else {
		$image_window_sect =
			Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/sel_window_section.svg", $self->{_shf}->icon_size('large-toolbar')));
	}
	$self->{_section} = Gtk3::ToolButton->new($image_window_sect, $d->get("Section"));

	$self->{_section}->set_tooltip_text($d->get("Captures only a section of the window. You will be able to select any child window by moving the mouse over it"));

	#--------------------------------------

	#button menu
	#--------------------------------------
	my $image_window_menu;
	if ($icontheme->has_icon('alacarte')) {
		$image_window_menu = Gtk3::Image->new_from_icon_name('alacarte', 'large-toolbar');
	} else {
		$image_window_menu =
			Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/sel_window_menu.svg", $self->{_shf}->icon_size('large-toolbar')));
	}
	$self->{_menu} = Gtk3::ToolButton->new($image_window_menu, $d->get("Menu"));

	$self->{_menu}->set_tooltip_text($d->get("Select a single menu or cascading menus from any application"));

	#--------------------------------------

	#button tooltip
	#--------------------------------------
	my $image_window_tooltip;
	if ($icontheme->has_icon('help-faq')) {
		$image_window_tooltip = Gtk3::Image->new_from_icon_name('help-faq', 'large-toolbar');
	} else {
		$image_window_tooltip =
			Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/sel_window_tooltip.svg", $self->{_shf}->icon_size('large-toolbar')));
	}
	$self->{_tooltip} = Gtk3::ToolButton->new($image_window_tooltip, $d->get("Tooltip"));

	$self->{_tooltip}->set_tooltip_text($d->get("Capture a tooltip"));

	#--------------------------------------

	#button web
	#--------------------------------------
	my $image_web;
	if ($icontheme->has_icon('web-browser')) {
		$image_web = Gtk3::Image->new_from_icon_name('web-browser', 'large-toolbar');
	} else {
		$image_web = Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/web_image.svg", $self->{_shf}->icon_size('large-toolbar')));
	}
	$self->{_web} = Gtk3::MenuToolButton->new($image_web, $d->get("Web"));

	$self->{_web}->set_tooltip_text($d->get("Take a screenshot of a website"));
	$self->{_web}->set_arrow_tooltip_text($d->get("Set how long Shutter will wait for the screenshot to complete before aborting the process if it's taking too long"));

	#--------------------------------------

	#expanding separator
	#--------------------------------------
	my $expander_r = Gtk3::SeparatorToolItem->new;
	$expander_r->set_expand(TRUE);
	$expander_r->set_draw(FALSE);

	#button edit
	#--------------------------------------
	my $image_edit;
	if ($icontheme->has_icon('applications-graphics')) {
		$image_edit = Gtk3::Image->new_from_icon_name('applications-graphics', 'large-toolbar');
	} else {
		$image_edit = Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/draw.svg", $self->{_shf}->icon_size('large-toolbar')));
	}
	$self->{_edit} = Gtk3::ToolButton->new($image_edit, $d->get("Edit"));
	$self->{_edit}->set_is_important(TRUE);

	$self->{_edit}->set_tooltip_text($d->get("Use the built-in editor to highlight important fragments of your screenshot or crop it to a desired size"));

	#--------------------------------------

	#button upload
	#--------------------------------------
	my $image_upload = Gtk3::Image->new_from_stock('gtk-network', 'large-toolbar');
	$self->{_upload} = Gtk3::MenuToolButton->new($image_upload, $d->get("Export"));
	$self->{_upload}->set_is_important(TRUE);

	$self->{_upload}->set_tooltip_text($d->get("Upload your images to an image hosting service, FTP site or export them to an arbitrary folder"));
	$self->{_upload}->set_arrow_tooltip_text($d->get("Show links to previous uploads"));

	#--------------------------------------

	#create the toolbar
	$self->{_toolbar} = Gtk3::Toolbar->new;
	$self->{_toolbar}->set_show_arrow(FALSE);
	$self->{_toolbar}->insert($self->{_redoshot},           -1);
	$self->{_toolbar}->insert(Gtk3::SeparatorToolItem->new, -1);
	$self->{_toolbar}->insert($self->{_select},             -1);
	$self->{_toolbar}->insert($self->{_full},               -1);

	#~ $self->{_toolbar}->insert( Gtk3::SeparatorToolItem->new, -1 );
	#~ $self->{_toolbar}->insert( $self->{_aindow},             -1 );
	$self->{_toolbar}->insert($self->{_window},  -1);
	$self->{_toolbar}->insert($self->{_section}, -1);
	$self->{_toolbar}->insert($self->{_menu},    -1);
	$self->{_toolbar}->insert($self->{_tooltip}, -1);

	#~ $self->{_toolbar}->insert( Gtk3::SeparatorToolItem->new, -1 );
	$self->{_toolbar}->insert($self->{_web}, -1);

	#~ $self->{_toolbar}->insert( Gtk3::SeparatorToolItem->new, -1 );
	$self->{_toolbar}->insert($expander_r,      -1);
	$self->{_toolbar}->insert($self->{_edit},   -1);
	$self->{_toolbar}->insert($self->{_upload}, -1);

	return $self->{_toolbar};
}

sub create_btoolbar {
	my $self = shift;

	my $d            = $self->{_common}->get_gettext;
	my $window       = $self->{_common}->get_mainwindow;
	my $shutter_root = $self->{_common}->get_root;

	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	#expanding separator
	#--------------------------------------
	my $expander_l = Gtk3::SeparatorToolItem->new;
	$expander_l->set_expand(TRUE);
	$expander_l->set_draw(FALSE);

	#--------------------------------------

	#button ascending
	#--------------------------------------
	my $image_sorta = Gtk3::Image->new_from_stock('gtk-sort-ascending', 'small-toolbar');
	$self->{_sorta} = Gtk3::ToggleToolButton->new();
	$self->{_sorta}->set_icon_widget($image_sorta);

	#--------------------------------------

	#button back
	#--------------------------------------
	my $image_back = Gtk3::Image->new_from_stock('gtk-go-back', 'small-toolbar');
	$self->{_back} = Gtk3::ToolButton->new($image_back, '');

	#--------------------------------------

	#button home
	#--------------------------------------
	my $image_home = Gtk3::Image->new_from_stock('gtk-index', 'small-toolbar');
	$self->{_home} = Gtk3::ToolButton->new($image_home, '');

	#--------------------------------------

	#button forward
	#--------------------------------------
	my $image_forw = Gtk3::Image->new_from_stock('gtk-go-forward', 'small-toolbar');
	$self->{_forw} = Gtk3::ToolButton->new($image_forw, '');

	#--------------------------------------

	#button sort descending
	#--------------------------------------
	my $image_sortd = Gtk3::Image->new_from_stock('gtk-sort-descending', 'small-toolbar');
	$self->{_sortd} = Gtk3::ToggleToolButton->new();
	$self->{_sortd}->set_icon_widget($image_sortd);

	#--------------------------------------

	#expanding separator
	#--------------------------------------
	my $expander_r = Gtk3::SeparatorToolItem->new;
	$expander_r->set_expand(TRUE);
	$expander_r->set_draw(FALSE);

	#--------------------------------------

	#create the toolbar
	$self->{_btoolbar} = Gtk3::Toolbar->new;
	$self->{_btoolbar}->set_no_show_all(TRUE);
	$self->{_btoolbar}->set_show_arrow(FALSE);
	$self->{_btoolbar}->set_style('icons');
	$self->{_btoolbar}->insert($expander_l,     -1);
	$self->{_btoolbar}->insert($self->{_sorta}, -1);
	$self->{_btoolbar}->insert($self->{_back},  -1);
	$self->{_btoolbar}->insert($self->{_home},  -1);
	$self->{_btoolbar}->insert($self->{_forw},  -1);
	$self->{_btoolbar}->insert($self->{_sortd}, -1);
	$self->{_btoolbar}->insert($expander_r,     -1);

	return $self->{_btoolbar};
}

1;
