package File::MimeInfo::Applications;

use strict;
use Carp;
use File::Spec;
use File::BaseDir qw/data_home data_dirs data_files/;
use File::MimeInfo qw/mimetype_canon mimetype_isa/;
use File::DesktopEntry;
require Exporter;

our $VERSION = '0.15';

our @ISA = qw(Exporter);
our @EXPORT = qw(
	mime_applications mime_applications_all
	mime_applications_set_default mime_applications_set_custom
);

print STDERR << 'EOT' unless data_files(qw/applications mimeinfo.cache/);
WARNING: You don't seem to have any mimeinfo.cache files.
Try running the update-desktop-database command. If you
don't have this command you should install the 
desktop-file-utils package. This package is available from
http://freedesktop.org/wiki/Software_2fdesktop_2dfile_2dutils
EOT

sub mime_applications {
	croak "usage: mime_applications(MIMETYPE)" unless @_ == 1;
	my $mime = mimetype_canon(shift @_);
	local $Carp::CarpLevel = $Carp::CarpLevel + 1;
	return wantarray ? (_default($mime), _others($mime)) : _default($mime); 
}

sub mime_applications_all {
	croak "usage: mime_applications(MIMETYPE)" unless @_ == 1;
	my $mime = shift;
	return mime_applications($mime),
		grep defined($_), map mime_applications($_), mimetype_isa($mime);
}

sub mime_applications_set_default {
	croak "usage: mime_applications_set_default(MIMETYPE, APPLICATION)"
		unless @_ == 2;
	my ($mimetype, $desktop_file) = @_;
	(undef, undef, $desktop_file) =
		File::Spec->splitpath($desktop_file->{file})
		if ref $desktop_file;
	croak "missing desktop entry filename for application"
		unless length $desktop_file;
	$desktop_file .= '.desktop' unless $desktop_file =~ /\.desktop$/;
	_write_list($mimetype, $desktop_file);
}

sub mime_applications_set_custom {
	croak "usage: mime_applications_set_custom(MIMETYPE, COMMAND)"
		unless @_ == 2;
	my ($mimetype, $command) = @_;
	$command =~ /(\w+)/;
	my $word = $1 or croak "COMMAND does not contain a word !?";

	# Algorithm to generate name copied from other implementations
	my $i = 1;
	my $desktop_file =
		data_home('applications', $word.'-usercreated-'.$i.'.desktop');
	while (-e $desktop_file) {
		$i++;
		$desktop_file =
		data_home('applications', $word.'-usercreated-'.$i.'.desktop');
	}

	my $object = File::DesktopEntry->new();
	$object->set(
		Type      => 'Application',
		Name      => $word,
		NoDsiplay => 'true',
		Exec      => $command,
	);
	my (undef, undef, $df) = File::Spec->splitpath($desktop_file);
	_write_list($mimetype, $df); # creates dir if needed
	$object->write($desktop_file);
	return $object;
}

sub _default {
	my $mimetype = shift;
	my $file = data_home(qw/applications defaults.list/);
	return undef unless -f $file && -r _;
	
	$Carp::CarpLevel++;
	my @list = _read_list($mimetype, $file);
	my $desktop_file = _find_file(reverse @list);
	$Carp::CarpLevel--;

	return $desktop_file;
}

sub _others {
	my $mimetype = shift;
	
	$Carp::CarpLevel++;
	my (@list, @done);
	for my $dir (data_dirs('applications')) {
		my $cache = File::Spec->catfile($dir, 'mimeinfo.cache');
		next if grep {$_ eq $cache} @done;
		push @done, $cache;
		next unless -f $cache and -r _;
		for (_read_list($mimetype, $cache)) {
			my $file = File::Spec->catfile($dir, $_);
			next unless -f $file and -r _;
			push @list, File::DesktopEntry->new($file);
		}
	}
	$Carp::CarpLevel--;

	return @list;
}

sub _read_list { # read list with "mime/type=foo.desktop;bar.desktop" format
	my ($mimetype, $file) = @_;
	my @list;
	open LIST, '<', $file or croak "Could not read file: $file";
	while (<LIST>) {
		/^$mimetype=(.*)$/ or next;
		push @list, grep defined($_), split ';', $1;
	}
	close LIST;

	return @list;
}

sub _write_list {
	my ($mimetype, $desktop_file) = @_;
	my $file = data_home(qw/applications defaults.list/);
	my $text;
	if (-f $file) {
		open LIST, '<', $file or croak "Could not read file: $file";
		while (<LIST>) {
			$text .= $_ unless /^$mimetype=/;
		}
		close LIST;
		$text =~ s/[\n\r]?$/\n/; # just to be sure
	}
	else {
		_mkdir($file);
		$text = "[Default Applications]\n";
	}

	open LIST, '>', $file or croak "Could not write file: $file";
	print LIST $text;
	print LIST "$mimetype=$desktop_file;\n";
	close LIST or croak "Could not write file: $file";
}

sub _find_file {
	my @list = shift;
	for (@list) {
		my $file = data_files('applications', $_);
		return File::DesktopEntry->new($file) if $file;
	}
	return undef;
}

sub _mkdir {
	my $dir = shift;
	return if -d $dir;
	
	my ($vol, $dirs, undef) = File::Spec->splitpath($dir);
	my @dirs = File::Spec->splitdir($dirs);
	my $path = File::Spec->catpath($vol, shift @dirs);
	while (@dirs) {
		mkdir $path; # fails silently
		$path = File::Spec->catdir($path, shift @dirs);
	}
	
	die "Could not create dir: $path\n" unless -d $path;
}

1;

__END__

=head1 NAME

File::MimeInfo::Applications - Find programs to open a file by mimetype

=head1 SYNOPSIS

  use File::MimeInfo::Magic;
  use File::MimeInfo::Applications;
  
  my $file = '/foo/bar';
  my $mimetype = mimetype($file)
      || die "Could not find mimetype for $file\n";
      
  my ($default, @other) = mime_applications($mimetype);
  
  if (defined $default) {
      $default->system($file)
  }
  else {
	  # prompt user with choice from @others
	  # ...
  }

=head1 DESCRIPTION

This module tries to find applications that can open files
with a certain mimetype. This is done in the way suggested by
the freedesktop Desktop Entry specification. This module is 
intended to be compatible with file managers and other applications that
implement this specification.

This module depends on L<File::DesktopEntry> being installed.

To use this module effectively you need to have the desktop-file-utils
package from freedesktop and run update-desktop-database after installing
new .desktop files.
See L<http://www.freedesktop.org/wiki/Software/desktop-file-utils>.

At the moment of writing this module is compatible with the way Nautilus (Gnome)
and with Thunar (XFCE) handle applications for mimetypes. I understand KDE 
is still working on implementing the freedesktop mime specifications but will
follow. At the very least all perl applications using this module are using
the same defaults.

=head1 EXPORT

All methods are exported by default.

=head1 METHODS

=over 4

=item C<mime_applications(MIMETYPE)>

Returns an array of L<File::DesktopEntry> objects. The first
is the default application for this mimetype, the rest are
applications that say they can handle this mimetype.

If the first result is undefined there is no default application
and it is good practise to ask the user which application he wants
to use.

=item C<mime_applications_all(MIMETYPE)>

Like C<mime_applications()> but also takes into account applications that 
can open mimetypes from which MIMETYPE inherits. Parent mimetypes tell
aomething about the data format, all code inherits from text/plain for example.

=item C<mime_applications_set_default(MIMETYPE, APPLICATION)>

Save a default application for this mimetype. This action will
affect other applications using the same mechanism to find a default
appliction.

APPLICATION can either be a File::DesktopEntry object or 
the basename of a .desktop file.

=item C<mime_applications_set_custom(MIMETYPE, COMMAND)>

Save a custom shell command as default application.
Generates a DesktopEntry file on the fly and calls
C<mime_applications_set_custom>.
Returns the DesktopEntry object.

No checks are done at all on COMMAND.
It should however contain at least one word.

=back

=head1 NOTES

At present the file with defaults is
F<$XDG_DATA_HOME/applications/defaults.list>.
This file is not specified in any freedesktop spec and if it gets standardized
it should probably be located in C<$XDG_CONFIG_HOME>. For this module I tried
to implement the status quo.

=head1 BUGS

Please mail the author when you encounter any bugs.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2005,2008 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<File::DesktopEntry>,
L<File::MimeInfo>,
L<File::MimeInfo::Magic>,
L<File::BaseDir>

L<http://freedesktop.org/wiki/Software_2fdesktop_2dfile_2dutils>

=cut
