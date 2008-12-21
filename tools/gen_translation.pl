#! /usr/bin/perl

#Copyright (C) Mario Kemper 2008 <mario.kemper@googlemail.com> Mi, 09 Apr 2008 22:58:09 +0200

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

use utf8;
use strict;
use warnings;

#read files to translate
open( LIST, "./to_translate" ) or die $!;
my @translate_files = <LIST>;
close LIST or die $!;

my $time = time;
#create file
system("touch ./gscrot_$time.pot");

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
		$_ =~ s/\$gscrot\_common->get\_gettext->get/gettext/ig;
		$_ =~ s/\$gscrot\_common->get\_gettext->nget/ngettext/ig;
		print FILE_TMP $_ . "\n";
	}
	close FILE     or die $!;
	close FILE_TMP or die $!;

	system("xgettext ./translate_tmp.pl --language=Perl -j -o gscrot_$time.pot");
	unlink("./translate_tmp.pl");

}

