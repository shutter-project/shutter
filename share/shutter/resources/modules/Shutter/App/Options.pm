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

package Shutter::App::Options;

use utf8;
use strict;
use warnings;

#Glib
use Glib qw/TRUE FALSE/; 

#Extended processing of command line options
use Getopt::Long qw(:config no_ignore_case pass_through);

#print a usage message from embedded pod documentation
use Pod::Usage;

sub new {
	my $class = shift;

	my $self = { _sc => shift, _shf => shift };

	bless $self, $class;
	return $self;
}

sub get_options {
	my $self = shift;

	GetOptions (
		's|select:s@' => sub{ my ($select, $sel_ref) = @_; $self->{_sc}->set_start_with("select", $sel_ref); $self->{_sc}->set_min(TRUE); },
		'f|full' => sub{ $self->{_sc}->set_start_with("full"); $self->{_sc}->set_min(TRUE); },
		'w|window:s' => sub{ my ($web, $name) = @_; $self->{_sc}->set_start_with("window", $name); $self->{_sc}->set_min(TRUE); },
		'a|active' => sub{ $self->{_sc}->set_start_with("awindow"); $self->{_sc}->set_min(TRUE); },
		'section' => sub{ $self->{_sc}->set_start_with("section"); $self->{_sc}->set_min(TRUE); },
		'm|menu' => sub{ $self->{_sc}->set_start_with("menu"); $self->{_sc}->set_min(TRUE); },
		't|tooltip' => sub{ $self->{_sc}->set_start_with("tooltip"); $self->{_sc}->set_min(TRUE); },
		'web:s' => sub{ my ($web, $url) = @_; $self->{_sc}->set_start_with("web", $url); },
		'r|redo' => sub{ $self->{_sc}->set_start_with("redoshot"); $self->{_sc}->set_min(TRUE); },
		
		'p|profile=s' => sub{ my ($p, $profile) = @_; $self->{_sc}->set_profile_to_start_with($profile); },
		'o|output=s' => sub{ my ($o, $output) = @_; $self->{_sc}->set_export_filename($output); },
		'c|include_cursor' => sub{ $self->{_sc}->set_include_cursor(TRUE); },
		'C|remove_cursor' => sub{ $self->{_sc}->set_remove_cursor(TRUE); },
		'd|delay=s' => sub{ my ($d, $delay) = @_; $self->{_sc}->set_delay($delay); },
		
		'h|help' => sub{ pod2usage(-verbose => 1); },
		'v|version' => sub{ print $self->{_sc}->get_version, " ", $self->{_sc}->get_rev, "\n"; exit; },
		'debug' => sub{ $self->{_sc}->set_debug(TRUE); },
		'clear_cache' => sub{ $self->{_sc}->set_clear_cache(TRUE); },
		'min_at_startup' => sub{ $self->{_sc}->set_min(TRUE); },
		'disable_systray' => sub{ $self->{_sc}->set_disable_systray(TRUE); },
		'e|exit_after_capture' => sub{ $self->{_sc}->set_exit_after_capture(TRUE); },
		'n|no_session' => sub{ $self->{_sc}->set_no_session(TRUE); },
	);

	#unknown value are passed through in @ARGV - might be filenames
	my @init_files;
	if ( @ARGV > 0 ) {
		foreach my $arg (@ARGV) {
			if ( $self->{_shf}->file_exists($arg) || $self->{_shf}->uri_exists($arg) ) {
				#push filename to array, open when GUI is initialized
				push @init_files, $arg;
				next;
			} else {
				warn "ERROR: unknown command or filename " . $arg . " \n\n";
				pod2usage(-verbose => 1);
			}
		}
	}

	return \@init_files;
}

1;
