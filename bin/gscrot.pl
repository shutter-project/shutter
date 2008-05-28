#! /usr/bin/perl

#Copyright (C) Mario Kemper 2008  Mi, 09 Apr 2008 22:58:09 +0200 

#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.

#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <http://www.gnu.org/licenses/>.

use utf8;
use strict;
use warnings;
use Glib qw/TRUE FALSE/;
use Gtk2 '-init';
use Gtk2::TrayIcon;
use Gtk2::Gdk::Keysyms;
use Gtk2::Pango;
use Image::Magick;
use File::Copy;
use POSIX;     # for setlocale()
use Locale::gettext;
use WWW::Mechanize;
use HTTP::Status;

my $gscrot_name = "GScrot";
my $gscrot_version = "v0.38";
my $gscrot_path = "";
#command line parameter
my $debug_cparam = FALSE;
my $min_cparam = FALSE;
my $boff_cparam = FALSE;
my @args = @ARGV;

&function_init();

my %gm_programs; #hash to store program infos
&function_check_installed_programs if keys(%gm_programs) > 0;
my %plugins; #hash to store plugin infos
&function_check_installed_plugins if keys(%plugins) > 0;
my %accounts; #hash to account infos

$accounts{'ubuntu-pics.de'}->{host} = "ubuntu-pics.de";
$accounts{'ubuntu-pics.de'}->{username} = "";
$accounts{'ubuntu-pics.de'}->{password} = "";

setlocale(LC_MESSAGES,"");
my $d = Locale::gettext->domain("gscrot");
$d->dir("$gscrot_path/share/locale");

my $is_in_tray = FALSE;
my $window = Gtk2::Window->new();

$window->set_title($gscrot_name." ".$gscrot_version);
$window->set_default_icon_from_file ("$gscrot_path/share/gscrot/resources/icons/gscrot24x24.png");
$window->signal_connect('delete-event' => \&event_delete_window);
$window->set_border_width(0);

#hash of screenshots during session	
my %session_screens;
my $notebook = Gtk2::Notebook->new;
$notebook->popup_enable;
$notebook->set_scrollable(TRUE);
$notebook->signal_connect('switch-page' => \&event_notebook_switch, 'tab-switched');
$notebook->set_size_request(-1, 150);
my $first_page = $notebook->append_page (function_create_tab ("", TRUE),
Gtk2::Label->new($d->get("All")));

#arrange settings in notebook
my $notebook_settings = Gtk2::Notebook->new;

#Clipboard
my $clipboard = Gtk2::Clipboard->get(Gtk2::Gdk->SELECTION_CLIPBOARD);

my $accel_group = Gtk2::AccelGroup->new;
$window->add_accel_group($accel_group);

my $statusbar = Gtk2::Statusbar->new;

my $vbox = Gtk2::VBox->new(FALSE, 10);
my $vbox_inner = Gtk2::VBox->new(FALSE, 10);
my $vbox_basic = Gtk2::VBox->new(FALSE, 10);
my $vbox_extras = Gtk2::VBox->new(FALSE, 10);
my $vbox_behavior = Gtk2::VBox->new(FALSE, 10);
my $vbox_plugins = Gtk2::VBox->new(FALSE, 10);
my $vbox_accounts = Gtk2::VBox->new(FALSE, 10);
my $file_vbox = Gtk2::VBox->new(FALSE, 0);
my $save_vbox = Gtk2::VBox->new(FALSE, 0);
my $behavior_vbox = Gtk2::VBox->new(FALSE, 0);
my $actions_vbox = Gtk2::VBox->new(FALSE, 0);
my $capture_vbox = Gtk2::VBox->new(FALSE, 0);
my $effects_vbox = Gtk2::VBox->new(FALSE, 0);
my $accounts_vbox = Gtk2::VBox->new(FALSE, 0);

my $button_box = Gtk2::HBox->new(TRUE, 10);
my $scale_box = Gtk2::HBox->new(TRUE, 0);
my $delay_box = Gtk2::HBox->new(TRUE, 0);
my $delay_box2 = Gtk2::HBox->new(FALSE, 0);
my $thumbnail_box = Gtk2::HBox->new(TRUE, 0);
my $thumbnail_box2 = Gtk2::HBox->new(FALSE, 0);
my $filename_box = Gtk2::HBox->new(TRUE, 0);
my $progname_box = Gtk2::HBox->new(TRUE, 0);
my $progname_box2 = Gtk2::HBox->new(FALSE, 0);
my $im_colors_box = Gtk2::HBox->new(TRUE, 0);
my $im_colors_box2 = Gtk2::HBox->new(FALSE, 0);
my $filetype_box = Gtk2::HBox->new(TRUE, 0);
my $saveDir_box = Gtk2::HBox->new(TRUE, 0);
my $behavior_box = Gtk2::HBox->new(TRUE, 0);
my $border_box = Gtk2::HBox->new(TRUE, 0);

$window->add($vbox);

#############MENU###################
my $menubar = Gtk2::MenuBar->new() ;

my $menu1= Gtk2::Menu->new() ;

my $menuitem_file = Gtk2::MenuItem->new_with_mnemonic($d->get("_File")) ;

my $menuitem_revert = Gtk2::ImageMenuItem->new_with_mnemonic($d->get("_Revert Settings")) ;
$menuitem_revert->set_image(Gtk2::Image->new_from_icon_name('gtk-revert-to-saved-ltr', 'menu'));
$menuitem_revert->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ Z }, qw/control-mask/, qw/visible/);
$menu1->append($menuitem_revert) ;
$menuitem_revert->signal_connect("activate" , \&event_settings , 'menu_revert') ;

my $menuitem_save = Gtk2::ImageMenuItem->new_with_mnemonic($d->get("_Save Settings")) ;
$menuitem_save->set_image(Gtk2::Image->new_from_icon_name('gtk-save', 'menu'));
$menuitem_save->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ S }, qw/control-mask/, qw/visible/);
$menu1->append($menuitem_save) ;
$menuitem_save->signal_connect("activate" , \&event_settings , 'menu_save') ;

my $separator_menu1 = Gtk2::SeparatorMenuItem->new();
$menu1->append($separator_menu1);

my $menuitem_quit = Gtk2::ImageMenuItem->new_with_mnemonic($d->get("_Quit")) ;
$menuitem_quit->set_image(Gtk2::Image->new_from_icon_name('gtk-quit', 'menu'));
$menuitem_quit->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ Q }, qw/control-mask/, qw/visible/);
$menu1->append($menuitem_quit) ;
$menuitem_quit->signal_connect("activate" , \&event_delete_window , 'menu_quit') ;

$menuitem_file->set_submenu($menu1);
$menubar->append($menuitem_file) ;


my $menu2 = Gtk2::Menu->new() ;

my $menuitem_selection = Gtk2::ImageMenuItem->new_with_mnemonic($d->get("Capture with selection")) ;
$menuitem_selection->set_image(Gtk2::Image->new_from_icon_name('gtk-cut', 'menu'));
$menuitem_selection->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ S }, qw/mod1-mask/, qw/visible/);
$menu2->append($menuitem_selection) ;
$menuitem_selection->signal_connect("activate" , \&event_handle, 'select') ;

my $menuitem_raw = Gtk2::ImageMenuItem->new_with_mnemonic($d->get("Capture")) ;
$menuitem_raw->set_image(Gtk2::Image->new_from_icon_name('gtk-fullscreen', 'menu'));
$menuitem_raw->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ F }, qw/mod1-mask/, qw/visible/);
$menu2->append($menuitem_raw) ;
$menuitem_raw->signal_connect("activate" , \&event_handle, 'raw') ;

my $menuitem_web = Gtk2::ImageMenuItem->new_with_mnemonic($d->get("Capture website")) ;
$menuitem_web->set_image(Gtk2::Image->new_from_file ("$gscrot_path/share/gscrot/resources/icons/web_image.png"));
$menuitem_web->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ W }, qw/mod1-mask/, qw/visible/);
$menu2->append($menuitem_web) ;
$menuitem_web->signal_connect("activate" , \&event_handle, 'web') ;

my $menuitem_action = Gtk2::MenuItem->new_with_mnemonic($d->get("_Actions")) ;

$menuitem_action->set_submenu($menu2) ;
$menubar->append($menuitem_action) ; 

my $menu3 = Gtk2::Menu->new() ;

my $menuitem_about = Gtk2::ImageMenuItem->new_with_mnemonic($d->get("_Info")) ;
$menuitem_about->set_image(Gtk2::Image->new_from_icon_name('gtk-about', 'menu'));
$menuitem_about->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ I }, qw/control-mask/, qw/visible/);
$menu3->append($menuitem_about) ;
$menuitem_about->signal_connect("activate" , \&event_about, $window) ;

my $menuitem_help = Gtk2::MenuItem->new_with_mnemonic($d->get("_Help")) ;

$menuitem_help->set_submenu($menu3) ;
$menubar->append($menuitem_help) ; 

$vbox->pack_start($menubar, FALSE, FALSE, 0);
#############MENU###################

#############BUTTON_SELECT###################
my $button_select = Gtk2::Button->new($d->get("Capture\nwith selection"));
$button_select->signal_connect(clicked => \&event_handle, 'select');

my $image_select = Gtk2::Image->new_from_icon_name ('gtk-cut', 'dialog');
$button_select->set_image($image_select);

my $tooltip_select = Gtk2::Tooltips->new;
$tooltip_select->set_tip($button_select,$d->get("Draw a rectangular capture area with your mouse\nto select a specified screen area\nor select a window to capture its content"));

$button_box->pack_start($button_select, TRUE, TRUE, 0);
#############BUTTON_SELECT###################

#############BUTTON_RAW######################
my $button_raw = Gtk2::Button->new($d->get("Capture"));
$button_raw->signal_connect(clicked => \&event_handle, 'raw');

my $image_raw = Gtk2::Image->new_from_icon_name ('gtk-fullscreen', 'dialog');
$button_raw->set_image($image_raw);

my $tooltip_raw = Gtk2::Tooltips->new;
$tooltip_raw->set_tip($button_raw,$d->get("Take a screenshot of your whole desktop"));

$button_box->pack_start($button_raw, TRUE, TRUE, 0);
#############BUTTON_RAW######################

#############BUTTON_WEB######################
my $button_web = Gtk2::Button->new($d->get("Capture\nwebsite"));
$button_web->signal_connect(clicked => \&event_handle, 'web');

my $image_web = Gtk2::Image->new_from_file ("$gscrot_path/share/gscrot/resources/icons/web_image.svg");
$button_web->set_image($image_web);

my $tooltip_web = Gtk2::Tooltips->new;
$tooltip_web->set_tip($button_web,$d->get("Take a screenshot of a website"));

$button_box->pack_start($button_web, TRUE, TRUE, 0);
#############BUTTON_WEB######################

$vbox_inner->pack_start($button_box, FALSE, FALSE, 0);

#############TRAYICON######################
my $icon = Gtk2::Image->new_from_file("$gscrot_path/share/gscrot/resources/icons/gscrot24x24.png");
my $eventbox = Gtk2::EventBox->new;
$eventbox->add($icon);
my $tray = Gtk2::TrayIcon->new('GScrot TrayIcon');
$tray->add($eventbox);

#tooltip
my $tooltip_tray = Gtk2::Tooltips->new;
$tooltip_tray->set_tip($tray, $gscrot_name." ".$gscrot_version);

#events and timeouts
$eventbox->signal_connect('button_release_event', \&event_show_icon_menu);
#show tray
$tray->show_all;
#############TRAYICON######################

#############SETTINGS######################
my $file_frame_label = Gtk2::Label->new;
$file_frame_label->set_markup($d->get("Image format"));
my $file_frame = Gtk2::Frame->new();
$file_frame->set_label_widget($file_frame_label);

my $save_frame_label = Gtk2::Label->new;
$save_frame_label->set_markup($d->get("Save"));
my $save_frame = Gtk2::Frame->new();
$save_frame->set_label_widget($save_frame_label);

my $behavior_frame_label = Gtk2::Label->new;
$behavior_frame_label->set_markup($d->get("Behavior"));
my $behavior_frame = Gtk2::Frame->new();
$behavior_frame->set_label_widget($behavior_frame_label);

my $actions_frame_label = Gtk2::Label->new;
$actions_frame_label->set_markup($d->get("Actions"));
my $actions_frame = Gtk2::Frame->new();
$actions_frame->set_label_widget($actions_frame_label);

my $capture_frame_label = Gtk2::Label->new;
$capture_frame_label->set_markup($d->get("Capture"));
my $capture_frame = Gtk2::Frame->new();
$capture_frame->set_label_widget($capture_frame_label);

my $scale_label = Gtk2::Label->new;
$scale_label->set_text($d->get("Quality"));

my $scale = Gtk2::HScale->new_with_range(1, 100, 1);
$scale->signal_connect('value-changed' => \&event_handle, 'quality_changed');
$scale->set_value_pos('right');
$scale->set_value(75);

my $tooltip_quality = Gtk2::Tooltips->new;
$tooltip_quality->set_tip($scale,$d->get("Quality/Compression:\nHigh value means high size / high compression\n(depending on file format chosen)\n\nHint: When capturing a website\nadjusting compression level of png files\nis not supported yet"));
$tooltip_quality->set_tip($scale_label,$d->get("Quality/Compression:\nHigh value means high size / high compression\n(depending on file format chosen)\n\nHint: When capturing a website\nadjusting compression level of png files\nis not supported yet"));
$scale_box->pack_start($scale_label, FALSE, TRUE, 10);
$scale_box->pack_start($scale, TRUE, TRUE, 10);

#delay
my $delay_label = Gtk2::Label->new;
$delay_label->set_text($d->get("Delay"));

my $delay = Gtk2::HScale->new_with_range(1, 10, 1);
$delay->signal_connect('value-changed' => \&event_handle, 'delay_changed');
$delay->set_value_pos('right');
$delay->set_value(0);

my $delay_active = Gtk2::CheckButton->new;
$delay_active->signal_connect('toggled' => \&event_handle, 'delay_toggled');
$delay_active->set_active(TRUE);
$delay_active->set_active(FALSE);

my $tooltip_delay = Gtk2::Tooltips->new;
$tooltip_delay->set_tip($delay,$d->get("Wait n seconds before taking a screenshot"));
$tooltip_delay->set_tip($delay_active,$d->get("Wait n seconds before taking a screenshot"));
$tooltip_delay->set_tip($delay_label,$d->get("Wait n seconds before taking a screenshot"));

$delay_box->pack_start($delay_label, FALSE, TRUE, 10);
$delay_box2->pack_start($delay_active, FALSE, FALSE, 0);
$delay_box2->pack_start($delay, TRUE, TRUE, 0);
$delay_box->pack_start($delay_box2, TRUE, TRUE, 10);

#end - delay

#thumbnail
my $thumbnail_label = Gtk2::Label->new;
$thumbnail_label->set_text($d->get("Thumbnail"));

my $thumbnail = Gtk2::HScale->new_with_range(1, 100, 1);
$thumbnail->signal_connect('value-changed' => \&event_handle, 'thumbnail_changed');
$thumbnail->set_value_pos('right');
$thumbnail->set_value(50);

my $thumbnail_active = Gtk2::CheckButton->new;
$thumbnail_active->signal_connect('toggled' => \&event_handle, 'thumbnail_toggled');
$thumbnail_active->set_active(TRUE);
$thumbnail_active->set_active(FALSE);

my $tooltip_thumb = Gtk2::Tooltips->new;
$tooltip_thumb->set_tip($thumbnail,$d->get("Generate thumbnail too.\nselect the percentage of the original size for the thumbnail to be"));
$tooltip_thumb->set_tip($thumbnail_active,$d->get("Generate thumbnail too.\nselect the percentage of the original size for the thumbnail to be"));
$tooltip_thumb->set_tip($thumbnail_label,$d->get("Generate thumbnail too.\nselect the percentage of the original size for the thumbnail to be"));

$thumbnail_box->pack_start($thumbnail_label, FALSE, TRUE, 10);
$thumbnail_box2->pack_start($thumbnail_active, FALSE, FALSE, 0);
$thumbnail_box2->pack_start($thumbnail, TRUE, TRUE, 0);
$thumbnail_box->pack_start($thumbnail_box2, TRUE, TRUE, 10);

#end - thumbnail

#filename
my $filename = Gtk2::Entry->new;
$filename->set_text("\%Y-\%m-\%d-\%T_\$wx\$h");
$filename->signal_connect('move-cursor' => \&event_handle, 'cursor_moved');

my $filename_label = Gtk2::Label->new;
$filename_label->set_text($d->get("Filename"));


my $tooltip_filename = Gtk2::Tooltips->new;
$tooltip_filename->set_tip($filename,$d->get("There are several wild-cards available, like\n%Y = year\n%m = month\n%d = day\n%T = time\n\$w = width\n\$h = height"));
$tooltip_filename->set_tip($filename_label,$d->get("There are several wild-cards available, like\n%Y = year\n%m = month\n%d = day\n%T = time\n\$w = width\n\$h = height"));

$filename_box->pack_start($filename_label, FALSE, TRUE, 10);
$filename_box->pack_start($filename, TRUE, TRUE, 10);
#end - filename

#type
my $combobox_type = Gtk2::ComboBox->new_text;
$combobox_type->insert_text (0, "jpeg");
$combobox_type->insert_text (1, "png");
$combobox_type->signal_connect('changed' => \&event_handle, 'type_changed');
$combobox_type->set_active (1);

my $filetype_label = Gtk2::Label->new;
$filetype_label->set_text($d->get("Image format"));

my $tooltip_filetype = Gtk2::Tooltips->new;
$tooltip_filetype->set_tip($combobox_type,$d->get("Select a file format"));
$tooltip_filetype->set_tip($filetype_label,$d->get("Select a file format"));

$filetype_box->pack_start($filetype_label, FALSE, TRUE, 10);
$filetype_box->pack_start($combobox_type, TRUE, TRUE, 10);
#end - filetype


#saveDir
my $saveDir_label = Gtk2::Label->new;
$saveDir_label->set_text($d->get("Directory"));

my $saveDir_button = Gtk2::FileChooserButton->new ('gscrot - Select a folder', 'select-folder');

my $tooltip_saveDir = Gtk2::Tooltips->new;
$tooltip_saveDir->set_tip($saveDir_button,$d->get("Your screenshots will be saved\nto this directory"));
$tooltip_saveDir->set_tip($saveDir_label,$d->get("Your screenshots will be saved\nto this directory"));

$saveDir_box->pack_start($saveDir_label, FALSE, TRUE, 10);
$saveDir_box->pack_start($saveDir_button, TRUE, TRUE, 10);
#end - saveDir

#behavior
my $hide_active = Gtk2::CheckButton->new_with_label($d->get("Autohide GScrot Window when taking a screenshot"));
my $ask_quit_active = Gtk2::CheckButton->new_with_label($d->get("Show \"Do you really want to quit?\" dialog when exiting"));
my $close_at_close_active = Gtk2::CheckButton->new_with_label($d->get("Minimize to tray when closing main window"));

$hide_active->signal_connect('toggled' => \&event_behavior_handle, 'hide_toggled');
$hide_active->set_active(TRUE);
my $tooltip_hide = Gtk2::Tooltips->new;
$tooltip_hide->set_tip($hide_active,$d->get("Automatically hide GScrot Window when taking a screenshot"));

$close_at_close_active->signal_connect('toggled' => \&event_behavior_handle, 'close_at_close_toggled');
$close_at_close_active->set_active(TRUE);
my $tooltip_close_at_close = Gtk2::Tooltips->new;
$tooltip_close_at_close->set_tip($close_at_close_active,$d->get("Automatically hide GScrot Window when taking a screenshot"));

$ask_quit_active->signal_connect('toggled' => \&event_behavior_handle, 'ask_quit_toggled');
$hide_active->set_active(TRUE);
my $tooltip_ask_quit = Gtk2::Tooltips->new;
$tooltip_ask_quit->set_tip($hide_active,$d->get("Show \"Do you really want to quit?\" dialog when exiting GScrot"));
#end - behavior


#program
my $model = Gtk2::ListStore->new ('Gtk2::Gdk::Pixbuf', 'Glib::String', 'Glib::String');
foreach (keys %gm_programs){
	if($gm_programs{$_}->{'binary'} ne "" && $gm_programs{$_}->{'name'} ne ""){
		my $pixbuf; 
		if (-f $gm_programs{$_}->{'pixmap'}){
			$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ($gm_programs{$_}->{'pixmap'}, 20, 20);
		}else{
			$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/executable.svg", 20, 20);
		} 
		$model->set ($model->append, 0, $pixbuf , 1, $gm_programs{$_}->{'name'}, 2, $_);				
	}else{
		print "WARNING: Program $_ is not configured properly, ignoring\n";	
	}	
}
my $progname = Gtk2::ComboBox->new ($model);
my $renderer_pix = Gtk2::CellRendererPixbuf->new;
$progname->pack_start ($renderer_pix, FALSE);
$progname->add_attribute ($renderer_pix, pixbuf => 0);
my $renderer_text = Gtk2::CellRendererText->new;
$progname->pack_start ($renderer_text, FALSE);
$progname->add_attribute ($renderer_text, text => 1);
$progname->set_active(0);

my $progname_active = Gtk2::CheckButton->new;
$progname_active->signal_connect('toggled' => \&event_handle, 'progname_toggled');
$progname_active->set_active($progname_active);

my $progname_label = Gtk2::Label->new;
$progname_label->set_text($d->get("Open with"));

my $tooltip_progname = Gtk2::Tooltips->new;
$tooltip_progname->set_tip($progname,$d->get("Open your screenshot\nwith this program after capturing"));
$tooltip_progname->set_tip($progname_active,$d->get("Open your screenshot\nwith this program after capturing"));
$tooltip_progname->set_tip($progname_label,$d->get("Open your screenshot\nwith this program after capturing"));

$progname_box->pack_start($progname_label, TRUE, TRUE, 10);
$progname_box2->pack_start($progname_active, FALSE, TRUE, 0);
$progname_box2->pack_start($progname, TRUE, TRUE, 0);
$progname_box->pack_start($progname_box2, TRUE, TRUE, 10);
#end - program

#im_colors
my $combobox_im_colors = Gtk2::ComboBox->new_text;
$combobox_im_colors->insert_text (0, $d->get("16 colors   - (4bit) "));
$combobox_im_colors->insert_text (1, $d->get("64 colors   - (6bit) "));
$combobox_im_colors->insert_text (2, $d->get("256 colors  - (8bit) "));

$combobox_im_colors->signal_connect('changed' => \&event_handle, 'border_changed');
$combobox_im_colors->set_active (2);

my $im_colors_active = Gtk2::CheckButton->new;
$im_colors_active->signal_connect('toggled' => \&event_handle, 'im_colors_toggled');
$im_colors_active->set_active(TRUE);
$im_colors_active->set_active(FALSE);

my $im_colors_label = Gtk2::Label->new;
$im_colors_label->set_text($d->get("Reduce colors"));

my $tooltip_im_colors = Gtk2::Tooltips->new;
$tooltip_im_colors->set_tip($combobox_im_colors,$d->get("Automatically reduce colors \nafter taking a screenshot"));
$tooltip_im_colors->set_tip($im_colors_active,$d->get("Automatically reduce colors \nafter taking a screenshot"));
$tooltip_im_colors->set_tip($im_colors_label,$d->get("Automatically reduce colors \nafter taking a screenshot"));

$im_colors_box->pack_start($im_colors_label, TRUE, TRUE, 10);
$im_colors_box2->pack_start($im_colors_active, FALSE, TRUE, 0);
$im_colors_box2->pack_start($combobox_im_colors, TRUE, TRUE, 0);
$im_colors_box->pack_start($im_colors_box2, TRUE, TRUE, 10);
#end - colors

#border
my $combobox_border = Gtk2::ComboBox->new_text;
$combobox_border->insert_text (1, $d->get("activate"));
$combobox_border->insert_text (0, $d->get("deactivate"));
$combobox_border->signal_connect('changed' => \&event_handle, 'border_changed');
$combobox_border->set_active (0);

my $border_label = Gtk2::Label->new;
$border_label->set_text($d->get("Window border"));
$border_label->set_justify('left');

my $tooltip_border = Gtk2::Tooltips->new;
$tooltip_border->set_tip($combobox_border,$d->get("When selecting a window, grab wm border too\n(capture with selection only)\nThere is no need of this option if you are using compiz"));
$tooltip_border->set_tip($border_label,$d->get("When selecting a window, grab wm border too\n(capture with selection only)\nThere is no need of this option if you are using compiz"));

$border_box->pack_start($border_label, FALSE, TRUE, 10);
$border_box->pack_start($combobox_border, TRUE, TRUE, 10);
#end - border

#accounts
my $accounts_model = Gtk2::ListStore->new ('Glib::String', 'Glib::String', 'Glib::String');

foreach (keys %accounts){
	$accounts_model->set ($accounts_model->append, 0, $accounts{$_}->{'host'} , 1, $accounts{$_}->{'username'}, 2, $accounts{$_}->{'password'});				
}
my $accounts_tree = Gtk2::TreeView->new_with_model ($accounts_model);
 
my $tv_clmn_name_text = Gtk2::TreeViewColumn->new;
$tv_clmn_name_text->set_title($d->get("Host"));
#pixbuf renderer
my $renderer_name_accounts = Gtk2::CellRendererText->new;
#pack it into the column
$tv_clmn_name_text->pack_start ($renderer_name_accounts, FALSE);
#set its atributes
$tv_clmn_name_text->set_attributes($renderer_name_accounts, text => 0);

#append this column to the treeview
$accounts_tree->append_column($tv_clmn_name_text);

my $tv_clmn_username_text = Gtk2::TreeViewColumn->new;
$tv_clmn_username_text->set_title($d->get("Username"));
#pixbuf renderer
my $renderer_username_accounts = Gtk2::CellRendererText->new;
#pack it into the column
$tv_clmn_username_text->pack_start ($renderer_username_accounts, FALSE);
#set its atributes
$tv_clmn_username_text->set_attributes($renderer_username_accounts, text => 1);

#append this column to the treeview
$accounts_tree->append_column($tv_clmn_username_text);

my $tv_clmn_password_text = Gtk2::TreeViewColumn->new;
$tv_clmn_password_text->set_title($d->get("Password"));
#pixbuf renderer
my $renderer_password_accounts = Gtk2::CellRendererText->new;
#pack it into the column
$tv_clmn_password_text->pack_start ($renderer_password_accounts, FALSE);
#set its atributes
$tv_clmn_password_text->set_attributes($renderer_password_accounts, text => 2);

#append this column to the treeview
$accounts_tree->append_column($tv_clmn_password_text);

#end accounts

#this is only important, if there are any plugins
my $effects_tree;
if (keys(%plugins) > 0){
	#plugins-effects
	my $effects_model = Gtk2::ListStore->new ('Gtk2::Gdk::Pixbuf', 'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String');
	foreach (keys %plugins){
		if($plugins{$_}->{'binary'} ne ""){
			my $pixbuf; 
			if (-f $plugins{$_}->{'pixmap'}){
				$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ($plugins{$_}->{'pixmap'}, 20, 20);
			}else{
				$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/executable.svg", 20, 20);
			} 
			#get translated plugin-name
			$plugins{$_}->{'name'} = `$plugins{$_}->{'binary'} name`;
			utf8::decode $plugins{$_}->{'name'};
			$plugins{$_}->{'category'} = `$plugins{$_}->{'binary'} sort`;
			utf8::decode $plugins{$_}->{'category'};
			$plugins{$_}->{'tooltip'} = `$plugins{$_}->{'binary'} tip`;
			utf8::decode $plugins{$_}->{'tooltip'};
			$plugins{$_}->{'ext'} = `$plugins{$_}->{'binary'} ext`;
			utf8::decode $plugins{$_}->{'ext'};			
			chomp($plugins{$_}->{'name'}); chomp($plugins{$_}->{'category'}); chomp($plugins{$_}->{'tooltip'}); chomp($plugins{$_}->{'ext'});
			
			#check if plugin can handle png and/or jpeg
			my $pixbuf_jpeg = 'gtk-no'; my $pixbuf_png = 'gtk-no';
			$pixbuf_jpeg = 'gtk-yes' if($plugins{$_}->{'ext'} =~ /jpeg/);
			$pixbuf_png = 'gtk-yes' if($plugins{$_}->{'ext'} =~ /png/);
			
			$effects_model->set ($effects_model->append, 0, $pixbuf , 1, $plugins{$_}->{'name'}, 2, $plugins{$_}->{'binary'}, 3, $plugins{$_}->{'category'}, 4, $plugins{$_}->{'tooltip'}, 5, $pixbuf_jpeg, 6, $pixbuf_png);				
		}else{
			print "WARNING: Program $_ is not configured properly, ignoring\n";	
		}	
	}

	$effects_tree = Gtk2::TreeView->new_with_model ($effects_model);
	$effects_tree->signal_connect('row-activated' => \&event_plugins, 'row_activated');
	$effects_tree->set_tooltip_column(4) if Gtk2->CHECK_VERSION (2, 11, 0);
	 
	my $tv_clmn_pix_text = Gtk2::TreeViewColumn->new;
	$tv_clmn_pix_text->set_title($d->get("Icon"));
	#pixbuf renderer
	my $renderer_pix_effects = Gtk2::CellRendererPixbuf->new;
	#pack it into the column
	$tv_clmn_pix_text->pack_start ($renderer_pix_effects, FALSE);
	#set its atributes
	$tv_clmn_pix_text->set_attributes($renderer_pix_effects, pixbuf => 0);

	#append this column to the treeview
	$effects_tree->append_column($tv_clmn_pix_text);

	my $tv_clmn_text_text = Gtk2::TreeViewColumn->new;
	$tv_clmn_text_text->set_title($d->get("Name"));
	#pixbuf renderer
	my $renderer_text_effects = Gtk2::CellRendererText->new;
	#pack it into the column
	$tv_clmn_text_text->pack_start ($renderer_text_effects, FALSE);
	#set its atributes
	$tv_clmn_text_text->set_attributes($renderer_text_effects, text => 1);

	#append this column to the treeview
	$effects_tree->append_column($tv_clmn_text_text);

	my $tv_clmn_category_text = Gtk2::TreeViewColumn->new;
	$tv_clmn_category_text->set_title($d->get("Category"));
	#pixbuf renderer
	my $renderer_category_effects = Gtk2::CellRendererText->new;
	#pack it into the column
	$tv_clmn_category_text->pack_start ($renderer_category_effects, FALSE);
	#set its atributes
	$tv_clmn_category_text->set_attributes($renderer_category_effects, text => 3);

	#append this column to the treeview
	$effects_tree->append_column($tv_clmn_category_text);

	my $tv_clmn_jpeg_text = Gtk2::TreeViewColumn->new;
	$tv_clmn_jpeg_text->set_title("jpeg");
	#pixbuf renderer
	my $renderer_jpeg_effects = Gtk2::CellRendererPixbuf->new;
	#pack it into the column
	$tv_clmn_jpeg_text->pack_start ($renderer_jpeg_effects, FALSE);
	#set its atributes
	$tv_clmn_jpeg_text->set_attributes($renderer_jpeg_effects, stock_id => 5);

	#append this column to the treeview
	$effects_tree->append_column($tv_clmn_jpeg_text);

	my $tv_clmn_png_text = Gtk2::TreeViewColumn->new;
	$tv_clmn_png_text->set_title("png");
	#pixbuf renderer
	my $renderer_png_effects = Gtk2::CellRendererPixbuf->new;
	#pack it into the column
	$tv_clmn_png_text->pack_start ($renderer_png_effects, FALSE);
	#set its atributes
	$tv_clmn_png_text->set_attributes($renderer_png_effects, stock_id => 6);

	#append this column to the treeview
	$effects_tree->append_column($tv_clmn_png_text);

	unless (Gtk2->CHECK_VERSION (2, 12, 0)){
		my $tv_clmn_descr_text = Gtk2::TreeViewColumn->new;
		$tv_clmn_descr_text->set_title($d->get("Description"));
		#pixbuf renderer
		my $renderer_descr_effects = Gtk2::CellRendererText->new;
		#pack it into the column
		$tv_clmn_descr_text->pack_start ($renderer_descr_effects, FALSE);
		#set its atributes
		$tv_clmn_descr_text->set_attributes($renderer_descr_effects, text => 4);

		#append this column to the treeview
		$effects_tree->append_column($tv_clmn_descr_text);		
	}

	my $tv_clmn_path_text = Gtk2::TreeViewColumn->new;
	$tv_clmn_path_text->set_title($d->get("Path"));
	#pixbuf renderer
	my $renderer_path_effects = Gtk2::CellRendererText->new;
	#pack it into the column
	$tv_clmn_path_text->pack_start ($renderer_path_effects, FALSE);
	#set its atributes
	$tv_clmn_path_text->set_attributes($renderer_path_effects, text => 2);

	#append this column to the treeview
	$effects_tree->append_column($tv_clmn_path_text);

}
#############SETTINGS######################


#############PACKING######################
$file_vbox->pack_start($scale_box, FALSE, TRUE, 5);
$file_vbox->pack_start($filetype_box, FALSE, TRUE, 5);
$file_frame->add($file_vbox);

$save_vbox->pack_start($filename_box, FALSE, TRUE, 5);
$save_vbox->pack_start($saveDir_box, FALSE, TRUE, 5);
$save_frame->add($save_vbox);

$vbox_basic->pack_start($file_frame, FALSE, TRUE, 5);
$vbox_basic->pack_start($save_frame, FALSE, TRUE, 5);
$vbox_basic->set_border_width(5);

$behavior_vbox->pack_start($hide_active, FALSE, TRUE, 5);
$behavior_vbox->pack_start($close_at_close_active, FALSE, TRUE, 5);
$behavior_vbox->pack_start($ask_quit_active, FALSE, TRUE, 5);
$behavior_frame->add($behavior_vbox);

$vbox_behavior->pack_start($behavior_frame, FALSE, TRUE, 5);
$vbox_behavior->set_border_width(5);

$capture_vbox->pack_start($delay_box, FALSE, TRUE, 5);
$capture_vbox->pack_start($thumbnail_box, FALSE, TRUE, 5);
$capture_vbox->pack_start($border_box, FALSE, TRUE, 5);
$capture_frame->add($capture_vbox);

$actions_vbox->pack_start($progname_box, FALSE, TRUE, 5);
$actions_vbox->pack_start($im_colors_box, FALSE, TRUE, 5);
$actions_frame->add($actions_vbox);

my $label_basic = Gtk2::Label->new;
$label_basic->set_markup ($d->get("<i>Basic Settings</i>"));

my $label_extras = Gtk2::Label->new;
$label_extras->set_markup ($d->get("<i>Extras</i>"));

my $label_behavior = Gtk2::Label->new;
$label_behavior->set_markup ($d->get("<i>Behavior</i>"));

my $notebook_settings_first = $notebook_settings->append_page ($vbox_basic,$label_basic);
my $notebook_settings_second = $notebook_settings->append_page ($vbox_extras,$label_extras);
my $notebook_settings_third = $notebook_settings->append_page ($vbox_behavior,$label_behavior);

$vbox_extras->pack_start($actions_frame, TRUE, TRUE, 1);
$vbox_extras->pack_start($capture_frame, TRUE, TRUE, 1);
$vbox_extras->set_border_width(5);

my $scrolled_accounts_window = Gtk2::ScrolledWindow->new;
$scrolled_accounts_window->set_policy ('automatic', 'automatic');
$scrolled_accounts_window->add($accounts_tree);

my $label_accounts = Gtk2::Label->new;
$label_accounts->set_markup ($d->get("<i>Accounts</i>"));

$accounts_vbox->pack_start($scrolled_accounts_window, TRUE, TRUE, 1);

$vbox_accounts->pack_start($accounts_vbox, TRUE, TRUE, 1);
$vbox_accounts->set_border_width(5);

my $notebook_settings_fourth = $notebook_settings->append_page ($vbox_accounts,$label_accounts);

if (keys(%plugins) > 0){

	my $scrolled_plugins_window = Gtk2::ScrolledWindow->new;
	$scrolled_plugins_window->set_policy ('automatic', 'automatic');
	$scrolled_plugins_window->add($effects_tree);

	my $label_plugins = Gtk2::Label->new;
	$label_plugins->set_markup ($d->get("<i>Plugins</i>"));

	$effects_vbox->pack_start($scrolled_plugins_window, TRUE, TRUE, 1);

	$vbox_plugins->pack_start($effects_vbox, TRUE, TRUE, 1);
	$vbox_plugins->set_border_width(5);

	my $notebook_settings_fifth = $notebook_settings->append_page ($vbox_plugins,$label_plugins);
}

$vbox_inner->pack_start($notebook_settings, FALSE, FALSE, 1);
$vbox_inner->pack_start($notebook, TRUE, TRUE, 1);
$vbox_inner->set_border_width(10);

$vbox->pack_start($vbox_inner, TRUE, TRUE, 1);
$vbox->pack_start($statusbar, FALSE, TRUE, 1);
#############PACKING######################

unless($min_cparam){
	$window->show_all;
}else{
	$window->hide;
}

#load saved settings
	&function_load_settings if(-f "$ENV{ 'HOME' }/.gscrot/settings.conf" && -r "$ENV{ 'HOME' }/.gscrot/settings.conf");

#GTK2 Main Loop
Gtk2->main;

0;

#initialize gscrot, check dependencies
sub function_init
{
	#are there any command line params?
	if(@ARGV > 0){
		my $arg;	
		foreach $arg (@args){
			if($arg eq "--debug"){
				$debug_cparam = TRUE;
			}elsif($arg eq "--help"){
				&function_usage();
				exit;
			}elsif($arg eq "--min_at_startup"){
				$min_cparam = TRUE;
			}elsif($arg eq "--beeper_off"){
				$boff_cparam = TRUE;
			}else{
				print "\ncommand ".$arg." not recognized --> will be ignored\n";
				&function_usage();
				exit;		
			}
			print "\ncommand ".$arg." recognized!\n";			
		}
	}else{
		print "INFO: no command line parameters set...\n";
	}	
	
	
	print "\nINFO: gathering system information...";
	print "\n";
	printf "Glib %s \n", $Glib::VERSION;
	printf "Gtk2 %s \n", $Gtk2::VERSION;
	print "\n";

	# The version info stuff appeared in 1.040.
	print "Glib built for ".join(".", Glib->GET_VERSION_INFO).", running with "
    	.join(".", &Glib::major_version, &Glib::minor_version, &Glib::micro_version)
    	."\n"
  	if $Glib::VERSION >= 1.040;
	print "Gtk2 built for ".join(".", Gtk2->GET_VERSION_INFO).", running with "
    	.join(".", &Gtk2::major_version, &Gtk2::minor_version, &Gtk2::micro_version)
    	."\n"
  	if $Gtk2::VERSION >= 1.040;
	print "\n";


	print "INFO: searching for dependencies...\n\n";
	
	if(system("which scrot")==0){
		print "SUCCESS: scrot is installed on your system!\n";
	}else{
		die "ERROR: dependency is missing --> scrot is not installed on your system!\n";
	}
	my $scrot_version = `scrot --version`;
	print "INFO: you are using $scrot_version\n";

	if(system("which gtklp")==0){
		print "SUCCESS: gtklp is installed on your system!\n\n";
	}else{
		die "ERROR: dependency is missing --> gtklp is not installed on your system!\n\n";
	}
	if(system("which gnome-web-photo")==0){
		print "SUCCESS: gnome-web-photo is installed on your system!\n\n";
	}else{
		die "ERROR: dependency is missing --> gnome-web-photo is not installed on your system!\n\n";
	}

	if(system("which gscrot.pl")==0){
		print "INFO: gscrot seems to be properly installed on your system!\n";
		print "INFO: gscrot will try to find resource directory at default location (/usr)!\n";
		$gscrot_path = "/usr";
	}else{
		print "INFO: gscrot is not installed on your system!\n";
		print "INFO: gscrot will try to find resource directory in place (../)!\n";
		$gscrot_path = "..";
	}

	#an old .gscrot file existing?
	rename("$ENV{ 'HOME' }/.gscrot", "$ENV{ 'HOME' }/.gscrot_old") if (-f "$ENV{ 'HOME' }/.gscrot");
	#is there already a .gscrot folder?
	mkdir("$ENV{ 'HOME' }/.gscrot") unless (-d "$ENV{ 'HOME' }/.gscrot");
	#an old .gscrot file existing (it is renamed above)?
	rename("$ENV{ 'HOME' }/.gscrot_old", "$ENV{ 'HOME' }/.gscrot/settings.conf") if (-f "$ENV{ 'HOME' }/.gscrot_old");

	%gm_programs = do "$gscrot_path/share/gscrot/resources/system/programs.conf";
	if (-f "$ENV{ 'HOME' }/.gscrot/programs.conf"){
		print "\nINFO: using custom program settings found at $ENV{ 'HOME' }/.gscrot/programs.conf\n";
		%gm_programs = do "$ENV{ 'HOME' }/.gscrot/programs.conf";
	}
	%plugins = do "$gscrot_path/share/gscrot/resources/system/plugins.conf" if (-f "$gscrot_path/share/gscrot/resources/system/plugins.conf");
	if (-f "$ENV{ 'HOME' }/.gscrot/plugins.conf"){
		print "\nINFO: using custom program settings found at $ENV{ 'HOME' }/.gscrot/plugins.conf\n";
		%plugins = do "$ENV{ 'HOME' }/.gscrot/plugins.conf";
	}    	
	
}

#nearly all events are handled here
sub event_handle
{
	my ($widget, $data) = @_;
	my $quality_value = undef;
	my $delay_value = undef;
	my $thumbnail_value = undef;
	my $progname_value = undef;
	my $im_colors_value = undef;
	my $filename_value = undef;
	my $filetype_value = undef;
	my $border_value = "";
	my $folder = undef;

	my $thumbnail_param = "";	
	my $echo_cmd = "-e 'echo \$f'";
	my $scrot_feedback = "";

	print "\n$data was emitted by widget $widget\n" if $debug_cparam;

	
#checkbox for "open with" -> entry active/inactive
	if($data eq "progname_toggled"){
		if($progname_active->get_active){
			$progname->set_sensitive(TRUE);			
		}else{
			$progname->set_sensitive(FALSE);
		}
	}
	
#checkbox for "color depth" -> entry active/inactive
	if($data eq "im_colors_toggled"){
		if($im_colors_active->get_active){
			$combobox_im_colors->set_sensitive(TRUE);			
		}else{
			$combobox_im_colors->set_sensitive(FALSE);
		}
	}

#checkbox for "thumbnail" -> HScale active/inactive
	if($data eq "delay_toggled"){
		if($delay_active->get_active){	
			$delay->set_sensitive(TRUE);			
		}else{	
			$delay->set_sensitive(FALSE);
		}
	}

#checkbox for "delay" -> HScale active/inactive
	if($data eq "thumbnail_toggled"){
		if($thumbnail_active->get_active){
			$thumbnail->set_sensitive(TRUE);			
		}else{
			$thumbnail->set_sensitive(FALSE);
		}
	}
	
#filetype changed
	if($data eq "type_changed"){
		$filetype_value = $combobox_type->get_active_text();
	
		if($filetype_value eq "jpeg"){
			$scale->set_range(1,100);			
			$scale->set_value(75);	
			$scale_label->set_text($d->get("Quality"));			
		}elsif($filetype_value eq "png"){
			$scale->set_range(0,9);				
			$scale->set_value(9);
			$scale_label->set_text($d->get("Compression"));					
		}
	} 
#capture desktop was chosen	
	if($data eq "raw" || $data eq "select" || $data eq "tray_raw" || $data eq "tray_select" || $data eq "web"|| $data eq "tray_web"){
		$border_value = '--border' if $combobox_border->get_active;
		$filetype_value = $combobox_type->get_active_text();
			
		if($filetype_value eq "jpeg"){
			$quality_value = $scale->get_value();
		}elsif($filetype_value eq "png"){
			$quality_value = $scale->get_value();
			$quality_value = 90-($quality_value*10);			
		}
		
		if($delay_active->get_active){		
			$delay_value = $delay->get_value();
		}else{
			$delay_value = 0;
		}

		if($thumbnail_active->get_active){		
			$thumbnail_value = $thumbnail->get_value();
			$thumbnail_param = "-t $thumbnail_value";
		}
		
		$filename_value = $filename->get_text();
		$filetype_value = $combobox_type->get_active_text();		
		$folder = $saveDir_button->get_filename();
		
		if($delay_value == 0 && $data eq "tray_raw"){
			$delay_value = 1;
		}

		system("xset b off") if $boff_cparam; #turns off the speaker if set as arg
		if($data eq "raw" || $data eq "tray_raw"){
			if($hide_active->get_active() && $window->visible){
				$window->hide;
				Gtk2::Gdk->flush;
				$is_in_tray = TRUE;
			}
			unless ($filename_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No valid filename specified")); return FALSE;};
			$scrot_feedback=`scrot '$folder/$filename_value.$filetype_value' -q $quality_value -d $delay_value $border_value $thumbnail_param $echo_cmd`;
			if($hide_active->get_active()){			
				$window->show_all;
				$is_in_tray = FALSE;
			}		
		}elsif($data eq "web" || $data eq "tray_web"){
			my $url = &dialog_website;
			return 0 unless $url;
			my $hostname = $url; $hostname =~ s/http:\/\///;
			if($hostname eq ""){&dialog_error_message($d->get("No valid url entered"));return 0;}
			#delay doesnt make much sense here, but it's implemented ;-)
			if($delay_active->get_active){		
				sleep $delay_value;
			}
			$filename_value = strftime $filename_value , localtime;
			$scrot_feedback=`gnome-web-photo --mode=photo --format=$filetype_value -q $quality_value $url '$folder/$filename_value.$filetype_value'`;
			my $width = 0;
			my $height = 0;
			if($scrot_feedback eq ""){
				$scrot_feedback = "$folder/$filename_value.$filetype_value";	
				$width = &function_imagemagick_perform("get_width", $scrot_feedback, 0, $filetype_value);
				$height = &function_imagemagick_perform("get_height", $scrot_feedback, 0, $filetype_value);
				if ($width < 1 or $height < 1){&dialog_error_message($d->get("Could not determine file geometry"));return 0;}
				my $scrot_feedback_old = $scrot_feedback;
				$scrot_feedback =~ s/\$w/$width/g;
				$scrot_feedback =~ s/\$h/$height/g;
				unless (rename($scrot_feedback_old, $scrot_feedback)){&dialog_error_message($d->get("Could not substitute wild-cards in filename"));return 0;}
			}else{
				&dialog_error_message($scrot_feedback);return 0;	
			}
			if($thumbnail_active->get_active){
				my $webthumbnail_ending = "thumb";
				$width *= ($thumbnail_value/100);
				$width = int($width);
				$height *= ($thumbnail_value/100);
				$height = int($height);
				my $webthumbnail_size = $width."x".$height;
				my $scrot_feedback_thumbnail = "$folder/$filename_value-$webthumbnail_ending.$filetype_value";
				$scrot_feedback_thumbnail =~ s/\$w/$width/g;
				$scrot_feedback_thumbnail =~ s/\$h/$height/g;
				unless (copy($scrot_feedback, $scrot_feedback_thumbnail)){&dialog_error_message($d-get("Could not generate thumbnail"));exit;}	
				&function_imagemagick_perform("resize", $scrot_feedback_thumbnail, $webthumbnail_size, $filetype_value);				
				unless (&function_file_exists($scrot_feedback_thumbnail)){&dialog_error_message($d-get("Could not generate thumbnail"));exit;}	
			}						
		}else{
			
			if($hide_active->get_active() && $window->visible){
				$window->hide;
				Gtk2::Gdk->flush;
				$is_in_tray = TRUE;
			}
			unless ($filename_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No valid filename specified")); return FALSE;};
			$scrot_feedback=`scrot '$folder/$filename_value.$filetype_value' --select -q $quality_value -d $delay_value $border_value $thumbnail_param $echo_cmd`;			
			if($hide_active->get_active()){			
				$window->show_all;
				$is_in_tray = FALSE;
			}
		}
		system("xset b on") if $boff_cparam; #turns on the speaker again if set as arg

		chomp($scrot_feedback);	
		if (-f $scrot_feedback){
			$scrot_feedback =~ s/$ENV{ HOME }/~/; #switch /home/username in path to ~ 
			print "screenshot successfully saved to $scrot_feedback!\n" if $debug_cparam;
			&dialog_status_message(1, "$scrot_feedback ".$d->get("saved"));
			#append a page to notebook using with label == filename
			my ($second, $minute, $hour) = localtime();
			my $theTime = "$hour:$minute:$second";
			my $theTimeKey = "[".&function_get_latest_tab_key."] - $theTime";
	
			#build hash of screenshots during session	
			$session_screens{$theTimeKey} = $scrot_feedback;
			#and append page with label == key			
			my $new_index = $notebook->append_page (function_create_tab ($theTimeKey, FALSE), Gtk2::Label->new($theTimeKey));
			$window->show_all unless $is_in_tray;				
			my $current_tab = $notebook->get_current_page+1;
			print "new tab $new_index created, current tab is $current_tab\n" if $debug_cparam;
			$notebook->set_current_page($new_index);
			
			#perform some im_actions
			if($im_colors_active->get_active){
				$im_colors_value = $combobox_im_colors->get_active_text();		
				&function_imagemagick_perform("reduce_colors", $scrot_feedback, $im_colors_value, $filetype_value);
			}	
			
			if($progname_active->get_active){		
				my $model = $progname->get_model();
				my $progname_iter = $progname->get_active_iter();
				$progname_value = $model->get_value($progname_iter, 2);
				unless ($progname_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No application specified to open the screenshot")); return FALSE;};
				system("$progname_value $scrot_feedback &"); #open picture in external program
			}
					
		}else{
			&dialog_error_message($d->get("file could not be saved")."\n$scrot_feedback");
			print "screenshot could not be saved\n$scrot_feedback!" if $debug_cparam;
			&dialog_status_message(1, $scrot_feedback." ".$d->get("could not be saved"));
		} 
							
	}
	#close about box
	if($data eq "cancel"){
		$widget->destroy();	
	}

}

#notebook-behavior events are handled here
sub event_behavior_handle
{
	my ($widget, $data) = @_;

	print "\n$data was emitted by widget $widget\n" if $debug_cparam;
	
	if ($data eq "close_at_close_toggled"){
		$ask_quit_active->set_sensitive(FALSE) if $close_at_close_active->get_active;
		$ask_quit_active->set_sensitive(TRUE) unless $close_at_close_active->get_active;			
	}
	
}

sub event_notebook_switch
{
	my ($widget, $data, $tab_index) = @_;
	my $filename;
	my $exists = TRUE; 
	print "\nselected tab $tab_index was emitted by widget $widget\n" if $debug_cparam;
	#$tab_index++;
	$widget = $notebook->get_nth_page($tab_index);
	my @widget_list = $widget->get_children->get_children->get_children; #scrolledwindow, viewport, vbox
	my @hbox_content;
	foreach my $hbox_widget(@widget_list){
		push(@hbox_content, $hbox_widget->get_children);
	}

	@hbox_content = reverse(@hbox_content); # a little bit dirty here to get the label with filename first
	foreach (@hbox_content){
		if ( $_ =~ /^Gtk2::Label/ && $tab_index != 0){ #normal tab
			$filename = $_->get_text();
		}elsif ($_ =~ /^Gtk2::Label/ && $tab_index == 0){ #all tab
			my $n_pages = keys(%session_screens);
			$_->set_text($n_pages." ".$d->nget("screenshot during this session", "screenshots during this session", $n_pages));
		}elsif ($_ =~ /^Gtk2::Image/ && $tab_index != 0){#normal tab
			if(&function_file_exists($filename)){	
				$_->set_from_icon_name ('gtk-yes', 'menu');
			}else{
				$_->set_from_icon_name ('gtk-no', 'menu');
				&dialog_status_message(1, $filename." ".$d->get("is not existing anymore"));
				$exists = FALSE;
				foreach my $key(keys %session_screens){
					delete($session_screens{$key}) if $session_screens{$key} eq $filename; # delete from hash	
				}			
			}
		}
		
	}
	#do it again and set buttons disabled
	@hbox_content = sort(@hbox_content); #do not disable first button (remove)
	foreach (@hbox_content){
		if ($_ =~ /^Gtk2::Button/ && $tab_index != 0 && $exists == FALSE){ #normal tab
			$_->set_sensitive(FALSE) unless $_->get_name =~ /btn_remove/;
		}
	}		
	&function_update_first_tab(); #update first tab for information

}

#close app
sub event_delete_window
{

	my ($widget, $data) = @_;
	print "\n$data was emitted by widget $widget\n" if $debug_cparam;

	if($data ne "menu_quit" && $close_at_close_active->get_active){
		$window->hide;
		$is_in_tray = TRUE;
		return TRUE;				
	}

	if($data eq "menu_quit" or !$ask_quit_active->get_active()){
		Gtk2->main_quit ;
		return FALSE;
	}	

	my $dialog_header = $d->get("Quit GScrot");
 	my $dialog = Gtk2::Dialog->new ($dialog_header,
        						$window,
                              	[qw/modal destroy-with-parent/],
                              	'gtk-no'     => 'no',
                              	'gtk-yes' => 'yes');

	$dialog->set_default_response ('no');
	
	my $exit_hbox = Gtk2::HBox->new(FALSE, 0);
	my $exit_vbox = Gtk2::VBox->new(FALSE, 0);
	my $exit_image = Gtk2::Image->new_from_icon_name ('gtk-dialog-question', 'dialog');
	my $exit_label = Gtk2::Label->new();
	$exit_label->set_text($d->get("Do you really want to quit GScrot?"));
	my $ask_active = Gtk2::CheckButton->new_with_label($d->get("Do not ask this question again"));
	$ask_active->set_active(FALSE);    
    $exit_vbox->pack_start($exit_label, TRUE, TRUE, 0);
    $exit_vbox->pack_start($ask_active, TRUE, TRUE, 0);    
    $exit_hbox->pack_start($exit_image, TRUE, TRUE, 0);
    $exit_hbox->pack_start($exit_vbox, TRUE, TRUE, 0);
    
    $dialog->vbox->add ($exit_hbox);	

	$dialog->show_all;
	
	my $response = $dialog->run ;
	
	if($ask_active->get_active){
		open(FILE, ">>$ENV{ HOME }/.gscrot/settings.conf") or &dialog_status_message(1, $d->get("Settings could not be saved"));	
		my @saved_lines = <FILE>; 
		close(FILE) or &dialog_status_message(1, $d->get("Settings could not be saved"));
		my $found = FALSE;
		foreach(@saved_lines){
			if ($_ =~ /CLOSE_ASK=/){
				$_ = "CLOSE_ASK=\n";
				$found = TRUE;
			} 
		}
		if ($found == FALSE){
			open(FILE, ">>$ENV{ HOME }/.gscrot/settings.conf") or &dialog_status_message(1, $d->get("Settings could not be saved"));	
			print FILE "CLOSE_ASK=\n";
			close(FILE) or &dialog_status_message(1, $d->get("Settings could not be saved"));
		}else{
			open(FILE, ">$ENV{ HOME }/.gscrot/settings.conf") or &dialog_status_message(1, $d->get("Settings could not be saved"));	
			foreach(@saved_lines){
				print FILE $_;
			}			
			close(FILE) or &dialog_status_message(1, $d->get("Settings could not be saved"));			
		}		
	}
	if ($response eq "yes" ) {
		$dialog->destroy() ;		
		Gtk2->main_quit ;
		return FALSE;
	}else {
		$dialog->destroy() ;
		return TRUE;
	}
}

#call about box
sub event_about 
{
	my ($widget, $data) = @_;
 	if($debug_cparam){
		print "\n$data was emitted by widget $widget\n";
	}

	open(GPL_HINT, "$gscrot_path/share/gscrot/resources/license/gplv3_hint") or die "ERROR--> Failed to open copyright-file!";
	my @copyright_hint = <GPL_HINT>;
	close(GPL_HINT);

	open(GPL, "$gscrot_path/share/gscrot/resources/license/gplv3") or die "ERROR--> Failed to open license-file!";
	my @copyright = <GPL>;
	close(GPL);
	
	my $all_lines = "";
	foreach my $line (@copyright){
		$all_lines = $all_lines.$line; 
	}

	my $all_hints = "";
	foreach my $hint (@copyright_hint){
		$all_hints = $all_hints.$hint; 
	}

	my $website = "http://launchpad.net/gscrot";
	my $about = Gtk2::AboutDialog->new;
	
	my $logo = Gtk2::Gdk::Pixbuf->new_from_file ("$gscrot_path/share/gscrot/resources/icons/gscrot48x48.png");	
	$about->set_logo ($logo);
	$about->set_name($gscrot_name) unless Gtk2->CHECK_VERSION (2, 12, 0);
	$about->set_program_name($gscrot_name) if Gtk2->CHECK_VERSION (2, 12, 0);
	$about->set_version($gscrot_version);
	$about->set_url_hook(\&function_gnome_open);
	$about->set_website_label($website);
	$about->set_website($website);
	$about->set_email_hook(\&function_gnome_open_mail);
	$about->set_authors("Mario Kemper <mario.kemper\@gmx.de>\n\nPlugins:\nMartin Rabeneck (cornix) <martinrabeneck\@gmx.net>\n\nubuntu-pics.de:\nRene Hennig <Rene.Hennig\@my-united.net>");
	$about->set_artists("Arne Weinberg","Pascal Grochol <pg0803\@gmail.com>");
	$about->set_translator_credits ("German: Mario Kemper <mario.kemper\@gmx.de>\nRussian: Michael Kogan (PhotonX)");	
	$about->set_copyright ($all_hints);
	$about->set_license ($all_lines);
	$about->set_comments ("Screenshot Tool");
	$about->show_all;
	$about->signal_connect('response' => \&event_handle);

}

#call context menu of tray-icon
sub event_show_icon_menu 
{
	my ($widget, $data) = @_;
	if($debug_cparam){
		print "\n$data was emitted by widget $widget\n";
	}

	#left button (mouse)
	if ($_[1]->button == 1) {
		if($window->visible){
			$window->hide;
			$is_in_tray = TRUE;
		}else{
			$window->show_all;
			$is_in_tray = FALSE;
		}		
	}   
	#right button (mouse)
	elsif ($_[1]->button == 3) {
	my $tray_menu = Gtk2::Menu->new();
	my $menuitem_select = Gtk2::ImageMenuItem->new($d->get("Capture with selection"));
	$menuitem_select->set_image(Gtk2::Image->new_from_icon_name('gtk-cut', 'menu'));
	$menuitem_select->signal_connect(activate => \&event_handle, 'tray_select');
	my $menuitem_raw = Gtk2::ImageMenuItem->new($d->get("Capture"));
	$menuitem_raw->set_image(Gtk2::Image->new_from_icon_name('gtk-fullscreen', 'menu'));
	$menuitem_raw->signal_connect(activate => \&event_handle, 'tray_raw');
	my $menuitem_web = Gtk2::ImageMenuItem->new($d->get("Capture website"));
	$menuitem_web->set_image(Gtk2::Image->new_from_file ("$gscrot_path/share/gscrot/resources/icons/web_image.png"));
	$menuitem_web->signal_connect(activate => \&event_handle, 'tray_web');
	my $menuitem_info = Gtk2::ImageMenuItem->new($d->get("Info"));
	$menuitem_info->set_image(Gtk2::Image->new_from_icon_name('gtk-about', 'menu'));
	$menuitem_info->signal_connect("activate" , \&event_about , $window) ;	
	my $menuitem_quit = Gtk2::ImageMenuItem->new($d->get("Quit"));
	$menuitem_quit->set_image(Gtk2::Image->new_from_icon_name('gtk-quit', 'menu'));
	$menuitem_quit->signal_connect("activate" , \&event_delete_window ,'menu_quit') ;

	my $separator_tray = Gtk2::SeparatorMenuItem->new();
	$separator_tray->show;
	$menuitem_select->show();
	$menuitem_raw->show();
	$menuitem_web->show();
	$menuitem_info->show();
	$menuitem_quit->show();
	$tray_menu->append($menuitem_select);
	$tray_menu->append($menuitem_raw);
	$tray_menu->append($menuitem_web);
	$tray_menu->append($separator_tray);
	$tray_menu->append($menuitem_info);
	$tray_menu->append($menuitem_quit);
	$tray_menu->popup(
		undef, # parent menu shell
		undef, # parent menu item
		undef, # menu pos func
		undef, # data
		$data->button,
		$data->time
		);
	}
	return 1;	
}


#notebook plugins - double-click-events are handled here
sub event_plugins
{
	my ($tree, $path, $column) = @_;
	
}

sub function_create_tab {
	my ($key, $is_all) = @_;

	my $scrolled_window = Gtk2::ScrolledWindow->new;
	$scrolled_window->set_policy ('automatic', 'automatic');
	$scrolled_window->set_shadow_type ('in');
	
	my $vbox_tab = Gtk2::VBox->new(FALSE, 0);
	my $hbox_tab_file = Gtk2::HBox->new(FALSE, 0);
	my $hbox_tab_actions = Gtk2::HBox->new(FALSE, 0);
	my $hbox_tab_actions2 = Gtk2::HBox->new(FALSE, 0);

	my $n_pages = 0;
	my $filename = $n_pages." ".$d->nget("screenshot during this session", "screenshots during this session", $n_pages);
	$filename = $session_screens{$key} unless $is_all;
	$n_pages = $notebook->get_n_pages() if $is_all;

	my $exists_status;
	if(&function_file_exists($filename) || $n_pages >= 1){	
		$exists_status = Gtk2::Image->new_from_icon_name ('gtk-yes', 'menu');
	}else{
		$exists_status = Gtk2::Image->new_from_icon_name ('gtk-no', 'menu');
	}

	$exists_status = Gtk2::Image->new_from_icon_name ('gtk-dnd-multiple', 'menu') if $is_all;
	
	my $filename_label = Gtk2::Label->new($filename);

	my $button_remove = Gtk2::Button->new;
	$button_remove->set_name("btn_remove");
	$button_remove->signal_connect(clicked => \&event_in_tab, 'remove'.$key);
	my $image_remove = Gtk2::Image->new_from_icon_name ('gtk-remove', 'button');
	$button_remove->set_image($image_remove);	

	my $tooltip_remove = Gtk2::Tooltips->new;
	$tooltip_remove->set_tip($button_remove,$d->get("Remove file(s) from session"));	

	my $button_delete = Gtk2::Button->new;
	$button_delete->signal_connect(clicked => \&event_in_tab, 'delete'.$key);
	my $image_delete = Gtk2::Image->new_from_icon_name ('gtk-delete', 'button');
	$button_delete->set_image($image_delete);	

	my $tooltip_delete = Gtk2::Tooltips->new;
	$tooltip_delete->set_tip($button_delete,$d->get("Delete file(s)"));
	
	my $button_clipboard = Gtk2::Button->new;
	$button_clipboard->signal_connect(clicked => \&event_in_tab, 'clipboard'.$key);
	my $image_clipboard = Gtk2::Image->new_from_icon_name ('gtk-copy', 'button');
	$button_clipboard->set_image($image_clipboard);

	my $tooltip_clipboard = Gtk2::Tooltips->new;
	$tooltip_clipboard->set_tip($button_clipboard,$d->get("Copy file(s) to clipboard"));

	my $button_reopen = Gtk2::Button->new;
	$button_reopen->signal_connect(clicked => \&event_in_tab, 'reopen'.$key);
	my $image_reopen = Gtk2::Image->new_from_icon_name ('gtk-redo-ltr', 'button');
	$button_reopen->set_image($image_reopen);	

	my $tooltip_reopen = Gtk2::Tooltips->new;
	$tooltip_reopen->set_tip($button_reopen,$d->get("Open file(s)"));

	my $button_upload = Gtk2::Button->new;
	$button_upload->signal_connect(clicked => \&event_in_tab, 'upload'.$key);
	my $image_upload = Gtk2::Image->new_from_icon_name ('gtk-go-up', 'button');
	$button_upload->set_image($image_upload);	

	my $tooltip_upload = Gtk2::Tooltips->new;
	$tooltip_upload->set_tip($button_upload,$d->get("Upload file to ubuntu-pics.de"));

	my $button_rename = Gtk2::Button->new;
	$button_rename->signal_connect(clicked => \&event_in_tab, 'rename'.$key);
	my $image_rename = Gtk2::Image->new_from_icon_name ('gtk-edit', 'button');
	$button_rename->set_image($image_rename);	

	my $tooltip_rename = Gtk2::Tooltips->new;
	$tooltip_rename->set_tip($button_rename,$d->get("Rename file"));
	
	my $button_plugin = Gtk2::Button->new;
	$button_plugin->signal_connect(clicked => \&event_in_tab, 'plugin'.$key);
	my $image_plugin = Gtk2::Image->new_from_icon_name ('gtk-execute', 'button');
	$button_plugin->set_image($image_plugin);	

	my $tooltip_plugin = Gtk2::Tooltips->new;
	$tooltip_plugin->set_tip($button_plugin,$d->get("Execute a plugin"));

	my $button_print = Gtk2::Button->new;
	$button_print->signal_connect(clicked => \&event_in_tab, 'print'.$key);
	my $image_print = Gtk2::Image->new_from_icon_name ('gtk-print', 'button');
	$button_print->set_image($image_print);	

	my $tooltip_print = Gtk2::Tooltips->new;
	$tooltip_print->set_tip($button_print,$d->get("Print file(s)"));

	#packing
	$hbox_tab_file->pack_start($exists_status, TRUE, TRUE, 1);
	$hbox_tab_file->pack_start($filename_label, TRUE, TRUE, 1);

	if($is_all){
		$hbox_tab_actions->pack_start($button_remove, TRUE, TRUE, 1);
		$hbox_tab_actions->pack_start($button_delete, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_reopen, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_print, TRUE, TRUE, 1);
	}else{
		$hbox_tab_actions->pack_start($button_remove, TRUE, TRUE, 1);
		$hbox_tab_actions->pack_start($button_delete, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_reopen, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_upload, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_print, TRUE, TRUE, 1);
		$hbox_tab_actions->pack_start($button_rename, TRUE, TRUE, 1);
		$hbox_tab_actions->pack_start($button_plugin, TRUE, TRUE, 1) if (keys(%plugins) > 0);
		$hbox_tab_actions2->pack_start($button_clipboard, TRUE, TRUE, 1);		
	}
	$vbox_tab->pack_start($hbox_tab_file, TRUE, TRUE, 1);
	$vbox_tab->pack_start($hbox_tab_actions, TRUE, TRUE, 1);
	$vbox_tab->pack_start($hbox_tab_actions2, TRUE, TRUE, 1);
	$scrolled_window->add_with_viewport($vbox_tab);

  return $scrolled_window;
}

#tab events are handled here
sub event_in_tab
{
	my ($widget, $data) = @_;
	print "\n$data was emitted by widget $widget\n" if $debug_cparam;

#single screenshots	
	my $current_file;
	if ($data =~ m/^print\[/){
		$data =~ s/^print//;
		my $current_file = &function_switch_home_in_file($session_screens{$data});
		system("gtklp $current_file &");
		&dialog_status_message(1, $session_screens{$data}." ".$d->get("will be printed"));
	}

	if ($data =~ m/^delete\[/){
		$data =~ s/^delete//;
		unlink(&function_switch_home_in_file($session_screens{$data})); #delete file
		$notebook->remove_page($notebook->get_current_page); #delete tab
		&dialog_status_message(1, $session_screens{$data}." ".$d->get("deleted"));
		delete($session_screens{$data}); # delete from hash
		
		&function_update_first_tab();
				
		$window->show_all;
	}
	
	if ($data =~ m/^remove\[/){
		$data =~ s/^remove//;
		$notebook->remove_page($notebook->get_current_page); #delete tab
		&dialog_status_message(1, $session_screens{$data}." ".$d->get("removed from session")) if defined($session_screens{$data});
		delete($session_screens{$data}); # delete from hash
		
		&function_update_first_tab();
				
		$window->show_all;
	}	

	if ($data =~ m/^reopen\[/){
		$data =~ s/^reopen//;
		my $model = $progname->get_model();
		my $progname_iter = $progname->get_active_iter();
		my $progname_value = $model->get_value($progname_iter, 2);
		unless ($progname_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No application specified to open the screenshot")); return FALSE;};
		system($progname_value." ".$session_screens{$data}." &");
		&dialog_status_message(1, $session_screens{$data}." ".$d->get("opened with")." ".$progname_value);
	}

	if ($data =~ m/^upload\[/){
		$data =~ s/^upload//;
		my %upload_response;
		%upload_response = &function_upload_ubuntu_pics(&function_switch_home_in_file($session_screens{$data}));	
		if (is_success($upload_response{'status'})){
			&dialog_upload_links($upload_response{'thumb1'}, $upload_response{'thumb2'}, $upload_response{'bbcode'}, $upload_response{'direct'}, $upload_response{'status'});				
		}else{
			&dialog_error_message($upload_response{'status'});	
		}			
		&dialog_status_message(1, $session_screens{$data}." ".$d->get("uploaded"));
	}
	
	if ($data =~ m/^rename\[/){
		$data =~ s/^rename//;
		&dialog_status_message(1, $session_screens{$data}." ".$d->get("renamed")) if &dialog_rename($session_screens{$data}, $data);
	}

	if ($data =~ m/^plugin\[/){
		$data =~ s/^plugin//;
		if (keys %plugins > 0){
			&dialog_status_message(1, $session_screens{$data}." ".$d->get("executed by plugin")) if &dialog_plugin($session_screens{$data}, $data);
		}else{
			&dialog_error_message($d->get("No plugin installed"));	
		}
	}

	if ($data =~ m/^clipboard\[/){
		$data =~ s/^clipboard//;
		my $pixbuf = Gtk2::Gdk::Pixbuf->new_from_file (&function_switch_home_in_file($session_screens{$data}) );
		$clipboard->set_image($pixbuf);
		&dialog_status_message(1, $session_screens{$data}." ".$d->get("copied to clipboard"));
	}

#all screenshots
	if ($data =~ m/^delete$/){ #tab == all
		foreach my $key(keys %session_screens){
			unlink(&function_switch_home_in_file($session_screens{$key})); #delete file		
			delete($session_screens{$key}); # delete from hash	
		}
		my $n_pages = $notebook->get_n_pages();
		while($n_pages > 1){  #delete tab all tabs
			$n_pages--;
			$notebook->remove_page($n_pages);		
		}
		&dialog_status_message(1, $d->get("All screenshots deleted"));
		&function_update_first_tab;
		$window->show_all;
	}
	
	if ($data =~ m/^remove$/){ #tab == all
		foreach my $key(keys %session_screens){	
			delete($session_screens{$key}); # delete from hash	
		}
		my $n_pages = $notebook->get_n_pages();
		while($n_pages > 1){  #delete tab all tabs
			$n_pages--;
			$notebook->remove_page($n_pages);		
		}
		&dialog_status_message(1, $d->get("All screenshots removed"));
		&function_update_first_tab;
		$window->show_all;
	}
	
	if ($data =~ m/^reopen$/){
		my $model = $progname->get_model();
		my $progname_iter = $progname->get_active_iter();
		my $progname_value = $model->get_value($progname_iter, 2);
		my $open_files;
		unless ($progname_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No application specified to open the screenshot")); return FALSE;};
		if($progname_value =~ /gimp/){
			foreach my $key(keys %session_screens){
				$open_files .= &function_switch_home_in_file($session_screens{$key})." ";
			}
			system($progname_value." ".$open_files." &");
		}else{
			foreach my $key(keys %session_screens){
				system($progname_value." ".&function_switch_home_in_file($session_screens{$key})." &");
			}			
		}
		&dialog_status_message(1, $d->get("Opened all files with")." ".$progname_value);
	}	

	if ($data =~ m/^print$/){ #tab == all
		my $print_files;		
		foreach my $key(keys %session_screens){
			$print_files .= &function_switch_home_in_file($session_screens{$key})." ";
		}
		system("gtklp $print_files &");
		&dialog_status_message(1, $d->get("Printing all screenshots"));
	}
}
####################SAVE AND REVERT################################
sub event_settings
{
	my ($widget, $data) = @_;
	print "\n$data was emitted by widget $widget\n" if $debug_cparam;

#save?
	if($data eq "menu_save"){
		if(-e "$ENV{ HOME }/.gscrot/settings.conf" && -w "$ENV{ HOME }/.gscrot/settings.conf"){
			if (&dialog_question_message($d->get("Do you want to overwrite the existing settings?"))){ #ask is settings-file exists
				&function_save_settings;
			}
		}else{
				&function_save_settings; #do it directly if not
		}
	}elsif($data eq "menu_revert"){
		if(-e "$ENV{ HOME }/.gscrot/settings.conf" && -r "$ENV{ HOME }/.gscrot/settings.conf"){
			&function_load_settings;
		}else{
			&dialog_info_message($d->get("There are no stored settings"));
		}
	}	
	
}

#save settings to file
sub function_save_settings
{
	open(FILE, ">$ENV{ HOME }/.gscrot/settings.conf") or &dialog_error_message(1, $d->get("Settings could not be saved"));	
	print FILE "FTYPE=".$combobox_type->get_active."\n";
	print FILE "QSCALE=".$scale->get_value()."\n";
	print FILE "FNAME=".$filename->get_text()."\n";
	print FILE "FOLDER=".$saveDir_button->get_filename()."\n";
	my $model = $progname->get_model();
	my $progname_iter = $progname->get_active_iter();
	my $progname_value = $model->get_value($progname_iter, 2);
	print FILE "PNAME=".$progname_value."\n";
	print FILE "PNAME_ACT=".$progname_active->get_active()."\n";
	print FILE "IM_COLORS=".$combobox_im_colors->get_active()."\n";
	print FILE "IM_COLORS_ACT=".$im_colors_active->get_active()."\n";
	print FILE "DELAY=".$delay->get_value()."\n";
	print FILE "DELAY_ACT=".$delay_active->get_active()."\n";
	print FILE "THUMB=".$thumbnail->get_value()."\n";
	print FILE "THUMB_ACT=".$thumbnail_active->get_active()."\n";
	print FILE "BORDER=".$combobox_border->get_active()."\n";
	print FILE "CLOSE_ASK=".$ask_quit_active->get_active()."\n";
	print FILE "AUTOHIDE=".$hide_active->get_active()."\n";
	print FILE "CLOSE_CLOSE=".$close_at_close_active->get_active()."\n";
	close(FILE) or &dialog_error_message(1, $d->get("Settings could not be saved"));


 	$statusbar->push (1, $d->get("Settings saved successfully"));
}

sub function_load_settings
{
	my @settings_file;
	open(FILE, "$ENV{ HOME }/.gscrot/settings.conf") or &dialog_status_message(1, $d->get("Settings could not be loaded"));	
	@settings_file = <FILE>;
	close(FILE) or &dialog_status_message(1, $d->get("Settings could not be loaded"));

	foreach (@settings_file){
		chomp;
		if($_ =~ m/^FTYPE=/){
			$_ =~ s/FTYPE=//;
			$combobox_type->set_active($_);
		}elsif($_ =~ m/^QSCALE=/){
			$_ =~ s/QSCALE=//;
			$scale->set_value($_);
		}elsif($_ =~ m/^FNAME=/){
			$_ =~ s/FNAME=//;
			$filename->set_text($_);
		}elsif($_ =~ m/^FOLDER=/){
			$_ =~ s/FOLDER=//;			
			$saveDir_button->set_current_folder($_);
		}elsif($_ =~ m/^PNAME=/){
			$_ =~ s/PNAME=//;
			my $model = $progname->get_model;
			$model->foreach (\&function_iter_programs, $_);
		}elsif($_ =~ m/^PNAME_ACT=/){
			$_ =~ s/PNAME_ACT=//;
			$progname_active->set_active($_);
		}elsif($_ =~ m/^IM_COLORS_ACT=/){
			$_ =~ s/IM_COLORS_ACT=//;
			$im_colors_active->set_active($_);
		}elsif($_ =~ m/^IM_COLORS=/){
			$_ =~ s/IM_COLORS=//;
			$combobox_im_colors->set_active($_);
		}elsif($_ =~ m/^PNAME_ACT=/){
			$_ =~ s/IM_LABEL_ACT=//;
			$progname_active->set_active($_);
		}elsif($_ =~ m/^DELAY=/){
			$_ =~ s/DELAY=//;
			$delay->set_value($_);
		}elsif($_ =~ m/^DELAY_ACT=/){
			$_ =~ s/DELAY_ACT=//;
			$delay_active->set_active($_);
		}elsif($_ =~ m/^THUMB=/){
			$_ =~ s/THUMB=//;
			$thumbnail->set_value($_);
		}elsif($_ =~ m/^THUMB_ACT=/){
			$_ =~ s/THUMB_ACT=//;
			$thumbnail_active->set_active($_);
		}elsif($_ =~ m/^BORDER=/){
			$_ =~ s/BORDER=//;
			$combobox_border->set_active($_);
		}elsif($_ =~ m/^CLOSE_ASK=/){
			$_ =~ s/CLOSE_ASK=//;
			$ask_quit_active->set_active($_);
		}elsif($_ =~ m/^AUTOHIDE=/){
			$_ =~ s/AUTOHIDE=//;
			$hide_active->set_active($_);
		}elsif($_ =~ m/^CLOSE_CLOSE=/){
			$_ =~ s/CLOSE_CLOSE=//;
			$close_at_close_active->set_active($_);
		}

	}

	&dialog_status_message(1, $d->get("Settings loaded successfully"));
}

####################SAVE AND REVERT################################


#################### MY FUNCTIONS  ################################
sub function_file_exists
{
	my ($filename) = @_;
	$filename = &function_switch_home_in_file($filename); 
	return TRUE if (-e $filename);
	return FALSE;
}

sub function_switch_home_in_file
{
	my ($filename) = @_ ;
	$filename =~ s/^~/$ENV{ HOME }/; #switch ~ in path to /home/username
	return $filename; 
}
sub dialog_status_message
{
	my ($index, $status_text) = @_;
	$statusbar->push ($index, $status_text);
}

sub dialog_error_message
{
	my ($dialog_error_message) = @_;
	my $error_dialog = Gtk2::MessageDialog->new ($window,
	[qw/modal destroy-with-parent/],
	'error' ,
	'ok' ,
	$dialog_error_message) ;
	my $error_response = $error_dialog->run ;	
	$error_dialog->destroy() if($error_response eq "ok");
	return TRUE;
}

#info messages
sub dialog_question_message
{
	my ($dialog_question_message) = @_;
	my $question_dialog = Gtk2::MessageDialog->new ($window,
	[qw/modal destroy-with-parent/],
	'question' ,
	'yes_no' ,
	$dialog_question_message ) ;
	my $question_response = $question_dialog->run ;
	if ($question_response eq "yes" ) {
		$question_dialog->destroy() ;		
		return TRUE;
	}else {
		$question_dialog->destroy() ;
		return FALSE;
	}
}

sub dialog_rename
{
	my ($dialog_rename_text, $data) = @_;
	my $dialog_header = $d->get("Rename file");
 	my $input_dialog = Gtk2::Dialog->new ($dialog_header,
        						$window,
                              	[qw/modal destroy-with-parent/],
                              	'gtk-ok'     => 'accept',
                              	'gtk-cancel' => 'reject');

	$input_dialog->set_default_response ('accept');

	my $new_filename = Gtk2::Entry->new();
	$dialog_rename_text =~ /.*\/(.*)\./;
	my $old_file_name = $1;
	my $old_file_name_full = $dialog_rename_text;
	$new_filename->set_text($old_file_name);
    $input_dialog->vbox->add ($new_filename);
    $input_dialog->show_all;

	my $input_response = $input_dialog->run ;    
	if ($input_response eq "accept" ) {
		my $new_name = $new_filename->get_text;
		$dialog_rename_text =~ s/$old_file_name/$new_name/;
		unless($old_file_name_full eq $dialog_rename_text){ #filenames eq? -> nothing to do here
			unless(&function_file_exists($dialog_rename_text)){
				rename(&function_switch_home_in_file($old_file_name_full), &function_switch_home_in_file($dialog_rename_text));
			}else{
				&dialog_error_message($d->get("File already exists,\nplease choose an alternative filename!"));	
				$input_dialog->destroy();		
				return FALSE;			
			}
			$session_screens{$data} = $dialog_rename_text;
			&function_update_tab($data);
		}
		$input_dialog->destroy();		
		return TRUE;
	}else {
		$input_dialog->destroy() ;
		return FALSE;
	}

}

sub dialog_plugin
{
	my ($dialog_plugin_text, $data) = @_;
	my $dialog_header = $d->get("Choose a plugin");
 	my $plugin_dialog = Gtk2::Dialog->new ($dialog_header,
        						$window,
                              	[qw/modal destroy-with-parent/],
                              	'gtk-ok'     => 'accept',
                              	'gtk-cancel' => 'reject');

	$plugin_dialog->set_default_response ('accept');

	#store the filetype of the current screenshot for further processing
	$dialog_plugin_text =~ /.*\.(.*)$/;
	my $filetype = $1;

	my $model = Gtk2::ListStore->new ('Gtk2::Gdk::Pixbuf', 'Glib::String', 'Glib::String');
	foreach (keys %plugins){
		next unless $plugins{$_}->{'ext'} =~ /$filetype/;
		if($plugins{$_}->{'binary'} ne ""){
			my $pixbuf; 
			if (-f $plugins{$_}->{'pixmap'}){
				$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ($plugins{$_}->{'pixmap'}, 20, 20);
			}else{
				$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/executable.svg", 20, 20);
			}
			#get translated plugin-name
			$plugins{$_}->{'name'} = `$plugins{$_}->{'binary'} name`;
			utf8::decode $plugins{$_}->{'name'};
			chomp($plugins{$_}->{'name'});
			$model->set ($model->append, 0, $pixbuf , 1, $plugins{$_}->{'name'}, 2, $plugins{$_}->{'binary'});				
		}else{
			print "WARNING: Program $_ is not configured properly, ignoring\n";	
		}	
	}
	my $plugin = Gtk2::ComboBox->new ($model);
	my $renderer_pix = Gtk2::CellRendererPixbuf->new;
	$plugin->pack_start ($renderer_pix, FALSE);
	$plugin->add_attribute ($renderer_pix, pixbuf => 0);
	my $renderer_text = Gtk2::CellRendererText->new;
	$plugin->pack_start ($renderer_text, FALSE);
	$plugin->add_attribute ($renderer_text, text => 1);
	$plugin->set_active(0);

    $plugin_dialog->vbox->add ($plugin);
    $plugin_dialog->show_all;

	my $plugin_response = $plugin_dialog->run ;    
	if ($plugin_response eq "accept" ) {
		$dialog_plugin_text = &function_switch_home_in_file($dialog_plugin_text);
		my $model = $plugin->get_model();
		my $plugin_iter = $plugin->get_active_iter();
		my $plugin_value = $model->get_value($plugin_iter, 2);
		my $plugin_name = $model->get_value($plugin_iter, 1);
		unless ($plugin_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No plugin specified")); return FALSE;};
		my $width = &function_imagemagick_perform("get_width", $dialog_plugin_text, 0, "");
		my $height = &function_imagemagick_perform("get_height", $dialog_plugin_text, 0, "");

		print "$plugin_value $dialog_plugin_text $width $height $filetype submitted to plugin\n" if $debug_cparam;
		if (system("$plugin_value $dialog_plugin_text $width $height $filetype") == 0){
			&dialog_info_message($d->get("Successfully executed plugin").": ".$plugin_name);
		}else{
			&dialog_error_message($d->get("Could not execute plugin").": ".$plugin_name);
		}
		$plugin_dialog->destroy();		
		return TRUE;
	}else {
		$plugin_dialog->destroy() ;
		return FALSE;
	}

}

sub dialog_website
{
	my $dialog_header = $d->get("URL to capture");
 	my $website_dialog = Gtk2::Dialog->new ($dialog_header,
        						$window,
                              	[qw/modal destroy-with-parent/],
                              	'gtk-ok'     => 'accept',
                              	'gtk-cancel' => 'reject');

	$website_dialog->set_default_response ('accept');

	my $website = Gtk2::Entry->new();
	$website->set_text("http://");
    $website_dialog->vbox->add ($website);
    $website_dialog->show_all;

	my $website_response = $website_dialog->run ;    
	if ($website_response eq "accept" ) {

		$website_dialog->destroy();		
		return $website->get_text;
	}else {
		$website_dialog->destroy() ;
		return FALSE;
	}

}

sub dialog_upload_links
{
	my ($thumb1, $thumb2, $bbcode, $direct, $status) = @_;
	my $dialog_header = $d->get("Upload");
 	my $upload_dialog = Gtk2::Dialog->new ($dialog_header,
        						$window,
                              	[qw/modal destroy-with-parent/],
                              	'gtk-ok'     => 'accept');

	$upload_dialog->set_default_response ('accept');
	$upload_dialog->set_size_request(300, 300);

	my $upload_hbox = Gtk2::HBox->new(FALSE, 0);
	my $upload_vbox = Gtk2::VBox->new(FALSE, 0);
	
	my $label_status = Gtk2::Label->new();
	$label_status->set_text($d->get("Upload status:")." ".status_message($status));	
	my $image_status;
	if (is_success($status)){
		$image_status = Gtk2::Image->new_from_icon_name ('gtk-yes', 'menu');
	}else{
		$image_status = Gtk2::Image->new_from_icon_name ('gtk-no', 'menu');
	}
	$upload_hbox->pack_start($image_status, TRUE, TRUE, 0);
    $upload_hbox->pack_start($label_status, TRUE, TRUE, 0);
		
	my $entry_thumb1 = Gtk2::Entry->new();
	my $entry_thumb2 = Gtk2::Entry->new();
	my $entry_bbcode = Gtk2::Entry->new();
	my $entry_direct = Gtk2::Entry->new();

	my $label_thumb1 = Gtk2::Label->new();
	my $label_thumb2 = Gtk2::Label->new();
	my $label_bbcode = Gtk2::Label->new();
	my $label_direct = Gtk2::Label->new();

	$label_thumb1->set_text($d->get("Thumbnail for websites (with border)"));
	$label_thumb2->set_text($d->get("Thumbnail for websites (without border)"));
	$label_bbcode->set_text($d->get("Thumbnail for forums"));
	$label_direct->set_text($d->get("Direct link"));

	$entry_thumb1->set_text($thumb1);
	$entry_thumb2->set_text($thumb2);
	$entry_bbcode->set_text($bbcode);
	$entry_direct->set_text($direct);

	$upload_vbox->pack_start($upload_hbox, TRUE, TRUE, 10);
	$upload_vbox->pack_start($label_thumb1, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_thumb1, TRUE, TRUE, 2);    
	$upload_vbox->pack_start($label_thumb2, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_thumb2, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_bbcode, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_bbcode, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_direct, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_direct, TRUE, TRUE, 2);
	    
    $upload_dialog->vbox->add ($upload_vbox);	
 
    $upload_dialog->show_all;

	my $upload_response = $upload_dialog->run ;    
	if ($upload_response eq "accept" ) {
		$upload_dialog->destroy();		
		return TRUE;
	}else {
		$upload_dialog->destroy() ;
		return FALSE;
	}

}

sub dialog_info_message
{
	my ($dialog_info_message) = @_;
	my $info_dialog = Gtk2::MessageDialog->new ($window,
	[qw/modal destroy-with-parent/],
	'info' ,
	'ok' ,
	$dialog_info_message ) ;
	my $info_response = $info_dialog->run ;	
	$info_dialog->destroy() if($info_response eq "ok");
	return TRUE;
}

sub function_usage
{
	print "gscrot.pl [options]\n";
	print "Available options:\n --min_at_startup - starts gscrot minimized to tray\n --beeper_off - turns audible feedback off\n --debug - prints a lot of debugging information to STDOUT\n";
	print " --help - displays this help\n";
}

sub function_update_first_tab
{
	#write new number of screenshot to first label
	my $current_page = $notebook->get_nth_page(0);
	my @widget_list = $current_page->get_children->get_children->get_children; #scrolledwindow, viewport, vbox
	my @hbox_content;
	foreach my $hbox_widget(@widget_list){
		push(@hbox_content, $hbox_widget->get_children) ;
	}
	my $n_pages = keys(%session_screens); 
	foreach (@hbox_content){
		if( $_ =~ /^Gtk2::Label/ ){
			$_->set_text($n_pages." ".$d->nget("screenshot during this session", "screenshots during this session", $n_pages));
		}elsif( $_ =~ /^Gtk2::Button/ && $n_pages == 0){
			$_->set_sensitive(FALSE);	
		}elsif( $_ =~ /^Gtk2::Button/ && $n_pages > 0){
			$_->set_sensitive(TRUE);	
		}
	}		
}

sub function_update_tab
{
	my ($data) = @_;
	$data =~ /\[(.*)\]/;
	my $number_of_page = $1;
	my $current_page = $notebook->get_nth_page($number_of_page);
	my @widget_list = $current_page->get_children->get_children->get_children; #scrolledwindow, viewport, vbox
	my @hbox_content;
	foreach my $hbox_widget(@widget_list){
		push(@hbox_content, $hbox_widget->get_children) ;
	}
	my $n_pages = keys(%session_screens); 
	foreach (@hbox_content){
		if( $_ =~ /^Gtk2::Label/ ){
			$_->set_text($session_screens{$data});
			last;
		}
	}		
}

sub function_get_latest_tab_key
{
	my $max_key = 0;
	foreach my $key(keys %session_screens){
		$key =~ /\[(.*)\]/;
		$max_key = $1 if($1 > $max_key);
	}
	return $max_key+1;
}

sub function_gnome_open
{
	my ($dialog, $link, $user_data) = @_;
	system("gnome-open $link");
}

sub function_gnome_open_mail
{
	my ($dialog, $mail, $user_data) = @_;
	system("gnome-open mailto:$mail");
}

sub function_imagemagick_perform
{
	my ($function, $file, $data, $type) = @_;
	my $image=Image::Magick->new;
	$file = &function_switch_home_in_file($file);
	$image->ReadImage($file);
	
	if($function eq "reduce_colors"){

		$data =~ /.*\(([0-9]*).*\)/;
		$image->Quantize(colors=>2**$1);
		if($type eq 'png'){
			$image->WriteImage(filename=>$file, depth=>8, quality=>95);
		}else{
			$image->WriteImage(filename=>$file, depth=>8);
		}	
	}elsif($function eq "get_width"){
		return $image->Get('columns');	
	}elsif($function eq "get_height"){
		return $image->Get('rows');	
	}elsif($function eq "resize"){
		$data =~ /(.*)x(.*)/;
		$image->Resize(width=>$1, height=>$2);
		if($type eq 'png'){
			$image->WriteImage(filename=>$file, depth=>8, quality=>95);
		}else{
			$image->WriteImage(filename=>$file, depth=>8);
		}	
	}
}


sub function_check_installed_programs
{
	print "\nINFO: checking installed applications...\n";	
	
	foreach (keys %gm_programs){
		if($gm_programs{$_}->{'binary'} ne "" && $gm_programs{$_}->{'name'} ne ""){
			unless (-e $gm_programs{$_}->{'binary'}){
				print " Could not detect binary for program $_, ignoring\n";	
				delete $gm_programs{$_};
				next;
			}
			print "$gm_programs{$_}->{'name'} - $gm_programs{$_}->{'binary'}\n";					
		}else{
			print "WARNING: Program $_ is not configured properly, ignoring\n";	
		}	
	}

}

sub function_check_installed_plugins
{
	print "\nINFO: checking installed plugins...\n";	
	
	foreach (keys %plugins){
		if($plugins{$_}->{'binary'} ne ""){
			unless (-e $plugins{$_}->{'binary'}){
				print " Could not detect binary for program $_, ignoring\n";	
				delete $plugins{$_};
				next;
			}
			$plugins{$_}->{'name'} = `$plugins{$_}->{'binary'} name`;
			utf8::decode $plugins{$_}->{'name'};
			chomp($plugins{$_}->{'name'});
			print "$plugins{$_}->{'name'} - $plugins{$_}->{'binary'}\n";					
		}else{
			print "WARNING: Plugin $_ is not configured properly, ignoring\n";	
		}	
	}

}

sub function_iter_programs
{
	my ($model, $path, $iter, $search_for) = @_;
	my $progname_value = $model->get_value($iter, 2);
	return FALSE if $search_for ne $progname_value;
	$progname->set_active_iter($iter);
	return TRUE;
}

sub function_upload_ubuntu_pics
{
	my ($upload_filename) = @_;

	my %links; #returned links will be stored here

	my $filesize = -s $upload_filename;
	if($filesize > 2048000){
		$links{'status'} = "Filesize exceeded - maximum 2000 Kb\nUpload aborted";
		return %links;			
	} 
	
	my $mech = WWW::Mechanize->new();

	$mech->get("http://www.ubuntu-pics.de/easy.html");

	$mech->submit_form(
		form_name 	=> 'upload_bild',
		fields      => {
			"datei[]"    => $upload_filename,
			}
		);
		
	my $http_status = $mech->status();

	if (is_success($http_status)){
		my $html_file = $mech->content;

		$html_file =~ /id="thumb1" value='(.*)' onclick/g;
		$links{'thumb1'} = &function_switch_html_entities($1);

		$html_file =~ /id="thumb2" value='(.*)' onclick/g;
		$links{'thumb2'} = &function_switch_html_entities($1);

		$html_file =~ /id="bbcode" value='(.*)' onclick/g;
		$links{'bbcode'} = &function_switch_html_entities($1);
		
		$html_file =~ /id="direct" value='(.*)' onclick/g;
		$links{'direct'} = &function_switch_html_entities($1);

		if ($debug_cparam){
			print "The following links were returned by http://www.ubuntu-pics.de:\n";
			print "Thumbnail for websites (with Border)\n$links{'thumb1'}\n";
			print "Thumbnail for websites (without Border)\n$links{'thumb2'}\n";
			print "Thumbnail for forums \n$links{'bbcode'}\n";
			print "Direct link \n$links{'direct'}\n";
		}
		
		$links{'status'} = $http_status;
		return %links;
		
	}else{
		$links{'status'} = $http_status;
		return %links;	
	}

}

sub function_switch_html_entities
{
	my ($code) = @_;
	$code =~ s/&amp;/\&/g;
	$code =~ s/&lt;/</g;
	$code =~ s/&gt;/>/g;
	$code =~ s/&quot;/\"/g;
	return $code;		
}
#################### MY FUNCTIONS  ################################

