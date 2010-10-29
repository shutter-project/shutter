###################################################
#
#  Copyright (C) 2008, 2009, 2010 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

package Shutter::App::Autostart;

use utf8;
use strict;
use warnings;

#Glib
use Glib qw/TRUE FALSE/; 

sub new {
	my $class = shift;

	my $self = { };

	#read data
	binmode DATA, ":utf8";
	while (my $data = <DATA>){
		push @{$self->{_data}}, $data;
	}

	bless $self, $class;
	return $self;
}

sub create_autostart_file {
	my $self = shift;
	my $dir = shift; # ~/.config/autostart in most cases
	my $enabled = shift;
	my $min = shift;
	my $notification = shift;
	
	#copy in order keep original data
	my @data = @{$self->{_data}};
	
	my $path = $dir."/shutter.desktop";

	open FILE, ">:utf8", $path or die $!;
	foreach my $line (@data){
		if($line =~ /Exec=shutter<options>/){
			#add options
			my $options = '';
			$options .= " --min_at_startup" if $min;
			$options .= " --disable_systray" if !$notification;
			#remove placeholder
			$line =~ s/<options>/$options/;
		}elsif($line =~ /X-GNOME-Autostart-enabled=false/){
			$line =~ s/false/true/ if $enabled;
		}
		print FILE $line;
	}
	close FILE or die $!;	
	
	return TRUE;
}

1;

__DATA__
[Desktop Entry]
Version=1.0
Name=Shutter
Name[de_DE]=Shutter
Name[pt_BR]=Shutter
GenericName[pt_BR]=Captura de tela
Comment=Feature-rich screenshot application
Comment[de_DE]=Vielseitiges Programm zur Aufnahme von Bildschirmfotos
Comment[pt_BR]=Aplicativo avançado para capturar imagens da tela
Exec=shutter<options>
Icon=shutter
Terminal=false
Type=Application
Categories=Utility;Application;
X-GNOME-Autostart-enabled=false

