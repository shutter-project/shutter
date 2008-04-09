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


my $gscrot_name = "GScrot";
my $gscrot_version = "v0.33";

#command line parameter
my $debug_cparam = FALSE;
my @args = @ARGV;

&init_gscrot();

my $window = Gtk2::Window->new();

$window->set_title($gscrot_name." ".$gscrot_version);
$window->set_default_icon_from_file ("/usr/share/pixmaps/gscrot.svg");
$window->signal_connect(delete_event => \&delete_event);
$window->set_border_width(10);


my $vbox = Gtk2::VBox->new(FALSE, 10);
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




$window->add($vbox);


#############MENU###################
my $menubar = Gtk2::MenuBar->new() ;

my $menu1= Gtk2::Menu->new() ;

my $menuitem_file = Gtk2::MenuItem->new_with_mnemonic("_Datei" ) ;


my $menuitem_quit = Gtk2::ImageMenuItem->new_with_mnemonic("_Beenden" ) ;
$menuitem_quit->set_image(Gtk2::Image->new_from_icon_name('gtk-quit', 'menu'));
$menu1->append($menuitem_quit) ;
$menuitem_quit->signal_connect("activate" , \&delete_event , 'menu_quit') ;

$menuitem_file->set_submenu($menu1);
$menubar->append($menuitem_file) ;

my $menu2 = Gtk2::Menu->new() ;

my $menuitem_about = Gtk2::ImageMenuItem->new_with_mnemonic("_Info") ;
$menuitem_about->set_image(Gtk2::Image->new_from_icon_name('gtk-about', 'menu'));
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

$vbox->pack_start($button_box, FALSE, FALSE, 0);


#############TRAYICON######################
my $icon = Gtk2::Image->new_from_file("/usr/share/gscrot/resources/icons/gscrot.png");
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

#ende - delay

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

#ende - thumbnail


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
#ende - filename

#type
my $combobox_type = Gtk2::ComboBox->new_text;
$combobox_type->insert_text (0, "jpeg");
$combobox_type->insert_text (1, "png");
$combobox_type->signal_connect('changed' => \&callback_function, 'type_changed');
$combobox_type->set_active (1);

my $filetype_label = Gtk2::Label->new;
$filetype_label->set_text("Dateityp");
$filetype_label->set_justify('left');


my $tooltip_filetype = Gtk2::Tooltips->new;
$tooltip_filetype->set_tip($combobox_type,"Wählen Sie ein Dateiformat");
$tooltip_filetype->set_tip($filetype_label,"Wählen Sie ein Dateiformat");

$filetype_box->pack_start($filetype_label, FALSE, TRUE, 10);
$filetype_box->pack_start($combobox_type, TRUE, TRUE, 10);
#ende - filetype


#saveDir
my $saveDir_label = Gtk2::Label->new;
$saveDir_label->set_text("Verzeichnis");

my $saveDir_button = Gtk2::FileChooserButton->new ('gscrot - Select a folder', 'select-folder');

my $tooltip_saveDir = Gtk2::Tooltips->new;
$tooltip_saveDir->set_tip($saveDir_button,"Wählen Sie ein Verzeichnis\nzum Speichern Ihrer Bildschirmaufnahmen");
$tooltip_saveDir->set_tip($saveDir_label,"Wählen Sie ein Verzeichnis\nzum Speichern Ihrer Bildschirmaufnahmen");

$saveDir_box->pack_start($saveDir_label, FALSE, TRUE, 10);
$saveDir_box->pack_start($saveDir_button, TRUE, TRUE, 10);
#ende - saveDir

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
#ende - porgram
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
$extras_frame->add($extras_vbox);


$vbox->pack_start($file_frame, TRUE, TRUE, 1);
$vbox->pack_start($save_frame, TRUE, TRUE, 1);
$vbox->pack_start($extras_frame, TRUE, TRUE, 1);
#############PACKING######################


$window->show_all;

#GTK2 Main Loop
Gtk2->main;

0;


#initialisiere gscrot, prüfe abhängigkeit von scrot
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


	print "INFO: searching for dependencies...\n";
	
	if(system("which scrot")==0){
		print "SUCCESS: scrot is installed on your system!\n";
	}else{
		die "ERROR: dependency is missing --> scrot is not installed on your system!\n";
	}
	my $scrot_version = `scrot --version`;
	print "INFO: you are using $scrot_version\n";

	#gibt es command line parameter?
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

#fast alle events werden hier behandelt
sub callback_function
{
	my ($widget, $data) = @_;
	my $quality_value = undef;
	my $delay_value = undef;
	my $thumbnail_value = undef;
	my $progname_value = undef;
	my $filename_value = undef;
	my $filetype_value = undef;
	my $folder = undef;

	my $thumbnail_param = "";	
	my $progname_param = "";

	if($debug_cparam){
		print "\n$data was emitted by widget $widget\n";
	}
	
#checkbox für extra "öffnen mit" -> eingabefeld aktiv/inaktiv
	if($data eq "progname_toggled"){
		if($progname_active->get_active){
			$progname->set_editable(TRUE);
			$progname->set_sensitive(TRUE);			
		}else{
			$progname->set_editable(FALSE);
			$progname->set_sensitive(FALSE);
		}
	}

#checkbox für extra "thumbnail" -> HScale aktiv/inaktiv
	if($data eq "delay_toggled"){
		if($delay_active->get_active){	
			$delay->set_sensitive(TRUE);			
		}else{	
			$delay->set_sensitive(FALSE);
		}
	}


#checkbox für extra "verzögerung" -> HScale aktiv/inaktiv
	if($data eq "thumbnail_toggled"){
		if($thumbnail_active->get_active){
			$thumbnail->set_sensitive(TRUE);			
		}else{
			$thumbnail->set_sensitive(FALSE);
		}
	}

#dateityp ändert sich
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

#aufnahme wurde gewählt	
	if($data eq "raw" || $data eq "select" || $data eq "tray_raw" || $data eq "tray_select"){
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
		
		if($progname_active->get_active){		
			$progname_value = $progname->get_text();
			$progname_param = "-e '$progname_value \$f'";
		}


		$filename_value = $filename->get_text();
		$progname_value = $progname->get_text();
		$filetype_value = $combobox_type->get_active_text();		
		$folder = $saveDir_button->get_filename();
		
		if($delay_value == 0 && $data eq "tray_raw"){
			$delay_value = 1;
		}


		if($data eq "raw" || $data eq "tray_raw"){
			system("scrot '$folder/$filename_value.$filetype_value' -q $quality_value -d $delay_value $thumbnail_param $progname_param &");
		}else{
			system("scrot '$folder/$filename_value.$filetype_value' --select -q $quality_value -d $delay_value $thumbnail_param $progname_param &");
		}
				
	}

	#about box wird geschlossen
	if($data eq "cancel"){
		$widget->destroy();	
	}
}


#anwendung wird geschlossen
sub delete_event
{

	my ($widget, $data) = @_;
	if($debug_cparam){
		print "\n$data was emitted by widget $widget\n";
	}

	if($data eq "menu_quit"){
		Gtk2->main_quit ;
		return FALSE;
	}	
	my $dialog = Gtk2::MessageDialog->new ($window,
	[qw/modal destroy-with-parent/],
	'question' ,
	'yes_no' ,
	"Möchten Sie das Porgramm\n wirklich beenden?" ) ;
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

#about box wird aufgerufen
sub on_about 
{

	my ($widget, $data) = @_;
 	if($debug_cparam){
		print "\n$data was emitted by widget $widget\n";
	}

	open(GPL_HINT, "/usr/share/gscrot/resources/license/gplv3_hint") or die "Copyright-Datei konnte nicht geöffnet werden!";
	my @copyright_hint = <GPL_HINT>;
	close(GPL_HINT);

	open(GPL, "/usr/share/gscrot/resources/license/gplv3") or die "License-Datei konnte nicht geöffnet werden!";
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
	$about->set_website_label('Visit the Team Homepage');
	$about->set_website('https://launchpad.net/gscrot');
	$about->set_authors("Mario Kemper");
	$about->set_copyright ($all_hints);
	$about->set_license ($all_lines);
	$about->show_all;
	$about->signal_connect('response' => \&callback_function);

}


#context menu des tray-icons wird aufgerufen
sub show_icon_menu 
{

	my ($widget, $data) = @_;
	if($debug_cparam){
		print "\n$data was emitted by widget $widget\n";
	}

	#Linke Maustaste
	if ($_[1]->button == 1) {
		if($window->visible){
			$window->hide;
		}else{
			$window->show_all;
		}		
	}   
	#Rechte Maustaste
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



