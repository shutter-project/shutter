###################################################
#
#  Copyright (C) Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package Shutter::App::Menu;

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

sub create_menu {
	my $self = shift;

	my $d           = $self->{_common}->get_gettext;
	my $window      = $self->{_common}->get_mainwindow;
	my $shutter_root = $self->{_common}->get_root;

	my $accel_group = Gtk2::AccelGroup->new;
	$window->add_accel_group($accel_group);

	$self->{_menubar} = Gtk2::MenuBar->new();

	#file
	$self->{_menu_file}     = Gtk2::Menu->new();
	$self->{_menuitem_file} = Gtk2::MenuItem->new_with_mnemonic( $d->get("_File") );

	$self->{_menuitem_new} = Gtk2::ImageMenuItem->new_from_stock('gtk-new');
	$self->{_menuitem_new}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Control>N"), qw/visible/ );
	$self->{_menuitem_new}->set_submenu( $self->_fct_ret_new_menu( $accel_group, $d, $shutter_root ) );
	$self->{_menu_file}->append( $self->{_menuitem_new} );

	$self->{_menu_file}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_open} = Gtk2::ImageMenuItem->new_from_stock('gtk-open');
	$self->{_menuitem_open}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Control>O"), qw/visible/ );
	$self->{_menu_file}->append( $self->{_menuitem_open} );

	$self->{_menu_file}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_save_as} = Gtk2::ImageMenuItem->new_from_stock('gtk-save-as');
	$self->{_menuitem_save_as}->set_sensitive(FALSE);
	$self->{_menuitem_save_as}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Shift><Control>S"), qw/visible/ );
	$self->{_menu_file}->append( $self->{_menuitem_save_as} );

	$self->{_menu_file}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_pagesetup} = Gtk2::ImageMenuItem->new_from_stock('gtk-page-setup');
	$self->{_menu_file}->append( $self->{_menuitem_pagesetup} );

	$self->{_menuitem_print} = Gtk2::ImageMenuItem->new_from_stock('gtk-print');
	$self->{_menuitem_print}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Control>P"), qw/visible/ );
	$self->{_menu_file}->append( $self->{_menuitem_print} );

	$self->{_menu_file}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_close} = Gtk2::ImageMenuItem->new_from_stock('gtk-close');
	$self->{_menuitem_close}->set_sensitive(FALSE);
	$self->{_menuitem_close}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Control>W"), qw/visible/ );
	$self->{_menu_file}->append( $self->{_menuitem_close} );

	$self->{_menuitem_close_all} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("C_lose all") );
	$self->{_menuitem_close_all}->set_image( Gtk2::Image->new_from_stock( 'gtk-close', 'menu' ) );
	$self->{_menuitem_close_all}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Shift><Control>W"), qw/visible/ );
	$self->{_menu_file}->append( $self->{_menuitem_close_all} );

	$self->{_menu_file}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_quit} = Gtk2::ImageMenuItem->new_from_stock('gtk-quit');
	$self->{_menuitem_quit}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Control>Q"), qw/visible/ );
	$self->{_menu_file}->append( $self->{_menuitem_quit} );

	$self->{_menuitem_file}->set_submenu( $self->{_menu_file} );
	$self->{_menubar}->append( $self->{_menuitem_file} );

	#end file
	#edit
	$self->{_menu_edit} = Gtk2::Menu->new();

	$self->{_menuitem_copy} = Gtk2::ImageMenuItem->new_from_stock('gtk-copy');
	$self->{_menuitem_copy}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Control>C"), qw/visible/ );
	$self->{_menuitem_copy}->set_sensitive(FALSE);
	$self->{_menu_edit}->append( $self->{_menuitem_copy} );

	$self->{_menuitem_trash} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("Move to Dele_ted Items folder") );
	$self->{_menuitem_trash}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("Delete"), qw/visible/ );
	$self->{_menuitem_trash}->set_image( Gtk2::Image->new_from_icon_name( 'gnome-stock-trash', 'menu' ) );
	$self->{_menuitem_trash}->set_sensitive(FALSE);
	$self->{_menu_edit}->append( $self->{_menuitem_trash} );

	$self->{_menu_edit}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_quicks} = Gtk2::MenuItem->new_with_label( $d->get("Quick select") );
	$self->{_menu_edit}->append( $self->{_menuitem_quicks} );

	$self->{_menu_edit}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_settings} = Gtk2::ImageMenuItem->new_from_stock('gtk-preferences');
	$self->{_menuitem_settings}->add_accelerator( "activate", $accel_group, $Gtk2::Gdk::Keysyms{P}, qw/mod1-mask/, qw/visible/ );
	$self->{_menu_edit}->append( $self->{_menuitem_settings} );

	$self->{_menuitem_edit} = Gtk2::MenuItem->new_with_mnemonic( $d->get("_Edit") );
	$self->{_menuitem_edit}->set_submenu( $self->{_menu_edit} );
	$self->{_menubar}->append( $self->{_menuitem_edit} );

	#end edit
	#actions
	$self->{_menu_actions} = Gtk2::Menu->new();

	$self->{_menuitem_reopen} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("_Open with ...") );
	$self->{_menuitem_reopen}->set_image( Gtk2::Image->new_from_stock( 'gtk-open', 'menu' ) );
	$self->{_menuitem_reopen}->set_sensitive(FALSE);
	$self->{_menu_actions}->append( $self->{_menuitem_reopen} );

	$self->{_menuitem_rename} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("_Rename") );
	$self->{_menuitem_rename}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("F2"), qw/visible/ );
	$self->{_menuitem_rename}->set_image( Gtk2::Image->new_from_stock( 'gtk-edit', 'menu' ) );
	$self->{_menuitem_rename}->set_sensitive(FALSE);
	$self->{_menu_actions}->append( $self->{_menuitem_rename} );

	$self->{_menu_actions}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_upload} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("_Upload") );
	$self->{_menuitem_upload}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Control>U"), qw/visible/ );
	$self->{_menuitem_upload}->set_image( Gtk2::Image->new_from_stock( 'gtk-network', 'menu' ) );
	$self->{_menuitem_upload}->set_sensitive(FALSE);
	$self->{_menu_actions}->append( $self->{_menuitem_upload} );

	$self->{_menu_actions}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_draw} = Gtk2::ImageMenuItem->new_from_stock( 'gtk-edit' );
	$self->{_menuitem_draw}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Control>E"), qw/visible/ );
	$self->{_menuitem_draw}->set_image(
		Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size( "$shutter_root/share/shutter/resources/icons/draw.svg", Gtk2::IconSize->lookup('menu') )
		)
	);
	
	$self->{_menuitem_draw}->set_sensitive(FALSE);
	$self->{_menu_actions}->append( $self->{_menuitem_draw} );

	$self->{_menuitem_plugin} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("Execute a _plugin") );
	$self->{_menuitem_plugin}->add_accelerator( "activate", $accel_group, Gtk2::Accelerator->parse("<Control><Shift>P"), qw/visible/ );
	$self->{_menuitem_plugin}->set_image( Gtk2::Image->new_from_stock( 'gtk-execute', 'menu' ) );
	$self->{_menuitem_plugin}->set_sensitive(FALSE);
	$self->{_menu_actions}->append( $self->{_menuitem_plugin} );

	#maybe lib is not installed
	eval { require Goo::Canvas };
	if ($@) {
		$self->{_menuitem_draw}->set_sensitive(FALSE);
	}

	$self->{_menuitem_actions} = Gtk2::MenuItem->new_with_mnemonic( $d->get("_Screenshot") );
	$self->{_menuitem_actions}->set_submenu( $self->{_menu_actions} );
	$self->{_menubar}->append( $self->{_menuitem_actions} );

	#end actions
	#session
	$self->{_menu_session} = Gtk2::Menu->new();

	$self->{_menuitem_back} = Gtk2::ImageMenuItem->new_from_stock('gtk-go-back');
	$self->{_menuitem_back}->add_accelerator( "activate", $accel_group, $Gtk2::Gdk::Keysyms{Left}, qw/mod1-mask/, qw/visible/ );
	$self->{_menu_session}->append( $self->{_menuitem_back} );

	$self->{_menuitem_forward} = Gtk2::ImageMenuItem->new_from_stock('gtk-go-forward');
	$self->{_menuitem_forward}->add_accelerator( "activate", $accel_group, $Gtk2::Gdk::Keysyms{Right}, qw/mod1-mask/, qw/visible/ );
	$self->{_menu_session}->append( $self->{_menuitem_forward} );

	$self->{_menu_session}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_first} = Gtk2::ImageMenuItem->new_from_stock('gtk-goto-first');
	$self->{_menuitem_first}->add_accelerator( "activate", $accel_group, $Gtk2::Gdk::Keysyms{Home}, qw/mod1-mask/, qw/visible/ );
	$self->{_menu_session}->append( $self->{_menuitem_first} );

	$self->{_menuitem_last} = Gtk2::ImageMenuItem->new_from_stock('gtk-goto-last');
	$self->{_menuitem_last}->add_accelerator( "activate", $accel_group, $Gtk2::Gdk::Keysyms{End}, qw/mod1-mask/, qw/visible/ );
	$self->{_menu_session}->append( $self->{_menuitem_last} );

	$self->{_menuitem_session} = Gtk2::MenuItem->new_with_mnemonic( $d->get("_Go") );
	$self->{_menuitem_session}->set_submenu( $self->{_menu_session} );
	$self->{_menubar}->append( $self->{_menuitem_session} );

	#end session
	#help
	$self->{_menu_help} = Gtk2::Menu->new();

	$self->{_menuitem_question} = Gtk2::ImageMenuItem->new( $d->get("Get Help Online ...") );
	$self->{_menuitem_question}->set_image(
		Gtk2::Image->new_from_icon_name( 'lpi-help', 'menu' )
	);

	$self->{_menu_help}->append( $self->{_menuitem_question} );

	$self->{_menuitem_translate} = Gtk2::ImageMenuItem->new( $d->get("Translate this Application ...") );
	$self->{_menuitem_translate}->set_image(
		Gtk2::Image->new_from_icon_name( 'lpi-translate', 'menu' )
	);

	$self->{_menu_help}->append( $self->{_menuitem_translate} );

	$self->{_menuitem_bug} = Gtk2::ImageMenuItem->new( $d->get("Report a Problem") );
	$self->{_menuitem_bug}->set_image(
		Gtk2::Image->new_from_icon_name( 'lpi-bug', 'menu' )
	);

	$self->{_menu_help}->append( $self->{_menuitem_bug} );

	$self->{_menu_help}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_about} = Gtk2::ImageMenuItem->new_from_stock('gtk-about');
	$self->{_menuitem_about}->add_accelerator( "activate", $accel_group, $Gtk2::Gdk::Keysyms{I}, qw/control-mask/, qw/visible/ );
	$self->{_menu_help}->append( $self->{_menuitem_about} );

	$self->{_menuitem_help} = Gtk2::MenuItem->new_with_mnemonic( $d->get("_Help") );
	$self->{_menuitem_help}->set_submenu( $self->{_menu_help} );

	$self->{_menubar}->append( $self->{_menuitem_help} );

	return $self->{_menubar};
}

sub _fct_ret_new_menu {
	my $self        = shift;
	my $accel_group = shift;
	my $d           = shift;
	my $shutter_root = shift;

	$self->{_menu_new}           = Gtk2::Menu->new;
	$self->{_menuitem_selection} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("_Selection") );
	$self->{_menuitem_selection}->set_image(
		Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size( "$shutter_root/share/shutter/resources/icons/selection.svg", Gtk2::IconSize->lookup('menu') )
		)
	);
	$self->{_menu_new}->append( $self->{_menuitem_selection} );

	$self->{_menu_new}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_full} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("_Full Screen") );
	$self->{_menuitem_full}->set_image(
		Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size( "$shutter_root/share/shutter/resources/icons/fullscreen.svg", Gtk2::IconSize->lookup('menu') )
		)
	);
	$self->{_menu_new}->append( $self->{_menuitem_full} );

	$self->{_menu_new}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_window} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("W_indow") );
	$self->{_menuitem_window}->set_image(
		Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size( "$shutter_root/share/shutter/resources/icons/sel_window.svg", Gtk2::IconSize->lookup('menu') )
		)
	);
	$self->{_menu_new}->append( $self->{_menuitem_window} );

	$self->{_menuitem_section} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("Se_ction") );
	$self->{_menuitem_section}->set_image(
		Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size(
				"$shutter_root/share/shutter/resources/icons/sel_window_section.svg",
				Gtk2::IconSize->lookup('menu')
			)
		)
	);
	$self->{_menu_new}->append( $self->{_menuitem_section} );

	$self->{_menu_new}->append( Gtk2::SeparatorMenuItem->new );

	$self->{_menuitem_web} = Gtk2::ImageMenuItem->new_with_mnemonic( $d->get("_Web") );

	#gnome web photo is optional, don't enable it when gnome-web-photo is not in PATH
	if ( system("which gnome-web-photo") == 0 ) {
		$self->{_menuitem_web}->set_sensitive(TRUE);
	} else {
		$self->{_menuitem_web}->set_sensitive(FALSE);
	}

	$self->{_menuitem_web}->set_image(
		Gtk2::Image->new_from_pixbuf(
			Gtk2::Gdk::Pixbuf->new_from_file_at_size( "$shutter_root/share/shutter/resources/icons/web_image.svg", Gtk2::IconSize->lookup('menu') )
		)
	);
	$self->{_menu_new}->append( $self->{_menuitem_web} );

	return $self->{_menu_new};
}

1;
