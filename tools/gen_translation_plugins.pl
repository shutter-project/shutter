#! /usr/bin/env perl

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

use utf8;
use strict;
use warnings;

my $language = " ";

my $time = time;

#create file
system("touch ./shutter-plugins-perl.pot");
system("touch ./shutter-plugins-bash.pot");

#read files to translate
open( LIST, "./to_translate_bash" ) or die $!;
my @translate_files = <LIST>;
close LIST or die $!;

#open files to translate
foreach my $file (@translate_files) {
	chomp $file;

	#folder? then add files included
	if ( -d $file ) {
		my @new_files = <$file/*>;
		push( @translate_files, @new_files );
		next;
	}
	next unless ( -T $file );    #textfile??
	next if ( $file =~ /\.svg/ );    #svg file??

	open( FILE, $file ) or die $! . " :$file";
	if ( $file =~ /bash/ ) {
		$language = " ";
	} elsif ( $file =~ /perl/ ) {
		$language = "--language=Perl";
	}
	$file =~ s{^.*/}{};
	open( FILE_TMP, ">./translate_tmp" ) or die $!;
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

	if ( $language eq "--language=Perl" ) {
		system("xgettext ./translate_tmp $language -j -o ./shutter-plugins-perl.pot");
	} else {
		system(
			"bash --dump-po-strings ./translate_tmp | xgettext -L PO -j -o ./shutter-plugins-bash.pot - "
		);
	}
	unlink("./translate_tmp");

	print "Done file $file\n";
}

#concatenate the files
system(
	"msgcat ./shutter-plugins-bash.pot ./shutter-plugins-perl.pot > ./shutter-plugins-$time.pot"
);

#delete temp files
unlink("./shutter-plugins-perl.pot");
unlink("./shutter-plugins-bash.pot");

