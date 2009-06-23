
require 5;
package Sort::Naturally;  # Time-stamp: "2004-12-29 18:30:03 AST"
$VERSION = '1.02';
@EXPORT = ('nsort', 'ncmp');
require Exporter;
@ISA = ('Exporter');

use strict;
use locale;
use integer;

#-----------------------------------------------------------------------------
# constants:
BEGIN { *DEBUG = sub () {0} unless defined &DEBUG }

use Config ();
BEGIN {
  # Make a constant such that if a whole-number string is that long
  #  or shorter, we KNOW it's treatable as an integer
  no integer;
  my $x = length(256 ** $Config::Config{'intsize'} / 2) - 1;
  die "Crazy intsize: <$Config::Config{'intsize'}>" if $x < 4;
  eval 'sub MAX_INT_SIZE () {' . $x . '}';
  die $@ if $@;
  print "intsize $Config::Config{'intsize'} => MAX_INT_SIZE $x\n" if DEBUG;
}

sub X_FIRST () {-1}
sub Y_FIRST () { 1}

my @ORD = ('same', 'swap', 'asis');

#-----------------------------------------------------------------------------
# For lack of a preprocessor:

my($code, $guts);
$guts = <<'EOGUTS';  # This is the guts of both ncmp and nsort:

    if($x eq $y) {
      # trap this expensive case first, and then fall thru to tiebreaker
      $rv = 0;

    # Convoluted hack to get numerics to sort first, at string start:
    } elsif($x =~ m/^\d/s) {
      if($y =~ m/^\d/s) {
        $rv = 0;    # fall thru to normal comparison for the two numbers
      } else {
        $rv = X_FIRST;
        DEBUG > 1 and print "Numeric-initial $x trumps letter-initial $y\n";
      }
    } elsif($y =~ m/^\d/s) {
      $rv = Y_FIRST;
      DEBUG > 1 and print "Numeric-initial $y trumps letter-initial $x\n";
    } else {
      $rv = 0;
    }
    
    unless($rv) {
      # Normal case:
      $rv = 0;
      DEBUG and print "<$x> and <$y> compared...\n";
      
     Consideration:
      while(length $x and length $y) {
      
        DEBUG > 2 and print " <$x> and <$y>...\n";
        
        # First, non-numeric comparison:
        $x2 = ($x =~ m/^(\D+)/s) ? length($1) : 0;
        $y2 = ($y =~ m/^(\D+)/s) ? length($1) : 0;
        # Now make x2 the min length of the two:
        $x2 = $y2 if $x2 > $y2;
        if($x2) {
          DEBUG > 1 and printf " <%s> and <%s> lexically for length $x2...\n", 
            substr($x,0,$x2), substr($y,0,$x2);
          do {
           my $i = substr($x,0,$x2);
           my $j = substr($y,0,$x2);
           my $sv = $i cmp $j;
           print "SCREAM! on <$i><$j> -- $sv != $rv \n" unless $rv == $sv;
           last;
          }
          
          
           if $rv =
           # The ''. things here force a copy that seems to work around a 
           #  mysterious intermittent bug that 'use locale' provokes in
           #  many versions of Perl.
                   $cmp
                   ? $cmp->(substr($x,0,$x2) . '',
                            substr($y,0,$x2) . '',
                           )
                   :
                   scalar(( substr($x,0,$x2) . '' ) cmp
                          ( substr($y,0,$x2) . '' )
                          )
          ;
          # otherwise trim and keep going:
          substr($x,0,$x2) = '';
          substr($y,0,$x2) = '';
        }
        
        # Now numeric:
        #  (actually just using $x2 and $y2 as scratch)

        if( $x =~ s/^(\d+)//s ) {
          $x2 = $1;
          if( $y =~ s/^(\d+)//s ) {
            # We have two numbers here.
            DEBUG > 1 and print " <$x2> and <$1> numerically\n";
            if(length($x2) < MAX_INT_SIZE and length($1) < MAX_INT_SIZE) {
              # small numbers: we can compare happily
              last if $rv = $x2 <=> $1;
            } else {
              # ARBITRARILY large integers!
              
              # This saves on loss of precision that could happen
              #  with actual stringification.
              # Also, I sense that very large numbers aren't too
              #  terribly common in sort data.
              
              # trim leading 0's:
              ($y2 = $1) =~ s/^0+//s;
              $x2 =~ s/^0+//s;
              print "   Treating $x2 and $y2 as bigint\n" if DEBUG;

              no locale; # we want the dumb cmp back.
              last if $rv = (
                 # works only for non-negative whole numbers:
                 length($x2) <=> length($y2)
                   # the longer the numeral, the larger the value
                 or $x2 cmp $y2
                   # between equals, compare lexically!!  amazing but true.
              );
            }
          } else {
            # X is numeric but Y isn't
            $rv = Y_FIRST;
            last;
          }        
        } elsif( $y =~ s/^\d+//s ) {  # we don't need to capture the substring
          $rv = X_FIRST;
          last;
        }
         # else one of them is 0-length.

       # end-while
      }
    }
EOGUTS

sub maker {
  my $code = $_[0];
  $code =~ s/~COMPARATOR~/$guts/g || die "Can't find ~COMPARATOR~";
  eval $code;
  die $@ if $@;
}

##############################################################################

maker(<<'EONSORT');
sub nsort {
  # get options:
  my($cmp, $lc);
  ($cmp,$lc) = @{shift @_} if @_ and ref($_[0]) eq 'ARRAY';

  return @_ unless @_ > 1 or wantarray; # be clever
  
  my($x, $x2, $y, $y2, $rv);  # scratch vars

  # We use a Schwartzian xform to memoize the lc'ing and \W-removal

  map $_->[0],
  sort {
    if($a->[0] eq $b->[0]) { 0 }   # trap this expensive case
    else {
    
    $x = $a->[1];
    $y = $b->[1];

~COMPARATOR~

    # Tiebreakers...
    DEBUG > 1 and print " -<${$a}[0]> cmp <${$b}[0]> is $rv ($ORD[$rv])\n";
    $rv ||= (length($x) <=> length($y))  # shorter is always first
        ||  ($cmp and $cmp->($x,$y) || $cmp->($a->[0], $b->[0]))
        ||  ($x      cmp $y     )
        ||  ($a->[0] cmp $b->[0])
    ;
    
    DEBUG > 1 and print "  <${$a}[0]> cmp <${$b}[0]> is $rv ($ORD[$rv])\n";
    $rv;
  }}

  map {;
    $x = $lc ? $lc->($_) : lc($_); # x as scratch
    $x =~ s/\W+//s;
    [$_, $x];
  }
  @_
}
EONSORT

#-----------------------------------------------------------------------------
maker(<<'EONCMP');
sub ncmp {
  # The guts are basically the same as above...

  # get options:
  my($cmp, $lc);
  ($cmp,$lc) = @{shift @_} if @_ and ref($_[0]) eq 'ARRAY';

  if(@_ == 0) {
    @_ = ($a, $b); # bit of a hack!
    DEBUG > 1 and print "Hacking in <$a><$b>\n";
  } elsif(@_ != 2) {
    require Carp;
    Carp::croak("Not enough options to ncmp!");
  }
  my($a,$b) = @_;
  my($x, $x2, $y, $y2, $rv);  # scratch vars
  
  DEBUG > 1 and print "ncmp args <$a><$b>\n";
  if($a eq $b) { # trap this expensive case
    0;
  } else {
    $x = ($lc ? $lc->($a) : lc($a));
    $x =~ s/\W+//s;
    $y = ($lc ? $lc->($b) : lc($b));
    $y =~ s/\W+//s;
    
~COMPARATOR~


    # Tiebreakers...
    DEBUG > 1 and print " -<$a> cmp <$b> is $rv ($ORD[$rv])\n";
    $rv ||= (length($x) <=> length($y))  # shorter is always first
        ||  ($cmp and $cmp->($x,$y) || $cmp->($a,$b))
        ||  ($x cmp $y)
        ||  ($a cmp $b)
    ;
    
    DEBUG > 1 and print "  <$a> cmp <$b> is $rv\n";
    $rv;
  }
}
EONCMP

# clean up:
undef $guts;
undef &maker;

#-----------------------------------------------------------------------------
1;

############### END OF MAIN SOURCE ###########################################
__END__

=head1 NAME

Sort::Naturally -- sort lexically, but sort numeral parts numerically

=head1 SYNOPSIS

  @them = nsort(qw(
   foo12a foo12z foo13a foo 14 9x foo12 fooa foolio Foolio Foo12a
  ));
  print join(' ', @them), "\n";

Prints:

  9x 14 foo fooa foolio Foolio foo12 foo12a Foo12a foo12z foo13a

(Or "foo12a" + "Foo12a" and "foolio" + "Foolio" and might be
switched, depending on your locale.)

=head1 DESCRIPTION

This module exports two functions, C<nsort> and C<ncmp>; they are used
in implementing my idea of a "natural sorting" algorithm.  Under natural
sorting, numeric substrings are compared numerically, and other
word-characters are compared lexically.

This is the way I define natural sorting:

=over

=item *

Non-numeric word-character substrings are sorted lexically,
case-insensitively: "Foo" comes between "fish" and "fowl".

=item *

Numeric substrings are sorted numerically:
"100" comes after "20", not before.

=item *

\W substrings (neither words-characters nor digits) are I<ignored>.

=item *

Our use of \w, \d, \D, and \W is locale-sensitive:  Sort::Naturally
uses a C<use locale> statement.

=item *

When comparing two strings, where a numeric substring in one
place is I<not> up against a numeric substring in another,
the non-numeric always comes first.  This is fudged by
reading pretending that the lack of a number substring has
the value -1, like so:

  foo       =>  "foo",  -1
  foobar    =>  "foo",  -1,  "bar"
  foo13     =>  "foo",  13,
  foo13xyz  =>  "foo",  13,  "xyz"

That's so that "foo" will come before "foo13", which will come
before "foobar".

=item *

The start of a string is exceptional: leading non-\W (non-word,
non-digit)
components are are ignored, and numbers come I<before> letters.

=item *

I define "numeric substring" just as sequences matching m/\d+/ --
scientific notation, commas, decimals, etc., are not seen.  If
your data has thousands separators in numbers
("20,000 Leagues Under The Sea" or "20.000 lieues sous les mers"),
consider stripping them before feeding them to C<nsort> or
C<ncmp>.

=back

=head2 The nsort function

This function takes a list of strings, and returns a copy of the list,
sorted.

This is what most people will want to use:

  @stuff = nsort(...list...);

When nsort needs to compare non-numeric substrings, it
uses Perl's C<lc> function in scope of a <use locale>.
And when nsort needs to lowercase things, it uses Perl's
C<lc> function in scope of a <use locale>.  If you want nsort
to use other functions instead, you can specify them in
an arrayref as the first argument to nsort:

  @stuff = nsort( [
                    \&string_comparator,   # optional
                    \&lowercaser_function  # optional
                  ],
                  ...list...
                );

If you want to specify a string comparator but no lowercaser,
then the options list is C<[\&comparator, '']> or
C<[\&comparator]>.  If you want to specify no string comparator
but a lowercaser, then the options list is
C<['', \&lowercaser]>.

Any comparator you specify is called as
C<$comparator-E<gt>($left, $right)>,
and, like a normal Perl C<cmp> replacement, must return
-1, 0, or 1 depending on whether the left argument is stringwise
less than, equal to, or greater than the right argument.

Any lowercaser function you specify is called as
C<$lowercased = $lowercaser-E<gt>($original)>.  The routine
must not modify its C<$_[0]>.

=head2 The ncmp function

Often, when sorting non-string values like this:

   @objects_sorted = sort { $a->tag cmp $b->tag } @objects;

...or even in a Schwartzian transform, like this:

   @strings =
     map $_->[0]
     sort { $a->[1] cmp $b->[1] }
     map { [$_, make_a_sort_key_from($_) ]
     @_
   ;
   
...you wight want something that replaces not C<sort>, but C<cmp>.
That's what Sort::Naturally's C<ncmp> function is for.  Call it with
the syntax C<ncmp($left,$right)> instead of C<$left cmp $right>,
but otherwise it's a fine replacement:

   @objects_sorted = sort { ncmp($a->tag,$b->tag) } @objects;

   @strings =
     map $_->[0]
     sort { ncmp($a->[1], $b->[1]) }
     map { [$_, make_a_sort_key_from($_) ]
     @_
   ;

Just as with C<nsort> can take different a string-comparator
and/or lowercaser, you can do the same with C<ncmp>, by passing
an arrayref as the first argument:

  ncmp( [
          \&string_comparator,   # optional
          \&lowercaser_function  # optional
        ],
        $left, $right
      )

You might get string comparators from L<Sort::ArbBiLex|Sort::ArbBiLex>.

=head1 NOTES

=over

=item *

This module is not a substitute for
L<Sort::Versions|Sort::Versions>!  If
you just need proper version sorting, use I<that!>

=item *

If you need something that works I<sort of> like this module's
functions, but not quite the same, consider scouting thru this
module's source code, and adapting what you see.  Besides
the functions that actually compile in this module, after the POD,
there's several alternate attempts of mine at natural sorting
routines, which are not compiled as part of the module, but which you
might find useful.  They should all be I<working> implementations of
slightly different algorithms
(all of them based on Martin Pool's C<nsort>) which I eventually
discarded in favor of my algorithm.  If you are having to
naturally-sort I<very large> data sets, and sorting is getting
ridiculously slow, you might consider trying one of those
discarded functions -- I have a feeling they might be faster on
large data sets.  Benchmark them on your data and see.  (Unless
you I<need> the speed, don't bother.  Hint: substitute C<sort>
for C<nsort> in your code, and unless your program speeds up
drastically, it's not the sorting that's slowing things down.
But if it I<is> C<nsort> that's slowing things down, consider
just:

      if(@set >= SOME_VERY_BIG_NUMBER) {
        no locale; # vroom vroom
        @sorted = sort(@set);  # feh, good enough
      } elsif(@set >= SOME_BIG_NUMBER) {
        use locale;
        @sorted = sort(@set);  # feh, good enough
      } else {
        # but keep it pretty for normal cases
        @sorted = nsort(@set);
      }

=item *

If you do adapt the routines in this module, email me; I'd
just be interested in hearing about it.

=item *

Thanks to the EFNet #perl people for encouraging this module,
especially magister and a-mused.

=back

=head1 COPYRIGHT AND DISCLAIMER

Copyright 2001, Sean M. Burke C<sburke@cpan.org>, all rights
reserved.  This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=head1 AUTHOR

Sean M. Burke C<sburke@cpan.org>

=cut

############   END OF DOCS   ############

############################################################################
############################################################################

############ BEGIN OLD STUFF ############

# We can't have "use integer;", or else (5 <=> 5.1) comes out "0" !

#-----------------------------------------------------------------------------
sub nsort {
  my($cmp, $lc);
  return @_ if @_ < 2;   # Just to be CLEVER.
  
  my($x, $i);  # scratch vars
  
  # And now, the GREAT BIG Schwartzian transform:
  
  map
    $_->[0],

  sort {
    # Uses $i as the index variable, $x as the result.
    $x = 0;
    $i = 1;
    DEBUG and print "\nComparing ", map("{$_}", @$a),
                 ' : ', map("{$_}", @$b), , "...\n";

    while($i < @$a and $i < @$b) {
      DEBUG and print "  comparing $i: {$a->[$i]} cmp {$b->[$i]} => ",
        $a->[$i] cmp $b->[$i], "\n";
      last if ($x = ($a->[$i] cmp $b->[$i])); # lexicographic
      ++$i;

      DEBUG and print "  comparing $i: {$a->[$i]} <=> {$b->[$i]} => ",
        $a->[$i] <=> $b->[$i], "\n";
      last if ($x = ($a->[$i] <=> $b->[$i])); # numeric
      ++$i;
    }

    DEBUG and print "{$a->[0]} : {$b->[0]} is ",
      $x || (@$a <=> @$b) || 0
      ,"\n"
    ;
    $x || (@$a <=> @$b) || ($a->[0] cmp $b->[0]);
      # unless we found a result for $x in the while loop,
      #  use length as a tiebreaker, otherwise use cmp
      #  on the original string as a fallback tiebreaker.
  }

  map {
    my @bit = ($x = defined($_) ? $_ : '');
    
    if($x =~ m/^[+-]?(?=\d|\.\d)\d*(?:\.\d*)?(?:[Ee](?:[+-]?\d+))?\z/s) {
      # It's entirely purely numeric, so treat it specially:
      push @bit, '', $x;
    } else {
      # Consume the string.
      while(length $x) {
        push @bit, ($x =~ s/^(\D+)//s) ? lc($1) : '';
        push @bit, ($x =~ s/^(\d+)//s) ?    $1  :  0;
      }
    }
    DEBUG and print "$bit[0] => ", map("{$_} ", @bit), "\n";

    # End result: [original bit         , (text, number), (text, number), ...]
    # Minimally:  [0-length original bit,]
    # Examples:
    #    ['10'         => ''   ,  10,              ]
    #    ['fo900'      => 'fo' , 900,              ]
    #    ['foo10'      => 'foo',  10,              ]
    #    ['foo9.pl'    => 'foo',   9,   , '.pl', 0 ]
    #    ['foo32.pl'   => 'foo',  32,   , '.pl', 0 ]
    #    ['foo325.pl'  => 'foo', 325,   , '.pl', 0 ]
    #  Yes, always an ODD number of elements.
    
    \@bit;
  }
  @_;
}

#-----------------------------------------------------------------------------
# Same as before, except without the pure-number trap.

sub nsorts {
  return @_ if @_ < 2;   # Just to be CLEVER.
  
  my($x, $i);  # scratch vars
  
  # And now, the GREAT BIG Schwartzian transform:
  
  map
    $_->[0],

  sort {
    # Uses $i as the index variable, $x as the result.
    $x = 0;
    $i = 1;
    DEBUG and print "\nComparing ", map("{$_}", @$a),
                 ' : ', map("{$_}", @$b), , "...\n";

    while($i < @$a and $i < @$b) {
      DEBUG and print "  comparing $i: {$a->[$i]} cmp {$b->[$i]} => ",
        $a->[$i] cmp $b->[$i], "\n";
      last if ($x = ($a->[$i] cmp $b->[$i])); # lexicographic
      ++$i;

      DEBUG and print "  comparing $i: {$a->[$i]} <=> {$b->[$i]} => ",
        $a->[$i] <=> $b->[$i], "\n";
      last if ($x = ($a->[$i] <=> $b->[$i])); # numeric
      ++$i;
    }

    DEBUG and print "{$a->[0]} : {$b->[0]} is ",
      $x || (@$a <=> @$b) || 0
      ,"\n"
    ;
    $x || (@$a <=> @$b) || ($a->[0] cmp $b->[0]);
      # unless we found a result for $x in the while loop,
      #  use length as a tiebreaker, otherwise use cmp
      #  on the original string as a fallback tiebreaker.
  }

  map {
    my @bit = ($x = defined($_) ? $_ : '');
    
    while(length $x) {
      push @bit, ($x =~ s/^(\D+)//s) ? lc($1) : '';
      push @bit, ($x =~ s/^(\d+)//s) ?    $1  :  0;
    }
    DEBUG and print "$bit[0] => ", map("{$_} ", @bit), "\n";

    # End result: [original bit         , (text, number), (text, number), ...]
    # Minimally:  [0-length original bit,]
    # Examples:
    #    ['10'         => ''   ,  10,              ]
    #    ['fo900'      => 'fo' , 900,              ]
    #    ['foo10'      => 'foo',  10,              ]
    #    ['foo9.pl'    => 'foo',   9,   , '.pl', 0 ]
    #    ['foo32.pl'   => 'foo',  32,   , '.pl', 0 ]
    #    ['foo325.pl'  => 'foo', 325,   , '.pl', 0 ]
    #  Yes, always an ODD number of elements.
    
    \@bit;
  }
  @_;
}

#-----------------------------------------------------------------------------
# Same as before, except for the sort-key-making

sub nsort0 {
  return @_ if @_ < 2;   # Just to be CLEVER.
  
  my($x, $i);  # scratch vars
  
  # And now, the GREAT BIG Schwartzian transform:
  
  map
    $_->[0],

  sort {
    # Uses $i as the index variable, $x as the result.
    $x = 0;
    $i = 1;
    DEBUG and print "\nComparing ", map("{$_}", @$a),
                 ' : ', map("{$_}", @$b), , "...\n";

    while($i < @$a and $i < @$b) {
      DEBUG and print "  comparing $i: {$a->[$i]} cmp {$b->[$i]} => ",
        $a->[$i] cmp $b->[$i], "\n";
      last if ($x = ($a->[$i] cmp $b->[$i])); # lexicographic
      ++$i;

      DEBUG and print "  comparing $i: {$a->[$i]} <=> {$b->[$i]} => ",
        $a->[$i] <=> $b->[$i], "\n";
      last if ($x = ($a->[$i] <=> $b->[$i])); # numeric
      ++$i;
    }

    DEBUG and print "{$a->[0]} : {$b->[0]} is ",
      $x || (@$a <=> @$b) || 0
      ,"\n"
    ;
    $x || (@$a <=> @$b) || ($a->[0] cmp $b->[0]);
      # unless we found a result for $x in the while loop,
      #  use length as a tiebreaker, otherwise use cmp
      #  on the original string as a fallback tiebreaker.
  }

  map {
    my @bit = ($x = defined($_) ? $_ : '');
    
    if($x =~ m/^[+-]?(?=\d|\.\d)\d*(?:\.\d*)?(?:[Ee](?:[+-]?\d+))?\z/s) {
      # It's entirely purely numeric, so treat it specially:
      push @bit, '', $x;
    } else {
      # Consume the string.
      while(length $x) {
        push @bit, ($x =~ s/^(\D+)//s) ? lc($1) : '';
        # Secret sauce:
        if($x =~ s/^(\d+)//s) {
          if(substr($1,0,1) eq '0' and $1 != 0) {
            push @bit, $1 / (10 ** length($1));
          } else {
            push @bit, $1;
          }
        } else {
          push @bit, 0;
        }
      }
    }
    DEBUG and print "$bit[0] => ", map("{$_} ", @bit), "\n";
    
    \@bit;
  }
  @_;
}

#-----------------------------------------------------------------------------
# Like nsort0, but WITHOUT pure number handling, and WITH special treatment
# of pulling off extensions and version numbers.

sub nsortf {
  return @_ if @_ < 2;   # Just to be CLEVER.
  
  my($x, $i);  # scratch vars
  
  # And now, the GREAT BIG Schwartzian transform:
  
  map
    $_->[0],

  sort {
    # Uses $i as the index variable, $x as the result.
    $x = 0;
    $i = 3;
    DEBUG and print "\nComparing ", map("{$_}", @$a),
                 ' : ', map("{$_}", @$b), , "...\n";

    while($i < @$a and $i < @$b) {
      DEBUG and print "  comparing $i: {$a->[$i]} cmp {$b->[$i]} => ",
        $a->[$i] cmp $b->[$i], "\n";
      last if ($x = ($a->[$i] cmp $b->[$i])); # lexicographic
      ++$i;

      DEBUG and print "  comparing $i: {$a->[$i]} <=> {$b->[$i]} => ",
        $a->[$i] <=> $b->[$i], "\n";
      last if ($x = ($a->[$i] <=> $b->[$i])); # numeric
      ++$i;
    }

    DEBUG and print "{$a->[0]} : {$b->[0]} is ",
      $x || (@$a <=> @$b) || 0
      ,"\n"
    ;
    $x || (@$a     <=> @$b    ) || ($a->[1] cmp $b->[1])
       || ($a->[2] <=> $b->[2]) || ($a->[0] cmp $b->[0]);
      # unless we found a result for $x in the while loop,
      #  use length as a tiebreaker, otherwise use the 
      #  lc'd extension, otherwise the verison, otherwise use
      #  the original string as a fallback tiebreaker.
  }

  map {
    my @bit = ( ($x = defined($_) ? $_ : ''), '',0 );
    
    {
      # Consume the string.
      
      # First, pull off any VAX-style version
      $bit[2] = $1 if $x =~ s/;(\d+)$//;
      
      # Then pull off any apparent extension
      if( $x !~ m/^\.+$/s and     # don't mangle ".", "..", or "..."
          $x =~ s/(\.[^\.\;]*)$//sg
          # We could try to avoid catching all-digit extensions,
          #  but I think that's getting /too/ clever.
      ) {
        $i = $1;
        if($x =~ m<[^\\\://]$>s) {
          # We didn't take the whole basename.
          $bit[1] = lc $i;
          DEBUG and print "Consuming extension \"$1\"\n";
        } else {
          # We DID take the whole basename.  Fix it.
          $x = $1;  # Repair it.
        }
      }

      push @bit, '', -1   if $x =~ m/^\./s;
       # A hack to make .-initial filenames sort first, regardless of locale.
       # And -1 is always a sort-firster, since in the code below, there's
       # no allowance for filenames containing negative numbers: -1.dat
       # will be read as string '-' followed by number 1.

      while(length $x) {
        push @bit, ($x =~ s/^(\D+)//s) ? lc($1) : '';
        # Secret sauce:
        if($x =~ s/^(\d+)//s) {
          if(substr($1,0,1) eq '0' and $1 != 0) {
            push @bit, $1 / (10 ** length($1));
          } else {
            push @bit, $1;
          }
        } else {
          push @bit, 0;
        }
      }
    }
    
    DEBUG and print "$bit[0] => ", map("{$_} ", @bit), "\n";
    
    \@bit;
  }
  @_;
}

# yowza yowza yowza.

