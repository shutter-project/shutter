use 5.010;
use strict;
use warnings;

use Gtk3;    # to escape warnings "Too late to run INIT block"
use Gtk3::ImageView 10;
use Glib qw/ TRUE FALSE /;
use Test::More;
use Data::Dumper;

require Test::Window;
require Test::Common;
require Test::SimpleApp;

require Shutter::App::SimpleDialogs;
require Shutter::App::HelperFunctions;
require Shutter::App::Common;
require Shutter::Draw::DrawingTool;

require_ok("Shutter::Draw::Ellipse");

subtest "simply create ellipse" => sub {
    my $app     = Test::SimpleApp->new;
    my $ellipse = Shutter::Draw::Ellipse->new( app => $app );

    ok( defined $ellipse, "ellipse defined" );
    is( $ellipse->app, $app, "check ellipse's app" );
};

subtest "internal methods" => sub {
    plan skip_all => "no env TEST_APP_SHUTTER_PATH found" unless $ENV{TEST_APP_SHUTTER_PATH};

    my $w  = Test::Window::simple_window();
    my $sc = Test::Common::get_common_object();
    $sc->set_mainwindow($w);

    my $dt = Shutter::Draw::DrawingTool->new($sc);
    $dt->{_canvas} = GooCanvas2::Canvas->new;

    my $ellipse = Shutter::Draw::Ellipse->new( app => $dt );

    subtest "attributes" => sub {
        ok( !defined $ellipse->event,     "event is null" );
        ok( !defined $ellipse->copy_item, "copy_item is null" );
        ok( !defined $ellipse->numbered,  "numbered is null" );
        is( $ellipse->X,      0, "value of X" );
        is( $ellipse->Y,      0, "value of Y" );
        is( $ellipse->width,  0, "value of width" );
        is( $ellipse->height, 0, "value of height" );

        ok( defined $ellipse->stroke_color, "stroke_color is defined" );
        is( $ellipse->stroke_color, $dt->stroke_color, "stroke_color value" );

        ok( defined $ellipse->fill_color, "fill_color is defined" );
        is( $ellipse->fill_color, $dt->fill_color, "fill_color value" );

        ok( defined $ellipse->line_width, "line_width is defined" );
        is( $ellipse->line_width, $dt->line_width, "line_width value" );
    };

    subtest "create_item" => sub {
        my $item = $ellipse->_create_item;

        ok( defined $item, "item is defined" );
        isa_ok( $item, "GooCanvas2::CanvasRect" );

        is( $item->get("parent"),          $dt->canvas->get_root_item, "item's parent" );
        is( $item->get("x"),               $ellipse->X,                "item's X" );
        is( $item->get("y"),               $ellipse->Y,                "item's Y" );
        is( $item->get("width"),           $ellipse->width,            "item's width" );
        is( $item->get("height"),          $ellipse->height,           "item's height" );
        is( $item->get("line-width"),      1,                          "item's line-width" );
        is( $item->get("fill-color-rgba"), 0,                          "item's fill-color-rgba" );

        ok( $item->get("line-dash"), "there's line-dash" );
        isa_ok( $item->get("line-dash"), "GooCanvas2::CanvasLineDash" );
    }
};

done_testing();

package SimpleApp { use Moo };
