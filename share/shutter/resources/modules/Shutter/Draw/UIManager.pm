###################################################
#
#  Copyright (C) 2021 Alexander Ruzhnikov <ruzhnikov85@gmail.com>
#
#  This file is part of Shutter.
#
#  Shutter is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  Shutter is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with Shutter; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
#
###################################################

package Shutter::Draw::UIManager;

use Moo;
use strictures 2;
use Gtk3;
use Glib qw/ TRUE FALSE /;

has app => ( is => "ro", required => 1 );

has dicons  => ( is => "ro", lazy => 1, default => sub { shift->app->dicons } );
has gettext => ( is => "ro", lazy => 1, default => sub { shift->app->gettext } );

sub setup {
    my $self = shift;

    $self->app->factory( $self->_create_factory );

    my $uimanager = Gtk3::UIManager->new;

    # keyboard accel_group
    my $accelgroup = $uimanager->get_accel_group;
    $self->app->drawing_window->add_accel_group($accelgroup);

    $uimanager->insert_action_group( $self->_create_main_group,    0 );
    $uimanager->insert_action_group( $self->_create_toggle_group,  0 );
    $uimanager->insert_action_group( $self->_create_drawing_group, 0 );

    eval {
        $uimanager->add_ui_from_string( $self->_get_ui_info );
        1;
    } or do {
        die "Unable to create menus: $@\n";
    };

    return $uimanager;
}

sub _create_factory {
    my $self = shift;

    my $factory = Gtk3::IconFactory->new;

    $factory->add( 'shutter-ellipse',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-ellipse.png' ) ) );

    $factory->add( 'shutter-eraser',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-eraser.png' ) ) );

    $factory->add( 'shutter-freehand',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-freehand.png' ) ) );

    $factory->add( 'shutter-highlighter',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-highlighter.png' ) ) );

    $factory->add( 'shutter-pointer',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-pointer.png' ) ) );

    $factory->add( 'shutter-rectangle',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-rectangle.png' ) ) );

    $factory->add( 'shutter-line',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-line.png' ) ) );

    $factory->add( 'shutter-arrow',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-arrow.png' ) ) );

    $factory->add( 'shutter-text',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-text.png' ) ) );

    $factory->add( 'shutter-censor',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-censor.png' ) ) );
    $factory->add( 'shutter-pixelize',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-pixelize.png' ) ) );
    $factory->add( 'shutter-number',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/draw-number.png' ) ) );
    $factory->add( 'shutter-crop',
        Gtk3::IconSet->new_from_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file( $self->dicons . '/transform-crop.png' ) ) );

    $factory->add_default();

    return $factory;
}

sub _create_main_group {
    my $self = shift;

    # Setup the main group.
    my $main_group = Gtk3::ActionGroup->new("main");
    $main_group->add_actions( $self->_create_main_actions );

    return $main_group;
}

sub _create_main_actions {
    my $self = shift;

    my @main_actions = (
        [ "File",  undef, $self->gettext->get("_File") ],
        [ "Edit",  undef, $self->gettext->get("_Edit") ],
        [ "Tools", undef, $self->gettext->get("_Tools") ],
        [ "View",  undef, $self->gettext->get("_View") ],
        [   "Undo",
            'gtk-undo',
            undef,
            "<control>Z",
            $self->gettext->get("Undo last action"),
            sub {
                $self->app->abort_current_mode;
                $self->app->xdo( 'undo', 'ui' );
            }
        ],
        [   "Redo",
            'gtk-redo',
            undef,
            "<control>Y",
            $self->gettext->get("Do again the last undone action"),
            sub {
                $self->abort_current_mode;
                $self->xdo( 'redo', 'ui' );
            }
        ],
        [   "Copy",
            'gtk-copy',
            undef,
            "<control>C",
            $self->gettext->get("Copy selection to clipboard"),
            sub {

                #clear clipboard
                $self->app->clipboard->set_text("");
                $self->app->cut(FALSE);
                $self->app->current_copy_item( $self->app->current_item );
            }
        ],
        [   "Cut",
            'gtk-cut',
            undef,
            "<control>X",
            $self->gettext->get("Cut selection to clipboard"),
            sub {

                #clear clipboard
                $self->app->clipboard->set_text("");
                $self->app->cut(TRUE);
                $self->app->current_copy_item( $self->app->current_item );
                $self->app->clear_item_from_canvas( $self->app->current_copy_item );
            }
        ],
        [   "Paste",
            'gtk-paste',
            undef,
            "<control>V",
            $self->gettext->get("Paste objects from clipboard"),
            sub {
                $self->app->paste_item( $self->app->current_copy_item, $self->app->cut );
                $self->app->cut(FALSE);
            }
        ],
        [   "Delete", 'gtk-delete', undef, "Delete",
            $self->gettext->get("Delete current object"),
            sub { $self->app->clear_item_from_canvas( $self->app->current_item ) }
        ],
        [   "Clear",
            'gtk-clear',
            undef,
            "<control>Delete",
            $self->gettext->get("Clear canvas"),
            sub {

                #store items to delete in temporary hash
                #sort them uid
                my %time_hash;
                for my $item ( values %{ $self->app->items } ) {
                    next if exists $item->{image} && $item->{image} == $self->app->canvas_bg;
                    $time_hash{ $item->{uid} } = $item;
                }

                #delete items
                for my $key ( sort keys %time_hash ) {
                    $self->app->clear_item_from_canvas( $time_hash{$key} );
                }
            }
        ],
        [   "Stop", 'gtk-stop', undef, "Escape",
            $self->gettext->get("Abort current mode"),
            sub { $self->app->abort_current_mode }
        ],
        [   "Close", 'gtk-close', undef, "<control>Q",
            $self->gettext->get("Close this window"),
            sub { $self->app->quit(TRUE) }
        ],
        [   "Save",
            'gtk-save',
            undef,
            "<control>S",
            $self->gettext->get("Save image"),
            sub {
                $self->app->save();
                $self->app->quit(FALSE);
            }
        ],
        [   "ExportTo",
            'gtk-save-as',
            $self->gettext->get("Export to _File..."),
            "<Shift><Control>E",
            $self->gettext->get("Export to File..."),
            sub {
                $self->app->export_to_file();
            }
        ],
        [   "ExportToSvg",
            undef,
            $self->gettext->get("_Export to SVG..."),
            "<Shift><Alt>V",
            $self->gettext->get("Export to SVG..."),
            sub {
                $self->app->export_to_svg();
            }
        ],
        [   "ExportToPdf",
            undef,
            $self->gettext->get("E_xport to PDF..."),
            "<Shift><Alt>P",
            $self->gettext->get("Export to PDF..."),
            sub {
                $self->app->export_to_pdf();
            }
        ],
        [   "ExportToPS",
            undef,
            $self->gettext->get("Export to Post_Script..."),
            "<Shift><Alt>S",
            $self->gettext->get("Export to PostScript..."),
            sub {
                $self->app->export_to_ps();
            }
        ],
        [ "ZoomIn",       'gtk-zoom-in', undef, "<control>plus",  undef, sub { $self->app->zoom_in_cb( $self->app ) } ],
        [ "ControlEqual", 'gtk-zoom-in', undef, "<control>equal", undef, sub { $self->app->zoom_in_cb( $self->app ) } ],
        [   "ControlKpAdd",
            'gtk-zoom-in',
            undef,
            "<control>KP_Add",
            undef,
            sub {
                $self->app->zoom_in_cb( $self->app );
            }
        ],
        [ "ZoomOut", 'gtk-zoom-out', undef, "<control>minus", undef, sub { $self->app->zoom_out_cb( $self->app ) } ],
        [   "ControlKpSub",
            'gtk-zoom-out',
            undef,
            "<control>KP_Subtract",
            undef,
            sub {
                $self->app->zoom_out_cb( $self->app );
            }
        ],
        [   "ZoomNormal",
            'gtk-zoom-100',
            undef,
            "<control>0",
            undef,
            sub {
                $self->app->zoom_normal_cb( $self->app );
            }
        ],
    );

    return \@main_actions;
}

sub _create_toggle_group {
    my $self = shift;

    #setup the menu toggle group
    my $toggle_group = Gtk3::ActionGroup->new("toggle");
    $toggle_group->add_toggle_actions( $self->_create_toggle_actions );

    return $toggle_group;
}

sub _create_toggle_actions {
    my $self = shift;

    my @toggle_actions = (
        [   "Autoscroll",
            undef,
            $self->gettext->get("Automatic scrolling"),
            undef, undef,
            sub {
                my $widget = shift;

                if ( $widget->get_active ) {
                    $self->app->autoscroll(TRUE);
                } else {
                    $self->app->autoscroll(FALSE);
                }

                #'redraw-when-scrolled' to reduce the flicker of static items
                #
                #this property is not available in older versions
                #it was added to goocanvas on Mon Nov 17 10:28:07 2008 UTC
                #http://svn.gnome.org/viewvc/goocanvas?view=revision&revision=28
                if ( $self->app->canvas && $self->app->canvas->find_property('redraw-when-scrolled') ) {
                    $self->app->canvas->set( 'redraw-when-scrolled' => !$self->app->autoscroll );
                }
            }
        ],
        [   "Fullscreen",
            'gtk-fullscreen',
            undef, "F11", undef,
            sub {
                my $action = shift;

                if ( $action->get_active ) {
                    $self->app->drawing_window->fullscreen;
                } else {
                    $self->app->drawing_window->unfullscreen;
                }
            }
        ],
    );

    return \@toggle_actions;
}

sub _create_drawing_group {
    my $self = shift;

    # Setup the drawing group.
    my $drawing_actions = $self->_create_drawing_actions;
    my $drawing_group   = Gtk3::ActionGroup->new("drawing");
    $drawing_group->add_radio_actions(
        $drawing_actions,
        10,
        sub {
            my $action = shift;
            $self->app->change_drawing_tool_cb($action);
        } );

    return $drawing_group;
}

sub _create_drawing_actions {
    my $self = shift;

    my @drawing_actions = (
        [   "Select", 'shutter-pointer',                                       $self->gettext->get("Select"),
            "<alt>0", $self->gettext->get("Select item to move or resize it"), 10
        ],
        [   "Freehand",                                  'shutter-freehand',
            $self->gettext->get("Freehand"),             "<alt>1",
            $self->gettext->get("Draw a freehand line"), 20
        ],
        [   "Highlighter",                      'shutter-highlighter',
            $self->gettext->get("Highlighter"), "<alt>2",
            $self->gettext->get("Highlighter"), 30
        ],
        [   "Line",                                      'shutter-line',
            $self->gettext->get("Line"),                 "<alt>3",
            $self->gettext->get("Draw a straight line"), 40
        ],
        [ "Arrow", 'shutter-arrow', $self->gettext->get("Arrow"), "<alt>4", $self->gettext->get("Draw an arrow"), 50 ],
        [   "Rect",                                  'shutter-rectangle',
            $self->gettext->get("Rectangle"),        "<alt>5",
            $self->gettext->get("Draw a rectangle"), 60
        ],
        [   "Ellipse",                             'shutter-ellipse',
            $self->gettext->get("Ellipse"),        "<alt>6",
            $self->gettext->get("Draw a ellipse"), 70
        ],
        [   "Text",   'shutter-text',                                         $self->gettext->get("Text"),
            "<alt>7", $self->gettext->get("Add some text to the screenshot"), 80
        ],
        [   "Censor", 'shutter-censor', $self->gettext->get("Censor"),
            "<alt>8", $self->gettext->get("Censor portions of your screenshot to hide private data"), 90
        ],
        [   "Pixelize",     'shutter-pixelize', $self->gettext->get("Pixelize"),
            "<alt><ctrl>8", $self->gettext->get("Pixelize selected areas of your screenshot to hide private data"), 100
        ],
        [   "Number", 'shutter-number', $self->gettext->get("Number"),
            "<alt>9", $self->gettext->get("Add an auto-increment shape to the screenshot"), 110
        ],
        [   "Crop",                                      'shutter-crop',
            $self->gettext->get("Crop"),                 "<alt>c",
            $self->gettext->get("Crop your screenshot"), 120
        ],
    );

    return \@drawing_actions;
}

sub _get_ui_info {
    my $self = shift;

    return "
    <ui>
      <menubar name = 'MenuBar'>
        <menu action = 'File'>
          <menuitem action = 'Save'/>
          <menuitem action = 'ExportTo'/>
          <menuitem action = 'ExportToSvg'/>
          <menuitem action = 'ExportToPdf'/>
          <menuitem action = 'ExportToPS'/>
          <separator/>
          <menuitem action = 'Close'/>
        </menu>
        <menu action = 'Edit'>
          <menuitem action = 'Undo'/>
          <menuitem action = 'Redo'/>
          <separator/>
          <menuitem action = 'Copy'/>
          <menuitem action = 'Cut'/>
          <menuitem action = 'Paste'/>
          <menuitem action = 'Delete'/>
          <menuitem action = 'Clear'/>            
          <separator/>
          <menuitem action = 'Stop'/>
          <separator/>
          <menuitem action = 'Autoscroll'/>
        </menu>
        <menu action = 'Tools'>
          <menuitem action='Select'/>
          <separator/>
          <menuitem action='Freehand'/>
          <menuitem action='Highlighter'/>
          <menuitem action='Line'/>
          <menuitem action='Arrow'/>
          <menuitem action='Rect'/>
          <menuitem action='Ellipse'/>
          <menuitem action='Text'/>
          <menuitem action='Censor'/>
          <menuitem action='Pixelize'/>
          <menuitem action='Number'/>
          <separator/>
          <menuitem action='Crop'/>
        </menu>
        <menu action = 'View'>
          <menuitem action = 'ControlEqual'/>   
          <menuitem action = 'ControlKpAdd'/>   
          <menuitem action = 'ZoomIn'/>
          <menuitem action = 'ZoomOut'/>
          <menuitem action = 'ControlKpSub'/>         
          <menuitem action = 'ZoomNormal'/>
          <separator/>
          <menuitem action = 'Fullscreen'/>
        </menu>
      </menubar>
      <toolbar name = 'ToolBar'>
        <toolitem action='Close'/>
        <toolitem action='Save'/>
        <toolitem action='ExportTo'/>
        <separator/>
        <toolitem action='ZoomIn'/>
        <toolitem action='ZoomOut'/>
        <toolitem action='ZoomNormal'/>
        <separator/>
        <toolitem action='Undo'/>
        <toolitem action='Redo'/>
        <separator/>
        <toolitem action='Copy'/>
        <toolitem action='Cut'/>
        <toolitem action='Paste'/>
        <toolitem action='Delete'/>     
        <toolitem action='Clear'/>      
      </toolbar>
      <toolbar name = 'ToolBarDrawing'>
        <toolitem action='Select'/>
        <separator/>
        <toolitem action='Freehand'/>
        <toolitem action='Highlighter'/>
        <toolitem action='Line'/>
        <toolitem action='Arrow'/>
        <toolitem action='Rect'/>
        <toolitem action='Ellipse'/>
        <toolitem action='Text'/>
        <toolitem action='Censor'/>
        <toolitem action='Pixelize'/>
        <toolitem action='Number'/>
        <separator/>
        <toolitem action='Crop'/>
      </toolbar>  
    </ui>";
}

1;
