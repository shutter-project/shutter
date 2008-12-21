#! /usr/bin/perl

###################################################
#
#  Copyright (C) Mario Kemper 2008 <mario.kemper@googlemail.com>
#
#  This file is part of GScrot.
#
#  GScrot is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  GScrot is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with GScrot; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
###################################################

use utf8;
use strict;
use warnings;

my $time     = time;
my $language = "--language=Shell";

#create file
system("touch ./gscrot_plugins_bash$time.pot");

#read files to translate
open( LIST, "./to_translate_bash" ) or die $!;
my @translate_files = <LIST>;
close LIST or die $!;

#open files to translate
foreach my $file (@translate_files) {
	chomp $file;

	#folder? then add files included
	if ( -d $file ) {
		if ( $file =~ /bash/ ) {
			$language = "--language=Shell";
		} elsif ( $file =~ /perl/ ) {
			$language = "--language=Perl";
		}
		my @new_files = <$file/*>;
		push( @translate_files, @new_files );
		next;
	}
	next unless ( -T $file );    #textfile??
	next if ( $file =~ /\.svg/ );    #svg file??

	open( FILE, $file ) or die $! . " :$file";
	$file =~ s{^.*/}{};
	open( FILE_TMP, ">./translate_tmp.sh" ) or die $!;
	print "Preparing file $file\n";
	while (<FILE>) {
		chomp;

		if ( $language eq "--language=Perl" ) {
			$_ =~ s/\$d->get/gettext/ig;
			$_ =~ s/\$d->nget/ngettext/ig;
			$_ =~ s/\$self->\{\_gettext\_object\}->get/gettext/ig;
			$_ =~ s/\$self->\{\_gettext\_object\}->nget/ngettext/ig;
			$_ =~ s/\$gscrot\_common->get\_gettext->get/gettext/ig;
			$_ =~ s/\$gscrot\_common->get\_gettext->nget/ngettext/ig;
		}

		print FILE_TMP $_ . "\n";
	}
	close FILE     or die $!;
	close FILE_TMP or die $!;
	print "Done file $file\n";

	system("xgettext ./translate_tmp.sh $language -j -o ./gscrot_plugins_bash$time.pot");
	unlink("./translate_tmp.sh");
}

