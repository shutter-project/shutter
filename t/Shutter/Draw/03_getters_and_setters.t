use 5.010;
use strict;
use warnings;

use Gtk3;    # to escape warnings "Too late to run INIT block"
use Gtk3::ImageView 10;
use Glib qw/ TRUE FALSE /;

use Test::More tests => 4;

require Test::Window;
require Test::Common;

require Shutter::App::SimpleDialogs;
require Shutter::App::HelperFunctions;
require Shutter::App::Common;

require_ok("Shutter::Draw::DrawingTool");

subtest "create drawing tool" => sub {
    plan skip_all => "no env TEST_APP_SHUTTER_PATH found" unless $ENV{TEST_APP_SHUTTER_PATH};

    my $w  = Test::Window::simple_window();
    my $sc = Test::Common::get_common_object();
    $sc->set_mainwindow($w);

    my $drawing_tool = Shutter::Draw::DrawingTool->new($sc);

    ok( defined $drawing_tool, "DrawingTool object" );
};

subtest "only getters" => sub {
    plan skip_all => "no env TEST_APP_SHUTTER_PATH found" unless $ENV{TEST_APP_SHUTTER_PATH};

    my $w  = Test::Window::simple_window();
    my $sc = Test::Common::get_common_object();
    $sc->set_mainwindow($w);

    my $dt = Shutter::Draw::DrawingTool->new($sc);

    # TODO: fix it later. This attribute("_d") is being setting up during invocation of the method "show",
    # and we should fairly call this method when the code base will be improved enough.
    $dt->{_d} = $sc->gettext_object;

    is( $dt->gettext, $sc->get_gettext, "gettext" );

    subtest "icons and dicons" => sub {
        $dt->{_dicons} = $sc->get_root . "/share/shutter/resources/icons/drawing_tool";
        $dt->{_icons}  = $sc->get_root . "/share/shutter/resources/icons";

        is( $dt->dicons, $dt->{_dicons}, "dicons" );
        is( $dt->icons,  $dt->{_icons},  "icons" );
    };

    subtest "clipboard" => sub {
        is( $dt->clipboard, $dt->{_clipboard}, "clipboard" );
        ok( defined $dt->clipboard, "clipboard is defined" );
        isa_ok( $dt->clipboard, "Gtk3::Clipboard" );
    };

    subtest "items" => sub {
        ok( exists $dt->{_items} && !defined $dt->{_items}, "items are empty" );
        $dt->{_items} = { foo => [], bar => [], baz => [] };
        is( $dt->items, $dt->{_items}, "items" );
    };

    subtest "drawing_window" => sub {
        ok( !exists $dt->{_drawing_window}, "there is no an attribute _drawing_window" );
        $dt->{_drawing_window} = Gtk3::Window->new('toplevel');
        is( $dt->drawing_window, $dt->{_drawing_window}, "drawing_window" );
    };

    subtest "canvas" => sub {
        ok( exists $dt->{_canvas} && !defined $dt->{_canvas}, "there's an attribute _canvas" );
        $dt->{_canvas} = GooCanvas2::Canvas->new;
        ok( defined $dt->{_canvas}, "_canvas is defined now" );
        is( $dt->canvas, $dt->{_canvas}, "canvas" );
    }
};

subtest "getters and setters" => sub {
    plan skip_all => "no env TEST_APP_SHUTTER_PATH found" unless $ENV{TEST_APP_SHUTTER_PATH};

    my $w  = Test::Window::simple_window();
    my $sc = Test::Common::get_common_object();
    $sc->set_mainwindow($w);

    my $dt = Shutter::Draw::DrawingTool->new($sc);

    subtest "cut" => sub {
        is( $dt->cut, $dt->{_cut}, "getter of 'cut'" );
        is( $dt->cut, FALSE,       "initial value of cut" );

        $dt->cut(TRUE);
        is( $dt->cut, $dt->{_cut}, "getter of 'cut'" );
        is( $dt->cut, TRUE,        "value of cut has been changed" );
    };

    subtest "current_copy_item" => sub {
        plan skip_all => "later";
    };

    subtest "current_item" => sub {
        plan skip_all => "later";
    };

    subtest "current_new_item" => sub {
        plan skip_all => "later";
    };

    subtest "canvas_bg" => sub {
        plan skip_all => "later";
    };

    subtest "factory" => sub {
        plan skip_all => "later";
    };

    subtest "autoscroll" => sub {
        plan skip_all => "later";
    };

    subtest "stroke_color" => sub {
        plan skip_all => "later";
    };

    subtest "fill_color" => sub {
        plan skip_all => "later";
    };

    subtest "line_width" => sub {
        plan skip_all => "later";
    };

    subtest "font" => sub {
        plan skip_all => "later";
    };

    subtest "uid" => sub {
        plan skip_all => "later";
    };
};

done_testing();

