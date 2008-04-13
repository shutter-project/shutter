#! /usr/bin/perl
use strict;
use warnings;

#Copyright (C) 2008  Mi, 09 Apr 2008 22:58:09 +0200 

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

use Glib qw/TRUE FALSE/;
use Gtk2 '-init';
use Gtk2::TrayIcon;
use Gtk2::Gdk::Keysyms;

my $gscrot_name = "GScrot";
my $gscrot_version = "v0.34";

#command line parameter
my $debug_cparam = FALSE;
my @args = @ARGV;

&init_gscrot();

my $is_in_tray = FALSE;

my $window = Gtk2::Window->new();

$window->set_title($gscrot_name." ".$gscrot_version);
$window->set_default_icon_from_file ("../share/pixmaps/gscrot.svg");
$window->signal_connect(delete_event => \&delete_event);
$window->set_border_width(0);

#hash of screenshots during session	
my %session_screens;
my $notebook = Gtk2::Notebook->new;
$notebook->popup_enable;
$notebook->set_scrollable(TRUE);
$notebook->signal_connect('switch-page' => \&notebook_switch, 'tab-switched');
my $first_page = $notebook->append_page (create_text ("", TRUE),
Gtk2::Label->new("Alle"));

#Clipboard
my $clipboard = Gtk2::Clipboard->get(Gtk2::Gdk->SELECTION_CLIPBOARD);


my $accel_group = Gtk2::AccelGroup->new;
$window->add_accel_group($accel_group);

my $statusbar = Gtk2::Statusbar->new;

my $vbox = Gtk2::VBox->new(FALSE, 10);
my $vbox_inner = Gtk2::VBox->new(FALSE, 10);
my $file_vbox = Gtk2::VBox->new(FALSE, 0);
my $save_vbox = Gtk2::VBox->new(FALSE, 0);
my $extras_vbox = Gtk2::VBox->new(FALSE, 0);

my $button_box = Gtk2::HBox->new(TRUE, 10);
my $scale_box = Gtk2::HBox->new(TRUE, 0);
my $delay_box = Gtk2::HBox->new(TRUE, 0);
my $delay_box2 = Gtk2::HBox->new(FALSE, 0);
my $thumbnail_box = Gtk2::HBox->new(TRUE, 0);
my $thumbnail_box2 = Gtk2::HBox->new(FALSE, 0);
my $filename_box = Gtk2::HBox->new(TRUE, 0);
my $progname_box = Gtk2::HBox->new(TRUE, 0);
my $progname_box2 = Gtk2::HBox->new(FALSE, 0);
my $filetype_box = Gtk2::HBox->new(TRUE, 0);
my $saveDir_box = Gtk2::HBox->new(TRUE, 0);
my $border_box = Gtk2::HBox->new(TRUE, 0);

$window->add($vbox);

#############MENU###################
my $menubar = Gtk2::MenuBar->new() ;

my $menu1= Gtk2::Menu->new() ;

my $menuitem_file = Gtk2::MenuItem->new_with_mnemonic("_Datei" ) ;

my $menuitem_revert = Gtk2::ImageMenuItem->new_with_mnemonic("_Einstellungen zurücksetzen" ) ;
$menuitem_revert->set_image(Gtk2::Image->new_from_icon_name('gtk-revert-to-saved-ltr', 'menu'));
$menuitem_revert->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ Z }, qw/control-mask/, qw/visible/);
$menu1->append($menuitem_revert) ;
$menuitem_revert->signal_connect("activate" , \&settings_event , 'menu_revert') ;

my $menuitem_save = Gtk2::ImageMenuItem->new_with_mnemonic("_Einstellungen speichern" ) ;
$menuitem_save->set_image(Gtk2::Image->new_from_icon_name('gtk-save', 'menu'));
$menuitem_save->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ S }, qw/control-mask/, qw/visible/);
$menu1->append($menuitem_save) ;
$menuitem_save->signal_connect("activate" , \&settings_event , 'menu_save') ;

my $separator_menu1 = Gtk2::SeparatorMenuItem->new();
$menu1->append($separator_menu1);

my $menuitem_quit = Gtk2::ImageMenuItem->new_with_mnemonic("_Beenden" ) ;
$menuitem_quit->set_image(Gtk2::Image->new_from_icon_name('gtk-quit', 'menu'));
$menuitem_quit->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ Q }, qw/control-mask/, qw/visible/);
$menu1->append($menuitem_quit) ;
$menuitem_quit->signal_connect("activate" , \&delete_event , 'menu_quit') ;

$menuitem_file->set_submenu($menu1);
$menubar->append($menuitem_file) ;

my $menu2 = Gtk2::Menu->new() ;

my $menuitem_about = Gtk2::ImageMenuItem->new_with_mnemonic("_Info") ;
$menuitem_about->set_image(Gtk2::Image->new_from_icon_name('gtk-about', 'menu'));
$menuitem_about->add_accelerator ("activate", $accel_group, $Gtk2::Gdk::Keysyms{ I }, qw/control-mask/, qw/visible/);
$menu2->append($menuitem_about) ;
$menuitem_about->signal_connect("activate" , \&on_about, $window) ;

my $menuitem_help = Gtk2::MenuItem->new_with_mnemonic("_Hilfe" ) ;

$menuitem_help->set_submenu($menu2) ;
$menubar->append($menuitem_help) ; 

$vbox->pack_start($menubar, FALSE, FALSE, 0);


#############MENU###################



#############BUTTON_SELECT###################
my $button_select = Gtk2::Button->new("Aufnahme\nmit Auswahl");
$button_select->signal_connect(clicked => \&callback_function, 'select');

my $image = Gtk2::Image->new_from_icon_name ('gtk-cut', 'button');
$button_select->set_image($image);

my $tooltip_select = Gtk2::Tooltips->new;
$tooltip_select->set_tip($button_select,"Ziehen Sie mit der linken Maustaste\nein Rechteck des gewünschten Bildbereiches\noder klicken Sie ein Fenster an, um dessen Inhalt aufzunehmen");


$button_box->pack_start($button_select, TRUE, TRUE, 0);

#############BUTTON_SELECT###################


#############BUTTON_RAW######################
my $button_raw = Gtk2::Button->new("Aufnahme");
$button_raw->signal_connect(clicked => \&callback_function, 'raw');

$image = Gtk2::Image->new_from_icon_name ('gtk-fullscreen', 'button');
$button_raw->set_image($image);

my $tooltip_raw = Gtk2::Tooltips->new;
$tooltip_raw->set_tip($button_raw,"Erzeugt ein Bildschirmfoto des gesamten Desktops");

$button_box->pack_start($button_raw, TRUE, TRUE, 0);

#############BUTTON_RAW######################

$vbox_inner->pack_start($button_box, FALSE, FALSE, 0);


#############TRAYICON######################
my $icon = Gtk2::Image->new_from_file("../share/gscrot/resources/icons/gscrot.png");
my $eventbox = Gtk2::EventBox->new;
$eventbox->add($icon);
my $tray = Gtk2::TrayIcon->new('Test');
$tray->add($eventbox);

#tooltip
my $tooltip_tray = Gtk2::Tooltips->new;
$tooltip_tray->set_tip($tray, $gscrot_name." ".$gscrot_version);

#events and timeouts
$eventbox->signal_connect('button_release_event', \&show_icon_menu);
#show tray
$tray->show_all;
#############TRAYICON######################


#############SETTINGS######################
my $file_frame = Gtk2::Frame->new("Dateityp");
my $save_frame = Gtk2::Frame->new("Speichern");
my $extras_frame = Gtk2::Frame->new("Extras");

my $scale_label = Gtk2::Label->new;
$scale_label->set_text("Qualität");


my $scale = Gtk2::HScale->new_with_range(1, 100, 1);
$scale->signal_connect('value-changed' => \&callback_function, 'quality_changed');
$scale->set_value_pos('right');
$scale->set_value(75);

my $tooltip_quality = Gtk2::Tooltips->new;
$tooltip_quality->set_tip($scale,"Bildqualität/Kompression:\nEin hoher Wert führt zu einer hohen Dateigröße / hohen Kompression (abhängig vom gewählten Dateityp)");
$tooltip_quality->set_tip($scale_label,"Bildqualität/Kompression:\nEin hoher Wert führt zu einer hohen Dateigröße / hohen Kompression (abhängig vom gewählten Dateityp)");
$scale_box->pack_start($scale_label, FALSE, TRUE, 10);
$scale_box->pack_start($scale, TRUE, TRUE, 10);

#delay
my $delay_label = Gtk2::Label->new;
$delay_label->set_text("Verzögerung");


my $delay = Gtk2::HScale->new_with_range(1, 10, 1);
$delay->signal_connect('value-changed' => \&callback_function, 'delay_changed');
$delay->set_value_pos('right');
$delay->set_value(0);

my $delay_active = Gtk2::CheckButton->new;
$delay_active->signal_connect('toggled' => \&callback_function, 'delay_toggled');
$delay_active->set_active(TRUE);
$delay_active->set_active(FALSE);

my $tooltip_delay = Gtk2::Tooltips->new;
$tooltip_delay->set_tip($delay,"Verzögert die Aufnahme\num n Sekunden");
$tooltip_delay->set_tip($delay_label,"Verzögert die Aufnahme\num n Sekunden");

$delay_box->pack_start($delay_label, FALSE, TRUE, 10);
$delay_box2->pack_start($delay_active, FALSE, FALSE, 0);
$delay_box2->pack_start($delay, TRUE, TRUE, 0);
$delay_box->pack_start($delay_box2, TRUE, TRUE, 10);

#end - delay

#thumbnail
my $thumbnail_label = Gtk2::Label->new;
$thumbnail_label->set_text("Thumbnail");


my $thumbnail = Gtk2::HScale->new_with_range(1, 100, 1);
$thumbnail->signal_connect('value-changed' => \&callback_function, 'thumbnail_changed');
$thumbnail->set_value_pos('right');
$thumbnail->set_value(50);

my $thumbnail_active = Gtk2::CheckButton->new;
$thumbnail_active->signal_connect('toggled' => \&callback_function, 'thumbnail_toggled');
$thumbnail_active->set_active(TRUE);
$thumbnail_active->set_active(FALSE);

my $tooltip_thumb = Gtk2::Tooltips->new;
$tooltip_thumb->set_tip($thumbnail,"Erzeugt einen Thumbnail im gleichen\nVerzeichnis mit der Größe n %");
$tooltip_thumb->set_tip($thumbnail_active,"Erzeugt einen Thumbnail im gleichen\nVerzeichnis mit der Größe n %");
$tooltip_thumb->set_tip($thumbnail_label,"Erzeugt einen Thumbnail im gleichen\nVerzeichnis mit der Größe n %");

$thumbnail_box->pack_start($thumbnail_label, FALSE, TRUE, 10);
$thumbnail_box2->pack_start($thumbnail_active, FALSE, FALSE, 0);
$thumbnail_box2->pack_start($thumbnail, TRUE, TRUE, 0);
$thumbnail_box->pack_start($thumbnail_box2, TRUE, TRUE, 10);

#end - thumbnail


#filename
my $filename = Gtk2::Entry->new;
$filename->set_text("\%Y-\%m-\%d-\%T_\$wx\$h");
$filename->signal_connect('move-cursor' => \&callback_function, 'cursor_moved');

my $filename_label = Gtk2::Label->new;
$filename_label->set_text("Dateiname");


my $tooltip_filename = Gtk2::Tooltips->new;
$tooltip_filename->set_tip($filename,"Geben Sie einen Dateinamen an");
$tooltip_filename->set_tip($filename_label,"Geben Sie einen Dateinamen an");

$filename_box->pack_start($filename_label, FALSE, TRUE, 10);
$filename_box->pack_start($filename, TRUE, TRUE, 10);
#end - filename

#type
my $combobox_type = Gtk2::ComboBox->new_text;
$combobox_type->insert_text (0, "jpeg");
$combobox_type->insert_text (1, "png");
$combobox_type->signal_connect('changed' => \&callback_function, 'type_changed');
$combobox_type->set_active (1);

my $filetype_label = Gtk2::Label->new;
$filetype_label->set_text("Dateityp");

my $tooltip_filetype = Gtk2::Tooltips->new;
$tooltip_filetype->set_tip($combobox_type,"Wählen Sie ein Dateiformat");
$tooltip_filetype->set_tip($filetype_label,"Wählen Sie ein Dateiformat");

$filetype_box->pack_start($filetype_label, FALSE, TRUE, 10);
$filetype_box->pack_start($combobox_type, TRUE, TRUE, 10);
#end - filetype


#saveDir
my $saveDir_label = Gtk2::Label->new;
$saveDir_label->set_text("Verzeichnis");

my $saveDir_button = Gtk2::FileChooserButton->new ('gscrot - Select a folder', 'select-folder');

my $tooltip_saveDir = Gtk2::Tooltips->new;
$tooltip_saveDir->set_tip($saveDir_button,"Wählen Sie ein Verzeichnis\nzum Speichern Ihrer Bildschirmaufnahmen");
$tooltip_saveDir->set_tip($saveDir_label,"Wählen Sie ein Verzeichnis\nzum Speichern Ihrer Bildschirmaufnahmen");

$saveDir_box->pack_start($saveDir_label, FALSE, TRUE, 10);
$saveDir_box->pack_start($saveDir_button, TRUE, TRUE, 10);
#end - saveDir

#program
my $progname = Gtk2::Entry->new;
$progname->set_text("gthumb");

my $progname_active = Gtk2::CheckButton->new;
$progname_active->signal_connect('toggled' => \&callback_function, 'progname_toggled');
$progname_active->set_active($progname_active);

my $progname_label = Gtk2::Label->new;
$progname_label->set_text("Öffnen mit");

my $tooltip_progname = Gtk2::Tooltips->new;
$tooltip_progname->set_tip($progname,"Öffne das Bildschirmfoto\nnach der Aufnahme mit diesem Programm");
$tooltip_progname->set_tip($progname_active,"Öffne das Bildschirmfoto\nnach der Aufnahme mit diesem Programm");
$tooltip_progname->set_tip($progname_label,"Öffne das Bildschirmfoto\nnach der Aufnahme mit diesem Programm");

$progname_box->pack_start($progname_label, TRUE, TRUE, 10);
$progname_box2->pack_start($progname_active, TRUE, TRUE, 0);
$progname_box2->pack_start($progname, TRUE, TRUE, 0);
$progname_box->pack_start($progname_box2, TRUE, TRUE, 10);
#end - program

#border
my $combobox_border = Gtk2::ComboBox->new_text;
$combobox_border->insert_text (1, "aktivieren");
$combobox_border->insert_text (0, "deaktivieren");
$combobox_border->signal_connect('changed' => \&callback_function, 'border_changed');
$combobox_border->set_active (0);

my $border_label = Gtk2::Label->new;
$border_label->set_text("Fensterrahmen");
$border_label->set_justify('left');

my $tooltip_border = Gtk2::Tooltips->new;
$tooltip_border->set_tip($combobox_border,"Fensterrahmen mit aufnehmen,\nwenn ein bestimmtes Fenster selektiert wird\n(Nur bei Aufnahme mit Auswahl)\nParameter bei der Verwendung von Compiz nicht notwendig");
$tooltip_border->set_tip($border_label,"Fensterrahmen mit aufnehmen,\nwenn ein bestimmtes Fenster selektiert wird\n(Nur bei Aufnahme mit Auswahl)\nParameter bei der Verwendung von Compiz nicht notwendig");

$border_box->pack_start($border_label, FALSE, TRUE, 10);
$border_box->pack_start($combobox_border, TRUE, TRUE, 10);
#end - border
#############SETTINGS######################


#############PACKING######################
$file_vbox->pack_start($scale_box, TRUE, TRUE, 1);
$file_vbox->pack_start($filetype_box, TRUE, TRUE, 1);
$file_frame->add($file_vbox);

$save_vbox->pack_start($filename_box, TRUE, TRUE, 1);
$save_vbox->pack_start($saveDir_box, TRUE, TRUE, 1);
$save_frame->add($save_vbox);

$extras_vbox->pack_start($progname_box, TRUE, TRUE, 1);
$extras_vbox->pack_start($delay_box, TRUE, TRUE, 1);
$extras_vbox->pack_start($thumbnail_box, TRUE, TRUE, 1);
$extras_vbox->pack_start($border_box, TRUE, TRUE, 1);
$extras_frame->add($extras_vbox);

$vbox_inner->pack_start($file_frame, TRUE, TRUE, 1);
$vbox_inner->pack_start($save_frame, TRUE, TRUE, 1);
$vbox_inner->pack_start($extras_frame, TRUE, TRUE, 1);
$vbox_inner->pack_start($notebook, TRUE, TRUE, 1);
$vbox_inner->set_border_width(10);

$vbox->pack_start($vbox_inner, TRUE, TRUE, 1);
$vbox->pack_start($statusbar, FALSE, FALSE, 1);
#############PACKING######################


$window->show_all;


#load saved settings
	&load_settings if(-e "$ENV{ HOME }/.gscrot" && -r "$ENV{ HOME }/.gscrot");

#GTK2 Main Loop
Gtk2->main;

0;


#initialize gscrot, check dependencies
sub init_gscrot()
{

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
		print "SUCCESS: gtklp is installed on your system!\n";
	}else{
		die "ERROR: dependency is missing --> gtklp is not installed on your system!\n";
	}

	#are there any command line params?
	if(@ARGV > 0){
		print "INFO: reading command line parameters...\n";
		my $arg;	
		foreach $arg (@args){
			if($arg eq "--debug"){
				$debug_cparam = TRUE;
				print "\ncommand ".$arg." recognized\n";
			}else{
				print "\ncommand ".$arg." not recognized --> will be ignored\n";		
			}			
		}
	}

}

#nearly all events are handled here
sub callback_function
{
	my ($widget, $data) = @_;
	my $quality_value = undef;
	my $delay_value = undef;
	my $thumbnail_value = undef;
	my $progname_value = undef;
	my $filename_value = undef;
	my $filetype_value = undef;
	my $border_value = "";
	my $folder = undef;

	my $thumbnail_param = "";	
	my $echo_cmd = "-e 'echo \$f'";
	my $scrot_feedback = "";

	if($debug_cparam){
		print "\n$data was emitted by widget $widget\n";
	}
	
#checkbox for "open with" -> entry active/inactive
	if($data eq "progname_toggled"){
		if($progname_active->get_active){
			$progname->set_editable(TRUE);
			$progname->set_sensitive(TRUE);			
		}else{
			$progname->set_editable(FALSE);
			$progname->set_sensitive(FALSE);
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
			$scale_label->set_text("Qualität");			
		}elsif($filetype_value eq "png"){
			$scale->set_range(0,9);				
			$scale->set_value(9);
			$scale_label->set_text("Kompression");					
		}

	}
	 
#capture desktop was chosen	
	if($data eq "raw" || $data eq "select" || $data eq "tray_raw" || $data eq "tray_select"){
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
		$progname_value = $progname->get_text();
		$filetype_value = $combobox_type->get_active_text();		
		$folder = $saveDir_button->get_filename();
		
		if($delay_value == 0 && $data eq "tray_raw"){
			$delay_value = 1;
		}


		if($data eq "raw" || $data eq "tray_raw"){
			$scrot_feedback=`scrot '$folder/$filename_value.$filetype_value' -q $quality_value -d $delay_value $border_value $thumbnail_param $echo_cmd`;
		}else{
			$scrot_feedback=`scrot '$folder/$filename_value.$filetype_value' --select -q $quality_value -d $delay_value $border_value $thumbnail_param $echo_cmd`;
		}

		chomp($scrot_feedback);	
		if (-f $scrot_feedback){
			$scrot_feedback =~ s/$ENV{ HOME }/~/; #switch /home/username in path to ~ 
			print "screenshot successfully saved to $scrot_feedback!\n" if $debug_cparam;
			&status_message(1, "$scrot_feedback gespeichert!");
			#append a page to notebook using with label == filename
			my ($second, $minute, $hour) = localtime();
			my $theTime = "$hour:$minute:$second";
			my $n_pages = $notebook->get_n_pages(); 
			my $theTimeKey = "[$n_pages] - $theTime";
			#build hash of screenshots during session	
			$session_screens{$theTimeKey} = $scrot_feedback;
			#and append page with label == key			
			my $new_index = $notebook->append_page (create_text ($theTimeKey, FALSE), Gtk2::Label->new($theTimeKey));
			$window->show_all unless $is_in_tray;				
			my $current_tab = $notebook->get_current_page+1;
			print "new tab $new_index created, $n_pages tabs overall, current tab is $current_tab\n" if $debug_cparam;
			$notebook->set_current_page($new_index);
	
		}else{
			&error_message("Datei konnte nicht gespeichert werden\n$scrot_feedback");
			print "screenshot could not be saved\n$scrot_feedback!" if $debug_cparam;
			&status_message(1, "Error --> Datei $scrot_feedback konnte nicht gespeichert werden!");
		} 
					
		if($progname_active->get_active){		
			$progname_value = $progname->get_text();
			system("$progname_value $scrot_feedback &"); #open picture in external program
		}

		
				
	}

	#close about box
	if($data eq "cancel"){
		$widget->destroy();	
	}

}

sub file_exists
{
	my ($filename) = @_;
	$filename = &switch_home_in_file($filename); 
	return TRUE if (-e $filename);
	return FALSE;
}

sub switch_home_in_file
{
	my ($filename) = @_ ;
	$filename =~ s/^~/$ENV{ HOME }/; #switch ~ in path to /home/username
	return $filename; 
}
sub status_message
{
	my ($index, $status_text) = @_;
	$statusbar->push ($index, $status_text);
}

sub error_message
{
	
	my ($error_message) = @_;

	my $error_dialog = Gtk2::MessageDialog->new ($window,
	[qw/modal destroy-with-parent/],
	'error' ,
	'ok' ,
	$error_message) ;
	my $error_response = $error_dialog->run ;	
	$error_dialog->destroy() if($error_response eq "ok");
	return TRUE;
}

#info messages
sub question_message
{
	my ($question_message) = @_;

	my $question_dialog = Gtk2::MessageDialog->new ($window,
	[qw/modal destroy-with-parent/],
	'question' ,
	'yes_no' ,
	$question_message ) ;
	my $question_response = $question_dialog->run ;
	if ($question_response eq "yes" ) {
		$question_dialog->destroy() ;		
		return TRUE;
	}else {
		$question_dialog->destroy() ;
		return FALSE;
	}
	
	
}

sub info_message
{
	my ($info_message) = @_;
	my $info_dialog = Gtk2::MessageDialog->new ($window,
	[qw/modal destroy-with-parent/],
	'question' ,
	'ok' ,
	$info_message ) ;
	my $info_response = $info_dialog->run ;	
	$info_dialog->destroy() if($info_response eq "ok");
	return TRUE;
}


sub notebook_switch
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
			$_->set_text("Bisher $n_pages Screenshots in dieser Sitzung");
		}elsif ($_ =~ /^Gtk2::Image/ && $tab_index != 0){#normal tab
			if(&file_exists($filename)){	
				$_->set_from_icon_name ('gtk-yes', 'menu');
			}else{
				$_->set_from_icon_name ('gtk-no', 'menu');
				&status_message(1, "$filename existiert nicht mehr!");
				$exists = FALSE;
				foreach my $key(keys %session_screens){
					delete($session_screens{$key}) if $session_screens{$key} eq $filename; # delete from hash	
				}
				
			}
		}
		
	}
	#do it again and set buttons disabled
	foreach (@hbox_content){
		if ( $_ =~ /^Gtk2::Button/ && $tab_index != 0 && $exists == FALSE){ #normal tab
			$_->set_sensitive(FALSE);
		}
		
	}		

}

#close app
sub delete_event
{

	my ($widget, $data) = @_;
	print "\n$data was emitted by widget $widget\n" if $debug_cparam;

	if($data eq "menu_quit"){
		Gtk2->main_quit ;
		return FALSE;
	}	
	my $dialog = Gtk2::MessageDialog->new ($window,
	[qw/modal destroy-with-parent/],
	'question' ,
	'yes_no' ,
	"Möchten Sie das Programm\n wirklich beenden?" ) ;
	my $response = $dialog->run ;
	if ($response eq "yes" ) {
		$dialog->destroy() ;		
		Gtk2->main_quit ;
		return FALSE;
	}else {
		$dialog->destroy() ;
		return TRUE;
	}
	
	
}

#save or revert settings
sub settings_event
{
	my ($widget, $data) = @_;
	print "\n$data was emitted by widget $widget\n" if $debug_cparam;

#save?
	if($data eq "menu_save"){
		if(-e "$ENV{ HOME }/.gscrot" && -w "$ENV{ HOME }/.gscrot"){
			if (&question_message("Möchten Sie die bestehenden Einstellungen überschreiben?")){ #ask is settings-file exists
				&save_settings;
			}
		}else{
				&save_settings; #do it directly if not
		}
	}elsif($data eq "menu_revert"){
		if(-e "$ENV{ HOME }/.gscrot" && -r "$ENV{ HOME }/.gscrot"){
			&load_settings;
		}else{
			&info_message("Es existieren keine gesicherten Einstellungen!");
		}
	}	
	
}


#save settings to file
sub save_settings
{
	open(FILE, ">$ENV{ HOME }/.gscrot") or &status_message(1, "Error --> Einstellungen konnten nicht gespeichert werden!");	
	print FILE "FTYPE=".$combobox_type->get_active."\n";
	print FILE "QSCALE=".$scale->get_value()."\n";
	print FILE "FNAME=".$filename->get_text()."\n";
	print FILE "FOLDER=".$saveDir_button->get_filename()."\n";
	print FILE "PNAME=".$progname->get_text()."\n";
	print FILE "PNAME_ACT=".$progname_active->get_active()."\n";
	print FILE "DELAY=".$delay->get_value()."\n";
	print FILE "DELAY_ACT=".$delay_active->get_active()."\n";
	print FILE "THUMB=".$thumbnail->get_value()."\n";
	print FILE "THUMB_ACT=".$thumbnail_active->get_active()."\n";
	print FILE "BORDER=".$combobox_border->get_active()."\n";
	close(FILE) or &status_message(1, "Error --> Einstellungen konnten nicht gespeichert werden!");


 	$statusbar->push (1, "Einstellungen erfolgreich gespeichert!");
}


sub load_settings
{
	my @settings_file;
	open(FILE, "$ENV{ HOME }/.gscrot") or &status_message(1, "Error --> Einstellungen konnten nicht geladen werden!");	
	@settings_file = <FILE>;
	close(FILE) or &status_message(1, "Error --> Einstellungen konnten nicht geladen werden!");

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
			$progname->set_text($_);
		}elsif($_ =~ m/^PNAME_ACT=/){
			$_ =~ s/PNAME_ACT=//;
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
		}

	}

	&status_message(1, "Einstellungen wurden erfolgreich geladen!");
}

#call about box
sub on_about 
{
	my ($widget, $data) = @_;
 	if($debug_cparam){
		print "\n$data was emitted by widget $widget\n";
	}

	open(GPL_HINT, "../share/gscrot/resources/license/gplv3_hint") or die "Copyright-Datei konnte nicht geöffnet werden!";
	my @copyright_hint = <GPL_HINT>;
	close(GPL_HINT);

	open(GPL, "../share/gscrot/resources/license/gplv3") or die "License-Datei konnte nicht geöffnet werden!";
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

	my $about = Gtk2::AboutDialog->new;
	$about->set_name($gscrot_name);
	$about->set_version($gscrot_version);
	$about->set_website_label('Visit the Homepage');
	$about->set_website('https://launchpad.net/gscrot');
	$about->set_authors("Mario Kemper");
	$about->set_artists("Arne Weinberg, Pascal Grochol");
	$about->set_copyright ($all_hints);
	$about->set_license ($all_lines);
	$about->show_all;
	$about->signal_connect('response' => \&callback_function);

}


#call context menu of tray-icon
sub show_icon_menu 
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
	my $menuitem_select = Gtk2::ImageMenuItem->new("Aufnahme mit Auswahl");
	$menuitem_select->set_image(Gtk2::Image->new_from_icon_name('gtk-cut', 'menu'));
	my $menuitem_raw = Gtk2::ImageMenuItem->new("Aufnahme");
	$menuitem_raw->set_image(Gtk2::Image->new_from_icon_name('gtk-fullscreen', 'menu'));
	my $menuitem_quit = Gtk2::ImageMenuItem->new("Beenden");
	$menuitem_quit->set_image(Gtk2::Image->new_from_icon_name('gtk-quit', 'menu'));
	$menuitem_quit->signal_connect("activate" , \&delete_event ,'menu_quit') ;
	$menuitem_select->signal_connect(activate => \&callback_function, 'tray_select');
	$menuitem_raw->signal_connect(activate => \&callback_function, 'tray_raw');
	my $separator_tray = Gtk2::SeparatorMenuItem->new();
	$separator_tray->show;
	$menuitem_select->show();
	$menuitem_raw->show();
	$menuitem_quit->show();
	$tray_menu->append($menuitem_select);
	$tray_menu->append($menuitem_raw);
	$tray_menu->append($separator_tray);
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

sub create_text {
	my ($key, $is_all) = @_;

	my $scrolled_window = Gtk2::ScrolledWindow->new;
	$scrolled_window->set_policy ('automatic', 'automatic');
	$scrolled_window->set_shadow_type ('in');
	
	my $vbox_tab = Gtk2::VBox->new(FALSE, 0);
	my $hbox_tab_file = Gtk2::HBox->new(FALSE, 0);
	my $hbox_tab_actions = Gtk2::HBox->new(FALSE, 0);

	my $n_pages = 0;
	my $filename = "Bisher $n_pages Screenshots in dieser Sitzung";
	$filename = $session_screens{$key} unless $is_all;
	$n_pages = $notebook->get_n_pages() if $is_all;

	my $exists_status;
	if(&file_exists($filename) || $n_pages >= 1){	
		$exists_status = Gtk2::Image->new_from_icon_name ('gtk-yes', 'menu');
	}else{
		$exists_status = Gtk2::Image->new_from_icon_name ('gtk-no', 'menu');
	}

	$exists_status = Gtk2::Image->new_from_icon_name ('gtk-dnd-multiple', 'menu') if $is_all;
	
	my $filename_label = Gtk2::Label->new($filename);

	my $button_delete = Gtk2::Button->new;
	$button_delete->signal_connect(clicked => \&tab_callback_function, 'delete'.$key);
	my $image_delete = Gtk2::Image->new_from_icon_name ('gtk-delete', 'button');
	$button_delete->set_image($image_delete);	

	my $button_clipboard = Gtk2::Button->new;
	$button_clipboard->signal_connect(clicked => \&tab_callback_function, 'clipboard'.$key);
	my $image_clipboard = Gtk2::Image->new_from_icon_name ('gtk-copy', 'button');
	$button_clipboard->set_image($image_clipboard);
	
	my $button_print = Gtk2::Button->new;
	$button_print->signal_connect(clicked => \&tab_callback_function, 'print'.$key);
	my $image_print = Gtk2::Image->new_from_icon_name ('gtk-print', 'button');
	$button_print->set_image($image_print);	
	
	#packing
	$hbox_tab_file->pack_start($exists_status, TRUE, TRUE, 1);
	$hbox_tab_file->pack_start($filename_label, TRUE, TRUE, 1);

	$hbox_tab_actions->pack_start($button_delete, TRUE, TRUE, 1);
	$hbox_tab_actions->pack_start($button_clipboard, TRUE, TRUE, 1) unless $is_all;
	$hbox_tab_actions->pack_start($button_print, TRUE, TRUE, 1);

	$vbox_tab->pack_start($hbox_tab_file, TRUE, TRUE, 1);
	$vbox_tab->pack_start($hbox_tab_actions, TRUE, TRUE, 1);
	$scrolled_window->add_with_viewport($vbox_tab);

  return $scrolled_window;
}

#tab events are handled here
sub tab_callback_function
{

	my ($widget, $data) = @_;
	print "\n$data was emitted by widget $widget\n" if $debug_cparam;


#single screenshots	
	my $current_file;
	if ($data =~ m/^print\[/){
		$data =~ s/^print//;
		my $current_file = &switch_home_in_file($session_screens{$data});
		system("gtklp $current_file &");
		&status_message(1, $session_screens{$data}." wird gedruckt!");
	}

	if ($data =~ m/^delete\[/){
		$data =~ s/^delete//;
		unlink(&switch_home_in_file($session_screens{$data})); #delete file
		$notebook->remove_page($notebook->get_current_page); #delete tab
		&status_message(1, $session_screens{$data}." gelöscht!");
		delete($session_screens{$data}); # delete from hash
		$window->show_all;
	}

	if ($data =~ m/^clipboard\[/){
		$data =~ s/^clipboard//;
		my $pixbuf = Gtk2::Gdk::Pixbuf->new_from_file (&switch_home_in_file($session_screens{$data}) );
		$clipboard->set_image($pixbuf);
		&status_message(1, $session_screens{$data}." wird in die Zwischenablage kopiert!");
	}


#all screenshots
	if ($data =~ m/^delete$/){ #tab == all
		foreach my $key(keys %session_screens){
			unlink(&switch_home_in_file($session_screens{$key})); #delete file		
			delete($session_screens{$key}); # delete from hash	
		}
		my $n_pages = $notebook->get_n_pages();
		while($n_pages > 1){  #delete tab all tabs
			$n_pages--;
			$notebook->remove_page($n_pages);		
		}
		&status_message(1, "Alle Aufnahmen dieser Sitzung gelöscht!");
		
		#write new number of screenshot to first label
		my $current_page = $notebook->get_nth_page(0);
		my @widget_list = $current_page->get_children->get_children->get_children; #scrolledwindow, viewport, vbox
		my @hbox_content;
		foreach my $hbox_widget(@widget_list){
			push(@hbox_content, $hbox_widget->get_children);
		}
		foreach (@hbox_content){
			if ( $_ =~ /^Gtk2::Label/ ){ 
				$_->set_text("Bisher 0 Screenshots in dieser Sitzung");
			}
		}
		
		$window->show_all;
	}

	if ($data =~ m/^print$/){ #tab == all
		my $print_files;		
		foreach my $key(keys %session_screens){
			$print_files .= &switch_home_in_file($session_screens{$key})." ";
		}
		system("gtklp $print_files &");
		&status_message(1, "Alle Aufnahmen werden gedruckt!");
	}


}


