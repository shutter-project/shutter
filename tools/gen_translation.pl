#! /usr/bin/env perl

###################################################
#
#  Copyright (C) 2008, 2009 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
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

use utf8;
use strict;
use warnings;

#read files to translate
open( LIST, "./to_translate" ) or die $!;
my @translate_files = <LIST>;
close LIST or die $!;

my $time = time;
#create file
system("touch ./shutter_$time.pot");

#open files to translate
my $file = undef;
foreach $file (@translate_files) {
	chomp $file;
	next unless ( -f $file );
	open( FILE, $file ) or die $! . " :$file";
	$file =~ s{^.*/}{};
	open( FILE_TMP, ">./translate_tmp.pl" ) or die $!;
	print "Preparing file $file\n";
	while (<FILE>) {
		chomp;
		next if $_ =~ /^\#/;
		next if $_ =~ /^__END/;
		$_ =~ s/\$d->get/gettext/ig;
		$_ =~ s/\$d->nget/ngettext/ig;
		$_ =~ s/\$self->\{\_gettext\_object\}->get/gettext/ig;
		$_ =~ s/\$self->\{\_gettext\_object\}->nget/ngettext/ig;
		$_ =~ s/\$shutter\_common->get\_gettext->get/gettext/ig;
		$_ =~ s/\$shutter\_common->get\_gettext->nget/ngettext/ig;
		print FILE_TMP $_ . "\n";
	}
	close FILE     or die $!;
	close FILE_TMP or die $!;

	system("xgettext ./translate_tmp.pl --language=Perl -j -o shutter_$time.pot");
	unlink("./translate_tmp.pl");

}

