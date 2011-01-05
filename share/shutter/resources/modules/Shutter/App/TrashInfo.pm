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

package Shutter::App::TrashInfo;

use utf8;
use strict;
use warnings;

#Glib
use Glib qw/TRUE FALSE/; 

use File::Temp qw/ tempfile tempdir /;

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

sub create_trashinfo_file {
	my $self = shift;
	my $filename = shift; #original filename
	
	my @data = @{$self->{_data}};
	
	my ( $tmpfh, $tmpfilename ) = tempfile(UNLINK => 1);

	open FILE, ">:utf8", $tmpfilename or die $!;
	foreach my $line (@data){
		if($line =~ /Path=<abspath>/){
			#remove placeholder
			$line =~ s/<abspath>/$filename/;
		}elsif($line =~ /DeletionDate=<ddate>/){
			#FIXME: Not implemented yet, see http://www.ramendik.ru/docs/trashspec.html
			my $ddate = '';
			#remove placeholder
			$line =~ s/<ddate>/$ddate/;
		}
		print FILE $line;
	}
	close FILE or die $!;	
	
	return $tmpfilename;
}

1;

__DATA__
[Trash Info]
Path=<abspath>
DeletionDate=<ddate>

