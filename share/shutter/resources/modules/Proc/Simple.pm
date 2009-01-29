######################################################################
package Proc::Simple;
######################################################################
# Copyright 1996-2001 by Michael Schilli, all rights reserved.
#
# This program is free software, you can redistribute it and/or 
# modify it under the same terms as Perl itself.
#
# The newest version of this module is available on
#     http://perlmeister.com/devel
# or on your favourite CPAN site under
#     CPAN/modules/by-author/id/MSCHILLI
#
######################################################################

=head1 NAME

Proc::Simple -- launch and control background processes

=head1 SYNOPSIS

   use Proc::Simple;

   $myproc = Proc::Simple->new();        # Create a new process object

   $myproc->start("shell-command-line"); # Launch an external program
   $myproc->start("command",             # Launch an external program
                  "param", ...);         # with parameters
                                        
   $myproc->start(sub { ... });          # Launch a perl subroutine
   $myproc->start(\&subroutine);         # Launch a perl subroutine
   $myproc->start(\&subroutine,          # Launch a perl subroutine
                  $param, ...);          # with parameters

   $running = $myproc->poll();           # Poll Running Process

   $exit_status = $myproc->wait();       # Wait until process is done

   $proc->kill_on_destroy(1);            # Set kill on destroy
   $proc->signal_on_destroy("KILL");     # Specify signal to be sent
                                         # on destroy

   $myproc->kill();                      # Kill Process (SIGTERM)



   $myproc->kill("SIGUSR1");             # Send specified signal

   $myproc->exit_status();               # Return exit status of process


   Proc::Simple::debug($level);          # Turn debug on

=head1 DESCRIPTION

The Proc::Simple package provides objects mimicing real-life
processes from a user's point of view. A new process object is created by

   $myproc = Proc::Simple->new();

Either external programs or perl subroutines can be launched and
controlled as processes in the background.

A 10-second sleep process, for example, can be launched 
as an external program as in

   $myproc->start("/bin/sleep 10");    # or
   $myproc->start("/bin/sleep", "10");

or as a perl subroutine, as in

   sub mysleep { sleep(shift); }    # Define mysleep()
   $myproc->start(\&mysleep, 10);   # Launch it.

or even as

   $myproc->start(sub { sleep(10); });

The I<start> Method returns immediately after starting the
specified process in background, i.e. there's no blocking.
It returns I<1> if the process has been launched
sucessfully and I<0> if not.

The I<poll> method checks if the process is still running

   $running = $myproc->poll();

and returns I<1> if it is, I<0> if it's not. Finally, 

   $myproc->kill();

terminates the process by sending it the SIGTERM signal. As an
option, another signal can be specified.

   $myproc->kill("SIGUSR1");

sends the SIGUSR1 signal to the running process. I<kill> returns I<1> if
it succeeds in sending the signal, I<0> if it doesn't.

The methods are discussed in more detail in the next section.

A destructor is provided so that a signal can be sent to
the forked processes automatically should the process object be
destroyed or if the process exits. By default this
behaviour is turned off (see the kill_on_destroy and
signal_on_destroy methods).

=cut

require 5.003;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXIT_STATUS %INTERVAL
            %DESTROYED);

use IO::Handle;
require Exporter;

@ISA     = qw(Exporter AutoLoader);
@EXPORT  = qw( );
$VERSION = '1.23';

######################################################################
# Globals: Debug and the mysterious waitpid nohang constant.
######################################################################
my $Debug = 0;
my $WNOHANG = get_system_nohang();

######################################################################

=head1 METHODS

The following methods are available:

=over 4

=item new (Constructor)

Create a new instance of this class by writing

  $proc = new Proc::Simple;

or

  $proc = Proc::Simple->new();

It takes no arguments.

=cut

######################################################################
# $proc_obj=Proc::Simple->new(); - Constructor
######################################################################
sub new { 
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $self  = {};
  
  # Init instance variables
  $self->{'kill_on_destroy'}   = undef;
  $self->{'signal_on_destroy'} = undef;
  $self->{'pid'}               = undef;
  $self->{'redirect_stdout'}   = undef;
  $self->{'redirect_stderr'}   = undef;

  bless($self, $class);
}

######################################################################

=item start

Launches a new process.
The C<start()> method can be used to launch both external programs 
(like C</bin/echo>) or one of your self-defined subroutines
(like C<foo()>) in a new process.

=head2 Starting External Programs

For an external program to be started, call

 $status = $proc->start("program-name");

If you want to pass a couple of parameters to the launched program,
there's two options: You can either pass them in one argument like
in

 $status = $proc->start("/bin/echo hello world");

or in several arguments like in

 $status = $proc->start("/bin/echo", "hello", "world");

Just as in Perl's function C<system()>, there's a big difference 
between the two methods: If you provide one argument containing
a blank-separated command line, your shell is going to
process any meta-characters (if you choose to use some) before
the process is actually launched:

 $status = $proc->start("/bin/ls -l /etc/initt*");

will expand C</etc/initt*> to C</etc/inittab> before running the C<ls>
command. If, on the other hand, you say

 $status = $proc->start("/bin/ls", "-l", "*");

the C<*> will stay unexpanded, meaning you'll look for a file with the
literal name C<*> (which is unlikely to exist on your system unless
you deliberately create confusingly named files :). For
more info on this, look up C<perldoc -f exec>.

=head2 Starting Subroutines

If, on the other hand, you want to start a Perl subroutine
in the background, simply provide the function reference like

 $status = $proc->start(\&your_function);

or supply an unnamed subroutine:

 $status = $proc->start( sub { sleep(1) } );

You can also provide additional parameters to be passed to the function:

 $status = $proc->start(\&printme, "hello", "world");

The I<start> Method returns immediately after starting the
specified process in background, i.e. non-blocking mode.
It returns I<1> if the process has been launched
sucessfully and I<0> if not.

=cut

######################################################################
# $ret = $proc_obj->start("prg"); - Launch process
######################################################################
sub start {
  my $self  = shift;
  my ($func, @params) = @_;

  # Reap Zombies automatically
  $SIG{'CHLD'} = \&THE_REAPER;

  # Fork a child process
  $self->{'pid'} = fork();
  return 0 unless defined $self->{'pid'};  #   return Error if fork failed

  if($self->{pid} == 0) { # Child

      if (defined $self->{'redirect_stderr'}) {
        $self->dprt("STDERR -> $self->{'redirect_stderr'}");
        open(STDERR, ">$self->{'redirect_stderr'}") ;
        autoflush STDERR 1 ;
      }

      if (defined $self->{'redirect_stdout'}) {
        $self->dprt("STDOUT -> $self->{'redirect_stdout'}");
        open(STDOUT, ">$self->{'redirect_stdout'}") ;
        autoflush STDOUT 1 ;
      }

      if(ref($func) eq "CODE") {
        $func->(@params); exit 0;            # Start perl subroutine
      } else {
          exec $func, @params;       # Start shell process
          exit 0;                    # In case something goes wrong
      }
  } elsif($self->{'pid'} > 0) {      # Parent:
      $INTERVAL{$self->{'pid'}}{'t0'} = time();
      $self->dprt("START($self->{'pid'})");
      # Register PID
      $EXIT_STATUS{$self->{'pid'}} = undef;
      $INTERVAL{$self->{'pid'}}{'t1'} = undef;
      return 1;                      #   return OK
  } else {      
      return 0;                      #   this shouldn't occur
  }
}

######################################################################

=item poll

The I<poll> method checks if the process is still running

   $running = $myproc->poll();

and returns I<1> if it is, I<0> if it's not.

=cut

######################################################################
# $ret = $proc_obj->poll(); - Check process status
#                             1="running" 0="not running"
######################################################################
sub poll {
  my $self = shift;

  # There's some weirdness going on with the signal handler. 
  # It runs into timing problems, so let's have poll() call
  # the REAPER every time to make sure we're getting rid of 
  # defuncts.
  $self->THE_REAPER();

  if(defined($self->{'pid'})) {
      if(kill(0, $self->{'pid'})) {
          $self->dprt("POLL($self->{'pid'}) RESPONDING");
	      return 1;
      } else {
          $self->dprt("POLL($self->{'pid'}) NOT RESPONDING");
      }
  } else {
     $self->dprt("POLL(NOT DEFINED)");
  }

  0;
}

######################################################################

=item kill

The kill() method:

   $myproc->kill();

terminates the process by sending it the SIGTERM signal. As an
option, another signal can be specified.

   $myproc->kill("SIGUSR1");

sends the SIGUSR1 signal to the running process. I<kill> returns I<1> if
it succeeds in sending the signal, I<0> if it doesn't.

=cut

######################################################################
# $ret = $proc_obj->kill([SIGXXX]); - Send signal to process
#                                     Default-Signal: SIGTERM
######################################################################
sub kill { 
  my $self = shift;
  my $sig  = shift;

  # If no signal specified => SIGTERM-Signal
  $sig = "SIGTERM" unless defined $sig;

  # Process initialized at all?
  return 0 if !defined $self->{'pid'};

  # Send signal
  if(kill($sig, $self->{'pid'})) {
      $self->dprt("KILL($self->{'pid'}) OK");
  } else {
      $self->dprt("KILL($self->{'pid'}) failed");
      return 0;
  }

  1;
}

######################################################################

=item kill_on_destroy

Set a flag to determine whether the process attached
to this object should be killed when the object is
destroyed. By default, this flag is set to false.
The current value is returned.

  $current = $proc->kill_on_destroy;
  $proc->kill_on_destroy(1); # Set flag to true
  $proc->kill_on_destroy(0); # Set flag to false

=cut

######################################################################
# Method to set the kill_on_destroy flag
######################################################################
sub kill_on_destroy {
    my $self = shift;
    if (@_) { $self->{kill_on_destroy} = shift; }
    return $self->{kill_on_destroy};
}

######################################################################

=item signal_on_destroy

Method to set the signal that will be sent to the
process when the object is destroyed (Assuming
kill_on_destroy is true). Returns the current setting.

  $current = $proc->signal_on_destroy;
  $proc->signal_on_destroy("KILL");

=cut

######################################################################
# Send a signal on destroy
# undef means send the default signal (SIGTERM)
######################################################################
sub signal_on_destroy {
    my $self = shift;
    if (@_) { $self->{signal_on_destroy} = shift; }
    return $self->{signal_on_destroy};
}

######################################################################

=item redirect_output

This allows to redirect the stdout and/or stderr output to a file.
Specify undef to leave th

  # stdout to a file, left stderr unchanged
  $proc->redirect_output ("/tmp/someapp.stdout", undef);
  
  # stderr to a file, left stdout unchanged
  $proc->redirect_output (undef, "/tmp/someapp.stderr");
  
  # stdout and stderr to a separate file
  $proc->redirect_output ("/tmp/someapp.stdout", "/tmp/someapp.stderr");

Call this method before running the start method.

=cut

######################################################################
sub redirect_output {
######################################################################

  my $self = shift ;
  ($self->{'redirect_stdout'}, $self->{'redirect_stderr'}) = @_ ;

  1 ;
}

######################################################################

=item pid

Returns the pid of the forked process associated with
this object

  $pid = $proc->pid;

=cut

######################################################################
sub pid {
######################################################################
  my $self = shift;

  # Allow the pid to be set - assume this is only
  # done internally so don't document this behaviour in the
  # pod.
  if (@_) { $self->{'pid'} = shift; }
  return $self->{'pid'};
}

######################################################################

=item t0

Returns the start time() of the forked process associated with
this object

  $pid = $proc->t0();

=cut

######################################################################
sub t0 {
######################################################################
  my $self = shift;

  return $INTERVAL{$self->{'pid'}}{'t0'};
}

######################################################################

=item t1

Returns the stop time() of the forked process associated with
this object

  return $proc->t1()

=cut

######################################################################
sub t1 {
######################################################################
  my $self = shift;

  return $INTERVAL{$self->{'pid'}}{'t1'};
}

=item DESTROY (Destructor)

Object destructor. This method is called when the
object is destroyed (eg with "undef" or on exiting
perl). If kill_on_destroy is true the process
associated with the object is sent the signal_on_destroy
signal (SIGTERM if undefined).

=cut

######################################################################
# Destroy method
# This is run automatically on undef
# Should probably not bother if a poll shows that the process is not
# running.
######################################################################
sub DESTROY {
    my $self = shift;

    # Processes never started don't have to be cleaned up in
    # any special way.
    return unless $self->pid();

    # If the kill_on_destroy flag is true then
    # We need to send a signal to the process
    if ($self->kill_on_destroy) {
        $self->dprt("Kill on DESTROY");
        if (defined $self->signal_on_destroy) {
            $self->kill($self->signal_on_destroy);
        } else {
            $self->dprt("Sending KILL");
            $self->kill;
        }
    }
    delete $EXIT_STATUS{ $self->pid };
    $DESTROYED{ $self->pid } = 1;
}

######################################################################

=item exit_status

Returns the exit status of the process as the $! variable indicates.
If the process is still running, C<undef> is returned.

=cut

######################################################################
# returns the exit status of the child process, undef if the child
# hasn't yet exited
######################################################################
sub exit_status{
        my( $self ) = @_;
        return $EXIT_STATUS{ $self->pid };
}

######################################################################

=item wait

The I<wait> method:

   $exit_status = $myproc->wait();

waits until the process is done and returns its exit status.

=cut

######################################################################
# waits until the child process terminates and then
# returns the exit status of the child process.
######################################################################
sub wait {
    my $self = shift;

    local $SIG{CHLD}; # disable until we're done

    my $pid = $self->pid();

    # test if the signal handler reap'd this pid some time earlier or even just
    # a split second before localizing $SIG{CHLD} above; also kickout if
    # they've wait'd or waitpid'd on this pid before ...

    return $EXIT_STATUS{$pid} if defined $EXIT_STATUS{$pid};

    # all systems support FLAGS==0 (accg to: perldoc -f waitpid)
    my $res = waitpid $pid, 0;
    my $rc = $?;

    $INTERVAL{$pid}{'t1'} = time();
    $EXIT_STATUS{$pid} = $rc;
    dprt("", "For $pid, reaped '$res' with exit_status=$rc");

    return $rc;
}

######################################################################
# Reaps processes, uses the magic WNOHANG constant
######################################################################
sub THE_REAPER {

    my $child;
    my $now = time();

    if(defined $WNOHANG) {
        # Try to reap every process we've ever started and 
        # whichs Proc::Simple object hasn't been destroyed.
        #
        # This is getting really ugly. But if we just call the REAPER
        # for every SIG{CHLD} event, code like this will fail:
        #
        # use Proc::Simple;
        # $proc = Proc::Simple->new(); $proc->start(\&func); sleep(5);
        # sub func { open(PIPE, "/bin/ls |"); @a = <PIPE>; sleep(1); 
        #            close(PIPE) or die "PIPE failed"; }
        # 
        # Reason: close() doesn't like it if the spawn has
        # been reaped already. Oh well.
        #

        # First, check if we can reap the processes which 
        # went out of business because their kill_on_destroy
        # flag was set and their objects were destroyed.
        foreach my $pid (keys %DESTROYED) {
            if(my $res = waitpid($pid, $WNOHANG) > 0) {
                # We reaped a zombie
                delete $DESTROYED{$pid};
                dprt("", "Reaped: $pid");
            }
        }
        
        foreach my $pid (keys %EXIT_STATUS) {
            dprt("", "Trying to reap $pid");
            next if defined $EXIT_STATUS{$pid};
            if(my $res = waitpid($pid, $WNOHANG) > 0) {
                # We reaped a truly running process
                $EXIT_STATUS{$pid} = $?;
                $INTERVAL{$pid}{'t1'} = $now;
                dprt("", "Reaped: $pid");
            } else {
                dprt("", "waitpid returned '$res'");
            }
        }
    } else { 
        # If we don't have $WNOHANG, we don't have a choice anyway.
        # Just reap everything.
        $child = CORE::wait();
        $EXIT_STATUS{$child} = $?;
        $INTERVAL{$child}{'t1'} = $now;
    }

    # Don't reset signal handler for crappy sysV systems. Screw them.
    # This caused problems with Irix 6.2
    # $SIG{'CHLD'} = \&THE_REAPER;
}

######################################################################

=item debug

Switches debug messages on and off -- Proc::Simple::debug(1) switches
them on, Proc::Simple::debug(0) keeps Proc::Simple quiet.

=cut

# Proc::Simple::debug($level) - Turn debug on/off
sub debug { $Debug = shift; }

######################################################################
# Internal debug print function
######################################################################
sub dprt {
  my $self = shift;
  print ref($self), "> @_\n" if $Debug;
}

######################################################################
sub get_system_nohang {
######################################################################
# This is for getting the WNOHANG constant of the system -- but since
# the waitpid(-1, &WNOHANG) isn't supported on all Unix systems, and
# we still want Proc::Simple to run on every system, we have to 
# quietly perform some tests to figure out if -- or if not.
# The function returns the constant, or undef if it's not available.
######################################################################
    my $nohang;

    open(SAVEERR, ">&STDERR");

       # If the system doesn't even know /dev/null, forget about it.
    open(STDERR, ">/dev/null") || return undef;
       # Close stderr, since some weirdo POSIX modules write nasty
       # error messages
    close(STDERR);

       # Check for the constant
    eval 'use POSIX ":sys_wait_h"; $nohang = &WNOHANG;';

       # Re-open STDERR
    open(STDERR, ">&SAVEERR");
    close(SAVEERR);

        # If there was an error, return undef
    return undef if $@;

    return $nohang;
}

1;

__END__

=head1 NOTE

Please keep in mind that there is no guarantee that the SIGTERM
signal really terminates a process. Processes can have signal
handlers defined that avoid the shutdown.
If in doubt, whether a process still exists, check it
repeatedly with the I<poll> routine after sending the signal.

=head1 REQUIREMENTS

I'd recommend using perl 5.6.0 although it might also run with 5.003
-- if you don't have it, this is the time to upgrade!

=head1 AUTHOR

Michael Schilli <michael@perlmeister.com>

Contributors:

Tim Jenness  <t.jenness@jach.hawaii.edu>
   did kill_on_destroy/signal_on_destroy/pid

Mark R. Southern <mark_southern@merck.com>
   worked on EXIT_STATUS tracking

Tobias Jahn <tjahn@users.sourceforge.net>
   added redirection to stdout/stderr

Clauss Strauch <Clauss_Strauch@aquila.fac.cs.cmu.edu>
suggested the multi-arg start()-methods.

Chip Capelik contributed a patch with the wait() method.

Jeff Holt provided a patch for time tracking with t0() and t1().

=cut
