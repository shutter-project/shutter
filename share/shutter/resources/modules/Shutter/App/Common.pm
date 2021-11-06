package Shutter::App::Common;

use utf8;
use Moo;
use Gtk3;

#Gettext and filename parsing
use POSIX qw/ setlocale /;
use Locale::gettext;

#Glib
use Glib qw/ TRUE FALSE /;

has shutter_root => ( is => "ro", required => 1 );
has main_window  => ( is => "rw", required => 1 );
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

has notification    => ( is => "rw", lazy => 1 );
has global_settings => ( is => "rw", lazy => 1 );

#icontheme to determine if icons exist or not
#in some cases we deliver fallback icons
has icontheme => (
    is      => "rw",
    lazy    => 1,
    builder => "_setup_icontheme",
);

#recently used upload tab
has ruu_tab => ( is => "rw", default => sub {0} );

#... and details
has ruu_hosting => ( is => "rw", default => sub {0} );
has ruu_places  => ( is => "rw", default => sub {0} );

# TODO: this attribute looks like isn't used. Consider to remove it later
has ruu_u1 => ( is => "rw", default => sub {0} );

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

sub _setup_icontheme {
    my $self = shift;

    my $theme = Gtk3::IconTheme::get_default();
    $theme->append_search_path( $self->shutter_root . "/share/icons" );

    return $theme;
}

sub get_current_monitor {
    my $self = shift;

    my ( $window_at_pointer, $x, $y, $mask ) = Gtk3::Gdk::get_default_root_window->get_pointer;
    my $mon = Gtk3::Gdk::Screen::get_default->get_monitor_geometry(
        Gtk3::Gdk::Screen::get_default->get_monitor_at_point( $x, $y ) );

    return ($mon);
}

# Methods that used in old realization and needed for backward compatibility

sub get_root                  { shift->shutter_root }
sub get_appname               { shift->appname }
sub get_version               { shift->version }
sub get_rev                   { shift->rev }
sub get_gettext               { shift->gettext_object }
sub get_theme                 { shift->icontheme }
sub get_notification_object   { shift->notification }
sub set_notification_object   { shift->notification(shift) if @_ }
sub get_globalsettings_object { shift->global_settings }
sub set_globalsettings_object { shift->global_settings(shift) if @_ }
sub get_rusf                  { shift->rusf }
sub set_rusf                  { shift->rusf(shift) if @_ }
sub get_ruof                  { shift->ruof }
sub set_ruof                  { shift->ruof(shift) if @_ }
sub get_ruu_tab               { shift->ruu_tab }
sub set_ruu_tab               { shift->ruu_tab(shift) if @_ }
sub get_ruu_hosting           { shift->ruu_hosting }
sub set_ruu_hosting           { shift->ruu_hosting(shift) if @_ }
sub get_ruu_places            { shift->ruu_places }
sub set_ruu_places            { shift->ruu_places(shift) if @_ }
sub get_debug                 { shift->debug }
sub set_debug                 { shift->debug(shift) if @_ }
sub get_clear_cache           { shift->clear_cache }
sub set_clear_cache           { shift->clear_cache(shift) if @_ }
sub get_mainwindow            { shift->main_window }
sub set_mainwindow            { shift->main_window(shift) if @_ }
sub get_min                   { shift->min }
sub set_min                   { shift->min(shift) if @_ }
sub get_disable_systray       { shift->disable_systray }
sub set_disable_systray       { shift->disable_systray(shift) if @_ }
sub get_exit_after_capture    { shift->exit_after_capture }
sub set_exit_after_capture    { shift->exit_after_capture(shift) if @_ }
sub get_no_session            { shift->no_session }
sub set_no_session            { shift->no_session(shift) if @_ }

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

sub get_profile_to_start_with { shift->profile_to_start_with }
sub set_profile_to_start_with { shift->profile_to_start_with(shift) if @_ }
sub get_export_filename       { shift->export_filename }
sub set_export_filename       { shift->export_filename(shift) if @_ }
sub get_include_cursor        { shift->include_cursor }
sub set_include_cursor        { shift->include_cursor(shift) if @_ }
sub get_remove_cursor         { shift->remove_cursor }
sub set_remove_cursor         { shift->remove_cursor(shift) if @_ }
sub get_delay                 { shift->delay }
sub set_delay                 { shift->delay(shift) if @_ }

1;
