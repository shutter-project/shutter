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

package Shutter::App::TrashInfo;

use utf8;
use strict;
use warnings;

use Glib qw/TRUE FALSE/; 
use POSIX qw/ strftime /;
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
			#The date and time are to be in the YYYY-MM-DDThh:mm:ss format (see RFC 3339).
			#The time zone should be the user's (or filesystem's) local time. The value type for this key is “string”.
			my $ddate = strftime "%Y-%m-%dT%H:%M:%S", localtime;
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

