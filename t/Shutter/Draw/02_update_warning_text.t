
use 5.010;
use strict;
use warnings;

use Locale::gettext;
use Test::More;
use Test::MockModule;

require_ok('Shutter::Draw::DrawingTool');

my $mock = Test::MockModule->new("Shutter::Draw::DrawingTool");
$mock->mock(
    "new",
    sub {
        my $cls = shift;

        return bless {
            _start_time => time(),
            _d          => Locale::gettext->domain("shutter") }, $cls;
    } );

subtest "Singular minute" => sub {
    my $draw        = Shutter::Draw::DrawingTool->new();
    my $warn_dialog = CustomWarnDialog->new();

    $draw->update_warning_text($warn_dialog);

    ok( $warn_dialog->{type} eq "secondary-text" );
    like( $warn_dialog->{txt}, qr/from the last minute/ );
};

subtest "Plural minutes" => sub {
    my $draw        = Shutter::Draw::DrawingTool->new();
    my $warn_dialog = CustomWarnDialog->new();

    $draw->{_start_time} = $draw->{_start_time} - 120;

    $draw->update_warning_text($warn_dialog);

    ok( $warn_dialog->{type} eq "secondary-text" );
    like( $warn_dialog->{txt}, qr/from the last 2 minutes/ );
};

done_testing();

package CustomWarnDialog {

    sub new {
        my $cls = shift;

        return bless { type => undef, txt => undef }, $cls;
    }

    sub set {
        my ( $self, $type, $txt ) = @_;

        $self->{type} = $type;
        $self->{txt}  = $txt;
    }
};
