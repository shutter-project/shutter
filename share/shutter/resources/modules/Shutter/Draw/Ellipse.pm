package Shutter::Draw::Ellipse;

use 5.010;
use Moo;
use strictures 2;

use GooCanvas2;
use Glib qw/ TRUE FALSE /;

use constant POSITION_INDENT => 20;

has app       => ( is => "ro", required => 1 );
has event     => ( is => "rw", lazy     => 1 );
has copy_item => ( is => "rw", lazy     => 1 );
has numbered  => ( is => "rw", lazy     => 1 );
has X         => ( is => "rw", default  => sub {0} );
has Y         => ( is => "rw", default  => sub {0} );
has width     => ( is => "rw", default  => sub {0} );
has height    => ( is => "rw", default  => sub {0} );

has stroke_color => ( is => "rw", lazy => 1, default => sub { shift->app->stroke_color } );
has fill_color   => ( is => "rw", lazy => 1, default => sub { shift->app->fill_color } );
has line_width   => ( is => "rw", lazy => 1, default => sub { shift->app->line_width } );

sub setup {
    my ( $self, $event, $copy_item, $numbered ) = @_;

    $self->event($event);
    $self->copy_item($copy_item);
    $self->numbered($numbered);

    $self->_check_event_and_copy_item;

    my $item = $self->_create_item;

    $self->app->current_new_item($item) unless $self->copy_item;
    $self->app->items->{$item} = $item;

    $self->_setup_item_ellipse($item);

    if ( $self->numbered ) {
        $self->_setup_ellipse_numbered($item);
    } else {

        # set type flag
        $item->{type} = 'ellipse';
        $item->{uid}  = $self->app->uid;
        $self->app->increase_uid;
    }

    # save color and opacity as well
    $item->{fill_color}   = $self->app->fill_color;
    $item->{stroke_color} = $self->app->stroke_color;

    # create rectangles
    $self->app->handle_rects( 'create', $item );
    if ( $self->copy_item ) {
        $self->app->handle_embedded( 'update', $item );
        $self->app->handle_rects( 'hide', $item );
    }

    if ( $self->numbered ) {
        $self->app->setup_item_signals( $item->{text} );
        $self->app->setup_item_signals_extra( $item->{text} );
    }

    $self->app->setup_item_signals( $item->{ellipse} );
    $self->app->setup_item_signals_extra( $item->{ellipse} );

    $self->app->setup_item_signals($item);
    $self->app->setup_item_signals_extra($item);

    return $item;
}

sub _setup_item_ellipse {
    my ( $self, $item ) = @_;

    $item->{ellipse} = GooCanvas2::CanvasEllipse->new(
        'parent'                => $self->app->canvas->get_root_item,
        'x'                     => $self->X,
        'y'                     => $self->Y,
        'width'                 => $self->width,
        'height'                => $self->height,
        'fill-color-gdk-rgba'   => $self->fill_color,
        'stroke-color-gdk-rgba' => $self->stroke_color,
        'line-width'            => $self->line_width,
    );
}

sub _setup_ellipse_numbered {
    my ( $self, $item ) = @_;

    my $number = $self->app->get_highest_auto_digit + 1;

    my $txt = GooCanvas2::CanvasText->new(
        'parent'              => $self->app->canvas->get_root_item,
        'text'                => "<span font_desc='" . $self->app->font . "' >" . $number . "</span>",
        'x'                   => $item->{ellipse}->get('center-x'),
        'y'                   => $item->{ellipse}->get('center-y'),
        'width'               => -1,
        'anchor'              => 'center',
        'use-markup'          => TRUE,
        'fill-color-gdk-rgba' => $self->stroke_color,
        'line-width'          => $self->line_width,
    );

    $txt->{digit} = $number;
    $item->{text} = $txt;

    $item->{type} = 'number';
    $item->{uid}  = $self->app->uid;

    $self->app->increase_uid;

    #adjust parent rectangle if numbered ellipse
    my $tb = $txt->get_bounds;

    #keep ratio = 1
    my $qs = abs( $tb->x1 - $tb->x2 );
    $qs = abs( $tb->y1 - $tb->y2 ) if abs( $tb->y1 - $tb->y2 ) > abs( $tb->x1 - $tb->x2 );

    #add line width of parent ellipse
    $qs += $item->{ellipse}->get('line-width') + 5;

    $item->set(
        'x'          => $self->copy_item ? ( $self->X + POSITION_INDENT ) : ( $self->X - $qs ),
        'y'          => $self->copy_item ? ( $self->Y + POSITION_INDENT ) : ( $self->Y - $qs ),
        'width'      => $qs,
        'height'     => $qs,
        'visibility' => 'hidden',
    );

    $self->app->handle_embedded( 'hide', $item );
}

sub _check_event_and_copy_item {
    my $self = shift;

    if ( $self->event ) {
        $self->X( $self->event->x );
        $self->Y( $self->event->y );
    } elsif ( $self->copy_item ) {
        $self->X( $self->copy_item->get('x') + POSITION_INDENT );
        $self->Y( $self->copy_item->get('y') + POSITION_INDENT );

        $self->width( $self->copy_item->get('width') );
        $self->height( $self->copy_item->get('height') );

        $self->stroke_color( $self->app->items->{ $self->copy_item }->{stroke_color} );
        $self->fill_color( $self->app->items->{ $self->copy_item }->{fill_color} );
        $self->line_width( $self->app->items->{ $self->copy_item }->{ellipse}->get('line-width') );

        $self->numbered(TRUE) if exists $self->app->items->{ $self->copy_item }->{text};
    }
}

sub _create_item {
    my $self = shift;

    my $item = GooCanvas2::CanvasRect->new(
        'parent'          => $self->app->canvas->get_root_item,
        'x'               => $self->X,
        'y'               => $self->Y,
        'width'           => $self->width,
        'height'          => $self->height,
        'fill-color-rgba' => 0,
        'line-dash'       => GooCanvas2::CanvasLineDash->newv( [ 5, 5 ] ),
        'line-width'      => 1,
        'stroke-color'    => 'gray',
    );

    return $item;
}

1;
