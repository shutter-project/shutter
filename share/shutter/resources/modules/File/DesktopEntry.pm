package File::DesktopEntry;

use strict;
use vars qw/$AUTOLOAD/;
use Carp;
use File::Spec;
use File::BaseDir 0.03 qw/data_files data_home/;

our $VERSION = 0.04;
our $VERBOSE = 0;

if ($^O eq 'MSWin32') {
	eval q/use Win32::Process/;
	die $@ if $@;
}

=head1 NAME

File::DesktopEntry - Object to handle .desktop files

=head1 SYNOPSIS

	use File::DesktopEntry;
	
	my $entry = File::DesktopEntry->new('firefox');

	print "Using ".$entry->Name." to open http://perl.org\n";
	$entry->run('http://perl.org');

=head1 DESCRIPTION

This module is used to work with F<.desktop> files. The format of these files
is specified by the freedesktop "Desktop Entry" specification. This module can
parse these files but also knows how to run the applciations defined by these
files.

For this module version 1.0 of the specification was used.

This module was written to support L<File::MimeInfo::Applications>.

Please remember: case is significant for the names of Desktop Entry keys.

=head1 VARIABLES

You can set the global variable C<$File::DesktopEntry::VERBOSE>. If set the
module print a warning every time a command gets executed.

The global variable C<$File::DesktopEntry::LOCALE> tells you what the default
locale being used is. However, changing it will not change the default locale.

=head1 AUTOLOAD

All methods that start with a capital are autoloaded as C<get(KEY)> where
key is the autoloaded method name.

=head1 METHODS

=over 4

=item C<new(FILE)>

=item C<new(\$TEXT)>

=item C<new(NAME)>

Constructor. FILE, NAME or TEXT are optional arguments.

When a name is given (a string without 'C</>', 'C<\>' or 'C<.>') a lookup is
done using File::BaseDir. If the file found in this lookup is not writable or
if no file was found, the XDG_DATA_HOME path will be used when writing.

=cut

our $LOCALE = 'C';

# POSIX setlocale(LC_MESSAGES) not supported on all platforms
# so we do it ourselves ...
# string might look like lang_COUNTRY.ENCODING@MODIFIER
for (qw/LC_ALL LC_MESSAGES LANGUAGE LANG/) {
	next unless $ENV{$_};
	$LOCALE = $ENV{$_};
	last;
}
our $_locale = _parse_lang($LOCALE);

sub new {
	my ($class, $file) = @_;
	my $self = bless {}, $class;
	if (! defined $file) { # initialise new file
		$self->set(Version => '1.0', Encoding => 'UTF-8');
	}
	elsif (ref $file)           { $self->read($file)   } # SCALAR
	elsif ($file =~ /[\/\\\.]/) { $$self{file} = $file } # file
	else {
		$$self{file} = $class->lookup($file);     # name
		$$self{name} = $file;
	}
	return $self;
}

sub AUTOLOAD {
	$AUTOLOAD =~ s/.*:://;
	return if $AUTOLOAD eq 'DESTROY';
	croak "No such method: File::DesktopEntry::$AUTOLOAD"
		unless $AUTOLOAD =~ /^[A-Z][A-Za-z0-9-]+$/;
	return $_[0]->get($AUTOLOAD);
}

=item C<lookup(NAME)>

Returns a filename for a desktop entry with desktop file id NAME.

=cut

sub lookup {
	my (undef, $name) = @_;
	$name .= '.desktop';
	my $file = data_files('applications', $name);
	if (! $file and $name =~ /-/) {
		# name contains "-" and was not found
		my @name = split /-/, $name;
		$file = data_files('applications', @name);
	}
	return $file;
}

sub _parse_lang {
	# lang might look like lang_COUNTRY.ENCODING@MODIFIER
	my $lang = shift;
	return '' if !$lang or $lang eq 'C' or $lang eq 'POSIX';
	$lang =~ m{^
		([^_@\.]+)		# lang	   $1
		(?: _  ([^@\.]+) )?	# COUNTRY  $2
		(?: \.  [^@]+    )?	# ENCODING 
		(?: \@ (.+)      )?	# MODIFIER $3
	$}x or return '';
	my ($l, $c, $m) = ($1, $2, $3);
	my @locale = (
		$l,
		($m         ? "$l\@$m"     : ()),
		($c         ? "$l\_$c"     : ()),
		(($m && $c) ? "$l\_$c\@$m" : ())  );
	return join '|', reverse @locale;
}

=item C<wants_uris( )>

Returns true if the Exec string for this desktop entry specifies that the
application uses URIs instead of paths. This can be used to determine
whether an application uses a VFS library.

=item C<wants_list( )>

Returns true if the Exec tring for this desktop entry specifies that the
application can handle multiple arguments at once.

=cut


sub wants_uris {
	my $self = shift;
	my $exec = $self->get('Exec');
	croak "No Exec string defined for desktop entry" unless length $exec;
	$exec =~ s/\%\%//g;
	return $exec =~ /\%U/i;
}

sub wants_list {
	my $self = shift;
	my $exec = $self->get('Exec');
	croak "No Exec string defined for desktop entry" unless length $exec;
	$exec =~ s/\%\%//g;
	return $exec !~ /\%[fud]/; # we default to %F if no /\%[FUD]/i is found
}
	
=item C<run(@FILES)>

Forks and runs the application specified in this Desktop Entry
with arguments FILES as a background process. Returns the pid.

The child process fails when this is not a Desktop Entry of type Application
or if the Exec key is missing or invalid.

If the desktop entry specifies that the program needs to be executed in a
terminal the $TERMINAL environment variable is used. If this variable is not
set C<xterm -e> is used as default.

(On Windows this method returns a L<Win32::Process> object.)

=item C<system(@FILES)>

Like C<run()> but using the C<system()> system call.
It only return after the application has ended.

=item C<exec(@FILES)>

Like C<run()> but using the C<exec()> system call. This method
is expected not to return but to replace the current process with the 
application you try to run.

On Windows this method doesn't always work the way you want it to
due to the C<fork()> emulation on this platform. Try using C<run()> or
C<system()> instead.

=cut

sub run {
	my $pid = fork;
	return $pid if $pid; # parent process
	unshift @_, 'exec'; goto \&_run;
}

sub system { unshift @_, 'system'; goto \&_run }

sub exec   { unshift @_, 'exec';   goto \&_run }

sub _run {
	my $call = shift;
	my $self = shift;
	
	croak "Desktop entry is not an Application"
		unless $self->get('Type') eq 'Application';

	my @exec = $self->parse_Exec(@_);

	my $t = $self->get('Terminal');
	if ($t and $t eq 'true') {
		my $term = $ENV{TERMINAL} || 'xterm -e';
		unshift @exec, _split($term);
	}

	my $cwd;
	if (my $path = $self->get('Path')) {
		require Cwd;
		$cwd = Cwd::getcwd();
		chdir $path or croak "Could not change to dir: $path";
		$ENV{PWD} = $path;
		warn "Running from directory: $path\n" if $VERBOSE;
	}
	
	warn "Running: "._quote(@exec)."\n" if $VERBOSE;
	#warn "RUNNING:\n", map "\t>>$_<<\n", @exec;
	if ($call eq 'exec') { CORE::exec   {$exec[0]} @exec; exit 1 }
	else                 { CORE::system {$exec[0]} @exec         }
	warn "Error: $!\n" if $VERBOSE and $?;

	if (defined $cwd) {
		chdir $cwd or croak "Could not change back to dir: $cwd";
		$ENV{PWD} = $cwd;
	}
}

=item C<parse_Exec(@FILES)>

Expands the Exec format in this desktop entry with. Returns a properly quoted
string in scalar context or a list of words in list context. Dies when the
Exec key is invalid.

It supports the following fields:

	%f	single file
	%F	multiple files
	%u	single url
	%U	multiple urls
	%i	Icon field prefixed by --icon
	%c	Name field, possibly translated
	%k	location of this .desktop file
	%%	literal '%'

If necessary this method tries to convert between paths and URLs but this
is not perfect.

Fields that are deprecated, but (still) supported by this module:

	%d	single directory
	%D	multiple directories

The fields C<%n>, C<%N>, C<%v> and C<%m> are deprecated and will cause a
warning if C<$VERBOSE> is used. Any other unknown fields will cause an error.

The fields C<%F>, C<%U>, C<%D> and C<%i> can only occur as seperate words
because they expand to multiple arguments.

Also see L</LIMITATIONS>.

=cut

sub parse_Exec {
	my ($self, @argv) = @_;
	my @format = _split( $self->get('Exec') );
	
	# Check format
	my $seen = 0;
	for (@format) {
		my $s = $_; # copy;
		$s =~ s/\%\%//g;
		$seen += ($s =~ /\%[fFuUdD]/);

		die "Exec key for '".$self->get('Name')."' contains " .
		    "'\%F\', '\%U' or '\%D' at the wrong place\n"
			if $s !~ /^\%[FUD]$/ and $s =~ /\%[FUD]/;
		
		die "Exec key for '".$self->get('Name')."' contains " .
		    "unknown field code '$1'\n"
			if $s =~ /(\%[^fFuUdDnNickvm])/;
		
		croak "Application '".$self->get('Name')."' ".
		      "takes only one argument"
			if @argv > 1 and $s =~ /\%[fud]/;
	
		warn "Exec key for '".$self->get('Name')."' contains " .
		     "deprecated field codes\n"
			if $VERBOSE and $s =~ /%([nNvm])/;
	}
	if    ($seen == 0) { push @format, '%F' }
	elsif ($seen >  1) {
		# not allowed according to the spec
		warn "Exec key for '".$self->get('Name')."' contains " .
		     "multiple fields for files or uris.\n"
	}

	# Expand format
	my @exec;
	#warn "FORMAT:\n", map "\t>>$_<<\n", @format;
	for (@format) {
		if (/^\%([FUD])$/) {
			push @exec,
				($1 eq 'F') ? _paths(@argv) :
				($1 eq 'U') ? _uris(@argv)  : _dirs(@argv)  ;
		}
		elsif ($_ eq '%i') {
			my $icon = $self->get('Icon');
			push @exec, '--icon', $icon if defined($icon);
		}
		else { # expand with word ( e.g. --input=%f )
			my $bad;
			s/\%(.)/
				($1 eq '%') ? '%'                :
				($1 eq 'f') ? (_paths(@argv))[0] :
				($1 eq 'u') ? (_uris(@argv) )[0] :
				($1 eq 'd') ? (_dirs(@argv) )[0] :
				($1 eq 'c') ? $self->get('Name') :
				($1 eq 'k') ? $$self{file}       : '' ;
			/eg;

			push @exec, $_;
		}
	}
	#warn "EXEC:\n", map "\t>>$_<<\n", @exec;

	if (wantarray and $^O eq 'MSWin32') {
		# Win32 requires different quoting *sigh*
		for (grep /"/, @exec) {
				s#"#\\"#g;
				$_ = qq#"$_"#;
		}
	}
	return wantarray ? (@exec) : _quote(@exec);
}

sub _split {
	# Reverse quoting and break string in words.
	# It allows single quotes to be used, which the spec doesn't.
	my $string = shift;
	my @args;
	while ($string =~ /\S/) {
		if ($string =~ /^(['"])/) {
			my $q = $1;
			$string =~ s/^($q(\\.|[^$q])*$q)//s;
			push @args, $1 if defined $1;
		}
		$string =~ s/(\S*)\s*//; # also fallback for above regex
		push @args, $1 if defined $1;
	}
	@args = grep length($_), @args;
	for (@args) {
		if (/^(["'])(.*)\1$/s) {
			$_ = $2;
			s/\\(["`\$\\])/$1/g; # remove backslashes
		}
	}
	return @args;
}

sub _quote {
	# Turn a list of words in a properly quoted Exec key
	my @words = @_; # copy;
	return join ' ', map {
		if (/([\s"'`\\<>~\|\&;\$\*\?#\(\)])/) { # reserved chars
			s/(["`\$\\])/\\$1/g; # add backslashes
			$_ = qq/"$_"/;       # add quotes
		}
		$_;
	} grep defined($_), @words;
}

sub _paths {
	# Check if we need to convert file:// uris to paths
	# support file:/path file://localhost/path and file:///path
	# A path like file://host/path is replace by smb://host/path
	# which the app probably can't open
	map {
		s#^file:(?://localhost/+|/|///+)(?!/)#/#i;
		s#^file://(?!/)#smb://#i;
		$_;
	} @_;
}

sub _dirs {
	# Like _paths, but makes the path a directory
	map {
		if (-d $_) { $_ }
		else {
			my ($vol, $dirs, undef) = File::Spec->splitpath($_);
			File::Spec->catpath($vol, $dirs, '');
		}
	} _paths(@_);
}

sub _uris {
	# Convert paths to file:// uris
	map {
		m#^\w+://# ? $_ : 'file://'.File::Spec->rel2abs($_) ;
	} @_;
}

=item C<get(KEY)>

=item C<get(GROUP, KEY)>

Get a value for KEY from GROUP. If GROUP is not specified 'Desktop Entry' is
used. All values are treated as string, so e.g. booleans will be returned as
the literal strings "true" and "false".

When KEY does not contain a language code you get the translation in the
current locale if available or a sensible default. The request a specific
language you can add the language part. E.g. C<< $entry->get('Name[nl_NL]') >>
can return either the value of the 'Name[nl_NL]', the 'Name[nl]' or the 'Name'
key in the Desktop Entry file. Exact language parsing order can be found in the
spec. To force you get the untranslated key use either 'Name[C]' or
'Name[POSIX]'.

=cut

# used for (un-)escaping strings
my %Chr = (s => ' ', n => "\n", r => "\r", t => "\t", '\\' => '\\');
my %Esc = reverse %Chr;

sub get {
	my ($self, $group, $key) = 
		(@_ == 2) ? ($_[0], '', $_[1]) : (@_) ;
	my $locale = $_locale;
	if ($key =~ /^(.*?)\[(.*?)\]$/) {
		$key = $1;
		$locale = _parse_lang($2);
	}
	#warn "GET: \"$key\" from \"$group\" ($locale)\n";
	my @lang = split /\|/, $locale;

	# Get values that match locale from group
	$self->read() unless $$self{groups};
	my $i = $self->_group($group);
	return undef unless defined $i;
	my $lang = join('|', map quotemeta($_), @lang) || 'C';
	my %matches = ( $$self{groups}[$i] =~
		/^(\Q$key\E\[(?:$lang)\]|\Q$key\E)\s*=\s*(.*?)\s*$/gm );
	return undef unless keys %matches;

	# Find preferred value
	#use Data::Dumper; warn "MATCHES: ", Dumper \%matches;
	my @keys = (map($key."[$_]", @lang), $key);
	my ($value) = grep defined($_), @matches{@keys};

	# Parse string (replace \n, \t, etc.)
	$value =~ s/\\(.)/$Chr{$1}||$1/eg;
	return $value;
}

sub _group { # returns index for a group name
	my ($self, $group, $dont_die) = @_;
	$group ||= 'Desktop Entry';
	croak "Group name contains invalid characters: $group"
		if $group =~ /[\[\]\r\n]/;
	for my $i (0 .. $#{$$self{groups}}) {
		return $i if $$self{groups}[$i] =~ /^\[\Q$group\E\]/;
	}
	return undef;
}

=item C<set(KEY => VALUE, ...)>

=item C<set(GROUP, KEY => VALUE, ...)>

Set values for one or more keys. If GROUP is not given "Desktop Entry" is used.
All values are treated as strings, backslashes, newlines and tabs are escaped.
To set a boolean key you need to use the literal strings "true" and "false".

Unlike the C<get()> call languages are not handled automatically for C<set()>.
KEY should include the language part if you want to set a translation.
E.g. C<< $entry->set("Name[nl_NL]" => "Tekst Verwerker") >> will set a Dutch
translation for the Name key. Using either "Name[C]" or "Name[POSIX]" will
be equivalent with not giving a language argument.

When setting the the Exec key without specifying a group it will be parsed
and quoted correctly as required by the spec. You can use quoted arguments
to include whitespace in a argument, escaping whitespace does not work.
To circumvent this quoting explicitly give the group name 'Desktop Entry'.

=cut

sub set {
	my $self = shift;
	my ($group, @data) = ($#_ % 2) ? (undef, @_) : (@_) ;

	$self->read() unless $$self{groups} or ! $$self{file};
	my $i = $self->_group($group);
	unless (defined $i) {
		$group ||= 'Desktop Entry';
		push @{$$self{groups}}, "[$group]\n";
		$i = $#{$$self{groups}};
	}

	#warn "SET: ($group) ".join(', ', map qq#"$_"#, @data)."\n";
	while (@data) {
		my ($k, $v) = splice(@data, 0, 2);
		$k =~ s/\[(C|POSIX)\]$//;  # remove default locale
		my ($word) = ($k =~ /^(.*?)(\[.*?\])?$/);
			# seperate key and locale
		croak "BUG: Key missing: $k" unless length $word;
		carp "Key contains invalid characters: $k"
			if $word =~ /[^A-Za-z0-9-]/;
		$v = _quote( _split($v) ) if ! $group and $k eq 'Exec';
			# Exec key needs extra quoting
		$v =~ s/([\\\n\r\t])/\\$Esc{$1}/g; # add escapes
		#warn qq#SET "$k" => "$v"\n#;
		$$self{groups}[$i] =~ s/^\Q$k\E=.*$/$k=$v/m and next;
		$$self{groups}[$i] .= "$k=$v\n";
	}
	#use Data::Dumper; warn Dumper $self;
}

=item C<text()>

Returns the (modified) text of the file.

=cut

sub text { 
	$_[0]->read() unless $_[0]{groups};
	return '' unless $_[0]{groups};
	s/\n?$/\n/ for @{$_[0]{groups}}; # just to be sure
	return join "\n", @{$_[0]{groups}};
}

=item C<read(FILE)>

=item C<read(\$SCALAR)>

Read Desktop Entry data from file or memory buffer.
Without argument defaults to file given at constructor.

If you gave a file, text buffer or name to the constructor this method will
be called automatically.

=item C<read_fh(IO)>

Read Desktop Entry data from filehandle or IO object.

=cut

sub read {
	my ($self, $file) = @_;
	$file ||= $$self{file};
	#warn "READ: $file called by ".join(' ', caller)."\n";
	croak "DesktopEntry has no filename to read from" unless length $file;

	my $fh;
	unless (ref $file)  {
		open $fh, "<$file" or croak "Could not open file: $file";
	}
	elsif ($] >= 5.008) {
		open $fh, '<', $file or croak "Could not open SCALAR ref !?";
	}
	else { # scalar ref needs dependency for perl < 5.008
		require IO::Scalar;
		$fh = IO::Scalar->new($file);
	}
	binmode $fh, ':utf8' unless $] < 5.008;
	$self->read_fh($fh);
	close $fh;
}

sub read_fh {
	my ($self, $fh) = @_;
	$$self{groups} = [];
	#warn "READ_FH: $fh\n";

	# Read groups
	my $group = '';
	while (my $l = <$fh>) {
		$l =~ s/\r?\n$/\n/; # DOS to Unix conversion
		if ($l =~ /^\[(.*?)\]\s*$/) {
			push @{$$self{groups}}, $group
				if length $group;
			$group = '';
		}
		$group .= $l;
	}
	push @{$$self{groups}}, $group;
	s/\n\n$/\n/ for @{$$self{groups}}; # remove last empty line
	#warn "GROUP: >>\n",$_,"<<\n" for @{$$self{groups}};
	
	# Some checks
	for (qw/Name Type/) {
		carp "Required key missing in Desktop Entry: $_"
			unless defined $self->get($_);
	}
	my $enc = $self->get('Encoding');
	carp "Desktop Entry uses unsupported encoding: $enc"
		if $enc and $enc ne 'UTF-8';
}

=item C<write(FILE)>

Write the Desktop Entry data to FILE. Without arguments it writes to
the filename given to the constructor if any.

The keys Name and Type are required. Type can be either C<Application>,
C<Link> or C<Directory>. For an application set the optional key C<Exec>. For
a link set the C<URL> key. 

=cut

# Officially we should check lines end with LF - this is \n on Unix
# but on Windows \n is CR LF, which breaks the spec

sub write {
	my $self = shift;
	my $file = shift || $$self{file};
	unless ($$self{groups}) {
		if ($$self{file}) { $self->read() }
		else { croak "Can not write empty Desktop Entry file" }
	}

	# Check keys
	for (qw/Name Type/) {
		croak "Can not write a desktop file without a $_ field"
			unless defined $self->get($_);
	}
	$self->set(Version => '1.0', Encoding => 'UTF-8');

	# Check file writable
	$file = $self->_data_home_file
		if (! $file or ! -w $file) and defined $$self{name};
	croak "No file given for writing Desktop Entry" unless length $file;

	# Write file
	s/\n?$/\n/ for @{$$self{groups}}; # just to be sure
	open OUT, ">$file" or die "Could not write file: $file\n";
	binmode OUT, ':utf8' unless $] < 5.008;
	print OUT join "\n", @{$$self{groups}};
	close OUT;
}

sub _data_home_file {
	# create new file name in XDG_DATA_HOME from name
	my $self = shift;
	my @parts = split /-/, $$self{name};
	$parts[-1] .= '.desktop';
	my $dir = data_home('applications', @parts[0 .. $#parts-1]);
	unless (-d $dir) { # create dir if it doesn't exist
		require File::Path;
		File::Path::mkpath($dir);
	}
	return data_home('applications', @parts);
}

=back

=head2 Backwards Compatibility

Methods supported for backwards compatibility with 0.02.

=over 4

=item C<new_from_file(FILE)>

Alias for C<new(FILE)>.

=item C<new_from_data(TEXT)>

Alias for C<new(\$TEXT)>.

=item C<get_value(NAME, GROUP, LANG)>

Identical to C<get(GROUP, "NAME[LANG]")>.
LANG defaults to 'C', GROUP is optional.

=cut

sub new_from_file { $_[0]->new($_[1])  }

sub new_from_data { $_[0]->new(\$_[1]) }

sub get_value {
	my ($self, $key, $group, $locale) = @_;
	$locale ||= 'C';
	$key .= "[$locale]";
	$group ? $self->get($group, $key) : $self->get($key);
}

=back

=head1 NON-UNIX PLATFORMS

This module has a few bit of code to make it save on Windows. It handles
C<file://> uri a bit different and it uses L<Win32::Process>. On other
platforms your mileage may vary.

Please note that the specification is targeting Unix platforms only and
will only have limited relevance on other platforms. Any platform dependend
behavior in this module should be considerd an extension of the spec.

=cut

if ($^O eq 'MSWin32') {
	# Re-define some modules - I assume this block gets optimized away by the
	# interpreter when not runnig on windows.
	no warnings;

	# Wrap _paths() to remove first '/'
	# As a special case tranlate SMB file:// uris
	my $_paths = \&_paths;
	*_paths = sub {
		my @paths = map {
			s#^file:////(?!/)#smb://#;
			$_;
		} @_;
		map {
			s#^/+([a-z]:/)#$1#i;
			$_;
		} &$_paths(@paths);
	};

	# Wrap _uris() to remove '\' in path
	my $_uris = \&_uris;
	*_uris = sub {
		map {
			s#\\#/#g;
			$_;
		} &$_uris(@_);
	};
	
	# Using Win32::Process because fork is not native on win32
	# Effect is that closing an application spawned with fork
	# can kill the parent process as well when using Gtk2
	*run = sub {
		my ($self, @files) = @_;
		
		my $cmd = eval { $self->parse_Exec(@files) };
		warn $@ if $@; # run should not die

		my $bin = (_split($cmd))[0];
		unless (-f $bin) { # we need the real binary path
			my ($b) = grep {-f $_}
			         map File::Spec->catfile($_, $bin),
			         split /[:;]/, $ENV{PATH} ;
			if (-f $b) { $bin = $b }
			else {
				warn "Could not find application: $bin\n";
				return;
			}
		}
		
		my $dir = $self->get('Path') || '.';
		
		if ($VERBOSE) {
				warn "Running from directory: $dir" unless $dir eq '.';
				warn "Running: $cmd\n";
		}
		my $obj;
		eval {
			Win32::Process::Create(
				$obj, $bin, $cmd, 0, &NORMAL_PRIORITY_CLASS, $dir );
		};
		warn $@ if $@;
		return $obj;
	};

}


1;

__END__

=head1 LIMITATIONS

If you try to exec a remote file with an application that can only handle files
on the local file system we should -according to the spec- download the file to
a temp location. This is not supported. Use the C<wants_uris()> method to check
if an application supports urls.

The values of the various Desktop Entry keys are not parsed (except for the
Exec key). This means that booleans will be returned as the strings "true" and
"false" and lists will still be ";" seperated.

If the icon is given as name and not as path it should be resolved for the C<%i>
code in the Exec key. We need a seperate module for the icon spec to deal with
this.

Files are read and writen using utf8, this is not available on perl versions
before 5.8. As a result for older perl versions translations in UTF-8 will not
be translated properly.

According to the spec comments can contain any encoding. However since this
module read files as utf8, invalid UTF-8 characters in a comment will cause
an error.

There is no support for Legacy-Mixed Encoding. Everybody is using utf8 now
... right ?

=head1 AUTHOR

Jaap Karssenberg (Pardus) E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2005, 2007 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<http://www.freedesktop.org/wiki/Specifications/desktop-entry-spec>

L<File::BaseDir> and L<File::MimeInfo::Applications>

L<X11::FreeDesktop::DesktopEntry>

=cut

