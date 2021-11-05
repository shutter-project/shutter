package Shutter::App::NewCommon;

use utf8;
use Moo;
use Gtk3;

#Gettext and filename parsing
use POSIX qw/ setlocale /;
use Locale::gettext;

#Glib
use Glib qw/ TRUE FALSE /;

has shutter_root => ( is => "ro", required => 1 );
has mainwindow   => ( is => "ro", required => 1 );
has appname      => ( is => "ro", required => 1 );
has version      => ( is => "ro", required => 1 );
has rev          => ( is => "ro", required => 1 );
has pid          => ( is => "ro", required => 1 );

has debug              => ( is => "rw", default => sub {TRUE} );
has clear_cache        => ( is => "rw", default => sub {FALSE} );
has min                => ( is => "rw", default => sub {FALSE} );
has disable_systray    => ( is => "rw", default => sub {FALSE} );
has exit_after_capture => ( is => "rw", default => sub {FALSE} );
has no_session         => ( is => "rw", default => sub {FALSE} );

# private attributes
has _start_with       => ( is => "rw", lazy => 1 );
has _start_with_extra => ( is => "rw", lazy => 1 );

has profile_to_start_with => ( is => "rw", lazy => 1 );
has export_filename       => ( is => "rw", lazy => 1 );
has delay                 => ( is => "rw", lazy => 1 );
has include_cursor        => ( is => "rw", lazy => 1 );
has remove_cursor         => ( is => "rw", lazy => 1 );

has gettext_object => (
    is      => "rw",
    lazy    => 1,
    builder => sub {
        my $self = shift;

        my $l = Locale::gettext->domain("shutter");
        $l->dir( $self->shutter_root . "/share/locale" );

        return $l;
    },
);

has notification   => ( is => "rw", lazy => 1 );
has globalsettings => ( is => "rw", lazy => 1 );

#icontheme to determine if icons exist or not
#in some cases we deliver fallback icons
has icontheme => (
    is      => "ro",
    lazy    => 1,
    builder => sub {
        my $self = shift;

        my $theme = Gtk3::IconTheme::get_default();
        $theme->append_search_path( $self->shutter_root . "/share/icons" );
    },
);

#recently used upload tab
has ruu_tab => ( is => "rw", default => sub {0} );

has ruu_hosting => ( is => "rw", default => sub {0} );
has ruu_places  => ( is => "rw", default => sub {0} );
has ruu_u1      => ( is => "rw", default => sub {0} );

#recently used save folder
has rusf => ( is => "rw", lazy => 1 );

#recently used open folder
has ruof => ( is => "rw", lazy => 1 );

sub BUILD {
    my ( $self, $args ) = @_;

    setlocale( LC_NUMERIC,  "C" );
    setlocale( LC_MESSAGES, "" );

    $ENV{'SHUTTER_INTL'} = $args->{shutter_root} . "/share/locale";
}

sub get_start_with {
    my $self = shift;

    return ( $self->_start_with, $self->_start_with_extra );
}

sub set_start_with {
    my $self = shift;

    if (@_) {
        $self->_start_with(shift);
        $self->_start_with_extra(shift);
    }

    return ( $self->_start_with, $self->_start_with_extra );
}

sub get_current_monitor {
    my $self = shift;

    my ( $window_at_pointer, $x, $y, $mask )
        = Gtk3::Gdk::get_default_root_window->get_pointer;
    my $mon = Gtk3::Gdk::Screen::get_default->get_monitor_geometry(
        Gtk3::Gdk::Screen::get_default->get_monitor_at_point( $x, $y ) );

    return ($mon);
}

1;
