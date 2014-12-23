#! /usr/bin/env perl
###################################################
#
#  Copyright (C) 2014      SwooshyCueb  <swooshycueb@tearmedia.info>
#
#  This file is a part of Shutter.
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

package vgyme;

use lib $ENV{'SHUTTER_ROOT'} . '/share/shutter/resources/modules';

use utf8;
use strict;
use POSIX qw/setlocale/;
use Locale::gettext;
use Glib qw/TRUE FALSE/;

use Shutter::Upload::Shared;
our @ISA = qw(Shutter::Upload::Shared);

my $d = Locale::gettext->domain("shutter-upload-plugins");
$d->dir($ENV{'SHUTTER_INTL'});

my %upload_plugin_info = (
              'module'       => "vgyme",
              'url'          => "http://vgy.me/",
              'registration' => "-",
              'description' => $d->get("Upload screenshots and such to vgy.me (API v2)"),
              'supports_anonymous_upload'  => TRUE,
              'supports_authorized_upload' => FALSE,
              'supports_oauth_upload'      => FALSE,
);

our ($url);

$url = "http://vgy.me";

binmode(STDOUT, ":utf8");
if (exists $upload_plugin_info{$ARGV[0]})
{
    print $upload_plugin_info{$ARGV[0]};
    exit;
}

# Methods below! Or whatever they're called in Perl...

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(shift, shift, shift, shift, shift, shift);

    bless $self, $class;
    return $self;
}

sub init
{

    my $self = shift;

    use WWW::Mechanize;
    use HTTP::Status;
    use HTTP::Request::Common 'POST';

    use File::Temp;
    use File::Spec;
    use File::Copy;

    use JSON::XS;

    $self->{_mech} =
      WWW::Mechanize->new(agent => "$self->{_ua}", timeout => 20);
    $self->{_http_status} = undef;

    return TRUE;
}

sub upload
{
    my ($self, $upload_filename) = @_;

    #no point in assingning variables for username and password yet.

    $self->{_filename} = $upload_filename;

    utf8::encode $upload_filename;

    my $original_filename = $upload_filename;
    my $ext               = undef;
    my $firsterr          = undef;
    my $json_data         = undef;
    my $json_worker       = undef;
    my $returned_data     = undef;
    my $nothumbnail       = 0;

    eval {
        #make sure service is actually up
        $self->{_mech}->get($url);
        $self->{_http_status} = $self->{_mech}->status();

        if (is_success($self->{_http_status}))
        {
            $json_worker = JSON::XS->new;

            

            #vgy.me doesn't like upper case file extensions.
            $original_filename =~ /\.([^.]+)$/;
            $ext = '.' . $1;
            if ($ext ne lc $ext)
            {
                $ext             = lc $ext;
                $upload_filename = File::Spec->catfile(File::Spec->tmpdir(),
                                            mktemp("shuttervgy~XXXXXX") . $ext);
                copy($original_filename, $upload_filename);
            }

            #Pickiness seems to have been mostly resolved, so only one attempt will be made.
            #There aren't any error codes or error id strings, so we have to rely on the error message.
            #That means if these ever change the script will need to be updated agian.
            $self->{_mech}->request(
                                  POST "http://vgy.me/upload.php",
                                  Content_Type => 'form-data',
                                  Content => [image => [$upload_filename],],
            );

            $self->{_http_status} = $self->{_mech}->status();

            if (is_success($self->{_http_status}))
            {

                $returned_data = $self->{_mech}->content;

                #print "Returned data:\n$returned_data\n";

                # Sometimes an invalid image will upload and be stored just fine,
                # but will fail thumbnail creation. Errors are returned in the
                # fetched data, before the JSON string, which causes problems for us.
                # Here, we clean that up
                if ($returned_data =~ m/<.*>\n/gms)
                {
                    $returned_data =~ s/^<.*>\n{/{/ms;
                    $nothumbnail = 1;
                    #print "Cleaned returned data:\n$returned_data\n";
                }

                $json_data = $json_worker->decode($returned_data);

                #my (undef, undef, $ext) = fileparse($upload_filename);
                #that should work, but it doesn't...
                $upload_filename =~ /\.([^.]+)$/;
                $ext = '.' . $1;

                if ($json_data->{'error'})
                {
                    #replace HTML line break with real line break
                    $json_data->{'errorMsg'} =~ s/<br>/\n/ig;
                    if ($json_data->{'errorMsg'} =~ m/That file is invalid/i)
                    {
                        $self->{_links}{'status'} =
                          'The image seems to be invalid or broken.';
                        warn
                          "vgy.me rejected $upload_filename, as the image seems to be broken or invalid. Upload aborted.\n";
                    }
                    elsif ($json_data->{'errorMsg'} =~ m/The file is too big/i)
                    {
                        #limit is 10MB now, which is acceptable. It also seems to be enforced well
                        $self->{_links}{'status'} = "The image is too large.\nMaximum file size is 10 MB.";
                        warn
                          "vgy.me rejected $upload_filename because it exceeded the 10MB file size limit. Upload aborted.\n";
                    }
                    elsif ($json_data->{'errorMsg'} =~ m/It appears that filetype is invalid/i)
                    {
                        #no bmp, no tiff, no tga
                        #actually bmp will upload just fine, but fails thumbnailng
                        $self->{_links}{'status'} =
                          "The image did not have an acceptable file extension.\njpg, jpeg, png, and gif are allowed.";
                        warn
                          "vgy.me rejected $upload_filename because it does not have an acceptable file extension. Upload aborted.\n";
                    }
                    elsif ($json_data->{'errorMsg'} =~ m/No file selected\. Aborted\./i)
                    {
                        #no bmp, no tiff, no tga
                        #actually bmp will upload just fine, but fails thumbnailng
                        $self->{_links}{'status'} =
                          "File not sent to server. Try again.";
                        warn
                          "vgy.me could not receive the file. Upload aborted.\n";
                    }
                    else
                    {
                        $self->{_links}{'status'} =
                          'An unknown error ocurred during upload.\n\nErrorMsg:\n' . $json_data->{'errorMsg'};
                        if ($self->{_debug})
                        {
                            warn
                              "An unknown error ocurred during upload of $upload_filename to vgy.me. Upload aborted.\n";
                        }
                    }
                    return %{$self->{_links}};
                }
                
                #linkies!
                $self->{_links}{'info'} = 'http:' . $json_data->{'imageUrl'};

                #for some reason the api starts returning the URL at "//"

                $self->{_links}{'direct'} = 'http:' . $json_data->{'hotlinkUrl'};

                if (! $nothumbnail)
                {
                    $self->{_links}{'thumbnail'} = 'http:' . $json_data->{'thumbNail'} . '.' .  $json_data->{'fileExt'};
                    #thumbnails are pretty broken right now, lol
                }

                if ($self->{_debug})
                {
                    print
                      "The following links were returned by http://vgy.me:\n";
                    print "Info: \n$self->{_links}{'info'}\n";
                    print "Direct Link: \n$self->{_links}{'direct'}\n";
                    if (! $nothumbnail)
                    {
                        print "Thumbnail: \n$self->{_links}{'thumbnail'}\n";
                    }
                }

                $self->{_links}{'status'} = $self->{_http_status};
            }
            else
            {
                $self->{_links}{'status'} = $self->{_http_status};
                last;
            }

        }
        else
        {
            $self->{_links}{'status'} = $self->{_http_status};
        }

    };

    if ($@)
    {
        $self->{_links}{'status'} = $@;
    }
    return %{$self->{_links}};
}

1;
