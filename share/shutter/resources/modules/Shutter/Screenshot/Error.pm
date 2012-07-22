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

package Shutter::Screenshot::Error;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

#Glib
use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;
	
	my $self = { _sc  => shift, _code => shift, _data => shift, _extra => shift };

	#############
	# code = 0 - pointer could not be grabbed - or invalid region
	# code = 1 - keyboard could not be grabbed
	# code = 2 - no window with type xy detected
	# code = 3 - no history object stored
	# code = 4 - window no longer available
	# code = 5 - user aborted
	# code = 6 - gnome-web-photo failed
	# code = 7 - no window with name xy detected
	# code = 8 - invalid pattern
	#############	

	bless $self, $class;
	return $self;
}

sub get_error {
	my $self = shift;
	return ($self->{_code}, $self->{_data}, $self->{_extra});
}

sub is_aborted_by_user {
	my $self = shift;
	if(defined $self->{_code} && $self->{_code} == 5){
		return TRUE;
	}else{
		return FALSE;
	}	
}

sub is_error {
	my $self = shift;
	if(defined $self->{_code} && $self->{_code} =~ /^\d+$/){
		return TRUE;
	}else{
		return FALSE;
	}
}

sub set_error {
	my $self = shift;
	if (@_) {
		$self->{_code} = shift;
		$self->{_data} = shift;
		$self->{_extra} = shift;
	}		
	return ($self->{_code}, $self->{_data}, $self->{_extra});
}

sub show_dialog {
	my $self = shift;
	my $detailed_error_text = shift || '';
	
	#load modules at custom path
	#--------------------------------------
	require lib;
	import lib $self->{_sc}->get_root."/share/shutter/resources/modules";
	require Shutter::App::SimpleDialogs;
	
	my $sd = Shutter::App::SimpleDialogs->new($self->{_sc}->get_mainwindow);

	#gettext
	my $d = $self->{_sc}->get_gettext;

	my $response;
	my $status_text = $d->get("Error while taking the screenshot.");

	#handle error codes
	if( $self->{_code} == 0 ) {

		#show error dialog
		my $response = $sd->dlg_error_message( 
			$d->get( "Maybe mouse pointer could not be grabbed or the selected area is invalid." ),
			$d->get( "Error while taking the screenshot." )
		);				
		
	#keyboard could not be grabbed
	}elsif( $self->{_code} == 1 ) {

		$response = $sd->dlg_error_message( 
			$d->get( "Keyboard could not be grabbed." ),
			$d->get( "Error while taking the screenshot." )
		);
			
	#no window with type xy detected
	}elsif( $self->{_code} == 2 ) {
		
		my $type = undef;
		if ( $self->{_data} eq "menu" ||  $self->{_data} eq "tray_menu" ) {
			$type = $d->get( "menu" );
		}elsif ( $self->{_data} eq "tooltip" ||  $self->{_data} eq "tray_tooltip" ) {
			$type = $d->get( "tooltip" );
		}

		$response = $sd->dlg_error_message( 
			sprintf( $d->get( "No window with type %s detected." ), "'".$type."'"),
			$d->get( "Error while taking the screenshot." )
		);
			
	#no history object stored
	}elsif( $self->{_code} == 3 ) {

		$response = $sd->dlg_error_message( 
			$d->get( "There is no last capture that can be redone." ),
			$d->get( "Error while taking the screenshot." )
		);
			
	#window no longer available
	}elsif( $self->{_code} == 4 ) {
		
		$response = $sd->dlg_error_message( 
			$d->get( "The window is no longer available." ),
			$d->get( "Error while taking the screenshot." )
		);

	#user aborted screenshot
	}elsif ( $self->{_code} == 5 ) {
		
		$status_text = $d->get("Capture aborted by user");

	#gnome-web-photo failed
	}elsif ( $self->{_code} == 6 ) {

		$response = $sd->dlg_error_message( $d->get("Unable to capture website"), 
			$d->get( "Error while taking the screenshot." ),
			undef, undef, undef, undef, undef, undef,
			$detailed_error_text 
		);
		
		$status_text = $d->get("Unable to capture website");
			
	#no window with name $pattern detected
	}elsif( $self->{_code} == 7 ) {
		
		my $name_pattern = $self->{_extra};
		
		$response = $sd->dlg_error_message( 
			sprintf( $d->get( "No window with name pattern %s detected." ), "'".$name_pattern."'"),
			$d->get( "Error while taking the screenshot." )
		);
		
	#invalid pattern
	}elsif( $self->{_code} == 8 ) {
		
		my $name_pattern = $self->{_extra};
		
		$response = $sd->dlg_error_message( 
			sprintf( $d->get( "Invalid pattern %s detected." ), "'".$name_pattern."'"),
			$d->get( "Error while taking the screenshot." ),
			undef, undef, undef, undef, undef, undef,
			$detailed_error_text 
		);

	}

	return ($response, $status_text);
}

1;
