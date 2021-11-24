use 5.020;    # List::Util >= 1.33
use strict;
use warnings;

use List::Util qw/ all /;

use Gtk3;     # to escape warnings "Too late to run INIT block"
use Gtk3::ImageView 10;
use Glib qw/ TRUE FALSE /;
use Test::More tests => 4;

require Test::Window;
require Test::Common;
require Test::SimpleApp;

require Shutter::App::SimpleDialogs;
require Shutter::App::HelperFunctions;
require Shutter::App::Common;
require Shutter::Draw::DrawingTool;

require_ok("Shutter::Draw::UIManager");

subtest "simply create uimanager" => sub {
    my $app       = Test::SimpleApp->new;
    my $uimanager = Shutter::Draw::UIManager->new( app => $app );

    ok( defined $uimanager, "uimanager defined" );
    is( $uimanager->app, $app, "check uimanager's app" );
};

subtest "internal methods" => sub {
    plan skip_all => "no env TEST_APP_SHUTTER_PATH found" unless $ENV{TEST_APP_SHUTTER_PATH};

    my $w  = Test::Window::simple_window();
    my $sc = Test::Common::get_common_object();
    $sc->set_mainwindow($w);

    my $dt = Shutter::Draw::DrawingTool->new($sc);

    $dt->{_d}      = $sc->gettext_object;
    $dt->{_dicons} = $sc->get_root . "/share/shutter/resources/icons/drawing_tool";
    $dt->{_icons}  = $sc->get_root . "/share/shutter/resources/icons";

    my $uimanager = Shutter::Draw::UIManager->new( app => $dt );

    subtest "attributes" => sub {
        is( $uimanager->gettext, $sc->get_gettext, "check attribute 'gettext'" );
        is( $uimanager->dicons,  $dt->dicons,      "check attribute 'dicons'" );
    };

    subtest "create_factory" => sub {
        my $f = $uimanager->_create_factory;

        ok( defined $f, "factory is defined" );
        isa_ok( $f, "Gtk3::IconFactory" );

        # check existence of several icons
        for my $stock_id (qw/ shutter-ellipse shutter-pointer shutter-text shutter-number /) {
            ok( defined $f->lookup($stock_id), "found '$stock_id'" );
            isa_ok( $f->lookup($stock_id), "Gtk3::IconSet" );
        }
    };

    subtest "create_main_actions" => sub {
        my $main_actions = $uimanager->_create_main_actions;

        ok( ref $main_actions eq "ARRAY",                   "main actions ref" );
        ok( ( all { ref $_ eq "ARRAY" } @{$main_actions} ), "ref of every action" );
        ok( ( all { defined $_->[0] } @{$main_actions} ),   "the first element of every action is defined" );
    };

    subtest "create_main_group" => sub {
        my $main_group = $uimanager->_create_main_group;

        ok( defined $main_group, "main_group's defined" );
        isa_ok( $main_group, "Gtk3::ActionGroup" );

        is( $main_group->get_name, "main", "name of main_group" );
        ok( scalar( $main_group->list_actions ) > 0, "list of actions is not empty" );

        # check some actions in the list
        for my $action (qw/ File Tools Redo Paste Stop ExportTo /) {
            my $action_object = $main_group->get_action($action);

            ok( defined $action_object, "has the action '$action'" );
            isa_ok( $action_object, "Gtk3::Action" );
        }
    };

    subtest "create_toggle_actions" => sub {
        my $toggle_actions = $uimanager->_create_toggle_actions;

        ok( defined $toggle_actions,                          "defined toggle_actions" );
        ok( ref $toggle_actions eq "ARRAY",                   "ref of toggle_actions" );
        ok( ( all { ref $_ eq "ARRAY" } @{$toggle_actions} ), "ref of every action" );
        ok( ( all { defined $_->[0] } @{$toggle_actions} ),   "the first element of every action is defined" );
    };

    subtest "create_toggle_group" => sub {
        my $toggle_group = $uimanager->_create_toggle_group;

        ok( defined $toggle_group, "toggle_group's defined" );
        isa_ok( $toggle_group, "Gtk3::ActionGroup" );

        is( $toggle_group->get_name, "toggle", "name of toggle_group" );
        ok( scalar( $toggle_group->list_actions ) > 0, "list of actions is not empty" );

        for my $action (qw/ Autoscroll Fullscreen /) {
            my $action_object = $toggle_group->get_action($action);

            ok( defined $action_object, "has the action '$action'" );
            isa_ok( $action_object, "Gtk3::ToggleAction" );
        }
    };

    subtest "create_drawing_actions" => sub {
        my $drawing_actions = $uimanager->_create_drawing_actions;

        ok( defined $drawing_actions,                          "defined drawing_actions" );
        ok( ref $drawing_actions eq "ARRAY",                   "ref of drawing_actions" );
        ok( ( all { ref $_ eq "ARRAY" } @{$drawing_actions} ), "ref of every action" );
        ok( ( all { defined $_->[0] } @{$drawing_actions} ),   "the first element of every action is defined" );
    };

    subtest "create_drawing_group" => sub {
        my $drawing_group = $uimanager->_create_drawing_group;

        ok( defined $drawing_group, "drawing_group's defined" );
        isa_ok( $drawing_group, "Gtk3::ActionGroup" );

        is( $drawing_group->get_name, "drawing", "name of drawing_group" );
        ok( scalar( $drawing_group->list_actions ) > 0, "list of actions is not empty" );

        for my $action (qw/ Select Highlighter Arrow Censor Crop /) {
            my $action_object = $drawing_group->get_action($action);

            ok( defined $action_object, "has the action '$action'" );
            isa_ok( $action_object, "Gtk3::RadioAction" );
        }
    };

    subtest "get_ui_info" => sub {
        my $ui_info = $uimanager->_get_ui_info;

        ok( $ui_info,                          "ui_info is not empty" );
        ok( $ui_info =~ m/\s+<ui>.+<\/ui>$/ms, "structure of ui_info" );
    };
};

subtest "setup" => sub {
    plan skip_all => "no env TEST_APP_SHUTTER_PATH found" unless $ENV{TEST_APP_SHUTTER_PATH};

    my $w  = Test::Window::simple_window();
    my $sc = Test::Common::get_common_object();
    $sc->set_mainwindow($w);

    my $dt = Shutter::Draw::DrawingTool->new($sc);

    $dt->{_d}              = $sc->gettext_object;
    $dt->{_dicons}         = $sc->get_root . "/share/shutter/resources/icons/drawing_tool";
    $dt->{_icons}          = $sc->get_root . "/share/shutter/resources/icons";
    $dt->{_drawing_window} = Gtk3::Window->new('toplevel');

    my $uimanager = Shutter::Draw::UIManager->new( app => $dt )->setup;

    ok( defined $uimanager, "defined uimanager" );
    isa_ok( $uimanager, "Gtk3::UIManager" );

    my @action_groups = $uimanager->get_action_groups;
    is( scalar @action_groups, 3, "number of action groups" );
};

done_testing();
