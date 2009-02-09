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

package Shutter::App::SimpleDialogs;

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
	my $self = { _window => shift };

	bless $self, $class;
	return $self;
}

sub dlg_info_message {
	my $self = shift;
	my $dlg_info_message = shift;
	my $dlg_info_header = shift;

	my $info_dialog = Gtk2::MessageDialog->new( $self->{_window}, [qw/modal destroy-with-parent/],
		'info', 'ok', $dlg_info_message );

	$info_dialog->set( 'text' => $dlg_info_header );

	$info_dialog->set( 'secondary-text' => $dlg_info_message );

	my $info_response = $info_dialog->run;
	$info_dialog->destroy() if ( $info_response eq "ok" );
	
	return TRUE;
}

sub dlg_question_message {
	my $self = shift;
	my $dlg_question_message = shift;
	my $dlg_question_header = shift;
	my $button_text_extra1 = shift;
	my $button_text_extra2 = shift;
	my $button_text_extra3 = shift;
	my $button_widget_extra1 = shift;
	my $button_widget_extra2 = shift;
	my $button_widget_extra3 = shift;

	my $question_dialog = Gtk2::MessageDialog->new( $self->{_window}, [qw/modal destroy-with-parent/], 'other', 'none', undef );

	$question_dialog->set( 'image' => Gtk2::Image->new_from_stock( 'gtk-dialog-question', 'dialog' ) );

	$question_dialog->set( 'text' => $dlg_question_header );

	$question_dialog->set( 'secondary-text' => $dlg_question_message );

	$question_dialog->add_button( $button_text_extra1, 10 ) if $button_text_extra1;
	$question_dialog->add_button( $button_text_extra2, 20 ) if $button_text_extra2;
	$question_dialog->add_button( $button_text_extra3, 30 ) if $button_text_extra3;

	$question_dialog->add_action_widget( $button_widget_extra1, 40 ) if $button_widget_extra1;
	$question_dialog->add_action_widget( $button_widget_extra2, 50 ) if $button_widget_extra2;
	$question_dialog->add_action_widget( $button_widget_extra3, 60 ) if $button_widget_extra3;

	$question_dialog->show_all;

	my $question_response = $question_dialog->run;

	$question_dialog->destroy();
	return $question_response;
}

sub dlg_error_message {
	my $self = shift;
	my $dlg_error_message = shift;
	my $dlg_error_header = shift;
	my $button_text_extra1 = shift;
	my $button_text_extra2 = shift;
	my $button_text_extra3 = shift;
	my $button_text_extra4 = shift;
	my $button_widget_extra1 = shift;
	my $button_widget_extra2 = shift;
	my $button_widget_extra3 = shift;
	my $button_widget_extra4 = shift;
	
	my $error_dialog = Gtk2::MessageDialog->new( $self->{_window}, [qw/modal destroy-with-parent/], 'other', 'none', undef );

	$error_dialog->set( 'image' => Gtk2::Image->new_from_stock( 'gtk-dialog-error', 'dialog' ) );

	$error_dialog->set( 'text' => $dlg_error_header );

	$error_dialog->set( 'secondary-text' => $dlg_error_message );

	$error_dialog->add_button( $button_text_extra1, 10 ) if $button_text_extra1;
	$error_dialog->add_button( $button_text_extra2, 20 ) if $button_text_extra2;
	$error_dialog->add_button( $button_text_extra3, 30 ) if $button_text_extra3;
	$error_dialog->add_button( $button_text_extra3, 40 ) if $button_text_extra3;

	$error_dialog->add_action_widget( $button_widget_extra1, 40 ) if $button_widget_extra1;
	$error_dialog->add_action_widget( $button_widget_extra2, 50 ) if $button_widget_extra2;
	$error_dialog->add_action_widget( $button_widget_extra3, 60 ) if $button_widget_extra3;
	$error_dialog->add_action_widget( $button_widget_extra3, 70 ) if $button_widget_extra3;

	$error_dialog->show_all;

	my $error_response = $error_dialog->run;

	$error_dialog->destroy();
	return $error_response;
}

1;
