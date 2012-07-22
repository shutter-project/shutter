###################################################
#
#  Copyright (C) 2008-2012 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package Shutter::App::AboutDialog;

#modules
#--------------------------------------
use utf8;
use strict;
use Gtk2;

#Glib
use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;

	#constructor
	my $self = { _sc => shift };

	bless $self, $class;
	return $self;
}

sub show {
	my $self = shift;

	my $shf = Shutter::App::HelperFunctions->new( $self->{_sc} );
	my $shutter_root = $self->{_sc}->get_root;
	my $d = $self->{_sc}->get_gettext;
	
	#everything is stored in external files, so it is easier to maintain
	my $all_hint = "";
	open( GPL_HINT, "$shutter_root/share/shutter/resources/license/gplv3_hint" )
		or die $!;
	while(my $hint = <GPL_HINT>){
		utf8::decode $hint;
		$all_hint .= $hint;	
	}
	close(GPL_HINT);
	
	my $all_gpl = "";
	open( GPL, "$shutter_root/share/shutter/resources/license/gplv3" )
		or die $!;
	while(my $gpl = <GPL>){
		utf8::decode $gpl;
		$all_gpl .= $gpl;	
	}	
	close(GPL);
	
	my $all_dev = "";
	open( DEVCREDITS, "$shutter_root/share/shutter/resources/credits/dev" )
		or die $!;
	while(my $dev = <DEVCREDITS>){
		utf8::decode $dev;
		$all_dev .= $dev;	
	}
	close(DEVCREDITS);

	my $all_art = "";
	open( ARTCREDITS, "$shutter_root/share/shutter/resources/credits/art" )
		or die $!;
	while(my $art = <ARTCREDITS>){
		utf8::decode $art;
		$all_art .= $art;	
	}
	close(ARTCREDITS);
	
	my $about   = Gtk2::AboutDialog->new;
	$about->set_logo_icon_name('shutter');
	if (Gtk2->CHECK_VERSION( 2, 12, 0 )){
		$about->set_program_name($self->{_sc}->get_appname);
	}else{
		$about->set_name($self->{_sc}->get_appname);
	}
	$about->set_version($self->{_sc}->get_version);
	$about->set_url_hook( sub { $shf->xdg_open(@_) } );
	#~ $about->set_website_label("Shutter-Website");
	$about->set_website("http://shutter-project.org");
	$about->set_email_hook( sub { $shf->xdg_open_mail(@_) } );
	$about->set_authors( $all_dev );
	$about->set_artists( $all_art );
	$about->set_translator_credits($d->get("translator-credits"));
	$about->set_copyright($all_hint);
	$about->set_license($all_gpl);
	$about->set_comments($self->{_sc}->get_rev);
	$about->show_all;
	$about->signal_connect( 'response' => sub { $about->destroy } );		
}

1;
