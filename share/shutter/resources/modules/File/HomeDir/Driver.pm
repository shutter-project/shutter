package File::HomeDir::Driver;

# Abstract base class that provides no functionality,
# but confirms the class is a File::HomeDir driver class.

use 5.00503;
use strict;
use Carp ();

use vars qw{$VERSION};
BEGIN {
	$VERSION = '0.86';
}

sub my_home {
	Carp::croak("$_[0] does not implement compulsory method $_[1]");
}

1;
