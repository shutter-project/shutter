# Heavily based on
# https://sourceforge.net/p/gscan2pdf/code/ci/master/tree/lib/Gscan2pdf/ImageView.pm

package Shutter::ImageView;

use warnings;
use strict;
no if $] >= 5.018, warnings => 'experimental::smartmatch';
use feature 'switch';
use Cairo;
use Glib qw(TRUE FALSE);    # To get TRUE and FALSE
use Gtk3;
use List::Util qw(min);
use Carp;
use Readonly;
Readonly my $HALF          => 0.5;
Readonly my $CURSOR_PIXELS => 5;
Readonly my $MAX_ZOOM      => 1;

our $VERSION = '2.8.1';

my %cursorhash = (
    left => {
        top    => 'nw-resize',
        mid    => 'w-resize',
        bottom => 'sw-resize',
    },
    mid => {
        top    => 'n-resize',
        mid    => 'crosshair',
        bottom => 's-resize',
    },
    right => {
        top    => 'ne-resize',
        mid    => 'e-resize',
        bottom => 'se-resize',
    },
);

# Note: in a BEGIN block to ensure that the registration is complete
#       by the time the use Subclass goes to look for it.
BEGIN {
    Glib::Type->register_enum( 'Shutter::ImageView::Tool',
        qw(dragger selector) );
}

use Glib::Object::Subclass Gtk3::DrawingArea::, signals => {
    'zoom-changed' => {
        param_types => ['Glib::Float'],    # new zoom
    },
    'offset-changed' => {
        param_types => [ 'Glib::Int', 'Glib::Int' ],    # new offset
    },
    'selection-changed' => {
        param_types => ['Glib::Scalar'],    # Gdk::Rectangle of selection area
    },
    'tool-changed' => {
        param_types => ['Glib::String'],    # new tool
    },
  },
  properties => [
    Glib::ParamSpec->object(
        'pixbuf',                           # name
        'pixbuf',                           # nickname
        'Gtk3::Gdk::Pixbuf to be shown',    # blurb
        'Gtk3::Gdk::Pixbuf',
        [qw/readable writable/]             # flags
    ),
    Glib::ParamSpec->scalar(
        'offset',                           # name
        'Image offset',                     # nick
        'Gdk::Rectangle hash of x, y',      # blurb
        [qw/readable writable/]             # flags
    ),
    Glib::ParamSpec->float(
        'zoom',                             # name
        'zoom',                             # nick
        'zoom level',                       # blurb
        0.001,                              # minimum
        100.0,                              # maximum
        1.0,                                # default_value
        [qw/readable writable/]             # flags
    ),
    Glib::ParamSpec->float(
        'resolution-ratio',                      # name
        'resolution-ratio',                      # nick
        'Ratio of x-resolution/y-resolution',    # blurb
        0.0001,                                  # minimum
        1000.0,                                  # maximum
        1.0,                                     # default_value
        [qw/readable writable/]                  # flags
    ),
    Glib::ParamSpec->enum(
        'tool',                                  # name
        'tool',                                  # nickname
        'Active Shutter::ImageView::Tool',     # blurb
        'Shutter::ImageView::Tool',
        'dragger',                               # default
        [qw/readable writable/]                  #flags
    ),
    Glib::ParamSpec->scalar(
        'selection',                                 # name
        'Selection',                                 # nick
        'Gdk::Rectangle hash of selected region',    # blurb
        [qw/readable writable/]                      # flags
    ),
    Glib::ParamSpec->boolean(
        'zoom-to-fit',                               # name
        'Zoom to fit',                               # nickname
        'Whether the zoom factor is automatically calculated to fit the window'
        ,                                            # blurb
        TRUE,                                        # default
        [qw/readable writable/]                      # flags
    ),
  ];

sub INIT_INSTANCE {
    my $self = shift;
    $self->signal_connect( draw                   => \&_draw );
	$self->signal_connect( 'button-press-event'   => \&_button_pressed );
	$self->signal_connect( 'button-release-event' => \&_button_released );
    $self->signal_connect( 'motion-notify-event'  => \&_motion );
    $self->signal_connect( 'scroll-event'         => \&_scroll );
    $self->signal_connect( configure_event        => \&_configure_event );
    $self->set_app_paintable(TRUE);

    if (
        $Glib::Object::Introspection::VERSION <
        0.043    ## no critic (ProhibitMagicNumbers)
      )
    {
        $self->add_events(
            ${ Gtk3::Gdk::EventMask->new(qw/exposure-mask/) } |
              ${ Gtk3::Gdk::EventMask->new(qw/button-press-mask/) } |
              ${ Gtk3::Gdk::EventMask->new(qw/button-release-mask/) } |
              ${ Gtk3::Gdk::EventMask->new(qw/pointer-motion-mask/) } |
              ${ Gtk3::Gdk::EventMask->new(qw/scroll-mask/) } );
    }
    else {
        $self->add_events(
            Glib::Object::Introspection->convert_sv_to_flags(
                'Gtk3::Gdk::EventMask', 'exposure-mask' ) |
              Glib::Object::Introspection->convert_sv_to_flags(
                'Gtk3::Gdk::EventMask', 'button-press-mask' ) |
              Glib::Object::Introspection->convert_sv_to_flags(
                'Gtk3::Gdk::EventMask', 'button-release-mask' ) |
              Glib::Object::Introspection->convert_sv_to_flags(
                'Gtk3::Gdk::EventMask', 'pointer-motion-mask' ) |
              Glib::Object::Introspection->convert_sv_to_flags(
                'Gtk3::Gdk::EventMask', 'scroll-mask'
              )
        );
    }
    $self->set_tool('selector');
    $self->set_redraw_on_allocate(FALSE);
    return $self;
}

sub SET_PROPERTY {
    my ( $self, $pspec, $newval ) = @_;
    my $name       = $pspec->get_name;
    my $oldval     = $self->get($name);
    my $invalidate = FALSE;
    if (   ( defined $newval and defined $oldval and $newval ne $oldval )
        or ( defined $newval xor defined $oldval ) )
    {
        given ($name) {
            when ('pixbuf') {
                $self->{$name} = $newval;
                $invalidate = TRUE;
            }
            when ('zoom') {
                $self->{$name} = $newval;
                $self->signal_emit( 'zoom-changed', $newval );
                $invalidate = TRUE;
            }
            when ('offset') {
                if (   ( defined $newval xor defined $oldval )
                    or $oldval->{x} != $newval->{x}
                    or $oldval->{y} != $newval->{y} )
                {
                    $self->{$name} = $newval;
                    $self->signal_emit( 'offset-changed', $newval->{x},
                        $newval->{y} );
                    $invalidate = TRUE;
                }
            }
            when ('resolution-ratio') {
                $self->{$name} = $newval;
                $invalidate = TRUE;
            }
            when ('selection') {
                if (   ( defined $newval xor defined $oldval )
                    or $oldval->{x} != $newval->{x}
                    or $oldval->{y} != $newval->{y}
                    or $oldval->{width} != $newval->{width}
                    or $oldval->{height} != $newval->{height} )
                {
                    $self->{$name} = $newval;
                    if ( $self->get_tool eq 'selector' ) {
                        $invalidate = TRUE;
                    }
                    $self->signal_emit( 'selection-changed', $newval );
                }
            }
            when ('tool') {
                $self->{$name} = $newval;
                if ( defined $self->get_selection ) {
                    $invalidate = TRUE;
                }
                $self->signal_emit( 'tool-changed', $newval );
            }
            default {
                $self->{$name} = $newval;

                #                $self->SUPER::SET_PROPERTY( $pspec, $newval );
            }
        }
        if ($invalidate) {
            $self->queue_draw();
        }
    }
    return;
}

sub set_pixbuf {
    my ( $self, $pixbuf, $zoom_to_fit ) = @_;
    $self->set( 'pixbuf', $pixbuf );
    $self->set_zoom_to_fit($zoom_to_fit);
    if ( not $zoom_to_fit ) {
        $self->set_offset( 0, 0 );
    }
    return;
}

sub get_pixbuf {
    my ($self) = @_;
    return $self->get('pixbuf');
}

sub get_pixbuf_size {
    my ($self) = @_;
    my $pixbuf = $self->get_pixbuf;
    if ( defined $pixbuf ) {
        return { width => $pixbuf->get_width, height => $pixbuf->get_height };
    }
    return;
}

sub _button_pressed {
    my ( $self, $event ) = @_;

	if ( $self->get_tool eq 'dragger' ) {
		# Convert the widget size to image scale to make the comparisons easier
		my $allocation = $self->get_allocation;
		( $allocation->{width}, $allocation->{height} ) =
		  $self->_to_image_distance( $allocation->{width}, $allocation->{height} );
		my $pixbuf_size = $self->get_pixbuf_size;
		if ($allocation->{width} > $pixbuf_size->{width} && $allocation->{height} > $pixbuf_size->{height}) {
			# Nothing to drag around, let drag-n-drop work
			return FALSE;
		}
	}

    $self->{drag_start} = { x => $event->x, y => $event->y };
    $self->{dragging} = TRUE;
    $self->update_cursor( $event->x, $event->y );
    if ( $self->get_tool eq 'selector' ) {
        $self->_update_selection($event);
    }
    return TRUE;


    # left mouse button
    if ( $event->button == 1 ) {
		#$self->set_tool('selector');
    }
    elsif ( $event->button == 2 ) {    # middle mouse button
        $self->set_tool('dragger');
    }
    else {
        return FALSE;
    }

    $self->{drag_start} = { x => $event->x, y => $event->y };
    $self->{dragging} = TRUE;
    $self->update_cursor( $event->x, $event->y );
    if ( $self->get_tool eq 'selector' ) {
        $self->_update_selection($event);
    }
    return TRUE;
}

sub _button_released {
    my ( $self, $event ) = @_;
    $self->{dragging} = FALSE;
    $self->update_cursor( $event->x, $event->y );
    if ( $self->get_tool eq 'selector' ) {
        $self->_update_selection($event);
    }
	#$self->set_tool('selector');
    return;
}

sub _motion {
    my ( $self, $event ) = @_;
    $self->update_cursor( $event->x, $event->y );
    if ( not $self->{dragging} ) { return FALSE }

    if ( $self->get_tool eq 'dragger' ) {
        my $offset = $self->get_offset;
        my $zoom   = $self->get_zoom;
        my $ratio  = $self->get_resolution_ratio;
        my $offset_x =
          $offset->{x} +
          ( $event->x - $self->{drag_start}{x} ) / $zoom * $ratio;
        my $offset_y =
          $offset->{y} + ( $event->y - $self->{drag_start}{y} ) / $zoom;
        ( $self->{drag_start}{x}, $self->{drag_start}{y} ) =
          ( $event->x, $event->y );
        $self->set_offset( $offset_x, $offset_y );
    }
    elsif ( $self->get_tool eq 'selector' ) {
        $self->_update_selection($event);
    }
    return;
}

sub _update_selection {
    my ( $self, $event ) = @_;
    my ( $x, $y, $x2, $y2, $x_old, $y_old, $x2_old, $y2_old );
    if ( not defined $self->{h_edge} ) { $self->{h_edge} = 'mid' }
    if ( not defined $self->{v_edge} ) { $self->{v_edge} = 'mid' }
    if ( $self->{h_edge} eq 'left' ) {
        $x = $event->x;
    }
    elsif ( $self->{h_edge} eq 'right' ) {
        $x2 = $event->x;
    }
    if ( $self->{v_edge} eq 'top' ) {
        $y = $event->y;
    }
    elsif ( $self->{v_edge} eq 'bottom' ) {
        $y2 = $event->y;
    }
    if ( $self->{h_edge} eq 'mid' and $self->{v_edge} eq 'mid' ) {
        $x  = $self->{drag_start}{x};
        $y  = $self->{drag_start}{y};
        $x2 = $event->x;
        $y2 = $event->y;
    }
    else {
        my $selection = $self->get_selection;
        if ( not defined $x or not defined $y ) {
            ( $x_old, $y_old ) =
              $self->_to_widget_coords( $selection->{x}, $selection->{y} );
        }
        if ( not defined $x2 or not defined $y2 ) {
            ( $x2_old, $y2_old ) = $self->_to_widget_coords(
                $selection->{x} + $selection->{width},
                $selection->{y} + $selection->{height}
            );
        }
        if ( not defined $x ) {
            $x = $x_old;
        }
        if ( not defined $x2 ) {
            $x2 = $x2_old;
        }
        if ( not defined $y ) {
            $y = $y_old;
        }
        if ( not defined $y2 ) {
            $y2 = $y2_old;
        }
    }
    my ( $w, $h ) = $self->_to_image_distance( abs $x2 - $x, abs $y2 - $y );
    ( $x, $y ) = $self->_to_image_coords( min( $x, $x2 ), min( $y, $y2 ) );
    $self->set_selection( { x => $x, y => $y, width => $w, height => $h } );
    return;
}

sub _scroll {
    my ( $self, $event ) = @_;
    my ( $center_x, $center_y ) =
      $self->_to_image_coords( $event->x, $event->y );
    my $zoom;
    $self->set_zoom_to_fit(FALSE);
    if ( $event->direction eq 'up' ) {
        $zoom = $self->get_zoom * 2;
    }
    else {
        $zoom = $self->get_zoom / 2;
    }
    $self->_set_zoom_with_center( $zoom, $center_x, $center_y );
    return;
}

sub _draw {
    my ( $self, $context ) = @_;
    my $allocation = $self->get_allocation;
    my $style      = $self->get_style_context;
    my $pixbuf     = $self->get_pixbuf;
    my $ratio      = $self->get_resolution_ratio;
    my $viewport   = $self->get_viewport;
    if ( defined $pixbuf ) {
        my $zoom = $self->get_zoom;
        $context->scale( $zoom / $ratio, $zoom );
        my $offset = $self->get_offset;
        $context->translate( $offset->{x}, $offset->{y} );
    }
    $style->save;
    $style->add_class(Gtk3::STYLE_CLASS_BACKGROUND);
    Gtk3::render_background( $style, $context, $viewport->{x}, $viewport->{y},
        $viewport->{width}, $viewport->{height} );
    $style->restore;
    if ( defined $pixbuf ) {
        Gtk3::Gdk::cairo_set_source_pixbuf( $context, $pixbuf, 0, 0 );
    }
    else {
        my $bgcol = $style->get( 'normal', 'background-color' );
        Gtk3::Gdk::cairo_set_source_rgba( $context, $bgcol );
    }
    $context->paint;

    my $selection = $self->get_selection;
    if ( defined $pixbuf and defined $selection ) {
        my ( $x, $y, $w, $h, ) = (
            $selection->{x},     $selection->{y},
            $selection->{width}, $selection->{height},
        );
        if ( $w <= 0 or $h <= 0 ) { return TRUE }

        $style->save;
        $style->add_class(Gtk3::STYLE_CLASS_RUBBERBAND);
        Gtk3::render_background( $style, $context, $x, $y, $w, $h );
        Gtk3::render_frame( $style, $context, $x, $y, $w, $h );
        $style->restore;
    }
    return TRUE;
}

sub _configure_event {
    my ( $self, $event ) = @_;
    if ( $self->get_zoom_to_fit ) {
        $self->zoom_to_box( $self->get_pixbuf_size );
    }
    return;
}

# setting the zoom via the public API disables zoom-to-fit

sub set_zoom {
    my ( $self, $zoom ) = @_;
    $self->set_zoom_to_fit(FALSE);
    $self->_set_zoom_no_center($zoom);
    return;
}

sub _set_zoom {
    my ( $self, $zoom ) = @_;
    if ( $zoom > $MAX_ZOOM ) { $zoom = $MAX_ZOOM }
    $self->set( 'zoom', $zoom );
    return;
}

sub get_zoom {
    my ($self) = @_;
    return $self->get('zoom');
}

# convert x, y in image coords to widget coords
sub _to_widget_coords {
    my ( $self, $x, $y ) = @_;
    my $zoom   = $self->get_zoom;
    my $ratio  = $self->get_resolution_ratio;
    my $offset = $self->get_offset;
    return ( $x + $offset->{x} ) * $zoom / $ratio,
      ( $y + $offset->{y} ) * $zoom;
}

# convert x, y in widget coords to image coords
sub _to_image_coords {
    my ( $self, $x, $y ) = @_;
    my $zoom   = $self->get_zoom;
    my $ratio  = $self->get_resolution_ratio;
    my $offset = $self->get_offset;
    return $x / $zoom * $ratio - $offset->{x}, $y / $zoom - $offset->{y};
}

# convert x, y in widget distance to image distance
sub _to_image_distance {
    my ( $self, $x, $y ) = @_;
    my $zoom  = $self->get_zoom;
    my $ratio = $self->get_resolution_ratio;
    return $x / $zoom * $ratio, $y / $zoom;
}

# set zoom with centre in image coordinates
sub _set_zoom_with_center {
    my ( $self, $zoom, $center_x, $center_y ) = @_;
    my $allocation = $self->get_allocation;
    my $ratio      = $self->get_resolution_ratio;
    my $offset_x   = $allocation->{width} / 2 / $zoom * $ratio - $center_x;
    my $offset_y   = $allocation->{height} / 2 / $zoom - $center_y;
    $self->_set_zoom($zoom);
    $self->set_offset( $offset_x, $offset_y );
    return;
}

# sets zoom, centred on the viewport
sub _set_zoom_no_center {
    my ( $self, $zoom ) = @_;
    my $allocation = $self->get_allocation;
    my ( $center_x, $center_y ) =
      $self->_to_image_coords( $allocation->{width} / 2,
        $allocation->{height} / 2 );
    $self->_set_zoom_with_center( $zoom, $center_x, $center_y );
    return;
}

sub set_zoom_to_fit {
    my ( $self, $zoom_to_fit ) = @_;
    $self->set( 'zoom-to-fit', $zoom_to_fit );
    if ( not $zoom_to_fit ) { return }
    $self->zoom_to_box( $self->get_pixbuf_size );
    return;
}

sub zoom_to_box {
    my ( $self, $box, $additional_factor ) = @_;
    if ( not defined $box ) { return }
    if ( not defined $box->{x} )          { $box->{x}          = 0 }
    if ( not defined $box->{y} )          { $box->{y}          = 0 }
    if ( not defined $additional_factor ) { $additional_factor = 1 }
    my $allocation  = $self->get_allocation;
    my $ratio       = $self->get_resolution_ratio;
    my $sc_factor_w = $allocation->{width} / $box->{width} * $ratio;
    my $sc_factor_h = $allocation->{height} / $box->{height};
    $self->_set_zoom_with_center(
        min( $sc_factor_w, $sc_factor_h ) * $additional_factor,
        ( $box->{x} + $box->{width} / 2 ) / $ratio,
        $box->{y} + $box->{height} / 2
    );
    return;
}

sub zoom_to_selection {
    my ( $self, $context_factor ) = @_;
    $self->zoom_to_box( $self->get_selection, $context_factor );
    return;
}

sub get_zoom_to_fit {
    my ($self) = @_;
    return $self->get('zoom-to-fit');
}

sub zoom_in {
    my ($self) = @_;
    $self->set_zoom_to_fit(FALSE);
    $self->_set_zoom_no_center( $self->get_zoom * 2 );
    return;
}

sub zoom_out {
    my ($self) = @_;
    $self->set_zoom_to_fit(FALSE);
    $self->_set_zoom_no_center( $self->get_zoom / 2 );
    return;
}

sub zoom_to_fit {
    my ($self) = @_;
    $self->set_zoom_to_fit(TRUE);
    return;
}

sub _clamp_direction {
    my ( $offset, $allocation, $pixbuf_size ) = @_;

    # Centre the image if it is smaller than the widget
    if ( $allocation > $pixbuf_size ) {
        $offset = ( $allocation - $pixbuf_size ) / 2;
    }

    # Otherwise don't allow the LH/top edge of the image to be visible
    elsif ( $offset > 0 ) {
        $offset = 0;
    }

    # Otherwise don't allow the RH/bottom edge of the image to be visible
    elsif ( $offset < $allocation - $pixbuf_size ) {
        $offset = $allocation - $pixbuf_size;
    }
    return $offset;
}

sub set_offset {
    my ( $self, $offset_x, $offset_y ) = @_;
    if ( not defined $self->get_pixbuf ) { return }

    # Convert the widget size to image scale to make the comparisons easier
    my $allocation = $self->get_allocation;
    ( $allocation->{width}, $allocation->{height} ) =
      $self->_to_image_distance( $allocation->{width}, $allocation->{height} );
    my $pixbuf_size = $self->get_pixbuf_size;

    $offset_x = _clamp_direction( $offset_x, $allocation->{width},
        $pixbuf_size->{width} );
    $offset_y = _clamp_direction( $offset_y, $allocation->{height},
        $pixbuf_size->{height} );

    $self->set( 'offset', { x => $offset_x, y => $offset_y } );
    return;
}

sub get_offset {
    my ($self) = @_;
    return $self->get('offset');
}

sub get_viewport {
    my ($self)     = @_;
    my $allocation = $self->get_allocation;
    my $pixbuf     = $self->get_pixbuf;
    my ( $x, $y, $w, $h );
    if ( defined $pixbuf ) {
        ( $x, $y, $w, $h ) = (
            $self->_to_image_coords( 0, 0 ),
            $self->_to_image_distance(
                $allocation->{width}, $allocation->{height}
            )
        );
    }
    else {
        ( $x, $y, $w, $h ) =
          ( 0, 0, $allocation->{width}, $allocation->{height} );
    }
    return { x => $x, y => $y, width => $w, height => $h };
}

sub set_tool {
    my ( $self, $tool ) = @_;
    $self->set( 'tool', $tool );
    return;
}

sub get_tool {
    my ($self) = @_;
    return $self->get('tool');
}

sub set_selection {
    my ( $self, $selection ) = @_;
    my $pixbuf_size = $self->get_pixbuf_size;
    if ( not defined $pixbuf_size ) { return }
    if ( $selection->{x} < 0 ) {
        $selection->{width} += $selection->{x};
        $selection->{x} = 0;
    }
    if ( $selection->{y} < 0 ) {
        $selection->{height} += $selection->{y};
        $selection->{y} = 0;
    }
    if ( $selection->{x} + $selection->{width} > $pixbuf_size->{width} ) {
        $selection->{width} = $pixbuf_size->{width} - $selection->{x};
    }
    if ( $selection->{y} + $selection->{height} > $pixbuf_size->{height} ) {
        $selection->{height} = $pixbuf_size->{height} - $selection->{y};
    }
    $self->set( 'selection', $selection );
    return;
}

sub get_selection {
    my ($self) = @_;
    return $self->get('selection');
}

sub set_resolution_ratio {
    my ( $self, $ratio ) = @_;
    $self->set( 'resolution-ratio', $ratio );
    if ( $self->get_zoom_to_fit ) {
        $self->zoom_to_box( $self->get_pixbuf_size );
    }
    return;
}

sub get_resolution_ratio {
    my ($self) = @_;
    return $self->get('resolution-ratio');
}

sub update_cursor {
    my ( $self, $x, $y ) = @_;
    my $pixbuf_size = $self->get_pixbuf_size;
    if ( not defined $pixbuf_size ) { return }
    my $win     = $self->get_window;
    my $display = Gtk3::Gdk::Display::get_default;
    my $tool    = $self->get_tool;
    my $cursor;

    if ( $tool eq 'dragger' ) {
        ( $x, $y ) = $self->_to_image_coords( $x, $y );
        if (    $x > 0
            and $x < $pixbuf_size->{width}
            and $y > 0
            and $y < $pixbuf_size->{height} )
        {
            if ( $self->{dragging} ) {
                $cursor =
                  Gtk3::Gdk::Cursor->new_from_name( $display, 'grabbing' );
            }
            else {
                $cursor = Gtk3::Gdk::Cursor->new_from_name( $display, 'grab' );
            }
        }
    }
    elsif ( $tool eq 'selector' ) {

        # If we are dragging, don't change the cursor, as we want to continue
        # to drag the corner or edge or mid element we started dragging.
        if ( $self->{dragging} ) { return }
        ( $self->{h_edge}, $self->{v_edge} ) = qw( mid mid );
        my $selection = $self->get_selection;
        if ( defined $selection ) {
            my ( $sx1, $sy1 ) =
              $self->_to_widget_coords( $selection->{x}, $selection->{y} );
            my ( $sx2, $sy2 ) = $self->_to_widget_coords(
                $selection->{x} + $selection->{width},
                $selection->{y} + $selection->{height}
            );
            if ( _between( $x, $sx1 - $CURSOR_PIXELS, $sx1 + $CURSOR_PIXELS ) )
            {
                $self->{h_edge} = 'left';
            }
            elsif (
                _between( $x, $sx2 - $CURSOR_PIXELS, $sx2 + $CURSOR_PIXELS ) )
            {
                $self->{h_edge} = 'right';
            }
            if ( _between( $y, $sy1 - $CURSOR_PIXELS, $sy1 + $CURSOR_PIXELS ) )
            {
                $self->{v_edge} = 'top';
            }
            elsif (
                _between( $y, $sy2 - $CURSOR_PIXELS, $sy2 + $CURSOR_PIXELS ) )
            {
                $self->{v_edge} = 'bottom';
            }
        }
        $cursor = Gtk3::Gdk::Cursor->new_from_name( $display,
            $cursorhash{ $self->{h_edge} }{ $self->{v_edge} } );
    }
    $win->set_cursor($cursor);
    return;
}

sub _between {
    my ( $value, $lower, $upper ) = @_;
    return ( $value > $lower and $value < $upper );
}

1;
