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

package Shutter::Screenshot::Web;

#modules
#--------------------------------------
use utf8;
use strict;
use warnings;

use Proc::Killfam;

use File::Temp qw/ tempfile tempdir /;

#timing issues
use Time::HiRes qw/ time usleep /;

use Shutter::Screenshot::History;

#Glib and Gtk2
use Gtk2;
use Glib qw/TRUE FALSE/; 

#--------------------------------------

sub new {
	my $class = shift;
	
	my $self = {
				 _sc			=> shift,
				 _timeout  		=> shift,
				 _width			=> shift,
			   };
	
	bless $self, $class;
	return $self;
}

#~ sub DESTROY {
    #~ my $self = shift;
    #~ print "$self dying at\n";
#~ } 

sub web {
	my $self = shift;
	
	#use http:// when nothing provided
	unless($self->{_url} =~ /^(http\:\/\/|https\:\/\/|file\:\/\/)/i){
		$self->{_url} = "http://".$self->{_url};
	}
	
	system("gnome-web-photo --timeout=$self->{_timeout} --mode=photo --width=$self->{_width} '$self->{_url}' '$self->{_dest_filename}'");
	
	return TRUE;
}

sub dlg_website {
	my $self = shift;
	my $url  = shift;
	
	#gettext
	my $d = $self->{_sc}->get_gettext;

	#load modules at custom path
	#--------------------------------------
	require lib;
	import lib $self->{_sc}->get_root."/share/shutter/resources/modules";

	require Proc::Simple;
	
	my $output  = 6;
	my $web_process = Proc::Simple->new;

	#gwp result will be saved to tempfile
	my ( $tmpfh, $tmpfilename ) = tempfile(UNLINK => 1);
	
	#redirect outputs
	my ( $tmpfh_stdout, $tmpfilename_stdout ) = tempfile(UNLINK => 1);
	my ( $tmpfh_stderr, $tmpfilename_sterr ) = tempfile(UNLINK => 1);
  	#~ $web_process->redirect_output ("$ENV{'HOME'}/shutter-debug-stdout.log", "$ENV{'HOME'}/shutter-debug-err.log");
  	$web_process->redirect_output ($tmpfilename_stdout, $tmpfilename_sterr);

	my $website_dialog = Gtk2::MessageDialog->new( $self->{_sc}->get_mainwindow, [qw/modal destroy-with-parent/], 'other', 'none', undef );

	$website_dialog->set_title("Shutter");

	$website_dialog->set( 'text' => $d->get("Take a screenshot of a website") );

	$website_dialog->set( 'secondary-text' => $d->get("URL to capture") . ": " );

	if($self->{_sc}->get_theme->has_icon('web-browser')){
		$website_dialog->set(
			'image' => Gtk2::Image->new_from_icon_name( 'web-browser', 'dialog' ) );		
	}else{
		$website_dialog->set(
			'image' => Gtk2::Image->new_from_pixbuf(
				Gtk2::Gdk::Pixbuf->new_from_file_at_size( $self->{_sc}->get_root."/share/shutter/resources/icons/web_image.svg", Gtk2::IconSize->lookup('dialog') )
			)
		);
	}

	#cancel button
	my $cancel_btn = Gtk2::Button->new_from_stock('gtk-cancel');

	#capture button
	my $execute_btn = Gtk2::Button->new_with_mnemonic( $d->get("C_apture") );
	$execute_btn->set_image( Gtk2::Image->new_from_stock( 'gtk-execute', 'button' ) );
	$execute_btn->set_sensitive(FALSE);
	$execute_btn->can_default(TRUE);

	$website_dialog->add_action_widget( $cancel_btn,  'cancel' );
	$website_dialog->add_action_widget( $execute_btn, 'accept' );

	$website_dialog->set_default_response('accept');

	my $website_hbox  = Gtk2::HBox->new();
	my $website_hbox2 = Gtk2::HBox->new();

	my $website = Gtk2::Entry->new;
	$website->set_activates_default(TRUE);

	#check if url is valid
	$website->signal_connect('changed' => sub {
		unless ( $website->get_text ) {
			$execute_btn->set_sensitive(FALSE);
		}else{
			$execute_btn->set_sensitive(TRUE);
		}
		return FALSE;
	});
	
	my $clipboard = Gtk2::Clipboard->get( Gtk2::Gdk->SELECTION_CLIPBOARD );
	my $clipboard_string = $clipboard->wait_for_text;
	print "Content of clipboard is: $clipboard_string\n"
		if $self->{_sc}->get_debug and defined $clipboard_string;

	#set textbox to url
	if(defined $url){
		$website->set_text($url);
		
	#or paste clipboard content	
	}else{
		if ( defined $clipboard_string ) {
			if (   $clipboard_string =~ /^http/
				|| $clipboard_string =~ /^file/
				|| $clipboard_string =~ /^www\./ )
			{
				$website->set_text($clipboard_string);
			}
		}		
	}

	$website_hbox->pack_start( $website, TRUE, TRUE, 12 );
	$website_dialog->vbox->add($website_hbox);

	my $website_progress = Gtk2::ProgressBar->new;
	$website_progress->set_no_show_all(TRUE);
	$website_progress->set_ellipsize('middle');
	$website_progress->set_orientation('left-to-right');
	$website_progress->set_fraction(0);
	$website_hbox2->pack_start( $website_progress, TRUE, TRUE, 12 );
	$website_dialog->vbox->add($website_hbox2);

	$website_dialog->show_all;
	
	my $website_response = "accept";
	if($url){
		$website_dialog->response("accept");
	}else{
		$website_response = $website_dialog->run;
	}
	
	if ( $website_response eq "accept" ) {

		$execute_btn->set_sensitive(FALSE);

		#show progress bar while executing gnome-web-photo
		$website_progress->show;
		$self->update_gui();
		
		#set url and filename
		$self->{_url} = $website->get_text;
		$self->{_dest_filename} = $tmpfilename;

		print "gnome-web-photo --timeout=$self->{_timeout} --mode=photo --width=$self->{_width} '$self->{_url}' '$self->{_dest_filename}'\n" if $self->{_sc}->get_debug;
		Proc::Simple::debug(1) if $self->{_sc}->get_debug;

		$web_process->start(
			sub {		
				#cleanup when catching TERM
				$SIG{TERM}   = sub {
					killfam 'TERM', $$;
				};
				#start gnome-web-photo
				$self->web();
				POSIX::_exit(0);
			}
		);
		
		$website_dialog->signal_connect(
			'delete-event' => sub{
				#kill process
				$web_process->kill;				
				$output = 5;				
			} 
		);

		$cancel_btn->signal_connect(
			'clicked' => sub {
				#kill process
				$web_process->kill;
				$output = 5;
			}
		);

		while ( $web_process->poll ) {
			$website_progress->pulse;
			$self->update_gui();
			usleep 100000;
		}

		#we cannot kill the process anymore
		#closing the dialog will confuse the user
		#because the image will appear in the session later on
		$cancel_btn->set_sensitive(FALSE);
		$self->update_gui();

		#exit status == OK
		if ( $web_process->exit_status() == 0 ) {

			$website_progress->set_fraction( 2 / 3 );
			$self->update_gui();

			eval { $output = Gtk2::Gdk::Pixbuf->new_from_file($tmpfilename) };
			if ($@) {
				#reading stdout from file
				while (<$tmpfh_stdout>){
					$self->{_error_text} .= $_;	
				}
				#reading stderr from file
				while (<$tmpfh_stderr>){
					$self->{_error_text} .= $_;
				}
				unlink $tmpfilename, $tmpfilename_stdout, $tmpfilename_sterr;
				$website_dialog->destroy();
			}else{

				#set name of the captured window
				#e.g. for use in wildcards
				$self->{_action_name} = $self->{_url};
				$self->{_action_name} =~ s/(http:\/\/|https:\/\/|file:\/\/)//g;
				
				#set history object
				$self->{_history} = Shutter::Screenshot::History->new($self->{_sc});
					
			}

			$website_progress->set_fraction( 3 / 3 );
			$self->update_gui();
	
		#exit status == FAIL
		}else{
			#reading stdout from file
			while (<$tmpfh_stdout>){
				$self->{_error_text} .= $_;
			}
			#reading stderr from file
			while (<$tmpfh_stderr>){
				$self->{_error_text} .= $_;
			}
		}

		#kill process, destroy dialog
		$web_process->kill('SIGKILL');
		$website_dialog->destroy();

		return $output;
	} else {
		
		#kill process, destroy dialog
		$web_process->kill('SIGKILL');
		$website_dialog->destroy();

		return 5;
	}
}

sub update_gui {
	my $self = shift;
	
	while ( Gtk2->events_pending ) {
		Gtk2->main_iteration;
	}
	Gtk2::Gdk->flush;

	return TRUE;
}

sub redo_capture {
	my $self = shift;
	my $output = 3;
	if(defined $self->{_history}){
		$output = $self->dlg_website($self->{_url});
	}
	return $output;
}	

sub get_history {
	my $self = shift;
	return $self->{_history};
}

sub get_error_text {
	my $self = shift;
	return $self->{_error_text};
}

sub get_action_name {
	my $self = shift;
	return $self->{_action_name};
}

1;
