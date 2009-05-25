package Net::DBus::Skype;

use Moose;
use File::Basename;
use Carp;

use Net::DBus;

our $VERSION = '0.02';

has 'debug' => ( isa => 'Bool', is => 'ro', default => 0 );

has 'dbus' => (
	isa       => 'Net::DBus'
	, is      => 'ro'
	, lazy    => 1
	, default => sub { Net::DBus->session }
);

has 'skype' => (
	isa            => 'Net::DBus::RemoteObject'
	, is           => 'rw'
	, lazy_build   => 1
);

around '_build_skype' => sub {
	my ( $sub, $self, @args ) = @_;
	my $skype = $self->$sub;
	$self->skype( $skype );
	$self->_init_skype;
	$skype;
};

sub _build_skype {
	my $self = shift;
	
	my $objects = $self->dbus
		->get_service("org.freedesktop.DBus")
		->get_object("/org/freedesktop/DBus")
	;

	my $skype_found = grep $_ eq 'com.Skype.API', @{$objects->ListNames};
	die 'No running API-capable Skype found'
		unless $skype_found
	;
	
	my $skype = $self->dbus
		->get_service('com.Skype.API')
		->get_object('/com/Skype', 'com.Skype.API')
	;

}

sub _init_skype {
	my $self = shift;

	{
		my $name = $0 eq '-e' ? 'action_handle' : File::Basename::basename($0);
		my $answer = $self->raw_skype("NAME $name");
		die 'Error communicating with Skype!'
			if $answer ne 'OK'
		;
	}

	{
		my $answer = $self->raw_skype('PROTOCOL 7');
		die 'Skype client too old!'
			if $answer ne 'PROTOCOL 7'
		;
	}

}

sub action {
	my ( $self, $arg ) = @_;

	my ( $user, $cmd, $multiuser );
	if ( $arg =~ /
		^
		(?:skype|callto|tel)
		:\/{0,2}
		([^?]+)
		(?:\??(.*))?
		$
	/x ) {
		$user = $1;
		$cmd  = $2 || 'call';
	}
	else {
		croak "Invalid argument! (format: skype:echo123?call)\n";
	}

	$multiuser = 1
		if $user =~ s/;/, /g
	;

	$cmd = lc($cmd);
	if ($cmd eq 'add') {
		croak "Command add takes only one user!\n"
			if $multiuser
		;
		$self->raw_skype("OPEN ADDAFRIEND $user")
	}
	
	elsif ($cmd eq 'call') {
		$self->raw_skype("CALL $user");
	}
	
	elsif ($cmd eq 'chat') {
		my $answer = $self->raw_skype("CHAT CREATE $user");
		my @chats = split(' ', $answer);
		$self->raw_skype("OPEN CHAT ".$chats[1]);
	}
	
	elsif ($cmd eq 'sendfile') {
		$self->raw_skype("OPEN FILETRANSFER $user");
	}
	
	elsif ($cmd eq 'userinfo') {
		croak "Command userinfo takes only one user!\n"
			if $multiuser
		;
		$self->raw_skype("OPEN USERINFO $user");
	}

	else {
		croak "Command $cmd currently unhandled!\n";
	}

}


sub raw_skype {
	my ($self, $cmd) = @_;

	my $answer = $self->skype->Invoke($cmd);
	print "$cmd: $answer\n" if $self->debug;
	
	return $answer;
}

1;

__END__

=head1 NAME

Net::DBus::Skype - Perl access to Skype's DBus API

=head1 DESCRIPTION

This module supplies a perl API into Skype via DBus. It was inspired by the discussion at L<http://forum.skype.com/lofiversion/index.php/t92761.html>, and adapted from Philipp Kolmann's code base. Nothing much of Philipps code remains other than his choice of error messagses.

B<If what your doing isn't specific to Skype, use the non proprietary "callto" protocol in your code! Example, href="callto:8325555555">

=head1 SYNOPSIS

	use Net::DBus::Skype;

	my $s = Net::DBus::Skype->new;
	my $s = Net::DBus::Skype->new({ debug => 1 });

	$s->action('skype:echo123?call');
	# -or-
	$s->action('skype:echo123');
	# -or-
	$s->action('skype://echo123');
	# -or-
	$s->raw_skype('CALL echo123');

=head1 SCRIPTS

This module also installs two scripts, B<skype-action-handler>, and B<skype-simple-dialer>. The first script, skype-action-handler, takes Skype action uris on the command line and simply creates an instance and feeds them to C<-E<gt>action>. The second script, skype-simple-dialer, takes a phone number, and simply feeds it to the C<-E<gt>raw_skype> CALL. The skype-action-handler script should be fully compatable with the C program by the same name that once was distributed with Skype.

=head1 METHODS

=head2 ->action

Takes a skype pseudo-uri, or pseudo-url, ex. skype://echo123?call. This is parsed into three components: protocol, user, and command. Valid options for protocol are "skype", "callto", and "tel". It is then translated into raw_skype and sent off through the DBus communication link. The default command is I<call>.

=head2 ->raw_skype

Issuess raw_skype commands exposed through the DBus API. An example of this command would be, "CALL echo123".

=head1 AUTHOR

Evan Carroll, C<< <me at evancarroll.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-net-dbus-skype at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-DBus-Skype>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

perldoc Net::DBus::Skype


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-DBus-Skype>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-DBus-Skype>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-DBus-Skype>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-DBus-Skype>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008 Evan Carroll, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut
