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

package Shutter::App::Menu;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;
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

sub create_menu {
	my $self = shift;

	my $d            = $self->{_common}->get_gettext;
	my $shutter_root = $self->{_common}->get_root;

	my $accel_group = Gtk3::AccelGroup->new;
	$self->{_common}->get_mainwindow->add_accel_group($accel_group);

	#MenuBar
	$self->{_menubar} = Gtk3::MenuBar->new();

	#file
	$self->{_menuitem_file} = Gtk3::MenuItem->new_with_mnemonic($d->get('_File'));
	$self->{_menuitem_file}->set_submenu($self->fct_ret_file_menu($accel_group, $d, $shutter_root));
	$self->{_menubar}->append($self->{_menuitem_file});

	#edit
	$self->{_menuitem_edit} = Gtk3::MenuItem->new_with_mnemonic($d->get('_Edit'));
	$self->{_menuitem_edit}->set_submenu($self->fct_ret_edit_menu($accel_group, $d, $shutter_root));
	$self->{_menubar}->append($self->{_menuitem_edit});

	#view
	$self->{_menuitem_view} = Gtk3::MenuItem->new_with_mnemonic($d->get('_View'));
	$self->{_menuitem_view}->set_submenu($self->fct_ret_view_menu($accel_group, $d, $shutter_root));
	$self->{_menubar}->append($self->{_menuitem_view});

	#actions
	$self->{_menuitem_actions} = Gtk3::MenuItem->new_with_mnemonic($d->get('_Screenshot'));
	$self->{_menuitem_actions}->set_submenu($self->fct_ret_actions_menu($accel_group, $d, $shutter_root));
	$self->{_menubar}->append($self->{_menuitem_actions});

	#go-to
	$self->{_menuitem_session} = Gtk3::MenuItem->new_with_mnemonic($d->get('_Go'));
	$self->{_menuitem_session}->set_submenu($self->fct_ret_session_menu($accel_group, $d, $shutter_root));
	$self->{_menubar}->append($self->{_menuitem_session});

	#help
	$self->{_menuitem_help} = Gtk3::MenuItem->new_with_mnemonic($d->get('_Help'));
	$self->{_menuitem_help}->set_submenu($self->fct_ret_help_menu($accel_group, $d, $shutter_root));
	$self->{_menubar}->append($self->{_menuitem_help});

	#we provide a larger (more actions) menuitem actions as well
	#this will not be added to any menu entries
	$self->fct_ret_actions_menu_large($accel_group, $d, $shutter_root);

	return $self->{_menubar};
}

sub fct_ret_file_menu {
	my $self         = shift;
	my $accel_group  = shift;
	my $d            = shift;
	my $shutter_root = shift;

	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	$self->{_menu_file} = Gtk3::Menu->new();

	$self->{_menuitem_new} = Gtk3::ImageMenuItem->new_from_stock('gtk-new');
	$self->{_menuitem_new}->set_submenu($self->fct_ret_new_menu($accel_group, $d, $shutter_root));
	$self->{_menu_file}->append($self->{_menuitem_new});

	$self->{_menu_file}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_open} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Open...'));
	$self->{_menuitem_open}->set_image(Gtk3::Image->new_from_stock('gtk-open', 'menu'));
	$self->{_menuitem_open}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>O'), qw/visible/);
	$self->{_menu_file}->append($self->{_menuitem_open});

	$self->{_menuitem_recent} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Recent _Files'));
	$self->{_menu_file}->append($self->{_menuitem_recent});

	$self->{_menu_file}->append(Gtk3::SeparatorMenuItem->new);

	#~ $self->{_menuitem_save} = Gtk3::ImageMenuItem->new_with_mnemonic( $d->get('_Save') );
	#~ $self->{_menuitem_save}->set_image( Gtk3::Image->new_from_stock( 'gtk-save', 'menu' ) );
	#~ $self->{_menuitem_save}->set_sensitive(FALSE);
	#~ $self->{_menuitem_save}->add_accelerator( 'activate', $accel_group, $self->{_shf}->accel('<Control>S'), qw/visible/ );
	#~ $self->{_menu_file}->append( $self->{_menuitem_save} );

	$self->{_menuitem_save_as} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Save _As...'));
	$self->{_menuitem_save_as}->set_image(Gtk3::Image->new_from_stock('gtk-save-as', 'menu'));
	$self->{_menuitem_save_as}->set_sensitive(FALSE);
	$self->{_menuitem_save_as}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Shift><Control>S'), qw/visible/);
	$self->{_menu_file}->append($self->{_menuitem_save_as});

	#~ $self->{_menuitem_export_svg} = Gtk3::ImageMenuItem->new_with_mnemonic( $d->get('Export to SVG...') );
	#~ $self->{_menuitem_export_svg}->set_sensitive(FALSE);
	#~ $self->{_menuitem_export_svg}->add_accelerator( 'activate', $accel_group, $self->{_shf}->accel('<Shift><Alt>G'), qw/visible/ );
	#~ $self->{_menu_file}->append( $self->{_menuitem_export_svg} );
 
	$self->{_menuitem_export_b64} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Export to Base64...'));
	$self->{_menuitem_export_b64}->set_sensitive(FALSE);
	$self->{_menuitem_export_b64}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Shift><Alt>B'), qw/visible/);
	$self->{_menu_file}->append($self->{_menuitem_export_b64});

	$self->{_menuitem_export_pdf} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('E_xport to PDF...'));
	$self->{_menuitem_export_pdf}->set_sensitive(FALSE);
	$self->{_menuitem_export_pdf}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Shift><Alt>P'), qw/visible/);
	$self->{_menu_file}->append($self->{_menuitem_export_pdf});

	$self->{_menuitem_export_pscript} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Export to Post_Script...'));
	$self->{_menuitem_export_pscript}->set_sensitive(FALSE);
	$self->{_menuitem_export_pscript}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Shift><Alt>S'), qw/visible/);
	$self->{_menu_file}->append($self->{_menuitem_export_pscript});

	$self->{_menu_file}->append(Gtk3::SeparatorMenuItem->new);

	#~ $self->{_menuitem_pagesetup} = Gtk3::ImageMenuItem->new_from_stock('gtk-page-setup');
	#~ $self->{_menu_file}->append( $self->{_menuitem_pagesetup} );

	$self->{_menuitem_pagesetup} = Gtk3::ImageMenuItem->new($d->get('Page Set_up'));
	$self->{_menuitem_pagesetup}->set_image(Gtk3::Image->new_from_icon_name('document-page-setup', 'menu'));
	$self->{_menuitem_pagesetup}->set_sensitive(FALSE);
	$self->{_menu_file}->append($self->{_menuitem_pagesetup});

	$self->{_menuitem_print} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Print...'));
	$self->{_menuitem_print}->set_image(Gtk3::Image->new_from_stock('gtk-print', 'menu'));
	$self->{_menuitem_print}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>P'), qw/visible/);
	$self->{_menuitem_print}->set_sensitive(FALSE);
	$self->{_menu_file}->append($self->{_menuitem_print});

	$self->{_menu_file}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_email} = Gtk3::ImageMenuItem->new($d->get('Send by E_mail...'));
	$self->{_menuitem_email}->set_image(Gtk3::Image->new_from_icon_name('mail-send', 'menu'));
	$self->{_menuitem_email}->set_sensitive(FALSE);
	$self->{_menuitem_email}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Shift><Control>E'), qw/visible/);
	$self->{_menu_file}->append($self->{_menuitem_email});

	$self->{_menu_file}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_close} = Gtk3::ImageMenuItem->new_from_stock('gtk-close');
	$self->{_menuitem_close}->set_sensitive(FALSE);
	$self->{_menuitem_close}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>W'), qw/visible/);
	$self->{_menu_file}->append($self->{_menuitem_close});

	$self->{_menuitem_close_all} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('C_lose all'));
	$self->{_menuitem_close_all}->set_image(Gtk3::Image->new_from_stock('gtk-close', 'menu'));
	$self->{_menuitem_close_all}->set_sensitive(FALSE);
	$self->{_menuitem_close_all}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Shift><Control>W'), qw/visible/);
	$self->{_menu_file}->append($self->{_menuitem_close_all});

	$self->{_menu_file}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_quit} = Gtk3::ImageMenuItem->new_from_stock('gtk-quit');
	$self->{_menuitem_quit}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>Q'), qw/visible/);
	$self->{_menu_file}->append($self->{_menuitem_quit});

	return $self->{_menu_file};
}

sub fct_ret_edit_menu {
	my $self         = shift;
	my $accel_group  = shift;
	my $d            = shift;
	my $shutter_root = shift;

	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	$self->{_menu_edit} = Gtk3::Menu->new();

	$self->{_menuitem_undo} = Gtk3::ImageMenuItem->new_from_stock('gtk-undo');
	$self->{_menuitem_undo}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>Z'), qw/visible/);
	$self->{_menuitem_undo}->set_sensitive(FALSE);
	$self->{_menu_edit}->append($self->{_menuitem_undo});

	$self->{_menuitem_redo} = Gtk3::ImageMenuItem->new_from_stock('gtk-redo');
	$self->{_menuitem_redo}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>Y'), qw/visible/);
	$self->{_menuitem_redo}->set_sensitive(FALSE);
	$self->{_menu_edit}->append($self->{_menuitem_redo});

	$self->{_menu_edit}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_copy} = Gtk3::ImageMenuItem->new_from_stock('gtk-copy');
	$self->{_menuitem_copy}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>C'), qw/visible/);
	$self->{_menuitem_copy}->set_sensitive(FALSE);
	$self->{_menu_edit}->append($self->{_menuitem_copy});

	$self->{_menuitem_copy_filename} = Gtk3::ImageMenuItem->new_from_stock('gtk-copy');
	$self->{_menuitem_copy_filename}->get_child->set_text_with_mnemonic($d->get('Copy _Filename'));
	$self->{_menuitem_copy_filename}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control><Shift>C'), qw/visible/);
	$self->{_menuitem_copy_filename}->set_sensitive(FALSE);
	$self->{_menu_edit}->append($self->{_menuitem_copy_filename});

	$self->{_menuitem_trash} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Move to _Trash'));
	$self->{_menuitem_trash}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('Delete'), qw/visible/);
	$self->{_menuitem_trash}->set_image(Gtk3::Image->new_from_icon_name('user-trash', 'menu'));
	$self->{_menuitem_trash}->set_sensitive(FALSE);
	$self->{_menu_edit}->append($self->{_menuitem_trash});

	$self->{_menu_edit}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_select_all} = Gtk3::ImageMenuItem->new_from_stock('gtk-select-all');
	$self->{_menuitem_select_all}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>A'), qw/visible/);
	$self->{_menu_edit}->append($self->{_menuitem_select_all});

	$self->{_menu_edit}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_quicks} = Gtk3::MenuItem->new_with_mnemonic($d->get('_Quick profile select'));
	$self->{_menu_edit}->append($self->{_menuitem_quicks});

	$self->{_menu_edit}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_settings} = Gtk3::ImageMenuItem->new_from_stock('gtk-preferences');
	$self->{_menuitem_settings}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Mod1>P'), qw/visible/);
	$self->{_menu_edit}->append($self->{_menuitem_settings});

	return $self->{_menu_edit};
}

sub fct_ret_view_menu {
	my $self         = shift;
	my $accel_group  = shift;
	my $d            = shift;
	my $shutter_root = shift;

	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	$self->{_menu_view} = Gtk3::Menu->new();

	$self->{_menuitem_btoolbar} = Gtk3::CheckMenuItem->new_with_mnemonic($d->get('Show Navigation _Toolbar'));
	$self->{_menuitem_btoolbar}->set_active(FALSE);
	$self->{_menu_view}->append($self->{_menuitem_btoolbar});

	$self->{_menu_view}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_zoom_in} = Gtk3::ImageMenuItem->new_from_stock('gtk-zoom-in');
	$self->{_menuitem_zoom_in}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<control>plus'),   qw/visible/);
	$self->{_menuitem_zoom_in}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<control>equal'),  qw/visible/);
	$self->{_menuitem_zoom_in}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<control>KP_Add'), qw/visible/);
	$self->{_menuitem_zoom_in}->set_sensitive(FALSE);
	$self->{_menu_view}->append($self->{_menuitem_zoom_in});

	$self->{_menuitem_zoom_out} = Gtk3::ImageMenuItem->new_from_stock('gtk-zoom-out');
	$self->{_menuitem_zoom_out}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<control>minus'),       qw/visible/);
	$self->{_menuitem_zoom_out}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<control>KP_Subtract'), qw/visible/);
	$self->{_menuitem_zoom_out}->set_sensitive(FALSE);
	$self->{_menu_view}->append($self->{_menuitem_zoom_out});

	$self->{_menuitem_zoom_100} = Gtk3::ImageMenuItem->new_from_stock('gtk-zoom-100');
	$self->{_menuitem_zoom_100}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<control>0'), qw/visible/);
	$self->{_menuitem_zoom_100}->set_sensitive(FALSE);
	$self->{_menu_view}->append($self->{_menuitem_zoom_100});

	$self->{_menuitem_zoom_best} = Gtk3::ImageMenuItem->new_from_stock('gtk-zoom-fit');
	$self->{_menuitem_zoom_best}->set_sensitive(FALSE);
	$self->{_menu_view}->append($self->{_menuitem_zoom_best});

	$self->{_menu_view}->append(Gtk3::SeparatorMenuItem->new);

	#create an image item from stock to reuse the translated text
	$self->{_menuitem_fullscreen_image} = Gtk3::ImageMenuItem->new_from_stock('gtk-fullscreen');
	$self->{_menuitem_fullscreen}       = Gtk3::CheckMenuItem->new_with_label($self->{_menuitem_fullscreen_image}->get_child->get_text);
	$self->{_menuitem_fullscreen}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('F11'), qw/visible/);
	$self->{_menu_view}->append($self->{_menuitem_fullscreen});

	return $self->{_menu_view};
}

sub fct_ret_session_menu {
	my $self         = shift;
	my $accel_group  = shift;
	my $d            = shift;
	my $shutter_root = shift;

	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	$self->{_menu_session} = Gtk3::Menu->new();

	$self->{_menuitem_back} = Gtk3::ImageMenuItem->new_from_stock('gtk-go-back');
	$self->{_menuitem_back}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Mod1>Left'), qw/visible/);
	$self->{_menu_session}->append($self->{_menuitem_back});

	$self->{_menuitem_forward} = Gtk3::ImageMenuItem->new_from_stock('gtk-go-forward');
	$self->{_menuitem_forward}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Mod1>Right'), qw/visible/);
	$self->{_menu_session}->append($self->{_menuitem_forward});

	$self->{_menu_session}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_first} = Gtk3::ImageMenuItem->new_from_stock('gtk-goto-first');
	$self->{_menuitem_first}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Mod1>Home'), qw/visible/);
	$self->{_menu_session}->append($self->{_menuitem_first});

	$self->{_menuitem_last} = Gtk3::ImageMenuItem->new_from_stock('gtk-goto-last');
	$self->{_menuitem_last}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Mod1>End'), qw/visible/);
	$self->{_menu_session}->append($self->{_menuitem_last});

	return $self->{_menu_session};
}

sub fct_ret_help_menu {
	my $self         = shift;
	my $accel_group  = shift;
	my $d            = shift;
	my $shutter_root = shift;

	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	$self->{_menu_help} = Gtk3::Menu->new();

	$self->{_menuitem_question} = Gtk3::ImageMenuItem->new($d->get('Get Help Online...'));
	if ($icontheme->has_icon('lpi-help')) {
		$self->{_menuitem_question}->set_image(Gtk3::Image->new_from_icon_name('lpi-help', 'menu'));
	} else {
		$self->{_menuitem_question}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/lpi-help.png", $self->{_shf}->icon_size('menu'))));
	}

	$self->{_menu_help}->append($self->{_menuitem_question});

	$self->{_menuitem_translate} = Gtk3::ImageMenuItem->new($d->get('Translate this Application...'));
	if ($icontheme->has_icon('lpi-translate')) {
		$self->{_menuitem_translate}->set_image(Gtk3::Image->new_from_icon_name('lpi-translate', 'menu'));
	} else {
		$self->{_menuitem_translate}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/lpi-translate.png", $self->{_shf}->icon_size('menu'))));
	}

	$self->{_menu_help}->append($self->{_menuitem_translate});

	$self->{_menuitem_bug} = Gtk3::ImageMenuItem->new($d->get('Report a Problem'));
	if ($icontheme->has_icon('lpi-bug')) {
		$self->{_menuitem_bug}->set_image(Gtk3::Image->new_from_icon_name('lpi-bug', 'menu'));
	} else {
		$self->{_menuitem_bug}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/lpi-bug.png", $self->{_shf}->icon_size('menu'))));
	}

	$self->{_menu_help}->append($self->{_menuitem_bug});

	$self->{_menu_help}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_about} = Gtk3::ImageMenuItem->new_from_stock('gtk-about');
	$self->{_menuitem_about}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>I'), qw/visible/);
	$self->{_menu_help}->append($self->{_menuitem_about});

	return $self->{_menu_help};
}

sub fct_ret_new_menu {
	my $self         = shift;
	my $accel_group  = shift;
	my $d            = shift;
	my $shutter_root = shift;

	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	$self->{_menu_new} = Gtk3::Menu->new;

	#redo last capture
	$self->{_menuitem_redoshot} = Gtk3::ImageMenuItem->new_from_stock('gtk-refresh');
	$self->{_menuitem_redoshot}->get_child->set_text_with_mnemonic($d->get('_Redo last screenshot'));
	$self->{_menuitem_redoshot}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('F5'), qw/visible/);
	$self->{_menuitem_redoshot}->set_sensitive(FALSE);
	$self->{_menu_new}->append($self->{_menuitem_redoshot});

	$self->{_menu_new}->append(Gtk3::SeparatorMenuItem->new);

	#selection
	$self->{_menuitem_selection} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Selection'));

	eval {
		my $ccursor_pb = Gtk3::Gdk::Cursor->new('left_ptr')->get_image->scale_simple($self->{_shf}->icon_size('menu'), 'bilinear');
		$self->{_menuitem_selection}->set_image(Gtk3::Image->new_from_pixbuf($ccursor_pb));
	};
	if ($@) {
		if ($icontheme->has_icon('applications-accessories')) {
			$self->{_menuitem_selection}->set_image(Gtk3::Image->new_from_icon_name('applications-accessories', 'menu'));
		} else {
			$self->{_menuitem_selection}
				->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/selection.svg", $self->{_shf}->icon_size('menu'))));
		}
	}
	$self->{_menu_new}->append($self->{_menuitem_selection});

	#~ $self->{_menu_new}->append( Gtk3::SeparatorMenuItem->new );

	#full screen
	$self->{_menuitem_full} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Desktop'));
	if ($icontheme->has_icon('user-desktop')) {
		$self->{_menuitem_full}->set_image(Gtk3::Image->new_from_icon_name('user-desktop', 'menu'));
	} elsif ($icontheme->has_icon('desktop')) {
		$self->{_menuitem_full}->set_image(Gtk3::Image->new_from_icon_name('desktop', 'menu'));
	} else {
		$self->{_menuitem_full}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/desktop.svg", $self->{_shf}->icon_size('menu'))));
	}
	$self->{_menu_new}->append($self->{_menuitem_full});

	#~ $self->{_menu_new}->append( Gtk3::SeparatorMenuItem->new );

	#awindow
	$self->{_menuitem_awindow} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Active Window'));
	if ($icontheme->has_icon('preferences-system-windows')) {
		$self->{_menuitem_awindow}->set_image(Gtk3::Image->new_from_icon_name('preferences-system-windows', 'menu'));
	} else {
		$self->{_menuitem_awindow}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/sel_window_active.svg", $self->{_shf}->icon_size('menu'))));
	}
	$self->{_menu_new}->append($self->{_menuitem_awindow});

	#window
	$self->{_menuitem_window} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Select W_indow'));
	if ($icontheme->has_icon('preferences-system-windows')) {
		$self->{_menuitem_window}->set_image(Gtk3::Image->new_from_icon_name('preferences-system-windows', 'menu'));
	} else {
		$self->{_menuitem_window}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/sel_window.svg", $self->{_shf}->icon_size('menu'))));
	}
	$self->{_menu_new}->append($self->{_menuitem_window});

	#section
	# No sections for now: https://github.com/shutter-project/shutter/issues/25
	#$self->{_menuitem_section} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Se_ction'));
	#if ($icontheme->has_icon('gdm-xnest')) {
	#	$self->{_menuitem_section}->set_image(Gtk3::Image->new_from_icon_name('gdm-xnest', 'menu'));
	#} else {
	#	$self->{_menuitem_section}
	#		->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/sel_window_section.svg", $self->{_shf}->icon_size('menu'))));
	#}
	#$self->{_menu_new}->append($self->{_menuitem_section});

	#menu
	$self->{_menuitem_menu} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Menu'));
	if ($icontheme->has_icon('alacarte')) {
		$self->{_menuitem_menu}->set_image(Gtk3::Image->new_from_icon_name('alacarte', 'menu'));
	} else {
		$self->{_menuitem_menu}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/sel_window_menu.svg", $self->{_shf}->icon_size('menu'))));
	}
	$self->{_menu_new}->append($self->{_menuitem_menu});

	#tooltip
	$self->{_menuitem_tooltip} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Tooltip'));
	if ($icontheme->has_icon('help-faq')) {
		$self->{_menuitem_tooltip}->set_image(Gtk3::Image->new_from_icon_name('help-faq', 'menu'));
	} else {
		$self->{_menuitem_tooltip}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/sel_window_tooltip.svg", $self->{_shf}->icon_size('menu'))));
	}
	$self->{_menu_new}->append($self->{_menuitem_tooltip});

	#~ $self->{_menu_new}->append( Gtk3::SeparatorMenuItem->new );

	#web
	$self->{_menuitem_web} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Web'));
	if ($icontheme->has_icon('web-browser')) {
		$self->{_menuitem_web}->set_image(Gtk3::Image->new_from_icon_name('web-browser', 'menu'));
	} else {
		$self->{_menuitem_web}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/web_image.svg", $self->{_shf}->icon_size('menu'))));
	}
	$self->{_menu_new}->append($self->{_menuitem_web});

	$self->{_menu_new}->append(Gtk3::SeparatorMenuItem->new);

	#import from clipboard
	$self->{_menuitem_iclipboard} = Gtk3::ImageMenuItem->new_from_stock('gtk-paste');
	$self->{_menuitem_iclipboard}->get_child->set_text_with_mnemonic($d->get('Import from clip_board'));
	$self->{_menuitem_iclipboard}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control><Shift>V'), qw/visible/);
	$self->{_menu_new}->append($self->{_menuitem_iclipboard});

	$self->{_menu_new}->show_all;

	return $self->{_menu_new};
}

sub fct_ret_actions_menu {
	my $self         = shift;
	my $accel_group  = shift;
	my $d            = shift;
	my $shutter_root = shift;

	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	$self->{_menu_actions} = Gtk3::Menu->new();

	$self->{_menuitem_reopen} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Open wit_h'));
	$self->{_menuitem_reopen}->set_image(Gtk3::Image->new_from_stock('gtk-open', 'menu'));
	$self->{_menuitem_reopen}->set_sensitive(FALSE);
	$self->{_menuitem_reopen}->set_name('item-reopen-list');
	$self->{_menu_actions}->append($self->{_menuitem_reopen});

	$self->{_menuitem_show_in_folder} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Show in _folder'));
	$self->{_menuitem_show_in_folder}->set_image(Gtk3::Image->new_from_stock('gtk-open', 'menu'));
	$self->{_menuitem_show_in_folder}->set_sensitive(FALSE);
	$self->{_menuitem_show_in_folder}->set_name('item-reopen-default');
	$self->{_menu_actions}->append($self->{_menuitem_show_in_folder});

	$self->{_menuitem_rename} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Rename...'));
	$self->{_menuitem_rename}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('F2'), qw/visible/) if $accel_group;
	$self->{_menuitem_rename}->set_image(Gtk3::Image->new_from_stock('gtk-edit', 'menu'));
	$self->{_menuitem_rename}->set_sensitive(FALSE);
	$self->{_menuitem_rename}->set_name('item-rename');
	$self->{_menu_actions}->append($self->{_menuitem_rename});

	$self->{_menu_actions}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_send} = Gtk3::ImageMenuItem->new($d->get('_Send To...'));
	$self->{_menuitem_send}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>S'), qw/visible/);
	$self->{_menuitem_send}->set_image(Gtk3::Image->new_from_icon_name('document-send', 'menu'));
	$self->{_menuitem_send}->set_sensitive(FALSE);
	$self->{_menuitem_send}->set_name('item-send');
	$self->{_menu_actions}->append($self->{_menuitem_send});

	$self->{_menuitem_upload} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('E_xport...'));
	$self->{_menuitem_upload}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>U'), qw/visible/) if $accel_group;
	$self->{_menuitem_upload}->set_image(Gtk3::Image->new_from_stock('gtk-network', 'menu'));
	$self->{_menuitem_upload}->set_sensitive(FALSE);
	$self->{_menuitem_upload}->set_name('item-upload');
	$self->{_menu_actions}->append($self->{_menuitem_upload});

	$self->{_menuitem_links} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Public URLs'));
	$self->{_menuitem_links}->set_image(Gtk3::Image->new_from_stock('gtk-network', 'menu'));
	$self->{_menuitem_links}->set_sensitive(FALSE);
	$self->{_menuitem_links}->set_name('item-links');
	$self->{_menu_actions}->append($self->{_menuitem_links});

	$self->{_menu_actions}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_draw} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Edit...'));
	$self->{_menuitem_draw}->set_image(Gtk3::Image->new_from_stock('gtk-edit', 'menu'));
	$self->{_menuitem_draw}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>E'), qw/visible/) if $accel_group;
	if ($icontheme->has_icon('applications-graphics')) {
		$self->{_menuitem_draw}->set_image(Gtk3::Image->new_from_icon_name('applications-graphics', 'menu'));
	} else {
		$self->{_menuitem_draw}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/draw.svg", $self->{_shf}->icon_size('menu'))));
	}

	$self->{_menuitem_draw}->set_sensitive(FALSE);
	$self->{_menuitem_draw}->set_name('item-draw');
	$self->{_menu_actions}->append($self->{_menuitem_draw});

	$self->{_menuitem_plugin} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Run a _plugin...'));
	$self->{_menuitem_plugin}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control><Shift>P'), qw/visible/) if $accel_group;
	$self->{_menuitem_plugin}->set_image(Gtk3::Image->new_from_stock('gtk-execute', 'menu'));
	$self->{_menuitem_plugin}->set_sensitive(FALSE);
	$self->{_menuitem_plugin}->set_name('item-plugin');
	$self->{_menu_actions}->append($self->{_menuitem_plugin});

	$self->{_menu_actions}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_redoshot_this} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Redo _this screenshot'));
	$self->{_menuitem_redoshot_this}->add_accelerator('activate', $accel_group, $self->{_shf}->accel('<Control>F5'), qw/visible/) if $accel_group;
	$self->{_menuitem_redoshot_this}->set_image(Gtk3::Image->new_from_stock('gtk-refresh', 'menu'));
	$self->{_menuitem_redoshot_this}->set_sensitive(FALSE);
	$self->{_menuitem_redoshot_this}->set_name('item-redoshot');
	$self->{_menu_actions}->append($self->{_menuitem_redoshot_this});

	$self->{_menu_actions}->show_all;

	return $self->{_menu_actions};

}

sub fct_ret_actions_menu_large {
	my $self         = shift;
	my $accel_group  = shift;
	my $d            = shift;
	my $shutter_root = shift;

	#Icontheme
	my $icontheme = $self->{_common}->get_theme;

	$self->{_menu_large_actions} = Gtk3::Menu->new();

	$self->{_menuitem_large_reopen} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Open wit_h'));
	$self->{_menuitem_large_reopen}->set_image(Gtk3::Image->new_from_stock('gtk-open', 'menu'));
	$self->{_menuitem_large_reopen}->set_sensitive(FALSE);
	$self->{_menuitem_large_reopen}->set_name('item-large-reopen-list');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_reopen});

	$self->{_menuitem_large_show_in_folder} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Show in _folder'));
	$self->{_menuitem_large_show_in_folder}->set_image(Gtk3::Image->new_from_stock('gtk-open', 'menu'));
	$self->{_menuitem_large_show_in_folder}->set_sensitive(FALSE);
	$self->{_menuitem_large_show_in_folder}->set_name('item-reopen-default');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_show_in_folder});

	$self->{_menuitem_large_rename} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Rename...'));
	$self->{_menuitem_large_rename}->set_image(Gtk3::Image->new_from_stock('gtk-edit', 'menu'));
	$self->{_menuitem_large_rename}->set_sensitive(FALSE);
	$self->{_menuitem_large_rename}->set_name('item-large-rename');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_rename});

	$self->{_menu_large_actions}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_large_send} = Gtk3::ImageMenuItem->new($d->get('_Send To...'));
	$self->{_menuitem_large_send}->set_image(Gtk3::Image->new_from_icon_name('document-send', 'menu'));
	$self->{_menuitem_send}->set_sensitive(FALSE);
	$self->{_menuitem_send}->set_name('item-large-send');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_send});

	$self->{_menuitem_large_upload} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('E_xport...'));
	$self->{_menuitem_large_upload}->set_image(Gtk3::Image->new_from_stock('gtk-network', 'menu'));
	$self->{_menuitem_large_upload}->set_sensitive(FALSE);
	$self->{_menuitem_large_upload}->set_name('item-large-upload');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_upload});

	$self->{_menuitem_large_links} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Public URLs'));
	$self->{_menuitem_large_links}->set_image(Gtk3::Image->new_from_stock('gtk-network', 'menu'));
	$self->{_menuitem_large_links}->set_sensitive(FALSE);
	$self->{_menuitem_large_links}->set_name('item-large-links');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_links});

	$self->{_menu_large_actions}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_large_copy} = Gtk3::ImageMenuItem->new_from_stock('gtk-copy');
	$self->{_menuitem_large_copy}->set_sensitive(FALSE);
	$self->{_menuitem_large_copy}->set_name('item-large-copy');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_copy});

	$self->{_menuitem_large_copy_filename} = Gtk3::ImageMenuItem->new_from_stock('gtk-copy');
	$self->{_menuitem_large_copy_filename}->get_child->set_text_with_mnemonic($d->get('Copy _Filename'));
	$self->{_menuitem_large_copy_filename}->set_sensitive(FALSE);
	$self->{_menuitem_large_copy_filename}->set_name('item-large-copy-filename');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_copy_filename});

	$self->{_menuitem_large_trash} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Move to _Trash'));
	$self->{_menuitem_large_trash}->set_image(Gtk3::Image->new_from_icon_name('gnome-stock-trash', 'menu'));
	$self->{_menuitem_large_trash}->set_sensitive(FALSE);
	$self->{_menuitem_large_trash}->set_name('item-large-trash');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_trash});

	$self->{_menu_large_actions}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_large_draw} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('_Edit...'));
	$self->{_menuitem_large_draw}->set_image(Gtk3::Image->new_from_stock('gtk-edit', 'menu'));
	if ($icontheme->has_icon('applications-graphics')) {
		$self->{_menuitem_large_draw}->set_image(Gtk3::Image->new_from_icon_name('applications-graphics', 'menu'));
	} else {
		$self->{_menuitem_large_draw}
			->set_image(Gtk3::Image->new_from_pixbuf(Gtk3::Gdk::Pixbuf->new_from_file_at_size("$shutter_root/share/shutter/resources/icons/draw.svg", $self->{_shf}->icon_size('menu'))));
	}

	$self->{_menuitem_large_draw}->set_sensitive(FALSE);
	$self->{_menuitem_large_draw}->set_name('item-large-draw');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_draw});

	$self->{_menuitem_large_plugin} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Run a _Plugin...'));
	$self->{_menuitem_large_plugin}->set_image(Gtk3::Image->new_from_stock('gtk-execute', 'menu'));
	$self->{_menuitem_large_plugin}->set_sensitive(FALSE);
	$self->{_menuitem_large_plugin}->set_name('item-large-plugin');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_plugin});

	$self->{_menu_large_actions}->append(Gtk3::SeparatorMenuItem->new);

	$self->{_menuitem_large_redoshot_this} = Gtk3::ImageMenuItem->new_with_mnemonic($d->get('Redo _this screenshot'));
	$self->{_menuitem_large_redoshot_this}->set_image(Gtk3::Image->new_from_stock('gtk-refresh', 'menu'));
	$self->{_menuitem_large_redoshot_this}->set_sensitive(FALSE);
	$self->{_menuitem_large_redoshot_this}->set_name('item-large-redoshot');
	$self->{_menu_large_actions}->append($self->{_menuitem_large_redoshot_this});

	$self->{_menu_large_actions}->show_all;

	return $self->{_menu_large_actions};

}

1;
