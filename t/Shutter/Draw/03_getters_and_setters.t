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

    # TODO: fix it later. This attribute("_d") is being set up during invocation of the method "show",
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
        is( $dt->current_copy_item, $dt->{_current_copy_item}, "getter of 'current_copy_item'" );
        ok( !defined $dt->current_copy_item, "initial value of current_copy_item" );

        $dt->current_copy_item( { foo => 1, bar => 2, baz => 3 } );
        is( $dt->current_copy_item, $dt->{_current_copy_item}, "getter of 'current_copy_item'" );
        ok( ref $dt->current_copy_item eq "HASH", "value of current_copy_item has been changed" );
    };

    subtest "current_item" => sub {
        is( $dt->current_item, $dt->{_current_item}, "getter of 'current_item'" );
        ok( !defined $dt->current_item, "initial value of current_item" );

        $dt->current_item( { foo => 1, bar => 2, baz => 3 } );
        is( $dt->current_item, $dt->{_current_item}, "getter of 'current_item'" );
        ok( ref $dt->current_item eq "HASH", "value of current_item has been changed" );
    };

    subtest "current_new_item" => sub {
        is( $dt->current_new_item, $dt->{_current_new_item}, "getter of 'current_new_item'" );
        ok( !defined $dt->current_new_item, "initial value of current_new_item" );

        $dt->current_new_item( { foo => 1, bar => 2, baz => 3 } );
        is( $dt->current_new_item, $dt->{_current_new_item}, "getter of 'current_new_item'" );
        ok( ref $dt->current_new_item eq "HASH", "value of current_new_item has been changed" );
    };

    subtest "canvas_bg" => sub {
        ok( ! exists $dt->{_canvas_bg}, "_canvas_bg doesn't exist" );
        ok( ! defined $dt->canvas_bg, "canvas_bg getter returns undef" );
    };

    subtest "factory" => sub {
        is( $dt->factory, $dt->{_factory}, "getter of 'factory'" );
        ok( !defined $dt->factory, "initial value of factory" );

        $dt->factory( Gtk3::IconFactory->new );
        is( $dt->factory, $dt->{_factory}, "getter of 'factory'" );
        isa_ok( $dt->factory, "Gtk3::IconFactory" );
    };

    subtest "autoscroll" => sub {
        is( $dt->autoscroll, $dt->{_autoscroll}, "getter of 'autoscroll'" );
        is( $dt->autoscroll, FALSE,              "initial value of autoscroll" );

        $dt->autoscroll(TRUE);
        is( $dt->autoscroll, $dt->{_autoscroll}, "getter of 'autoscroll'" );
        is( $dt->autoscroll, TRUE,               "value of autoscroll has been changed" );
    };

    subtest "stroke_color" => sub {
        is( $dt->stroke_color, $dt->{_stroke_color}, "getter of 'stroke_color'" );
        isa_ok( $dt->stroke_color, "Gtk3::Gdk::RGBA" );

        my $new_value = Gtk3::Gdk::RGBA::parse('#0000ff');
        $dt->stroke_color($new_value);

        is( $dt->stroke_color, $new_value,           "new value of stroke_color" );
        is( $dt->stroke_color, $dt->{_stroke_color}, "getter of 'stroke_color'" );
    };

    subtest "fill_color" => sub {
        is( $dt->fill_color, $dt->{_fill_color}, "getter of 'fill_color'" );
        isa_ok( $dt->fill_color, "Gtk3::Gdk::RGBA" );

        my $new_value = Gtk3::Gdk::RGBA::parse('#ff0000');
        $dt->fill_color($new_value);

        is( $dt->fill_color, $new_value,         "new value of fill_color" );
        is( $dt->fill_color, $dt->{_fill_color}, "getter of 'fill_color'" );
    };

    subtest "line_width" => sub {
        is( $dt->line_width, $dt->{_line_width}, "getter of 'line_width'" );
        ok( defined $dt->line_width, "line_width is not empty" );
    };

    subtest "font" => sub {
        is( $dt->font, $dt->{_font}, "getter of 'font'" );
        ok( defined $dt->font, "font is not empty" );
    };

    subtest "uid" => sub {
        is( $dt->uid, $dt->{_uid}, "getter of 'uid'" );
        ok( defined $dt->uid, "uid is defined" );

        my $last_value = $dt->uid;
        is( $last_value, $dt->uid, "uid wasn't changed" );
        $dt->increase_uid;

        ok( $dt->uid - $last_value == 1, "uid has been increased" );
    };
};

done_testing();

