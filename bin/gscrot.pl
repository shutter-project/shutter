#! /usr/bin/perl

#Copyright (C) Mario Kemper 2008 <mario.kemper@googlemail.com> Mi, 09 Apr 2008 22:58:09 +0200 

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
use HTTP::Status;
use XML::Simple;
use Data::Dumper;
use Gnome2;
use Gnome2::Wnck;
use Gnome2::GConf;

function_die_with_action("initializing GNOME VFS") unless (Gnome2::VFS -> init());

#version info
my $gscrot_branch = "Rev.140";
my $ppa_version = "ppa4";
my $gscrot_name = "GScrot";
my $gscrot_version = "v0.50";
my $gscrot_version_detailed = "$gscrot_branch - $ppa_version";
my $gscrot_path = "";
#command line parameter
my $debug_cparam = FALSE;
my $min_cparam = FALSE;
my $boff_cparam = FALSE;
my @args = @ARGV;
my $start_with = undef;

&function_init();

setlocale(LC_MESSAGES,"");
my $d = Locale::gettext->domain("gscrot");
$d->dir("$gscrot_path/share/locale");

#custom modules load at runtime
require lib;
import lib "$gscrot_path/share/gscrot/resources/modules";
require GScrot::ImageBanana;
import GScrot::ImageBanana;
require GScrot::UbuntuPics;
import GScrot::UbuntuPics;
require GScrot::Draw;
import GScrot::Draw;

my %gm_programs; #hash to store program infos
&function_check_installed_programs if keys(%gm_programs) > 0;
my %plugins; #hash to store plugin infos
&function_check_installed_plugins if keys(%plugins) > 0;
my %accounts; #hash to account infos
my %settings; #hash to store settings

&function_load_accounts();

my $is_in_tray = FALSE;

#signal-handler
$SIG{USR1} = sub {&event_take_screenshot('global_keybinding', 'raw')};
$SIG{USR2} = sub {&event_take_screenshot('global_keybinding', 'select')};

#main window
my $window = Gtk2::Window->new('toplevel');
$window->set_title($gscrot_name." ".$gscrot_version);
$window->set_default_icon_from_file ("$gscrot_path/share/gscrot/resources/icons/gscrot24x24.png");
$window->signal_connect('delete-event' => \&event_delete_window);
$window->set_border_width(0);
$window->set_resizable(0);
$window->set_position('center');

#hash of screenshots during session	
my %session_screens;
my %session_start_screen;
my $notebook = Gtk2::Notebook->new;
$notebook->set(homogeneous => 1);

#create first page etc.
&function_create_session_notebook;

#arrange settings in notebook
my $notebook_settings = Gtk2::Notebook->new;

my $notebook_sizegroup = Gtk2::SizeGroup->new ('both');
$notebook_sizegroup->add_widget($notebook);
$notebook_sizegroup->add_widget($notebook_settings);

#Clipboard
my $clipboard = Gtk2::Clipboard->get(Gtk2::Gdk->SELECTION_CLIPBOARD);

my $accel_group = Gtk2::AccelGroup->new;
$window->add_accel_group($accel_group);

my $statusbar = Gtk2::Statusbar->new;

my $vbox = Gtk2::VBox->new(FALSE, 0);
my $vbox_inner1 = Gtk2::VBox->new(FALSE, 10);
my $vbox_inner2 = Gtk2::VBox->new(FALSE, 10);
my $vbox_inner3 = Gtk2::VBox->new(FALSE, 10);
my $vbox_basic = Gtk2::VBox->new(FALSE, 10);
my $vbox_extras = Gtk2::VBox->new(FALSE, 10);
my $vbox_behavior = Gtk2::VBox->new(FALSE, 10);
my $vbox_plugins = Gtk2::VBox->new(FALSE, 10);
my $vbox_accounts = Gtk2::VBox->new(FALSE, 10);
my $file_vbox = Gtk2::VBox->new(FALSE, 0);
my $save_vbox = Gtk2::VBox->new(FALSE, 0);
my $behavior_vbox = Gtk2::VBox->new(FALSE, 0);
my $keybinding_vbox = Gtk2::VBox->new(FALSE, 0);
my $actions_vbox = Gtk2::VBox->new(FALSE, 0);
my $capture_vbox = Gtk2::VBox->new(FALSE, 0);
my $effects_vbox = Gtk2::VBox->new(FALSE, 0);
my $accounts_vbox = Gtk2::VBox->new(FALSE, 0);

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
my $key_box = Gtk2::HBox->new(TRUE, 0);
my $key_box2 = Gtk2::HBox->new(FALSE, 0);
my $key_sel_box = Gtk2::HBox->new(TRUE, 0);
my $key_sel_box2 = Gtk2::HBox->new(FALSE, 0);
my $border_box = Gtk2::HBox->new(TRUE, 0);

$window->add($vbox);

#############MENU###################
my $menubar = Gtk2::MenuBar->new() ;

my $menu1= Gtk2::Menu->new() ;

my $menuitem_file = Gtk2::MenuItem->new_with_mnemonic($d->get("_File")) ;

my $menuitem_open = Gtk2::ImageMenuItem->new($d->get("Open")) ;
$menuitem_open->set_image(Gtk2::Image->new_from_icon_name('gtk-open', 'menu'));
$menuitem_open->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ O }, qw/control-mask/, qw/visible/);
$menu1->append($menuitem_open) ;
$menuitem_open->signal_connect("activate" , \&event_settings , 'menu_open') ;

$menu1->append(Gtk2::SeparatorMenuItem->new);

my $menuitem_revert = Gtk2::ImageMenuItem->new($d->get("Revert Settings")) ;
$menuitem_revert->set_image(Gtk2::Image->new_from_icon_name('gtk-revert-to-saved-ltr', 'menu'));
$menuitem_revert->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ Z }, qw/control-mask/, qw/visible/);
$menu1->append($menuitem_revert) ;
$menuitem_revert->signal_connect("activate" , \&event_settings , 'menu_revert') ;

my $menuitem_save = Gtk2::ImageMenuItem->new($d->get("Save Settings")) ;
$menuitem_save->set_image(Gtk2::Image->new_from_icon_name('gtk-save', 'menu'));
$menuitem_save->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ S }, qw/control-mask/, qw/visible/);
$menu1->append($menuitem_save) ;
$menuitem_save->signal_connect("activate" , \&event_settings , 'menu_save') ;

$menu1->append(Gtk2::SeparatorMenuItem->new);

my $menuitem_quit = Gtk2::ImageMenuItem->new($d->get("Quit")) ;
$menuitem_quit->set_image(Gtk2::Image->new_from_icon_name('gtk-quit', 'menu'));
$menuitem_quit->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ Q }, qw/control-mask/, qw/visible/);
$menu1->append($menuitem_quit) ;
$menuitem_quit->signal_connect("activate" , \&event_delete_window , 'menu_quit') ;

$menuitem_file->set_submenu($menu1);
$menubar->append($menuitem_file) ;


my $menu2 = Gtk2::Menu->new() ;

my $menuitem_selection = Gtk2::ImageMenuItem->new($d->get("Selection"));
$menuitem_selection->set_image(Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/selection.svg", Gtk2::IconSize->lookup ('menu'))));
$menuitem_selection->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ S }, qw/mod1-mask/, qw/visible/);
$menu2->append($menuitem_selection) ;
$menuitem_selection->signal_connect("activate" , \&event_take_screenshot, 'select') ;

my $menuitem_raw = Gtk2::ImageMenuItem->new($d->get("Fullscreen"));
$menuitem_raw->set_image(Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/fullscreen.svg", Gtk2::IconSize->lookup ('menu'))));
$menuitem_raw->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ F }, qw/mod1-mask/, qw/visible/);
$menu2->append($menuitem_raw) ;
$menuitem_raw->signal_connect("activate" , \&event_take_screenshot, 'raw') ;

my $menuitem_window = Gtk2::ImageMenuItem->new($d->get("Window"));
$menuitem_window->set_image(Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/sel_window.svg", Gtk2::IconSize->lookup ('menu'))));
$menuitem_window->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ W }, qw/mod1-mask/, qw/visible/);
$menu2->append($menuitem_window) ;
$menuitem_window->signal_connect("activate" , \&event_take_screenshot, 'window') ;

my $menuitem_web = Gtk2::ImageMenuItem->new($d->get("Web"));
$menuitem_web->set_image(Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/web_image.svg", Gtk2::IconSize->lookup ('menu'))));
$menuitem_web->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ W }, qw/shift-mask/, qw/visible/);
$menu2->append($menuitem_web) ;
$menuitem_web->signal_connect("activate" , \&event_take_screenshot, 'web') ;

my $menuitem_action = Gtk2::MenuItem->new_with_mnemonic($d->get("_Actions")) ;

$menuitem_action->set_submenu($menu2) ;
$menubar->append($menuitem_action) ; 

my $menu3 = Gtk2::Menu->new() ;

my $menuitem_question = Gtk2::ImageMenuItem->new($d->get("Ask a question"));
$menuitem_question->set_image(Gtk2::Image->new_from_pixbuf(Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/help.svg", Gtk2::IconSize->lookup ('menu'))));
$menuitem_question->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ A }, qw/control-mask/, qw/visible/);
$menu3->append($menuitem_question) ;
$menuitem_question->signal_connect("activate" , \&event_question, $window) ;

my $menuitem_bug = Gtk2::ImageMenuItem->new($d->get("Report a bug"));
$menuitem_bug->set_image(Gtk2::Image->new_from_pixbuf(Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/aiutare.svg", Gtk2::IconSize->lookup ('menu'))));
$menuitem_bug->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ B }, qw/control-mask/, qw/visible/);
$menu3->append($menuitem_bug) ;
$menuitem_bug->signal_connect("activate" , \&event_bug, $window) ;

my $menuitem_translate = Gtk2::ImageMenuItem->new($d->get("Add a translation"));
$menuitem_translate->set_image(Gtk2::Image->new_from_pixbuf(Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/translate.svg", Gtk2::IconSize->lookup ('menu'))));
$menuitem_translate->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ T }, qw/control-mask/, qw/visible/);
$menu3->append($menuitem_translate) ;
$menuitem_translate->signal_connect("activate" , \&event_translate, $window) ;

$menu3->append(Gtk2::SeparatorMenuItem->new);

my $menuitem_about = Gtk2::ImageMenuItem->new($d->get("Info")) ;
$menuitem_about->set_image(Gtk2::Image->new_from_icon_name('gtk-about', 'menu'));
$menuitem_about->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ I }, qw/control-mask/, qw/visible/);
$menu3->append($menuitem_about) ;
$menuitem_about->signal_connect("activate" , \&event_about, $window) ;

my $menuitem_help = Gtk2::MenuItem->new_with_mnemonic($d->get("_Help")) ;

$menuitem_help->set_submenu($menu3) ;
$menubar->append($menuitem_help) ; 

$vbox->pack_start($menubar, FALSE, TRUE, 0);
#############MENU###################

#############BUTTON_SELECT###################
my $button_select = Gtk2::Button->new($d->get("Selection"));
$button_select->signal_connect(clicked => \&event_take_screenshot, 'select');
$button_select->set_relief('none'); 
$button_select->set_image_position('top');

my $image_select = Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/selection.svg", Gtk2::IconSize->lookup ('large-toolbar')));
$button_select->set_image($image_select);

my $tooltip_select = Gtk2::Tooltips->new;
$tooltip_select->set_tip($button_select,$d->get("Draw a rectangular capture area with your mouse\nto select a specified screen area"));

#############BUTTON_SELECT###################

#############BUTTON_RAW######################
my $button_raw = Gtk2::Button->new($d->get("Fullscreen"));
$button_raw->signal_connect(clicked => \&event_take_screenshot, 'raw');
$button_raw->set_image_position('top');
$button_raw->set_relief('none'); 

my $image_raw = Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/fullscreen.svg", Gtk2::IconSize->lookup ('large-toolbar')));
$button_raw->set_image($image_raw);

my $tooltip_raw = Gtk2::Tooltips->new;
$tooltip_raw->set_tip($button_raw,$d->get("Take a screenshot of your whole desktop"));

#############BUTTON_RAW######################

#############BUTTON_WINDOW######################
my $button_window = Gtk2::Button->new($d->get("Window"));
$button_window->signal_connect(clicked => \&event_take_screenshot, 'window');
$button_window->set_relief('none'); 
$button_window->set_image_position('top');

my $image_window = Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/sel_window.svg", Gtk2::IconSize->lookup ('large-toolbar')));
$button_window->set_image($image_window);

my $tooltip_window = Gtk2::Tooltips->new;
$tooltip_window->set_tip($button_window,$d->get("Take a screenshot of a specific window"));

#############BUTTON_WINDOW######################

#############BUTTON_WEB######################
my $button_web = Gtk2::Button->new($d->get("Web"));
$button_web->signal_connect(clicked => \&event_take_screenshot, 'web');
$button_web->set_relief('none'); 
$button_web->set_image_position('top');

my $image_web = Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/web_image.svg", Gtk2::IconSize->lookup ('large-toolbar')));
$button_web->set_image($image_web);

my $tooltip_web = Gtk2::Tooltips->new;
$tooltip_web->set_tip($button_web,$d->get("Take a screenshot of a website"));

#############BUTTON_WEB######################

#create the toolbar
my $toolbar = Gtk2::Toolbar->new;
$toolbar->set_show_arrow(1);
my $toolitem_select = Gtk2::ToolItem->new;
$toolitem_select->set_expand(1);
$toolitem_select->set_homogeneous(1);
my $toolitem_raw = Gtk2::ToolItem->new;
$toolitem_raw->set_expand(1);
$toolitem_raw->set_homogeneous(1);
my $toolitem_window = Gtk2::ToolItem->new;
$toolitem_window->set_expand(1);
$toolitem_window->set_homogeneous(1);
my $toolitem_web = Gtk2::ToolItem->new;
$toolitem_web->set_expand(1);
$toolitem_web->set_homogeneous(1);

$toolitem_select->add($button_select);
$toolbar->insert ($toolitem_select, 0);
$toolitem_raw->add($button_raw);
$toolbar->insert ($toolitem_raw, 1);
$toolitem_window->add($button_window);
$toolbar->insert ($toolitem_window, 2);
$toolitem_web->add($button_web);
$toolbar->insert ($toolitem_web, 3);

$toolbar->set_size_request(400,-1);  
#a detachable toolbar
my $handlebox = Gtk2::HandleBox->new;
$handlebox->add($toolbar); 
  
$vbox->pack_start($handlebox, FALSE, TRUE, 0);

#############TRAYICON######################
my $icon = Gtk2::Image->new_from_file("$gscrot_path/share/gscrot/resources/icons/gscrot24x24.png");
my $eventbox = Gtk2::EventBox->new;
$eventbox->add($icon);
my $tray = Gtk2::TrayIcon->new('gscrot TrayIcon');
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

my $keybinding_frame_label = Gtk2::Label->new;
$keybinding_frame_label->set_markup($d->get("Gnome-Keybinding"));
my $keybinding_frame = Gtk2::Frame->new();
$keybinding_frame->set_label_widget($keybinding_frame_label);

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
$scale->signal_connect('value-changed' => \&event_value_changed, 'quality_changed');
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
$delay->signal_connect('value-changed' => \&event_value_changed, 'delay_changed');
$delay->set_value_pos('right');
$delay->set_value(0);

my $delay_active = Gtk2::CheckButton->new;
$delay_active->signal_connect('toggled' => \&event_value_changed, 'delay_toggled');
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
$thumbnail->signal_connect('value-changed' => \&event_value_changed, 'thumbnail_changed');
$thumbnail->set_value_pos('right');
$thumbnail->set_value(50);

my $thumbnail_active = Gtk2::CheckButton->new;
$thumbnail_active->signal_connect('toggled' => \&event_value_changed, 'thumbnail_toggled');
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
$filename->set_text("screenshot\%NN");

my $filename_label = Gtk2::Label->new;
$filename_label->set_text($d->get("Filename"));

my $tooltip_filename = Gtk2::Tooltips->new;
$tooltip_filename->set_tip($filename,$d->get("There are several wild-cards available, like\n%Y = year\n%m = month\n%d = day\n%T = time\n\$w = width\n\$h = height\n%NN = counter"));
$tooltip_filename->set_tip($filename_label,$d->get("There are several wild-cards available, like\n%Y = year\n%m = month\n%d = day\n%T = time\n\$w = width\n\$h = height\n%NN = counter"));

$filename_box->pack_start($filename_label, FALSE, TRUE, 10);
$filename_box->pack_start($filename, TRUE, TRUE, 10);
#end - filename

#type
my $combobox_type = Gtk2::ComboBox->new_text;
$combobox_type->insert_text (0, "jpeg");
$combobox_type->insert_text (1, "png");
$combobox_type->signal_connect('changed' => \&event_value_changed, 'type_changed');
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
my $capture_key = Gtk2::Entry->new;
$capture_key->set_text("Print");

my $capture_label = Gtk2::Label->new;
$capture_label->set_text($d->get("Capture"));

my $tooltip_capture = Gtk2::Tooltips->new;
$tooltip_capture->set_tip($capture_key,$d->get("Configure global keybinding for capture\nThe format looks like \"<Control>a\" or \"<Shift><Alt>F1\". The parser is fairly liberal and allows lower or upper case, and also abbreviations such as \"<Ctl>\" and \"<Ctrl>\". If you set the option to the special string \"disabled\", then there will be no keybinding for this action. "));
$tooltip_capture->set_tip($capture_label,$d->get("Configure global keybinding for capture\nThe format looks like \"<Control>a\" or \"<Shift><Alt>F1\". The parser is fairly liberal and allows lower or upper case, and also abbreviations such as \"<Ctl>\" and \"<Ctrl>\". If you set the option to the special string \"disabled\", then there will be no keybinding for this action. "));

my $capture_sel_key = Gtk2::Entry->new;
$capture_sel_key->set_text("<Alt>Print");

my $capture_sel_label = Gtk2::Label->new;
$capture_sel_label->set_text($d->get("Capture with selection"));

my $tooltip_sel_capture = Gtk2::Tooltips->new;
$tooltip_sel_capture->set_tip($capture_sel_key,$d->get("Configure global keybinding for capture with selection\nThe format looks like \"<Control>a\" or \"<Shift><Alt>F1\". The parser is fairly liberal and allows lower or upper case, and also abbreviations such as \"<Ctl>\" and \"<Ctrl>\". If you set the option to the special string \"disabled\", then there will be no keybinding for this action. "));
$tooltip_sel_capture->set_tip($capture_sel_label,$d->get("Configure global keybinding for capture with selection\nThe format looks like \"<Control>a\" or \"<Shift><Alt>F1\". The parser is fairly liberal and allows lower or upper case, and also abbreviations such as \"<Ctl>\" and \"<Ctrl>\". If you set the option to the special string \"disabled\", then there will be no keybinding for this action. "));


my $keybinding_active = Gtk2::CheckButton->new;
$keybinding_active->signal_connect('toggled' => \&event_behavior_handle, 'keybinding_toggled');
$keybinding_active->set_active(TRUE);
$keybinding_active->set_active(FALSE);

my $keybinding_sel_active = Gtk2::CheckButton->new;
$keybinding_sel_active->signal_connect('toggled' => \&event_behavior_handle, 'keybinding_sel_toggled');
$keybinding_sel_active->set_active(TRUE);
$keybinding_sel_active->set_active(FALSE);

$key_box->pack_start($capture_label, FALSE, TRUE, 10);
$key_box2->pack_start($keybinding_active, FALSE, FALSE, 0);
$key_box2->pack_start($capture_key, TRUE, TRUE, 0);
$key_box->pack_start($key_box2, TRUE, TRUE, 10);

$key_sel_box->pack_start($capture_sel_label, FALSE, TRUE, 10);
$key_sel_box2->pack_start($keybinding_sel_active, FALSE, FALSE, 0);
$key_sel_box2->pack_start($capture_sel_key, TRUE, TRUE, 0);
$key_sel_box->pack_start($key_sel_box2, TRUE, TRUE, 10);

my $hide_active = Gtk2::CheckButton->new_with_label($d->get("Autohide GScrot Window when taking a screenshot"));
my $close_at_close_active = Gtk2::CheckButton->new_with_label($d->get("Minimize to tray when closing main window"));
my $save_at_close_active = Gtk2::CheckButton->new_with_label($d->get("Save settings when exiting"));
my $ask_quit_active = Gtk2::CheckButton->new_with_label($d->get("Show \"Do you really want to quit?\" dialog when exiting"));

$hide_active->signal_connect('toggled' => \&event_behavior_handle, 'hide_toggled');
$hide_active->set_active(TRUE);
my $tooltip_hide = Gtk2::Tooltips->new;
$tooltip_hide->set_tip($hide_active,$d->get("Automatically hide GScrot Window when taking a screenshot"));

$close_at_close_active->signal_connect('toggled' => \&event_behavior_handle, 'close_at_close_toggled');
$close_at_close_active->set_active(TRUE);
my $tooltip_close_at_close = Gtk2::Tooltips->new;
$tooltip_close_at_close->set_tip($close_at_close_active,$d->get("Minimize to tray when closing main window"));

$save_at_close_active->signal_connect('toggled' => \&event_behavior_handle, 'save_at_close_toggled');
$save_at_close_active->set_active(TRUE);
my $tooltip_save_at_close = Gtk2::Tooltips->new;
$tooltip_save_at_close->set_tip($save_at_close_active,$d->get("Save settings automatically when exiting GScrot"));

$ask_quit_active->signal_connect('toggled' => \&event_behavior_handle, 'ask_quit_toggled');
$hide_active->set_active(TRUE);
my $tooltip_ask_quit = Gtk2::Tooltips->new;
$tooltip_ask_quit->set_tip($ask_quit_active,$d->get("Show \"Do you really want to quit?\" dialog when exiting"));
#end - behavior

#program
my $model = Gtk2::ListStore->new ('Gtk2::Gdk::Pixbuf', 'Glib::String', 'Glib::String');
foreach (keys %gm_programs){
	if($gm_programs{$_}->{'binary'} ne "" && $gm_programs{$_}->{'name'} ne ""){
		my $pixbuf; 
		if (-f $gm_programs{$_}->{'pixmap'}){
			$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ($gm_programs{$_}->{'pixmap'}, Gtk2::IconSize->lookup ('menu'));
		}else{
			$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/executable.svg", Gtk2::IconSize->lookup ('menu'));
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
$progname_active->signal_connect('toggled' => \&event_value_changed, 'progname_toggled');
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

$combobox_im_colors->signal_connect('changed' => \&event_value_changed, 'border_changed');
$combobox_im_colors->set_active (2);

my $im_colors_active = Gtk2::CheckButton->new;
$im_colors_active->signal_connect('toggled' => \&event_value_changed, 'im_colors_toggled');
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
$combobox_border->signal_connect('changed' => \&event_value_changed, 'border_changed');
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
my $accounts_model = Gtk2::ListStore->new ('Glib::String', 'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String');

foreach (keys %accounts){
	my $hidden_text = "";
	for(my $i = 1; $i <= length($accounts{$_}->{'password'}); $i++){
		$hidden_text .= '*';	
	}
	$accounts_model->set ($accounts_model->append, 0, $accounts{$_}->{'host'} , 1, $accounts{$_}->{'username'}, 2, $hidden_text , 3, $accounts{$_}->{'register'}, 4, $accounts{$_}->{'register_color'}, 5, $accounts{$_}->{'register_text'});				
}
my $accounts_tree = Gtk2::TreeView->new_with_model ($accounts_model);
$accounts_tree->signal_connect('row-activated' => \&event_accounts, 'row_activated');
 
my $tv_clmn_name_text = Gtk2::TreeViewColumn->new;
$tv_clmn_name_text->set_title($d->get("Host"));
my $renderer_name_accounts = Gtk2::CellRendererText->new;
#pack it into the column
$tv_clmn_name_text->pack_start ($renderer_name_accounts, FALSE);
#set its atributes
$tv_clmn_name_text->set_attributes($renderer_name_accounts, text => 0);

#append this column to the treeview
$accounts_tree->append_column($tv_clmn_name_text);

my $renderer_username_accounts = Gtk2::CellRendererText->new;
$renderer_username_accounts->set (editable => TRUE);;
$renderer_username_accounts->signal_connect (edited => sub {
		my ($cell, $text_path, $new_text, $model) = @_;
		my $path = Gtk2::TreePath->new_from_string ($text_path);
		my $iter = $model->get_iter ($path);
		$accounts{$model->get_value($iter, 0)}->{'username'} = $new_text; #save entered username to the hash
		$model->set ($iter, 1, $new_text);
	}, $accounts_model);
my $tv_clmn_username_text = Gtk2::TreeViewColumn->new_with_attributes ($d->get("Username"), $renderer_username_accounts, text => 1);	
#append this column to the treeview
$accounts_tree->append_column($tv_clmn_username_text);

my $tv_clmn_password_text = Gtk2::TreeViewColumn->new;
$tv_clmn_password_text->set_title($d->get("Password"));

my $renderer_password_accounts = Gtk2::CellRendererText->new;
$renderer_password_accounts->set (editable => TRUE);;
$renderer_password_accounts->signal_connect (edited => sub {
		my ($cell, $text_path, $new_text, $model) = @_;
		my $path = Gtk2::TreePath->new_from_string ($text_path);
		my $iter = $model->get_iter ($path);
		my $hidden_text = "";
		for(my $i = 1; $i <= length($new_text); $i++){
			$hidden_text .= '*';	
		}
		$accounts{$model->get_value($iter, 0)}->{'password'} = $new_text; #save entered password to the hash
		$model->set ($iter, 2, $hidden_text);
	}, $accounts_model);
#pack it into the column
$tv_clmn_password_text->pack_start ($renderer_password_accounts, FALSE);
#set its atributes
$tv_clmn_password_text->set_attributes($renderer_password_accounts, text => 2);

#append this column to the treeview
$accounts_tree->append_column($tv_clmn_password_text);
#create column
my $treeview = Gtk2::TreeView->new;

my $tv_clmn_pix_text = Gtk2::TreeViewColumn->new;
#create column title
$tv_clmn_pix_text->set_title($d->get("Register"));

#create new object for column
my $ren_text = Gtk2::CellRendererText->new();
#pack it into the column	
$tv_clmn_pix_text->pack_start ($ren_text, FALSE);
#set color and text for column
$tv_clmn_pix_text->set_attributes($ren_text, 'text', ($d->get(5)), 'foreground', 4);

#append this column to the treeview
$accounts_tree->append_column($tv_clmn_pix_text);

my $accounts_label = Gtk2::Label->new;
$accounts_label->set_line_wrap (TRUE);
$accounts_label->set_markup($d->get("<b>Note:</b> Entering your Accounts for specific hosting-sites is optional. If entered it will give you the same benefits as the upload on the website. If you leave these fields empty you will be able to upload to the specific hosting-partner as a guest."));
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
				$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ($plugins{$_}->{'pixmap'}, Gtk2::IconSize->lookup ('menu'));
			}else{
				$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/executable.svg", Gtk2::IconSize->lookup ('menu'));
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
$behavior_vbox->pack_start($save_at_close_active, FALSE, TRUE, 5);
$behavior_frame->add($behavior_vbox);

$keybinding_vbox->pack_start($key_box, FALSE, TRUE, 5);
$keybinding_vbox->pack_start($key_sel_box, FALSE, TRUE, 5);
$keybinding_frame->add($keybinding_vbox);

$vbox_behavior->pack_start($behavior_frame, FALSE, TRUE, 0);
$vbox_behavior->pack_start($keybinding_frame, FALSE, TRUE, 0);
$vbox_behavior->set_border_width(5);

$capture_vbox->pack_start($delay_box, FALSE, TRUE, 5);
$capture_vbox->pack_start($thumbnail_box, FALSE, TRUE, 5);
$capture_vbox->pack_start($border_box, FALSE, TRUE, 5);
$capture_frame->add($capture_vbox);

$actions_vbox->pack_start($progname_box, FALSE, TRUE, 5);
$actions_vbox->pack_start($im_colors_box, FALSE, TRUE, 5);
$actions_frame->add($actions_vbox);

my $label_basic = Gtk2::Label->new;
$label_basic->set_markup ($d->get("<i>Main</i>"));

my $label_extras = Gtk2::Label->new;
$label_extras->set_markup ($d->get("<i>Advanced</i>"));

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
$accounts_vbox->pack_start($accounts_label, TRUE, TRUE, 1);

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

$vbox_inner2->pack_start($notebook_settings, FALSE, FALSE, 1);
$vbox_inner2->set_border_width(10);
$vbox_inner3->pack_start($notebook, TRUE, TRUE, 1);
$vbox_inner3->set_border_width(10);

my $expander1 = Gtk2::Expander->new ($d->get("Settings"));
$expander1->signal_connect('activate' => \&event_expander, 'exp_settings');
$expander1->add($vbox_inner2);

my $expander2 = Gtk2::Expander->new ($d->get("Current Session"));
$expander2->signal_connect('activate' => \&event_expander, 'exp_session');
$expander2->set_expanded(1);
$expander2->add($vbox_inner3);

$vbox_inner1->pack_start($expander2, FALSE, TRUE, 1);
$vbox_inner1->pack_start($expander1, FALSE, TRUE, 1);

$vbox->pack_start($vbox_inner1, FALSE, TRUE, 1);

$vbox->pack_start($statusbar, FALSE, TRUE, 1);
#############PACKING######################

unless($min_cparam){
	$window->show_all;
}else{
	$window->hide;
}

#load saved settings
my $loaded_settings = &function_load_settings if(-f "$ENV{ 'HOME' }/.gscrot/settings.xml" && -r "$ENV{ 'HOME' }/.gscrot/settings.xml");
my $folder_to_save = $loaded_settings->{'general'}->{'folder'} || $ENV{'HOME'};

if($start_with && $folder_to_save){
	if ($start_with eq "raw"){	
		&event_take_screenshot('global_keybinding', "raw", $folder_to_save); 
	}elsif ($start_with eq "select"){
		&event_take_screenshot('global_keybinding', "select", $folder_to_save);	
	}
}

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
			}elsif($arg eq "--window"){
				#is there already a process of gscrot running?
				my @gscrot_pids = `pidof -o $$ -x gscrot.pl`;
				foreach (@gscrot_pids){
					kill USR2 => $_;
					die;  
				}
				$start_with = "select";				
			}elsif($arg eq "--full"){	
				#is there already a process of gscrot running?
				my @gscrot_pids = `pidof -o $$ -x gscrot.pl`;
				foreach (@gscrot_pids){
					kill USR1 => $_;
					die;  
				}
				$start_with = "raw";									
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

	if(system("which gscrot.pl")==0){
		print "INFO: gscrot seems to be properly installed on your system!\n";
		print "INFO: gscrot will try to find resource directory at default location (/usr)!\n";
		$gscrot_path = "/usr";
	}else{
		print "INFO: gscrot is not installed on your system!\n";
		print "INFO: gscrot will try to find resource directory in place (../)!\n";
		$gscrot_path = "..";
	}	

	print "INFO: searching for dependencies...\n\n";
	
	
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

	#an old .gscrot file existing?
	unlink("$ENV{ 'HOME' }/.gscrot") if (-f "$ENV{ 'HOME' }/.gscrot");
	#an old .gscrot/settings.conf file existing?
	unlink("$ENV{ 'HOME' }/.gscrot/settings.conf") if (-f "$ENV{ 'HOME' }/.gscrot/settings.conf");
	#is there already a .gscrot folder?
	mkdir("$ENV{ 'HOME' }/.gscrot") unless (-d "$ENV{ 'HOME' }/.gscrot");

	%gm_programs = do "$gscrot_path/share/gscrot/resources/system/programs.conf";
	if (-f "$ENV{ 'HOME' }/.gscrot/programs.conf"){
		print "\nINFO: using custom program settings found at $ENV{ 'HOME' }/.gscrot/programs.conf\n";
		%gm_programs = do "$ENV{ 'HOME' }/.gscrot/programs.conf";
	}

	my @plugins = <$gscrot_path/share/gscrot/resources/system/plugins/*/*>; 	
	foreach(@plugins){
		if (-d $_){
			my $dir_name = $_;
			$dir_name =~ s{^.*/}{};				
			$plugins{$_}->{'binary'} = "$_/$dir_name" if (-f "$_/$dir_name" && -r "$_/$dir_name");
			$plugins{$_}->{'pixmap'} = "$_/$dir_name.png" if (-f "$_/$dir_name.png" && -r "$_/$dir_name.png");   
		}
	}
	my @custom_plugins = <$ENV{'HOME'}/.gscrot/plugins/*/*>; 	
	foreach(@custom_plugins){
		if (-d $_){
			my $dir_name = $_;
			$dir_name =~ s{^.*/}{};				
			$plugins{$_}->{'binary'} = "$_/$dir_name" if (-f "$_/$dir_name" && -r "$_/$dir_name");
			$plugins{$_}->{'pixmap'} = "$_/$dir_name.png" if (-f "$_/$dir_name.png" && -r "$_/$dir_name.png");   
		}
	}
}

sub event_expander
{
	my ($widget, $data) = @_;
	print "\n$data was emitted by widget $widget\n" if $debug_cparam;
	if($data eq "exp_settings"){
		$expander2->set_expanded(0);
	}else{
		$expander1->set_expanded(0);
	}
	return 1;
}	
sub event_value_changed
{
	my ($widget, $data) = @_;	

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
		if($combobox_type->get_active_text eq "jpeg"){
			$scale->set_range(1,100);			
			$scale->set_value(75);	
			$scale_label->set_text($d->get("Quality"));			
		}elsif($combobox_type->get_active_text eq "png"){
			$scale->set_range(0,9);				
			$scale->set_value(9);
			$scale_label->set_text($d->get("Compression"));					
		}
	} 	
}


#screenshot events are handled here
sub event_take_screenshot
{
	my ($widget, $data, $folder_from_config) = @_;
	my $quality_value = undef;
	my $delay_value = undef;
	my $thumbnail_value = undef;
	my $progname_value = undef;
	my $im_colors_value = undef;
	my $filename_value = undef;
	my $filetype_value = undef;
	my $folder = undef;
	
	my $screenshot = undef;
	my $screenshot_name = undef;	
	my $screenshot_thumbnail = undef;
	my $screenshot_thumbnail_name = undef;
	my $thumbnail_ending = "thumb";

	print "\n$data was emitted by widget $widget\n" if $debug_cparam;

	&function_set_toolbar_sensitive(FALSE);

	$filetype_value = $combobox_type->get_active_text();
		
	if($filetype_value eq "jpeg"){
		$quality_value = $scale->get_value();
	}elsif($filetype_value eq "png"){
		$quality_value = $scale->get_value*10+5;		
	}
	
	if($delay_active->get_active){		
		$delay_value = $delay->get_value;
	}else{
		$delay_value = 0;
	}

	if($thumbnail_active->get_active){		
		$thumbnail_value = $thumbnail->get_value;
	}

	#prepare filename, parse wild-cards	
	$filename_value = $filename->get_text();
	my $current_counter = sprintf("%02d", scalar(keys %session_screens)+1);
	$filename_value =~ s/\%NN/$current_counter/g;				
	$filename_value = strftime $filename_value , localtime;
	$filename_value =~ s/\\//g;

	#determine current file type
	$filetype_value = $combobox_type->get_active_text;		

	#determine folder to save
	$folder = $saveDir_button->get_filename || $folder_from_config;
	
	#mh...just sleep until window/popup is hidden (fixme?)
	if($delay_value < 2 && $hide_active->get_active && $is_in_tray == FALSE && ($data eq "tray_raw" || $data eq "raw")){
		$delay_value = 2;
	}

	#fullscreen screenshot
	if($data eq "raw" || $data eq "tray_raw"){
		system("xset b off") if $boff_cparam; #turns off the speaker if set as arg
		
		if($hide_active->get_active() && $is_in_tray == FALSE){
			$window->hide;
			Gtk2::Gdk->flush;
			$is_in_tray = TRUE;
		}
		unless ($filename_value =~ /[a-zA-Z0-9]+/ && defined($folder) && defined($filetype_value)) { &dialog_error_message($d->get("No valid filename specified")); &function_set_toolbar_sensitive(TRUE); return FALSE;};
			
		my $root = Gtk2::Gdk->get_default_root_window;
		my ($rootxp, $rootyp, $rootwidthp, $rootheightp) = $root->get_geometry;

		#sleep if there is any delay
		sleep $delay_value;
		
		#get the pixbuf from drawable and save the file
		my $pixbuf = Gtk2::Gdk::Pixbuf->get_from_drawable ($root, undef, $rootxp, $rootyp, 0, 0, $rootwidthp, $rootheightp);
		my $output = Image::Magick->new(magick=>'png');
		$output->BlobToImage( $pixbuf->save_to_buffer('png') );
		$screenshot = $output;

		if($hide_active->get_active()){			
			$window->show_all;
			$is_in_tray = FALSE;
		}
							
	#window
	}elsif($data eq "window" || $data eq "tray_window"){
		
		if($hide_active->get_active() && $is_in_tray == FALSE){
			$window->hide;
			Gtk2::Gdk->flush;
			$is_in_tray = TRUE;
		}
		unless ($filename_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No valid filename specified")); &function_set_toolbar_sensitive(TRUE); return FALSE;};
		
		$screenshot = &function_gscrot_window($folder, $filename_value, $filetype_value, $quality_value, $delay_value, $combobox_border->get_active);
		
		if($hide_active->get_active()){			
			$window->show_all;
			$is_in_tray = FALSE;
		}
				
	#selection
	}elsif($data eq "select" || $data eq "tray_select"){
		if($hide_active->get_active() && $is_in_tray == FALSE){
			$window->hide;
			Gtk2::Gdk->flush;
			$is_in_tray = TRUE;
		}
		unless ($filename_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No valid filename specified")); &function_set_toolbar_sensitive(TRUE); return FALSE;};
		$screenshot = &function_gscrot_area($folder, $filename_value, $filetype_value, $quality_value, $delay_value);
		
		if($hide_active->get_active()){			
			$window->show_all;
			$is_in_tray = FALSE;
		}
	
	#web
	}elsif($data eq "web" || $data eq "tray_web"){
		my $url = &dialog_website;
		unless($url){&function_set_toolbar_sensitive(TRUE); return 0};
		
		my $hostname = $url; $hostname =~ s/http:\/\///;
		if($hostname eq ""){&dialog_error_message($d->get("No valid url entered")); &function_set_toolbar_sensitive(TRUE); return 0;}
		
		#delay doesnt make much sense here, but it's implemented ;-)
		if($delay_active->get_active){		
			sleep $delay_value;
		}

		$screenshot=`gnome-web-photo --mode=photo --format=$filetype_value -q $quality_value $url '$folder/$filename_value.$filetype_value'`;
		my $width = 0;
		my $height = 0;
		if($screenshot eq ""){
			$screenshot_name = "$folder/$filename_value.$filetype_value";	
			$width = &function_imagemagick_perform("get_width", $screenshot_name, 0, $filetype_value);
			$height = &function_imagemagick_perform("get_height", $screenshot_name, 0, $filetype_value);
			if ($width < 1 or $height < 1){&dialog_error_message($d->get("Could not determine file geometry")); &function_set_toolbar_sensitive(TRUE); return 0;}
			my $screenshot_old = $screenshot_name;
			$screenshot_name =~ s/\$w/$width/g;
			$screenshot_name =~ s/\$h/$height/g;
			unless (rename($screenshot_old, $screenshot_name)){&dialog_error_message($d->get("Could not substitute wild-cards in filename")); &function_set_toolbar_sensitive(TRUE); return 0;}
		}else{
			&dialog_error_message($screenshot_name);
			&function_set_toolbar_sensitive(TRUE); 
			return 0;	
		}

		#perform some im_actions
		if($im_colors_active->get_active){
			$im_colors_value = $combobox_im_colors->get_active_text();	
			&function_imagemagick_perform("reduce_colors", $screenshot_name, $im_colors_value, $filetype_value);
		}	
			
		if($thumbnail_active->get_active){
			$width *= ($thumbnail_value/100);
			$width = int($width);
			$height *= ($thumbnail_value/100);
			$height = int($height);
			my $webthumbnail_size = $width."x".$height;
			$screenshot_thumbnail_name = "$folder/$filename_value-$thumbnail_ending.$filetype_value";
			$screenshot_thumbnail_name =~ s/\$w/$width/g;
			$screenshot_thumbnail_name =~ s/\$h/$height/g;
			unless (copy($screenshot_name, $screenshot_thumbnail_name)){&dialog_error_message($d-get("Could not generate thumbnail"));exit;}	
			&function_imagemagick_perform("resize", $screenshot_thumbnail_name, $webthumbnail_size, $filetype_value);				
			unless (&function_file_exists($screenshot_thumbnail_name)){&dialog_error_message($d-get("Could not generate thumbnail"));exit;}	
		}
	}
	
	
	#screenshot was taken at this stage...
	#start postprocessing here
	
	system("xset b on") if $boff_cparam; #turns on the speaker again if set as arg

	#save and process it if it is not a web-photo
	unless($data eq "web" || $data eq "tray_web"){

		#user aborted screenshot
		if($screenshot == 5){
			&dialog_status_message(1, $d->get("Capture aborted by user"));	
			&function_set_toolbar_sensitive(TRUE); 
			return 0;			
		}


		#...successfully???
		unless($screenshot){
			&dialog_error_message($d->get("Screenshot failed!\nMaybe mouse pointer could not be grabbed or the selected area is invalid."));
			print "Screenshot failed!" if $debug_cparam;
			&dialog_status_message(1, $d->get("Screenshot failed!\nMaybe mouse pointer could not be grabbed or the selected area is invalid."));	
			&function_set_toolbar_sensitive(TRUE); 
			return 0;
		}

		#quantize
		if($im_colors_active->get_active){
			$im_colors_value = $combobox_im_colors->get_active_text();
			$im_colors_value =~ /.*\(([0-9]*).*\)/;
			$screenshot->Quantize(colors=>2**$1);
		}

		#generate the thumbnail
		if($thumbnail_active->get_active){
			
			#copy orig image object
			$screenshot_thumbnail = $screenshot->copy;

			#calculate size
			my $twidth = int($screenshot_thumbnail->Get('columns')*($thumbnail_value/100));
			my $theight = int($screenshot_thumbnail->Get('rows')*($thumbnail_value/100));
						
			#resize it
			$screenshot_thumbnail->Sample(width=>$twidth, height=>$theight);

			#save path of thumbnail
			$screenshot_thumbnail_name = "$folder/$filename_value-$thumbnail_ending.$filetype_value";
			
			#parse wild cards
			$screenshot_thumbnail_name =~ s/\$w/$twidth/g;
			$screenshot_thumbnail_name =~ s/\$h/$theight/g;

			#finally save it to disk
			$screenshot_thumbnail->Write(filename => $screenshot_thumbnail_name, quality => $quality_value);			
			
			unless (&function_file_exists($screenshot_thumbnail_name)){
				&dialog_error_message($d-get("Could not generate thumbnail"));
				undef $screenshot_thumbnail;
				&function_set_toolbar_sensitive(TRUE); 
				return 0;
			}	
		
		}		
				
		#and save the filename
		$screenshot_name="$folder/$filename_value.$filetype_value";		

		my $swidth = $screenshot->Get('columns');
		my $sheight = $screenshot->Get('rows');

		#parse wild cards
		$screenshot_name =~ s/\$w/$swidth/g;
		$screenshot_name =~ s/\$h/$sheight/g;

		#save orig file to disk
		$screenshot->Write(filename => $screenshot_name, quality => $quality_value);			
	}
	

	if (&function_file_exists($screenshot_name)){
		
		$screenshot_name=~ s/$ENV{ HOME }/~/; #switch /home/username in path to ~ 
		print "screenshot successfully saved to $screenshot!\n" if $debug_cparam;
		&dialog_status_message(1, "$screenshot_name ".$d->get("saved"));

		#integrate it into the notebook
		my $new_key_screenshot = &function_integrate_screenshot_in_notebook($screenshot_name);

		#thumbnail as well if present
		my $new_key_screenshot_thumbnail = &function_integrate_screenshot_in_notebook($screenshot_thumbnail_name) if $thumbnail_active->get_active;
				
		#open screenshot with configured program
		if($progname_active->get_active){		
			my $model = $progname->get_model();
			my $progname_iter = $progname->get_active_iter();
			$progname_value = $model->get_value($progname_iter, 2);
			unless ($progname_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No application specified to open the screenshot")); &function_set_toolbar_sensitive(TRUE); return FALSE;};
			system("$progname_value $screenshot_name &"); #open picture in external program
		}

				
	}else{
			&dialog_error_message($d->get("Screenshot failed!\nMaybe mouse pointer could not be grabbed or the selected area is invalid."));
			print "Screenshot failed!" if $debug_cparam;
			&dialog_status_message(1, $d->get("Screenshot failed!\nMaybe mouse pointer could not be grabbed or the selected area is invalid."));
	} 
	
	#destroy the imagemagick objects and free memory
	undef $screenshot;
	undef $screenshot_thumbnail;

	&function_set_toolbar_sensitive(TRUE); 

	return 1;						
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
	

#checkbox for "keybinding" -> entry active/inactive
	if($data eq "keybinding_toggled"){
		if($keybinding_active->get_active){
			$capture_key->set_sensitive(TRUE);			
		}else{
			$capture_key->set_sensitive(FALSE);
		}
	}

#checkbox for "keybinding_sel" -> entry active/inactive
	if($data eq "keybinding_sel_toggled"){
		if($keybinding_sel_active->get_active){
			$capture_sel_key->set_sensitive(TRUE);			
		}else{
			$capture_sel_key->set_sensitive(FALSE);
		}
	}
	
}

sub event_notebook_switch
{
	my ($widget, $pointer, $int) = @_;
		
	&function_update_first_tab(); #update first tab for information
}

#close app
sub event_delete_window
{

	my ($widget, $data) = @_;
	print "\n$data was emitted by widget $widget\n" if $debug_cparam;
	
	
	if($data eq "menu_quit" && $save_at_close_active->get_active){
	if(-f "$ENV{ HOME }/.gscrot/settings.xml" && -w "$ENV{ HOME }/.gscrot/settings.xml"){
	&function_save_settings;}}
	
	if($data ne "menu_quit" && $save_at_close_active->get_active){
	if(-f "$ENV{ HOME }/.gscrot/settings.xml" && -w "$ENV{ HOME }/.gscrot/settings.xml"){
	&function_save_settings;}}
	

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

#call bug report
sub event_bug 
{
	&function_gnome_open(undef, "https://bugs.launchpad.net/gscrot", undef);
}

#ask a question
sub event_question
{
	&function_gnome_open(undef, "https://answers.launchpad.net/gscrot", undef);
}

#add a translation
sub event_translate
{
	&function_gnome_open(undef, "https://translations.launchpad.net/gscrot", undef);
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
	$about->set_authors("Development:\nMario Kemper <mario.kemper\@gmx.de>\nRene Hennig <Rene.Hennig\@my-united.net>\n\nPlugins:\nMartin Rabeneck (cornix) <martinrabeneck\@gmx.net>\n\nubuntu-pics.de:\nRene Hennig <Rene.Hennig\@my-united.net>");
	$about->set_artists("Arne Weinberg","Pascal Grochol <pg0803\@gmail.com>");
	$about->set_translator_credits ("German: Mario Kemper <mario.kemper\@gmx.de>\nRussian: Michael Kogan (PhotonX)\nCatalan: David Pinilla (DPini) <Davidpini\@gmail.com>\nSpanish: Nicolas Espina Tacchetti <nicolasespina\@gmail.com>");	
	$about->set_copyright ($all_hints);
	$about->set_license ($all_lines);
	$about->set_comments ("$gscrot_version_detailed");
	$about->show_all;
	$about->signal_connect('response' => sub { $about->destroy });

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
	my $menuitem_select = Gtk2::ImageMenuItem->new($d->get("Selection"));
	$menuitem_select->set_image(Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/selection.svg", Gtk2::IconSize->lookup ('menu'))));
	$menuitem_select->signal_connect(activate => \&event_take_screenshot, 'tray_select');
	my $menuitem_raw = Gtk2::ImageMenuItem->new($d->get("Fullscreen"));
	$menuitem_raw->set_image(Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/fullscreen.svg", Gtk2::IconSize->lookup ('menu'))));
	$menuitem_raw->signal_connect(activate => \&event_take_screenshot, 'tray_raw');
	my $menuitem_window = Gtk2::ImageMenuItem->new($d->get("Window"));
	$menuitem_window->set_image(Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/sel_window.svg", Gtk2::IconSize->lookup ('menu'))));
	$menuitem_window->signal_connect(activate => \&event_take_screenshot, 'tray_window');
	my $menuitem_web = Gtk2::ImageMenuItem->new($d->get("Web"));
	$menuitem_web->set_image(Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/web_image.svg", Gtk2::IconSize->lookup ('menu'))));
	$menuitem_web->signal_connect(activate => \&event_take_screenshot, 'tray_web');
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
	$menuitem_window->show();
	$menuitem_web->show();
	$menuitem_info->show();
	$menuitem_quit->show();
	$tray_menu->append($menuitem_select);
	$tray_menu->append($menuitem_raw);
	$tray_menu->append($menuitem_window);
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

#notebook accounts - double-click-events are handled here
sub event_accounts
{
	my ($tree, $path, $column) = @_;

	#open browser if register url is clicked
	if ($column->get_title eq $d->get("Register")){
		my $model = $tree->get_model();
		my $account_iter = $model->get_iter($path);
		my $account_value = $model->get_value($account_iter, 3);
		&function_gnome_open(undef, $account_value, undef);
	}
	return 1;	
}

sub function_create_session_notebook
{
	$notebook->set_scrollable(TRUE);
	$notebook->signal_connect('switch-page' => \&event_notebook_switch, 'tab-switched');
	$notebook->set_size_request(410, 280);

	my $hbox_first_label = Gtk2::HBox->new(FALSE, 0);	
	my $thumb_first_icon = Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size("$gscrot_path/share/gscrot/resources/icons/session.svg", Gtk2::IconSize->lookup ('menu')));	
	my $tab_first_label = Gtk2::Label->new($d->get("Session"));
	$hbox_first_label->pack_start($thumb_first_icon , FALSE, TRUE, 1);	
	$hbox_first_label->pack_start($tab_first_label , TRUE, TRUE, 1);
	$hbox_first_label->show_all;

	my $first_page = $notebook->append_page (function_create_tab ("", TRUE), $hbox_first_label);	

	return 1; 
}

sub function_integrate_screenshot_in_notebook
{
	my ($filename) = @_;

	#append a page to notebook using with label == filename
	my ($second, $minute, $hour) = localtime();
	my $theTime = "$hour:$minute:$second";
	my $key = "[".&function_get_latest_tab_key."] - $theTime";

	#build hash of screenshots during session	
	$session_screens{$key}->{'filename'} = $filename;
	#create thumbnail for gui
	&function_create_thumbnail_and_fileinfos($filename, $key);

	my $hbox_tab_label = Gtk2::HBox->new(FALSE, 0);	
	my $close_icon = Gtk2::Image->new_from_icon_name ('gtk-close', 'menu');
		
	$session_screens{$key}->{'tab_icon'} = Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size (&function_switch_home_in_file($session_screens{$key}->{'filename'}), Gtk2::IconSize->lookup ('menu')));	

	my $tab_close_button = Gtk2::Button->new;
	$tab_close_button->set_relief('none');
	$tab_close_button->set_image($close_icon);
	my $tab_label = Gtk2::Label->new($key);
	$hbox_tab_label->pack_start($session_screens{$key}->{'tab_icon'} , FALSE, TRUE, 1);	
	$hbox_tab_label->pack_start($tab_label , TRUE, TRUE, 1);
	$hbox_tab_label->pack_start($tab_close_button, FALSE, TRUE, 1);
	$hbox_tab_label->show_all;
	
	#and append page with label == key		
	my $new_index = $notebook->append_page (function_create_tab ($key, FALSE), $hbox_tab_label);
	$session_screens{$key}->{'tab_child'} = $notebook->get_nth_page ($new_index);
	$tab_close_button->signal_connect(clicked => \&event_in_tab, 'remove'.$key.'__ind__'.$new_index.'__indold__'.$notebook->get_current_page);	
	
	$window->show_all unless $is_in_tray;			
	my $current_tab = $notebook->get_current_page+1;
	print "new tab $new_index created, current tab is $current_tab\n" if $debug_cparam;
	
	$notebook->set_current_page($new_index);

	return $key;	
}

sub function_set_toolbar_sensitive
{
	my ($set) = @_;

	#set all buttons insensitive/sensitive
	$button_select->set_sensitive($set);
	$button_raw->set_sensitive($set);
	$button_window->set_sensitive($set);
	$button_web->set_sensitive($set);
	
	return 1;
}

sub function_create_tab {
	my ($key, $is_all) = @_;

	my $scrolled_window = Gtk2::ScrolledWindow->new;
	$scrolled_window->set_policy ('automatic', 'automatic');
	$scrolled_window->set_shadow_type ('in');
	
	my $vbox_tab = Gtk2::VBox->new(FALSE, 0);
	my $hbox_tab = Gtk2::HBox->new(FALSE, 0);
	my $vbox_all = Gtk2::VBox->new(FALSE, 0);	
	my $vbox_fileinfos = Gtk2::VBox->new(FALSE, 0);
	my $vbox_fileinfos2 = Gtk2::VBox->new(FALSE, 0);	
	my $hbox_tab_file = Gtk2::HBox->new(FALSE, 0);
	my $hbox_tab_actions = Gtk2::HBox->new(FALSE, 0);
	my $hbox_tab_actions2 = Gtk2::HBox->new(FALSE, 0);

	
	my $button_remove = Gtk2::Button->new;
	$button_remove->set_name("btn_remove");
	$button_remove->signal_connect(clicked => \&event_in_tab, 'remove'.$key);
	my $image_remove = Gtk2::Image->new_from_icon_name ('gtk-close', 'button');
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
	$tooltip_upload->set_tip($button_upload,$d->get("Upload file to hosting-site"));

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

	my $button_draw = Gtk2::Button->new;
	$button_draw->signal_connect(clicked => \&event_in_tab, 'draw'.$key);

	my $draw_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size("$gscrot_path/share/gscrot/resources/icons/draw.svg", Gtk2::IconSize->lookup ('button'));
	my $image_draw = Gtk2::Image->new_from_pixbuf ($draw_pixbuf);
	$button_draw->set_image($image_draw);	

	my $tooltip_draw = Gtk2::Tooltips->new;
	$tooltip_draw->set_tip($button_draw,$d->get("Draw"));

	my $button_print = Gtk2::Button->new;
	$button_print->signal_connect(clicked => \&event_in_tab, 'print'.$key);
	my $image_print = Gtk2::Image->new_from_icon_name ('gtk-print', 'button');
	$button_print->set_image($image_print);	

	my $tooltip_print = Gtk2::Tooltips->new;
	$tooltip_print->set_tip($button_print,$d->get("Print file(s)"));

	unless($is_all){
		my $filename_label = Gtk2::Label->new;
		$filename_label->set_markup("<b>".$d->get("Filename")."</b>");

		$session_screens{$key}->{'filename_label'} = Gtk2::Label->new($session_screens{$key}->{'short'});
		$session_screens{$key}->{'filename_label'}->set_width_chars (20);
		$session_screens{$key}->{'filename_label'}->set_line_wrap (1);
		$session_screens{$key}->{'filename_label'}->set_line_wrap_mode('char');

		$session_screens{$key}->{'tooltip_filename_tab'} = Gtk2::Tooltips->new;
		$session_screens{$key}->{'tooltip_filename_tab'}->set_tip($session_screens{$key}->{'filename_label'},$session_screens{$key}->{'filename'});
		
		my $mime_type_label = Gtk2::Label->new;
		$mime_type_label->set_markup("<b>".$d->get("Mime-Type")."</b>");
		
		$session_screens{$key}->{'mime_type_label'} = Gtk2::Label->new($session_screens{$key}->{'mime_type'});
				
		my $size_label = Gtk2::Label->new;
		$size_label->set_markup("<b>".$d->get("Filesize")."</b>");
		
		$session_screens{$key}->{'size_label'} = Gtk2::Label->new(sprintf("%.2f", $session_screens{$key}->{'size'} / 1024)." KB");
			
		my $geometry_label = Gtk2::Label->new;
		$geometry_label->set_markup("<b>".$d->get("Geometry")."</b>");
		
		$session_screens{$key}->{'geometry_label'} = Gtk2::Label->new($session_screens{$key}->{'width'}."x".$session_screens{$key}->{'height'});
		
		if(&function_file_exists($session_screens{$key}->{'filename'})){	
			$session_screens{$key}->{'image'} = Gtk2::Image->new_from_pixbuf($session_screens{$key}->{'thumb'});
		}else{
			$session_screens{$key}->{'image'} = Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size("$gscrot_path/share/gscrot/resources/icons/Image-missing.svg", Gtk2::IconSize->lookup ('dialog' )));
		}

		#packing
		my $tab_infos_sizegroup = Gtk2::SizeGroup->new ('vertical');
		$tab_infos_sizegroup->add_widget($session_screens{$key}->{'filename_label'});
		$tab_infos_sizegroup->add_widget($session_screens{$key}->{'size_label'});
		$tab_infos_sizegroup->add_widget($session_screens{$key}->{'mime_type_label'});
		$tab_infos_sizegroup->add_widget($session_screens{$key}->{'geometry_label'});

		$vbox_fileinfos->pack_start($filename_label, TRUE, TRUE, 0);
		$vbox_fileinfos->pack_start($session_screens{$key}->{'filename_label'}, TRUE, TRUE, 1);

		$vbox_fileinfos2->pack_start($size_label, TRUE, TRUE, 1);		
		$vbox_fileinfos2->pack_start($session_screens{$key}->{'size_label'}, TRUE, TRUE, 1);

		$vbox_fileinfos->pack_start($mime_type_label, TRUE, TRUE, 1);
		$vbox_fileinfos->pack_start($session_screens{$key}->{'mime_type_label'}, TRUE, TRUE, 1);	

		$vbox_fileinfos2->pack_start($geometry_label, TRUE, TRUE, 1);		
		$vbox_fileinfos2->pack_start($session_screens{$key}->{'geometry_label'}, TRUE, TRUE, 1);
		
		$hbox_tab_file->pack_start($session_screens{$key}->{'image'}, TRUE, TRUE, 1);
		
		$hbox_tab_file->pack_start($vbox_fileinfos, TRUE, TRUE, 1);
		$hbox_tab_file->pack_start($vbox_fileinfos2, TRUE, TRUE, 1);		

		$session_screens{$key}->{'scrolled_window'} = $scrolled_window;
		$session_screens{$key}->{'btn_delete'} = $button_delete;
		$session_screens{$key}->{'btn_reopen'} = $button_reopen;
		$session_screens{$key}->{'btn_upload'} = $button_upload;
		$session_screens{$key}->{'btn_print'} = $button_print;
		$session_screens{$key}->{'btn_rename'} = $button_rename;
		$session_screens{$key}->{'btn_plugin'} = $button_plugin;
		$session_screens{$key}->{'btn_draw'} = $button_draw;
		$session_screens{$key}->{'btn_clipboard'} = $button_clipboard;

		my $tab_sizegroup = Gtk2::SizeGroup->new ('both');
		$tab_sizegroup->add_widget($button_delete);
		$tab_sizegroup->add_widget($button_reopen);
		$tab_sizegroup->add_widget($button_upload);
		$tab_sizegroup->add_widget($button_print);
		$tab_sizegroup->add_widget($button_rename);
		$tab_sizegroup->add_widget($button_plugin);
		$tab_sizegroup->add_widget($button_draw);
		$tab_sizegroup->add_widget($button_clipboard);

		$hbox_tab_actions->pack_start($button_delete, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_reopen, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_upload, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_print, TRUE, TRUE, 1);
		$hbox_tab_actions->pack_start($button_rename, TRUE, TRUE, 1);
		$hbox_tab_actions->pack_start($button_plugin, TRUE, TRUE, 1) if (keys(%plugins) > 0);
		$hbox_tab_actions->pack_start($button_draw, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_clipboard, TRUE, TRUE, 1);	

		$vbox_tab->pack_start($hbox_tab_file, TRUE, TRUE, 1);
		
	}else{
		my $stats_label = Gtk2::Label->new;
		$stats_label->set_markup("<b>".$d->get("Statistic")."</b>");

		$session_start_screen{'first_page'}->{'statistics_counter'} = Gtk2::Label->new($notebook->get_n_pages." ".$d->nget("screenshot during this session", "screenshots during this session", $notebook->get_n_pages));
		
		$session_start_screen{'first_page'}->{'size_counter'} = Gtk2::Label->new("0.00 KB");

		$vbox_all->pack_start($stats_label, FALSE, TRUE, 1);
		$vbox_all->pack_start($session_start_screen{'first_page'}->{'statistics_counter'}, FALSE, TRUE, 1);
		$vbox_all->pack_start($session_start_screen{'first_page'}->{'size_counter'}, FALSE, TRUE, 1);

		$session_start_screen{'first_page'}->{'image'} = Gtk2::Image->new_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size("$gscrot_path/share/gscrot/resources/icons/session.svg", Gtk2::IconSize->lookup ('dialog' ))) if $is_all;

		$hbox_tab_file->pack_start($session_start_screen{'first_page'}->{'image'}, TRUE, TRUE, 1);		
		
		$hbox_tab_file->pack_start($vbox_all, TRUE, TRUE, 1);			

		$session_start_screen{'first_page'}->{'scrolled_window'} = $scrolled_window;
		$session_start_screen{'first_page'}->{'btn_remove'} = $button_remove;
		$session_start_screen{'first_page'}->{'btn_delete'} = $button_delete;
		$session_start_screen{'first_page'}->{'btn_reopen'} = $button_reopen;
		$session_start_screen{'first_page'}->{'btn_print'} = $button_print;

		$hbox_tab_actions->pack_start($button_remove, TRUE, TRUE, 1);
		$hbox_tab_actions->pack_start($button_delete, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_reopen, TRUE, TRUE, 1);
		$hbox_tab_actions2->pack_start($button_print, TRUE, TRUE, 1);

		$vbox_tab->pack_start($hbox_tab_file, TRUE, FALSE, 1);

	}

	$vbox_tab->pack_start($hbox_tab_actions, FALSE, TRUE, 1);
	$vbox_tab->pack_start($hbox_tab_actions2, FALSE, TRUE, 1);		
	$scrolled_window->add_with_viewport($vbox_tab);

  	return $scrolled_window;
}

#tab events are handled here
sub event_in_tab
{
	my ($widget, $key) = @_;
	print "\n$key was emitted by widget $widget\n" if $debug_cparam;

#single screenshots	
	my $current_file;
	if ($key =~ m/^print\[/){	
		$key =~ s/^print//;
		unless(&function_create_thumbnail_and_fileinfos($session_screens{$key}->{'filename'}, $key)){
			&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("not found"));		
			&function_update_tab($key);
			return 0;	
		}		
		my $current_file = &function_switch_home_in_file($session_screens{$key}->{'filename'});
		system("gtklp $current_file &");
		&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("will be printed"));
	}

	if ($key =~ m/^delete\[/){
		$key =~ s/^delete//;
		unless(&function_create_thumbnail_and_fileinfos($session_screens{$key}->{'filename'}, $key)){
			&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("not found"));		
			&function_update_tab($key);
			return 0;	
		}	
		unlink(&function_switch_home_in_file($session_screens{$key}->{'filename'})); #delete file
		$notebook->remove_page($notebook->get_current_page); #delete tab
		&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("deleted")) if defined($session_screens{$key}->{'filename'});
		delete($session_screens{$key}); # delete from hash
		
		&function_update_first_tab();
				
		$window->show_all;
	}
	
	if ($key =~ m/^remove\[/){
		$key =~ /^remove(.*)__ind__(.*)__indold__(.*)/;
		$key = $1;
		my $delete_index = $2;
		my $last_index = $3;
		#~ $notebook->set_current_page($delete_index);
		print "Child: ".$notebook->page_num ($session_screens{$key}->{'tab_child'})."\n" if $debug_cparam;
		$notebook->remove_page($notebook->page_num ($session_screens{$key}->{'tab_child'})); #delete tab
		#~ $notebook->set_current_page($last_index-1) unless $delete_index = $last_index;		
		&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("removed from session")) if defined($session_screens{$key}->{'filename'});
		delete($session_screens{$key}); # delete from hash
		
		&function_update_first_tab();
				
		$window->show_all;
	}	

	if ($key =~ m/^reopen\[/){
		$key =~ s/^reopen//;
		my $model = $progname->get_model();
		my $progname_iter = $progname->get_active_iter();
		my $progname_value = $model->get_value($progname_iter, 2);
		unless(&function_create_thumbnail_and_fileinfos($session_screens{$key}->{'filename'}, $key)){
			&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("not found"));		
			&function_update_tab($key);
			return 0;	
		}			
		unless ($progname_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No application specified to open the screenshot")); return FALSE;};
		system($progname_value." ".$session_screens{$key}->{'filename'}." &");
		&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("opened with")." ".$progname_value);
		&function_update_tab($key);
	}

	if ($key =~ m/^upload\[/){
		$key =~ s/^upload//;
		unless(&function_create_thumbnail_and_fileinfos($session_screens{$key}->{'filename'}, $key)){
			&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("not found"));		
			&function_update_tab($key);
			return 0;	
		}	
		&dialog_account_chooser_and_upload($session_screens{$key}->{'filename'});	
	}

	if ($key =~ m/^draw\[/){
		$key =~ s/^draw//;
		unless(&function_create_thumbnail_and_fileinfos($session_screens{$key}->{'filename'}, $key)){
			&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("not found"));		
			&function_update_tab($key);
			return 0;	
		}			
		my $full_filename = &function_switch_home_in_file($session_screens{$key}->{'filename'});
		my $width = &function_imagemagick_perform("get_width", $full_filename, 0, "");
		my $height = &function_imagemagick_perform("get_height", $full_filename, 0, "");
		&function_start_drawing($full_filename, $width, $height, $session_screens{$key}->{'filetype'}, $d);	
		&function_update_tab($key);
	}
	
	if ($key =~ m/^rename\[/){
		$key =~ s/^rename//;
		unless(&function_create_thumbnail_and_fileinfos($session_screens{$key}->{'filename'}, $key)){
			&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("not found"));		
			&function_update_tab($key);
			return 0;	
		}			
		&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("renamed")) if &dialog_rename($session_screens{$key}->{'filename'}, $key);
		&function_update_tab($key);
	}

	if ($key =~ m/^plugin\[/){
		$key =~ s/^plugin//;
		unless(&function_create_thumbnail_and_fileinfos($session_screens{$key}->{'filename'}, $key)){
			&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("not found"));		
			&function_update_tab($key);
			return 0;	
		}			
		unless (keys %plugins > 0){
			&dialog_error_message($d->get("No plugin installed"));
		}else{
			&dialog_plugin($session_screens{$key}->{'filename'}, $key);			
		}	
		&function_update_tab($key);
	}

	if ($key =~ m/^clipboard\[/){		
		$key =~ s/^clipboard//;
		unless(&function_create_thumbnail_and_fileinfos($session_screens{$key}->{'filename'}, $key)){
			&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("not found"));		
			&function_update_tab($key);
			return 0;	
		}	
		my $pixbuf = Gtk2::Gdk::Pixbuf->new_from_file (&function_switch_home_in_file($session_screens{$key}->{'filename'}) );
		$clipboard->set_image($pixbuf);
		&dialog_status_message(1, $session_screens{$key}->{'filename'}." ".$d->get("copied to clipboard"));
	}

#all screenshots
	if ($key =~ m/^delete$/){ #tab == all
		foreach my $key(keys %session_screens){
			unlink(&function_switch_home_in_file($session_screens{$key}->{'filename'})); #delete file		
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
	
	if ($key =~ m/^remove$/){ #tab == all
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
	
	if ($key =~ m/^reopen$/){
		my $model = $progname->get_model();
		my $progname_iter = $progname->get_active_iter();
		my $progname_value = $model->get_value($progname_iter, 2);
		my $open_files;
		unless ($progname_value =~ /[a-zA-Z0-9]+/) { &dialog_error_message($d->get("No application specified to open the screenshot")); return FALSE;};
		if($progname_value =~ /gimp/){
			foreach my $key(keys %session_screens){
				$open_files .= &function_switch_home_in_file($session_screens{$key}->{'filename'})." ";
			}
			system($progname_value." ".$open_files." &");
		}else{
			foreach my $key(keys %session_screens){
				system($progname_value." ".&function_switch_home_in_file($session_screens{$key}->{'filename'})." &");
			}			
		}
		&dialog_status_message(1, $d->get("Opened all files with")." ".$progname_value);
	}	

	if ($key =~ m/^print$/){ #tab == all
		my $print_files;		
		foreach my $key(keys %session_screens){
			$print_files .= &function_switch_home_in_file($session_screens{$key}->{'filename'})." ";
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
		if(-f "$ENV{ HOME }/.gscrot/settings.xml" && -w "$ENV{ HOME }/.gscrot/settings.xml"){
			if (&dialog_question_message($d->get("Do you want to overwrite the existing settings?"))){ #ask is settings-file exists
				&function_save_settings;
			}
		}else{
			&function_save_settings; #do it directly if not
		}
	}elsif($data eq "menu_revert"){
		if(-f "$ENV{ HOME }/.gscrot/settings.xml" && -r "$ENV{ HOME }/.gscrot/settings.xml"){
			&function_load_settings;
		}else{
			&dialog_info_message($d->get("There are no stored settings"));
		}
	}elsif($data eq "menu_open"){
		my $fs = Gtk2::FileChooserDialog->new($d->get("Choose file to open"), $window, 'open',
																		'gtk-ok'     => 'accept',
																		'gtk-cancel' => 'reject');
		my $pngfilter = Gtk2::FileFilter->new;
		$pngfilter->set_name ("*.png");
		$pngfilter->add_pattern ("*.png");
		
		my $jpegfilter = Gtk2::FileFilter->new;
		$jpegfilter->set_name ("*.jpeg");
		$jpegfilter->add_pattern ("*.jpeg");

		$fs->add_filter($pngfilter);
		$fs->add_filter($jpegfilter);

		my $fs_resp = $fs->run;                  	
		if ($fs_resp eq "accept" ) {
			my $new_file = $fs->get_filename;
			$new_file =~ s/$ENV{ HOME }/~/; #switch /home/username in path to ~ 
			&function_integrate_screenshot_in_notebook($new_file);			
			$fs->destroy();		
			return TRUE;
		}else {
			$fs->destroy() ;
			return FALSE;
		}
	}		
	
}

#save settings to file
sub function_save_settings
{

	my $client = Gnome2::GConf::Client->get_default;
	my $shortcut_full = "/apps/metacity/global_keybindings/run_command_screenshot";
	my $shortcut_sel = "/apps/metacity/global_keybindings/run_command_window_screenshot";
	my $command_full = "/apps/metacity/keybinding_commands/command_screenshot";
	my $command_sel = "/apps/metacity/keybinding_commands/command_window_screenshot";	
	
	open(SETTFILE, ">$ENV{ HOME }/.gscrot/settings.xml") or &dialog_error_message($d->get("Settings could not be saved!"));	
	$settings{'general'}->{'filetype'} = $combobox_type->get_active;
	$settings{'general'}->{'quality'} = $scale->get_value();
	$settings{'general'}->{'filename'} = $filename->get_text();
	$settings{'general'}->{'folder'} = $saveDir_button->get_filename();

	my $model = $progname->get_model();
	my $progname_iter = $progname->get_active_iter();
	my $progname_value = $model->get_value($progname_iter, 2);
	$settings{'general'}->{'program'} = $progname_value;
	$settings{'general'}->{'programe_active'} = $progname_active->get_active();
	$settings{'general'}->{'im_colors'} = $combobox_im_colors->get_active();
	$settings{'general'}->{'im_colors_active'} = $im_colors_active->get_active();
	$settings{'general'}->{'delay'} = $delay->get_value();
	$settings{'general'}->{'delay_active'} = $delay_active->get_active();
	$settings{'general'}->{'thumbnail'} = $thumbnail->get_value();
	$settings{'general'}->{'thumbnail_active'} = $thumbnail_active->get_active();
	$settings{'general'}->{'border'} = $combobox_border->get_active();
	$settings{'general'}->{'ask_at_close'} = $ask_quit_active->get_active();
	$settings{'general'}->{'autohide'} = $hide_active->get_active();
	$settings{'general'}->{'close_at_close'} = $close_at_close_active->get_active();
	$settings{'general'}->{'save_at_close'} = $save_at_close_active->get_active();

	$settings{'general'}->{'keybinding'} = $keybinding_active->get_active();
	$settings{'general'}->{'keybinding_sel'} = $keybinding_sel_active->get_active();
	
	#set gconf values if needed
	if ($keybinding_active->get_active()){
		$client->set($command_full, { type => 'string', value => "$gscrot_path/bin/gscrot.pl --full", });
		$client->set($shortcut_full, { type => 'string', value => $capture_key->get_text(), });		
	}else{
		$client->set($command_full, { type => 'string', value => 'gnome-screenshot', });
		$client->set($shortcut_full, { type => 'string', value => 'Print', });		
	}
	if ($keybinding_sel_active->get_active()){
		$client->set($command_sel, { type => 'string', value => "$gscrot_path/bin/gscrot.pl --window", });		
		$client->set($shortcut_sel, { type => 'string', value => $capture_sel_key->get_text(), });		
	}else{
		$client->set($command_sel, { type => 'string', value => 'gnome-screenshot --window', });			
		$client->set($shortcut_sel, { type => 'string', value => '<Alt>Print', });		
	}
	
	$settings{'general'}->{'capture_key'} = $capture_key->get_text();
	$settings{'general'}->{'capture_sel_key'} = $capture_sel_key->get_text();


	my $settings_out = XMLout(\%settings);	
  	print SETTFILE $settings_out;

	close(SETTFILE) or &dialog_error_message($d->get("Settings could not be saved!"));

	&dialog_status_message(1, $d->get("Settings saved successfully!"));

	open(ACC_FILE, ">$ENV{ HOME }/.gscrot/accounts.xml") or &dialog_error_message($d->get("Account-settings could not be saved!"));	
	my $accounts_out = XMLout(\%accounts);	
  	print ACC_FILE $accounts_out;
	close(ACC_FILE) or &dialog_error_message($d->get("Account-settings could not be saved!"));

	return 1;
}

sub function_load_settings
{
	my $settings_xml = undef;	
	if (&function_file_exists("$ENV{ HOME }/.gscrot/settings.xml")){
		$settings_xml = XMLin("$ENV{ HOME }/.gscrot/settings.xml");
		$combobox_type->set_active($settings_xml->{'general'}->{'filetype'});
		$scale->set_value($settings_xml->{'general'}->{'quality'});
		$filename->set_text($settings_xml->{'general'}->{'filename'});
		$saveDir_button->set_current_folder($settings_xml->{'general'}->{'folder'});
		my $model = $progname->get_model;
		$model->foreach (\&function_iter_programs, $settings_xml->{'general'}->{'program'});
		$progname_active->set_active($settings_xml->{'general'}->{'programe_active'});
		$im_colors_active->set_active($settings_xml->{'general'}->{'im_colors_active'});
		$combobox_im_colors->set_active($settings_xml->{'general'}->{'im_colors'});
		$delay->set_value($settings_xml->{'general'}->{'delay'});
		$delay_active->set_active($settings_xml->{'general'}->{'delay_active'});
		$thumbnail->set_value($settings_xml->{'general'}->{'thumbnail'});
		$thumbnail_active->set_active($settings_xml->{'general'}->{'thumbnail_active'});
		$combobox_border->set_active($settings_xml->{'general'}->{'border'});
		$ask_quit_active->set_active($settings_xml->{'general'}->{'ask_at_close'});
		$hide_active->set_active($settings_xml->{'general'}->{'autohide'});
		$close_at_close_active->set_active($settings_xml->{'general'}->{'close_at_close'});
		$save_at_close_active->set_active($settings_xml->{'general'}->{'save_at_close'});				
		$keybinding_active->set_active($settings_xml->{'general'}->{'keybinding'});
		$keybinding_sel_active->set_active($settings_xml->{'general'}->{'keybinding_sel'});
		$capture_key->set_text($settings_xml->{'general'}->{'capture_key'});
		$capture_sel_key->set_text($settings_xml->{'general'}->{'capture_sel_key'});
		&dialog_status_message(1, $d->get("Settings loaded successfully"));
	}
	return $settings_xml;	
}

sub function_load_accounts
{	
	my $accounts_xml = XMLin("$ENV{ HOME }/.gscrot/accounts.xml") if &function_file_exists("$ENV{ HOME }/.gscrot/accounts.xml");
	#account data, load defaults if nothing is set
	unless(exists($accounts_xml->{'ubuntu-pics.de'})){
		$accounts{'ubuntu-pics.de'}->{host} = "ubuntu-pics.de";
		$accounts{'ubuntu-pics.de'}->{username} = "";
		$accounts{'ubuntu-pics.de'}->{password} = "";
		$accounts{'ubuntu-pics.de'}->{register} = "http://www.ubuntu-pics.de/registrieren.html";
		$accounts{'ubuntu-pics.de'}->{register_color} = "blue";
		$accounts{'ubuntu-pics.de'}->{register_text} = ($d->get("click me"));
		$accounts{'ubuntu-pics.de'}->{module} = "UbuntuPics.pm";
	}else{
		$accounts{'ubuntu-pics.de'}->{host} = $accounts_xml->{'ubuntu-pics.de'}->{host};
		$accounts{'ubuntu-pics.de'}->{username} = $accounts_xml->{'ubuntu-pics.de'}->{username};
		$accounts{'ubuntu-pics.de'}->{password} = $accounts_xml->{'ubuntu-pics.de'}->{password};
		$accounts{'ubuntu-pics.de'}->{register} = "http://www.ubuntu-pics.de/registrieren.html";
		$accounts{'ubuntu-pics.de'}->{register_color} = "blue";
		$accounts{'ubuntu-pics.de'}->{register_text} = ($d->get("click me"));
		$accounts{'ubuntu-pics.de'}->{module} = $accounts_xml->{'ubuntu-pics.de'}->{module};	
	}
	unless(exists($accounts_xml->{'imagebanana.com'})){
		$accounts{'imagebanana.com'}->{host} = "imagebanana.com";
		$accounts{'imagebanana.com'}->{username} = "";
		$accounts{'imagebanana.com'}->{password} = "";
		$accounts{'imagebanana.com'}->{register} = "http://www.imagebanana.com/myib/registrieren/";
		$accounts{'imagebanana.com'}->{register_color} = "blue";
		$accounts{'imagebanana.com'}->{register_text} = ($d->get("click me"));
		$accounts{'imagebanana.com'}->{module} = "ImageBanana.pm";
	}else{
		$accounts{'imagebanana.com'}->{host} = $accounts_xml->{'imagebanana.com'}->{host};
		$accounts{'imagebanana.com'}->{username} = $accounts_xml->{'imagebanana.com'}->{username};
		$accounts{'imagebanana.com'}->{password} = $accounts_xml->{'imagebanana.com'}->{password};
		$accounts{'imagebanana.com'}->{register} = "http://www.imagebanana.com/myib/registrieren/";
		$accounts{'imagebanana.com'}->{register_color} = "blue";
		$accounts{'imagebanana.com'}->{register_text} = ($d->get("click me"));
		$accounts{'imagebanana.com'}->{module} = $accounts_xml->{'imagebanana.com'}->{module};	
	}			
	return 1;	
}

####################SAVE AND REVERT################################


#################### MY FUNCTIONS  ################################
sub function_file_exists
{
	my ($filename) = @_;
	$filename = &function_switch_home_in_file($filename); 
	return TRUE if (-f $filename);
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
	return 1;
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
			$session_screens{$data}->{'filename'} = $dialog_rename_text;
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
	my ($dialog_plugin_text, $key) = @_;
	my $dialog_header = $d->get("Choose a plugin");
 	my $plugin_dialog = Gtk2::Dialog->new ($dialog_header,
        						$window,
                              	[qw/modal destroy-with-parent/],
                              	'gtk-ok'     => 'accept',
                              	'gtk-cancel' => 'reject');

	$plugin_dialog->set_default_response ('accept');

	my $model = Gtk2::ListStore->new ('Gtk2::Gdk::Pixbuf', 'Glib::String', 'Glib::String');
	foreach (keys %plugins){
		next unless $plugins{$_}->{'ext'} =~ /$session_screens{$key}->{'filetype'}/;
		if($plugins{$_}->{'binary'} ne ""){
			my $pixbuf; 
			if (-f $plugins{$_}->{'pixmap'}){
				$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ($plugins{$_}->{'pixmap'}, Gtk2::IconSize->lookup ('menu'));
			}else{
				$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file_at_size ("$gscrot_path/share/gscrot/resources/icons/executable.svg", Gtk2::IconSize->lookup ('menu'));
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

		print "$plugin_value $dialog_plugin_text $session_screens{$key}->{'width'} $session_screens{$key}->{'height'} $session_screens{$key}->{'filetype'} submitted to plugin\n" if $debug_cparam;
		if (system("$plugin_value $dialog_plugin_text $session_screens{$key}->{'width'} $session_screens{$key}->{'height'} $session_screens{$key}->{'filetype'}") == 0){
			&dialog_status_message(1, $d->get("Successfully executed plugin").": ".$plugin_name);	
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

sub dialog_account_chooser_and_upload
{
	my ($file_to_upload) = @_;

	my $dialog_header = $d->get("Choose hosting-site and account");
 	my $hosting_dialog = Gtk2::Dialog->new ($dialog_header,
        						$window,
                              	[qw/modal destroy-with-parent/],
                              	'gtk-ok'     => 'accept',
                              	'gtk-cancel' => 'reject');

	$hosting_dialog->set_default_response ('accept');
	$hosting_dialog->set_size_request(300);

	my $model = Gtk2::ListStore->new ('Glib::String', 'Glib::String', 'Glib::String');
	foreach (keys %accounts){
			$model->set ($model->append, 0, $accounts{$_}->{'host'} , 1, $accounts{$_}->{'username'}, 2, $accounts{$_}->{'password'}) if($accounts{$_}->{'username'} ne "" && $accounts{$_}->{'password'} ne "");		
			$model->set ($model->append, 0, $accounts{$_}->{'host'} , 1, $d->get("Guest"), 2, "");	
	}
	
	my $hosting = Gtk2::ComboBox->new ($model);
	my $renderer_host = Gtk2::CellRendererText->new;
	$hosting->pack_start ($renderer_host, FALSE);
	$hosting->add_attribute ($renderer_host, text => 0);
	my $renderer_username = Gtk2::CellRendererText->new;
	$hosting->pack_start ($renderer_username, FALSE);
	$hosting->add_attribute ($renderer_username, text => 1);
	$hosting->set_active(0);
	
    $hosting_dialog->vbox->add ($hosting);
    $hosting_dialog->show_all;

	my $hosting_response = $hosting_dialog->run ;    
	if ($hosting_response eq "accept" ) {
		my $model = $hosting->get_model();
		my $hosting_iter = $hosting->get_active_iter();
		my $hosting_host = $model->get_value($hosting_iter, 0);
		my $hosting_username = $model->get_value($hosting_iter, 1);
		my $hosting_password = $model->get_value($hosting_iter, 2);		

		if($hosting_host eq "ubuntu-pics.de"){
			my %upload_response;
			%upload_response = &function_upload_ubuntu_pics(&function_switch_home_in_file($file_to_upload), $hosting_username, $hosting_password, $debug_cparam);	
			if (is_success($upload_response{'status'})){
				&dialog_upload_links_ubuntu_pics($hosting_host, $hosting_username, $upload_response{'thumb1'}, $upload_response{'thumb2'}, $upload_response{'bbcode'}, $upload_response{'ubuntucode'},$upload_response{'direct'}, $upload_response{'status'});				
				&dialog_status_message(1, $file_to_upload." ".$d->get("uploaded"));
			}else{
				&dialog_error_message($upload_response{'status'});	
			}
		}elsif($hosting_host eq "imagebanana.com"){
			my %upload_response;
			%upload_response = &function_upload_imagebanana(&function_switch_home_in_file($file_to_upload), $hosting_username, $hosting_password, $debug_cparam);	
			if (is_success($upload_response{'status'})){
				&dialog_upload_links_imagebanana($hosting_host, $hosting_username, $upload_response{'thumb1'}, $upload_response{'thumb2'}, $upload_response{'thumb3'}, $upload_response{'friends'}, $upload_response{'popup'}, $upload_response{'direct'}, $upload_response{'hotweb'}, $upload_response{'hotboard1'}, $upload_response{'hotboard2'}, $upload_response{'status'});				
				&dialog_status_message(1, $file_to_upload." ".$d->get("uploaded"));
			}else{
				&dialog_error_message($upload_response{'status'});	
			}					
		}		
		
		$hosting_dialog->destroy();		
		return TRUE;
	}else {
		$hosting_dialog->destroy() ;
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

sub dialog_upload_links_ubuntu_pics
{
	my ($host, $username, $thumb1, $thumb2, $bbcode, $ubuntucode, $direct, $status) = @_;
	my $dialog_header = $d->get("Upload")." - ".$host." - ".$username;
 	my $upload_dialog = Gtk2::Dialog->new ($dialog_header,
        						$window,
                              	[qw/modal destroy-with-parent/],
                              	'gtk-ok'     => 'accept');

	$upload_dialog->set_default_response ('accept');
	$upload_dialog->set_size_request(400, 400);

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
	my $entry_ubuntucode = Gtk2::Entry->new();
	my $entry_direct = Gtk2::Entry->new();

	my $label_thumb1 = Gtk2::Label->new();
	my $label_thumb2 = Gtk2::Label->new();
	my $label_bbcode = Gtk2::Label->new();
	my $label_ubuntucode = Gtk2::Label->new();
	my $label_direct = Gtk2::Label->new();

	$label_thumb1->set_text($d->get("Thumbnail for websites (with border)"));
	$label_thumb2->set_text($d->get("Thumbnail for websites (without border)"));
	$label_bbcode->set_text($d->get("Thumbnail for forums"));
	$label_ubuntucode->set_text($d->get("Thumbnail for Ubuntuusers.de forum"));
	$label_direct->set_text($d->get("Direct link"));

	$entry_thumb1->set_text($thumb1);
	$entry_thumb2->set_text($thumb2);
	$entry_bbcode->set_text($bbcode);
	$entry_ubuntucode->set_text($ubuntucode);
	$entry_direct->set_text($direct);

	$upload_vbox->pack_start($upload_hbox, TRUE, TRUE, 10);
	$upload_vbox->pack_start($label_thumb1, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_thumb1, TRUE, TRUE, 2);    
	$upload_vbox->pack_start($label_thumb2, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_thumb2, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_bbcode, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_bbcode, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_ubuntucode, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_ubuntucode, TRUE, TRUE, 2);
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

sub dialog_upload_links_imagebanana
{
	my ($host, $username, $thumb1, $thumb2, $thumb3, $friends, $popup, $direct, $hotweb, $hotboard1, $hotboard2, $status) = @_;
	my $dialog_header = $d->get("Upload")." - ".$host." - ".$username;
 	my $upload_dialog = Gtk2::Dialog->new ($dialog_header,
        						$window,
                              	[qw/modal destroy-with-parent/],
                              	'gtk-ok'     => 'accept');

	$upload_dialog->set_default_response ('accept');
	$upload_dialog->set_size_request(400, 600);

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
	my $entry_thumb3 = Gtk2::Entry->new();	
	my $entry_friends = Gtk2::Entry->new();
	my $entry_popup = Gtk2::Entry->new();
	my $entry_direct = Gtk2::Entry->new();
	my $entry_hotweb = Gtk2::Entry->new();
	my $entry_hotboard1 = Gtk2::Entry->new();
	my $entry_hotboard2 = Gtk2::Entry->new();

	my $label_thumb1 = Gtk2::Label->new();
	my $label_thumb2 = Gtk2::Label->new();
	my $label_thumb3 = Gtk2::Label->new();	
	my $label_friends = Gtk2::Label->new();
	my $label_popup = Gtk2::Label->new();
	my $label_direct = Gtk2::Label->new();
	my $label_hotweb = Gtk2::Label->new();
	my $label_hotboard1 = Gtk2::Label->new();
	my $label_hotboard2 = Gtk2::Label->new();

	$label_thumb1->set_text($d->get("Thumbnail for websites"));
	$label_thumb2->set_text($d->get("Thumbnail for boards (1)"));
	$label_thumb3->set_text($d->get("Thumbnail for boards (2)"));
	$label_friends->set_text($d->get("Show your friends"));	
	$label_popup->set_text($d->get("Popup for websites"));
	$label_direct->set_text($d->get("Direct link"));
	$label_hotweb->set_text($d->get("Hotlink for websites"));
	$label_hotboard1->set_text($d->get("Hotlink for boards (1)"));							
	$label_hotboard2->set_text($d->get("Hotlink for boards (2)"));	

	$entry_thumb1->set_text($thumb1);
	$entry_thumb2->set_text($thumb2);
	$entry_thumb3->set_text($thumb3);
	$entry_friends->set_text($friends);	
	$entry_popup->set_text($popup);
	$entry_direct->set_text($direct);
	$entry_hotweb->set_text($hotweb);
	$entry_hotboard1->set_text($hotboard1);							
	$entry_hotboard2->set_text($hotboard2);	

	$upload_vbox->pack_start($upload_hbox, TRUE, TRUE, 10);
	$upload_vbox->pack_start($label_thumb1, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_thumb1, TRUE, TRUE, 2);    
	$upload_vbox->pack_start($label_thumb2, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_thumb2, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_thumb3, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_thumb3, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_friends, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_friends, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_popup, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_popup, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_direct, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_direct, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_hotweb, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_hotweb, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_hotboard1, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_hotboard1, TRUE, TRUE, 2);
	$upload_vbox->pack_start($label_hotboard2, TRUE, TRUE, 2);
	$upload_vbox->pack_start($entry_hotboard2, TRUE, TRUE, 2);
    
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
	$session_start_screen{'first_page'}->{'statistics_counter'}->set_text(scalar(keys(%session_screens))." ".$d->nget("screenshot during this session", "screenshots during this session", scalar(keys(%session_screens))));
	my $total_size = 0;
	foreach (keys %session_screens){
		$total_size += $session_screens{$_}->{'size'};	
	}					
	$session_start_screen{'first_page'}->{'size_counter'}->set_text($d->get("Total size").": ".sprintf("%.2f", $total_size / 1024)." KB");
	if(keys(%session_screens) == 0){
		$session_start_screen{'first_page'}->{'btn_remove'}->set_sensitive(FALSE);
		$session_start_screen{'first_page'}->{'btn_delete'}->set_sensitive(FALSE);
		$session_start_screen{'first_page'}->{'btn_reopen'}->set_sensitive(FALSE);
		$session_start_screen{'first_page'}->{'btn_print'}->set_sensitive(FALSE);
	}else{
		$session_start_screen{'first_page'}->{'btn_remove'}->set_sensitive(TRUE);
		$session_start_screen{'first_page'}->{'btn_delete'}->set_sensitive(TRUE);
		$session_start_screen{'first_page'}->{'btn_reopen'}->set_sensitive(TRUE);
		$session_start_screen{'first_page'}->{'btn_print'}->set_sensitive(TRUE);
	}				
}

sub function_update_tab
{
	my ($key) = @_;
	$key =~ /\[(.*)\]/;

	#update fileinfos
	if(&function_create_thumbnail_and_fileinfos($session_screens{$key}->{'filename'}, $key)){

		#update tab icon - maybe pic changed due to use of plugin or drawing tool
		$session_screens{$key}->{'tab_icon'}->set_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size (&function_switch_home_in_file($session_screens{$key}->{'filename'}), Gtk2::IconSize->lookup ('menu')));
		$session_screens{$key}->{'image'}->set_from_pixbuf($session_screens{$key}->{'thumb'});
		$session_screens{$key}->{'filename_label'}->set_text($session_screens{$key}->{'short'});
		$session_screens{$key}->{'tooltip_filename_tab'}->set_tip($session_screens{$key}->{'filename_label'},$session_screens{$key}->{'filename'});
		$session_screens{$key}->{'mime_type_label'}->set_text($session_screens{$key}->{'mime_type'});
		$session_screens{$key}->{'size_label'}->set_text(sprintf("%.2f", $session_screens{$key}->{'size'} / 1024)." KB");
		$session_screens{$key}->{'geometry_label'}->set_text($session_screens{$key}->{'width'}."x".$session_screens{$key}->{'height'});

	}else{

		#update tab icon - file is not existing anymore, maybe deleted manually
		$session_screens{$key}->{'tab_icon'}->set_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size("$gscrot_path/share/gscrot/resources/icons/Image-missing.svg", Gtk2::IconSize->lookup ('menu')));	
		$session_screens{$key}->{'image'}->set_from_pixbuf (Gtk2::Gdk::Pixbuf->new_from_file_at_size("$gscrot_path/share/gscrot/resources/icons/Image-missing.svg", Gtk2::IconSize->lookup ('dialog')));
		$session_screens{$key}->{'filename_label'}->set_text("-");
		$session_screens{$key}->{'tooltip_filename_tab'}->set_tip($session_screens{$key}->{'filename_label'}, "-");
		$session_screens{$key}->{'mime_type_label'}->set_text("-");
		$session_screens{$key}->{'size_label'}->set_text("-");
		$session_screens{$key}->{'geometry_label'}->set_text("-");

		$session_screens{$key}->{'btn_delete'}->set_sensitive(0);
		$session_screens{$key}->{'btn_reopen'}->set_sensitive(0);
		$session_screens{$key}->{'btn_upload'}->set_sensitive(0);
		$session_screens{$key}->{'btn_print'}->set_sensitive(0);
		$session_screens{$key}->{'btn_rename'}->set_sensitive(0);
		$session_screens{$key}->{'btn_plugin'}->set_sensitive(0);
		$session_screens{$key}->{'btn_draw'}->set_sensitive(0);
		$session_screens{$key}->{'btn_clipboard'}->set_sensitive(0);
			
	}
	return 1;
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
		$image->Sample(width=>$1, height=>$2);
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
sub function_gscrot_area
{
	my ($folder, $filename_value, $filetype_value, $quality_value, $delay_value) = @_;
	
	#get basic infos
	my $screen = Gnome2::Wnck::Screen->get_default();
	my $root = Gtk2::Gdk->get_default_root_window;
	my $disp = Gtk2::Gdk::Display->get_default;
	my ($rootxp, $rootyp, $rootwidthp, $rootheightp) = $root->get_geometry;

	my $root_item = undef;
	my $cursor_item = undef;
	
	#define zoom window
	my $zoom_window = Gtk2::Window->new('toplevel');
	$zoom_window->set_decorated (0);
	$zoom_window->set_skip_taskbar_hint (1);
	$zoom_window->set_keep_above (1);
	my ($zoom_window_width, $zoom_window_height) = $zoom_window->get_size;
	my ($zoom_window_x, $zoom_window_y) = $zoom_window->get_position;
	my $zoom_window_init = TRUE;

	#pack canvas to a scrolled window
	my $scwin = Gtk2::ScrolledWindow->new();
	$scwin->set_size_request(100, 100);
	$scwin->set_policy('never','never');
	
	#define and setup the canvas
	my $canvas = Gnome2::Canvas->new();
	$canvas->modify_bg('normal',Gtk2::Gdk::Color->new (65535, 65535, 65535));
	$canvas->set_pixels_per_unit (5);
	$canvas->set_scroll_region(-10,-10,$rootwidthp+50,$rootheightp+50);
	my $canvas_root = $canvas->root();

	#do some packing
	$scwin->add($canvas);
	$zoom_window->add($scwin);
	$zoom_window->show_all();
	$zoom_window->move($rootxp, $rootyp);

	$root_item->destroy if defined($root_item);
	$root_item = Gnome2::Canvas::Item->new($canvas_root,
					   "Gnome2::Canvas::Pixbuf",
						x => 0,
						y => 0,
						pixbuf => Gtk2::Gdk::Pixbuf->get_from_drawable ($root, undef, 0, 0, 0, 0, $rootwidthp, $rootheightp),
					);

	#define gscrot cursor
	my $cursor_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file ("$gscrot_path/share/gscrot/resources/icons/gscrot_cursor.png");
	my $cursor = Gtk2::Gdk::Cursor->new_from_pixbuf (Gtk2::Gdk::Display->get_default, $cursor_pixbuf, 10, 10);

	#define graphics context
	my $white = Gtk2::Gdk::Color->new (65535, 65535, 65535);
	my $black = Gtk2::Gdk::Color->new (0, 0, 0);
	my $gc = Gtk2::Gdk::GC->new ($root, undef);
	$gc->set_line_attributes (1, 'double-dash', 'round', 'round');
	$gc->set_rgb_bg_color($black);
	$gc->set_rgb_fg_color($white);
	$gc->set_subwindow ('include-inferiors');
	$gc->set_function ('xor');

	#all screen events are send to gscrot			   
	Gtk2::Gdk->pointer_grab ($root, 0, [qw/
				   pointer-motion-mask
				   button-press-mask
				   button-motion-mask
				   button-release-mask/], undef, $cursor, Gtk2->get_current_event_time);

	Gtk2::Gdk->keyboard_grab($root,0,Gtk2->get_current_event_time); 


	if (Gtk2::Gdk->pointer_is_grabbed){
		my $done = 0;
		my $counter_outer = 0;
		my $counter_inner = 0;
		my $rx = 0;
		my $ry = 0; 
		my $rw = 0;
		my $rh = 0; 
		my $btn_pressed = 0;
		my $rect_x = 0; 
		my $rect_y = 0; 
		my $rect_w = 0; 
		my $rect_h = 0;
		my $rectangle = undef;
		my $last_selected_window = 0;
		my %smallest_coords = ();
		my $drawable = undef;


		while(1){
			while(!$done && Gtk2::Gdk->events_pending){
				my $event = $disp->get_event;
				next unless defined $event;

				#quit on escape	
				if($event->type eq 'key-press'){

					if($event->keyval == $Gtk2::Gdk::Keysyms{Escape}){
						if($rect_w > 1){
							#clear the last rectangle
							$root->draw_rectangle($gc, 0, $rect_x, $rect_y, $rect_w, $rect_h);
						}	
						$zoom_window->destroy;
						#ungrab pointer and keyboard
						Gtk2::Gdk->pointer_ungrab(Gtk2->get_current_event_time);
						Gtk2::Gdk->keyboard_ungrab(Gtk2->get_current_event_time); 
						return 5;	
					}
						
				}elsif($event->type eq 'button-release'){
					$done = 1;
					print "Type: ".$event->type."\n" if (defined $event && $debug_cparam);
					print "Trying to clear a rectangle ($rect_x, $rect_y, $rect_w, $rect_h)\n" if $debug_cparam;									
					
					#ungrab pointer and keyboard
					Gtk2::Gdk->pointer_ungrab(Gtk2->get_current_event_time);
					Gtk2::Gdk->keyboard_ungrab(Gtk2->get_current_event_time); 
					$zoom_window->destroy;
					
					if($rect_w > 1){
						#clear the last rectangle
						$root->draw_rectangle($gc, 0, $rect_x, $rect_y, $rect_w, $rect_h);
												
						#sleep if there is any delay
						sleep $delay_value;
						
						#get the pixbuf from drawable and save the file
						my $pixbuf = Gtk2::Gdk::Pixbuf->get_from_drawable ($root, undef, $rect_x, $rect_y, 0, 0, $rect_w, $rect_h);
						my $output = Image::Magick->new(magick=>'png');
						$output->BlobToImage( $pixbuf->save_to_buffer('png') );
						return $output;
											
					}else{
						return 0;	
					}
					
				}elsif($event->type eq 'button-press'){
					print "Type: ".$event->type."\n" if (defined $event && $debug_cparam);		
					$btn_pressed = 1;
					if (defined $smallest_coords{'last_win'}){
						$root->draw_rectangle($gc, 0, $smallest_coords{'last_win'}->{'x'}, $smallest_coords{'last_win'}->{'y'}, $smallest_coords{'last_win'}->{'width'}, $smallest_coords{'last_win'}->{'height'});       			
					}
					#rectangle starts here...
					$rx = $event->x;
					$ry = $event->y; 					

				}elsif($event->type eq 'motion-notify'){
					print "Type: ".$event->type."\n" if (defined $event && $debug_cparam);	

					#check pos and geometry of the zoom window and move it if needed
					($zoom_window_width, $zoom_window_height) = $zoom_window->get_size;
					($zoom_window_x, $zoom_window_y) = $zoom_window->get_position;							
					if((($event->x >= $zoom_window_x-150) && ($event->x <= ($zoom_window_x+$zoom_window_width+150))) && (($event->y >= $zoom_window_y-150) && ($event->y <= ($zoom_window_y+$zoom_window_height+150)))){
						if($zoom_window_init){
							$zoom_window->move($rootxp, $rootyp);
							$zoom_window_init = FALSE;					
						}else{
							$zoom_window->move(0, $rootheightp-$zoom_window_height);
							$zoom_window_init = TRUE;	
						}
					}

					#draw cursor on the canvas...
					$cursor_item->destroy if defined($cursor_item);
					$cursor_item = Gnome2::Canvas::Item->new($canvas_root,
									   "Gnome2::Canvas::Pixbuf",
										x => $event->x-10,
										y => $event->y-10,
										pixbuf => $cursor_pixbuf,
									);	
					
					#...scroll to centered position (*5 because of zoom factor)
					$canvas->scroll_to ($event->x*5, $event->y*5);
					
					#...finally update canvas
					$canvas->update_now;
		
				
					if($btn_pressed){
						#redras last rect to clear it
						if ($rect_w > 0) {
							print "Trying to clear a rectangle ($rect_x, $rect_y, $rect_w, $rect_h)\n" if $debug_cparam;						
							$root->draw_rectangle($gc, 0, $rect_x, $rect_y, $rect_w, $rect_h);
							#~ Gtk2::Gdk->flush;
					  	}
						$rect_x = $rx;
						$rect_y = $ry;
						$rect_w = $event->x - $rect_x;
						$rect_h = $event->y - $rect_y;											
		
						if ($rect_w < 0) {
						  $rect_x += $rect_w;
						  $rect_w = 0 - $rect_w;
						}
						if ($rect_h < 0) {
						  $rect_y += $rect_h;
						  $rect_h = 0 - $rect_h;
						}
					
						#draw new rect to the root window
						if($rect_w != 0){
							print "Trying to draw a rectangle ($rect_x, $rect_y, $rect_w, $rect_h)\n" if $debug_cparam;
							$root->draw_rectangle($gc, 0, $rect_x, $rect_y, $rect_w, $rect_h);
							#~ Gtk2::Gdk->flush;		
						}			
					}
				}			
			}
			#exit loop if drawing finished
			last if $done;
		}				 
	}	
	return 0;	
	#ungrab pointer and keyboard
	Gtk2::Gdk->pointer_ungrab(Gtk2->get_current_event_time);
	Gtk2::Gdk->keyboard_ungrab(Gtk2->get_current_event_time); 
	$zoom_window->destroy if defined $zoom_window;
}

sub function_gscrot_window
{
	my ($folder, $filename_value, $filetype_value, $quality_value, $delay_value, $border) = @_;
	
	#get basic infos
	my $screen = Gnome2::Wnck::Screen->get_default;
	$screen->force_update;
	my @windows = $screen->get_windows;
	my $root = Gtk2::Gdk->get_default_root_window;
	my $disp = Gtk2::Gdk::Display->get_default;
	my ($rootxp, $rootyp, $rootwidthp, $rootheightp) = $root->get_geometry;

	#define gscrot cursor
	my $cursor_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file ("$gscrot_path/share/gscrot/resources/icons/gscrot_cursor.png");
	my $cursor = Gtk2::Gdk::Cursor->new_from_pixbuf (Gtk2::Gdk::Display->get_default, $cursor_pixbuf, 10, 10);

	#define graphics context
	my $white = Gtk2::Gdk::Color->new (65535, 65535, 65535);
	my $black = Gtk2::Gdk::Color->new (0, 0, 0);
	my $gc = Gtk2::Gdk::GC->new ($root, undef);
	$gc->set_line_attributes (5, 'solid', 'round', 'round');
	$gc->set_rgb_bg_color($black);
	$gc->set_rgb_fg_color($white);
	$gc->set_subwindow ('include-inferiors');
	$gc->set_function ('xor');

	#all screen events are send to gscrot			   
	Gtk2::Gdk->pointer_grab ($root, 0, [qw/
				   pointer-motion-mask
				   button-release-mask/], undef, $cursor, Gtk2->get_current_event_time);

	Gtk2::Gdk->keyboard_grab($root,0,Gtk2->get_current_event_time); 


	if (Gtk2::Gdk->pointer_is_grabbed){
		my $done = 0;
		my $rect_x = 0; 
		my $rect_y = 0; 
		my $rect_w = 0; 
		my $rect_h = 0;
		my $rectangle = undef;
		my $last_selected_window = 0;
		my %smallest_coords = ();
		my $drawable = undef;


		while(1){
			while(!$done && Gtk2::Gdk->events_pending){
				my $event = $disp->get_event;
				next unless defined $event;
				
				#handle key events here
				if($event->type eq 'key-press'){
					next unless defined $event->keyval;
					if($event->keyval == $Gtk2::Gdk::Keysyms{Escape}){
						#clear the last rectangle
						if (defined $smallest_coords{'last_win'}){
							$root->draw_rectangle($gc, 0, $smallest_coords{'last_win'}->{'x'}, $smallest_coords{'last_win'}->{'y'}, $smallest_coords{'last_win'}->{'width'}, $smallest_coords{'last_win'}->{'height'});       			
						}
						#ungrab pointer and keyboard
						Gtk2::Gdk->pointer_ungrab(Gtk2->get_current_event_time);
						Gtk2::Gdk->keyboard_ungrab(Gtk2->get_current_event_time); 
						return 5;	
					}
						
				}elsif($event->type eq 'button-release'){
					$done = 1;
					print "Type: ".$event->type."\n" if (defined $event && $debug_cparam);
					print "Trying to clear a rectangle ($rect_x, $rect_y, $rect_w, $rect_h)\n" if $debug_cparam;									
				
					#ungrab pointer and keyboard
					Gtk2::Gdk->pointer_ungrab(Gtk2->get_current_event_time);
					Gtk2::Gdk->keyboard_ungrab(Gtk2->get_current_event_time); 

					#clear the last rectangle
					if (defined $smallest_coords{'last_win'}){
						#focus selected window (maybe it is hidden)
						$smallest_coords{'last_win'}->{'gdk_window'}->focus(time);
						Gtk2::Gdk->flush;
						sleep 1;

						$root->draw_rectangle($gc, 0, $smallest_coords{'last_win'}->{'x'}, $smallest_coords{'last_win'}->{'y'}, $smallest_coords{'last_win'}->{'width'}, $smallest_coords{'last_win'}->{'height'});       			
																			
						#sleep if there is any delay
						sleep $delay_value;
					
						#get the pixbuf from drawable and save the file
						my $pixbuf = Gtk2::Gdk::Pixbuf->get_from_drawable ($root, undef, $smallest_coords{'curr_win'}->{'x'}, $smallest_coords{'curr_win'}->{'y'}, 0, 0, $smallest_coords{'curr_win'}->{'width'}, $smallest_coords{'curr_win'}->{'height'});
						my $output = Image::Magick->new(magick=>'png');
						$output->BlobToImage( $pixbuf->save_to_buffer('png') );
						return $output;
					}else{
						return 0;	
					}

				}elsif($event->type eq 'motion-notify'){
					print "Type: ".$event->type."\n" if (defined $event && $debug_cparam);	
								
					my $min_x = $screen->get_width; 
					my $min_y = $screen->get_height;
										
					print "Searching for window...\n" if $debug_cparam;
					foreach my $curr_window(@windows){
						$drawable = Gtk2::Gdk::Window->foreign_new ($curr_window->get_xid);					
						#do not detect gscrot window when it is hidden
						next if ($curr_window->get_xid == $window->window->get_xid && $is_in_tray);
						if($curr_window->is_visible_on_workspace ($screen->get_active_workspace)){
							my ($xp, $yp, $widthp, $heightp) = (0, 0, 0, 0);
							if ($border){
								($xp, $yp, $widthp, $heightp) = $curr_window->get_geometry;	
							}else{
								($xp, $yp, $widthp, $heightp) = $curr_window->get_client_window_geometry;	
							}						
							print "Current Event x: ".$event->x.", y: ".$event->y."\n" if $debug_cparam;
							if((($event->x >= $xp) && ($event->x <= ($xp+$widthp))) && (($event->y >= $yp) && ($event->y <= ($yp+$heightp)))){
								if(($xp+$widthp <= $min_x) && ($yp+$heightp <= $min_y)){
									print "X: $xp, Y: $yp, Width: $widthp, Height: $heightp\n" if $debug_cparam;
									$smallest_coords{'curr_win'}->{'window'} = $curr_window;
									$smallest_coords{'curr_win'}->{'gdk_window'} = $drawable;
									$smallest_coords{'curr_win'}->{'x'} = $xp;
									$smallest_coords{'curr_win'}->{'y'} = $yp;
									$smallest_coords{'curr_win'}->{'width'} = $widthp;
									$smallest_coords{'curr_win'}->{'height'} = $heightp;
									$min_x = $xp+$widthp;
									$min_y = $yp+$heightp;	
								}
							}					
						}
					}
					
					if (defined $smallest_coords{'curr_win'}){

						print "Currently smallest window: ".$smallest_coords{'curr_win'}->{'window'}->get_name."\n" if $debug_cparam;
						print "X: $smallest_coords{'curr_win'}->{'x'}, Y: $smallest_coords{'curr_win'}->{'y'}, Width: $smallest_coords{'curr_win'}->{'width'}, Height: $smallest_coords{'curr_win'}->{'height'}\n" if $debug_cparam;
						if($last_selected_window ne $smallest_coords{'curr_win'}->{'window'}->get_xid){	
			
							#clear last rectangle
							if (defined $smallest_coords{'last_win'}){
								$root->draw_rectangle($gc, 0, $smallest_coords{'last_win'}->{'x'}, $smallest_coords{'last_win'}->{'y'}, $smallest_coords{'last_win'}->{'width'}, $smallest_coords{'last_win'}->{'height'});
							}
														
							#draw new rectangle for current window
							$root->draw_rectangle($gc, 0, $smallest_coords{'curr_win'}->{'x'}-3, $smallest_coords{'curr_win'}->{'y'}-3, $smallest_coords{'curr_win'}->{'width'}+5, $smallest_coords{'curr_win'}->{'height'}+5);							
							$last_selected_window = $smallest_coords{'curr_win'}->{'window'}->get_xid;
							$smallest_coords{'last_win'}->{'window'} = $smallest_coords{'curr_win'}->{'window'};
							$smallest_coords{'last_win'}->{'gdk_window'} = $smallest_coords{'curr_win'}->{'gdk_window'};
							$smallest_coords{'last_win'}->{'x'} = $smallest_coords{'curr_win'}->{'x'}-3;
							$smallest_coords{'last_win'}->{'y'} = $smallest_coords{'curr_win'}->{'y'}-3;
							$smallest_coords{'last_win'}->{'width'} = $smallest_coords{'curr_win'}->{'width'}+5;
							$smallest_coords{'last_win'}->{'height'} = $smallest_coords{'curr_win'}->{'height'}+5;															
							
						}						
					}
				}			
			}
			#exit loop if drawing finished
			last if $done;
		}				 
	}
	
	#ungrab pointer and keyboard
	Gtk2::Gdk->pointer_ungrab(Gtk2->get_current_event_time);
	Gtk2::Gdk->keyboard_ungrab(Gtk2->get_current_event_time); 		
	return 0;	
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

sub function_die_with_action {
   my ($action) = @_;
   die("An error occured while $action.\n");
}

sub function_create_thumbnail_and_fileinfos {
	my ($filename, $key) = @_;
	return 0 unless &function_file_exists($filename);
	
	$filename = &function_switch_home_in_file($filename);	
	my $uri = Gnome2::VFS->get_uri_from_local_path ($filename);
	my $mime_type = Gnome2::VFS->get_mime_type ($uri);
	print "Uri: $uri - Mime-Type: $mime_type\n" if $debug_cparam;
	my $thumbnailfactory = Gnome2::ThumbnailFactory->new ('normal');
	if ($thumbnailfactory->can_thumbnail ($uri, $mime_type, time)){
		my $thumb = $thumbnailfactory->generate_thumbnail ($uri, $mime_type);
		$session_screens{$key}->{'thumb'} = $thumb;			
		$session_screens{$key}->{'mime_type'} = $mime_type;
		$session_screens{$key}->{'width'} = &function_imagemagick_perform("get_width", $filename, 0, "");
		$session_screens{$key}->{'height'} = &function_imagemagick_perform("get_height", $filename, 0, "");	
		$session_screens{$key}->{'size'} = -s $filename;
		#short filename
		$session_screens{$key}->{'short'} = $filename;	
		$session_screens{$key}->{'short'} =~ s{^.*/}{};		
		#store the filetype of the current screenshot for further processing
		$filename =~ /.*\.(.*)$/;
		$session_screens{$key}->{'filetype'} = $1;						
	}
	return 1;
}

sub function_iter_programs
{
	my ($model, $path, $iter, $search_for) = @_;
	my $progname_value = $model->get_value($iter, 2);
	return FALSE if $search_for ne $progname_value;
	$progname->set_active_iter($iter);
	return TRUE;
}



#################### MY FUNCTIONS  ################################
