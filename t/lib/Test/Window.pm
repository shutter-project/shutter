package Test::Window;

use 5.010;
use strict;
use warnings;

use Gtk3;

sub simple_window {
    Gtk3::init;

    my $w = Gtk3::Window->new('toplevel');
    $w->set_title("Foo");
    $w->set_position('center');
    $w->set_modal(1);
    $w->signal_connect( 'delete_event', sub { Gtk3->main_quit } );
    $w->set_default_size( 640, 480 );
    $w->show_all;
    $w->get_window->focus( Gtk3::get_current_event_time() );

    return $w;
}

1;
