#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Gtk3 '-init';
use Shutter::Screenshot::Popup;

{
    package PopupTest::Common;
    use strict;
    use warnings;
    sub get_gettext { shift }
    sub get { $_[1] }
    sub get_mainwindow { undef }
}
my $sc = bless {}, 'PopupTest::Common';
my $pixbuf = Gtk3::Gdk::Pixbuf->new('rgb', 0, 8, 100, 80);
$pixbuf->fill(0xff0000ff);
my $patch = Gtk3::Gdk::Pixbuf->new('rgb', 0, 8, 20, 10);
$patch->fill(0x00ff00ff);
$patch->copy_area(0, 0, 20, 10, $pixbuf, 30, 40);
my $crop = Shutter::Screenshot::Popup::crop_region($pixbuf, {x=>30,y=>40,width=>20,height=>10});
is($crop->get_width, 20, 'crop width in source pixels');
is($crop->get_height, 10, 'crop height in source pixels');
is(substr($crop->get_pixels, 0, 3), "\x00\xff\x00", 'crop contains the selected pixels');
$pixbuf->fill(0xff0000ff);
is(substr($crop->get_pixels, 0, 3), "\x00\xff\x00", 'crop is independent of the original buffer');

for my $region (undef, {}, {x=>0,y=>0,width=>0,height=>1}, {x=>110,y=>0,width=>20,height=>10}) {
    ok(!defined Shutter::Screenshot::Popup::crop_region($pixbuf, $region), 'invalid selection rejected');
}
$crop = Shutter::Screenshot::Popup::crop_region($pixbuf, {x=>-10,y=>-5,width=>200,height=>200});
is($crop->get_width, 100, 'crop clamped horizontally');
is($crop->get_height, 80, 'crop clamped vertically');

# Drive the actual GTK dialog in Xvfb, including selection at a scaled zoom.
$pixbuf = Gtk3::Gdk::Pixbuf->new('rgb', 0, 8, 3840, 2160);
$pixbuf->fill(0xff0000ff);
for my $response ('ok', 'cancel', 'delete-event') {
    my $driven;
    Glib::Idle->add(sub {
        my ($dialog) = grep { $_->isa('Gtk3::Dialog') } Gtk3::Window::list_toplevels();
        return 1 unless $dialog;
        my ($view) = grep { $_->isa('Gtk3::ImageView') } $dialog->get_content_area->get_children;
        ok(!$dialog->get_widget_for_response('ok')->get_sensitive, 'empty selection cannot be confirmed');
        $view->set_zoom(0.5);
        $view->set_selection({x=>30,y=>40,width=>20,height=>10});
        ok($dialog->get_widget_for_response('ok')->get_sensitive, 'valid selection enables confirmation');
        $driven = 1;
        $dialog->response($response);
        return 0;
    });
    my $result = Shutter::Screenshot::Popup::select_region($sc, $pixbuf);
    ok($driven, "dialog driven for $response");
    if ($response eq 'ok') {
        is($result->get_width, 20, 'scaled preview preserves source crop width');
        is($result->get_height, 10, 'scaled preview preserves source crop height');
    } else {
        ok(!defined $result, "$response cancels without an image");
    }
}

done_testing;
