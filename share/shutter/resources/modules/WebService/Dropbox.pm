package WebService::Dropbox;
use strict;
use warnings;
use Carp ();
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK SEEK_SET SEEK_END);
use JSON;
use Net::OAuth;
use URI;
use URI::Escape;

our $VERSION = '1.22';

my $request_token_url = 'https://api.dropbox.com/1/oauth/request_token';
my $access_token_url = 'https://api.dropbox.com/1/oauth/access_token';
my $authorize_url = 'https://www.dropbox.com/1/oauth/authorize';

__PACKAGE__->mk_accessors(qw/
    key
    secret
    request_token
    request_secret
    access_token
    access_secret
    root

    no_decode_json
    error
    code
    request_url
    request_method
    timeout
/);

$WebService::Dropbox::USE_LWP = 0;

sub import {
    eval {
        require Furl::HTTP;
        require IO::Socket::SSL;
    };if ($@) {
        __PACKAGE__->use_lwp;
    }
}

sub use_lwp {
    require LWP::UserAgent;
    require HTTP::Request;
    $WebService::Dropbox::USE_LWP++;
}

sub new {
    my ($class, $args) = @_;

    bless {
        key            => $args->{key}            || '',
        secret         => $args->{secret}         || '',
        request_token  => $args->{request_token}  || '',
        request_secret => $args->{request_secret} || '',
        access_token   => $args->{access_token}   || '',
        access_secret  => $args->{access_secret}  || '',
        root           => $args->{root}           || 'dropbox',
        timeout        => $args->{timeout}        || (60 * 60 * 24),
        no_decode_json => $args->{no_decode_json} || 0,
        no_uri_escape  => $args->{no_uri_escape}  || 0,
        env_proxy      => $args->{lwp_env_proxy}  || $args->{env_proxy} || 0,
    }, $class;
}

sub login {
    my ($self, $callback_url) = @_;

    my $body = $self->api({
        method => 'POST',
        url  => $request_token_url
    }) or return;

    my $response = Net::OAuth->response('request token')->from_post_body($body);
    $self->request_token($response->token);
    $self->request_secret($response->token_secret);

    my $url = URI->new($authorize_url);
    $url->query_form(
        oauth_token => $response->token,
        oauth_callback => $callback_url
    );
    $url->as_string;
}

sub auth {
    my $self = shift;

    my $body = $self->api({
        method => 'POST',
        url  => $access_token_url
    }) or return;

    my $response = Net::OAuth->response('access token')->from_post_body($body);
    $self->access_token($response->token);
    $self->access_secret($response->token_secret);
}

sub account_info {
    my $self = shift;

    $self->api_json({
        url => 'https://api.dropbox.com/1/account/info'
    });
}

sub files {
    my ($self, $path, $output, $params, $opts) = @_;

    $opts ||= {};
    if (ref $output eq 'CODE') {
        $opts->{write_code} = $output; # code ref
    } elsif (ref $output) {
        $opts->{write_file} = $output; # file handle
        binmode $opts->{write_file};
    } else {
        open $opts->{write_file}, '>', $output; # file path
        Carp::croak("invalid output, output must be code ref or filehandle or filepath.")
            unless $opts->{write_file};
        binmode $opts->{write_file};
    }
    $self->api({
        url => $self->url('https://api-content.dropbox.com/1/files/' . $self->root, $path),
        extra_params => $params,
        %$opts
    });

    return if $self->error;
    return 1;
}

sub files_put {
    my ($self, $path, $content, $params, $opts) = @_;

    $opts ||= {};
    $self->api_json({
        method => 'PUT',
        url => $self->url('https://api-content.dropbox.com/1/files_put/' . $self->root, $path),
        content => $content,
        extra_params => $params,
        %$opts
    });
}

sub files_post {
    my ($self, $path, $content, $params, $opts) = @_;

    $opts ||= {};
    $self->api_json({
        method => 'POST',
        url => $self->url('https://api-content.dropbox.com/1/files/' . $self->root, $path),
        content => $content,
        extra_params => $params,
        %$opts
    });
}

sub files_put_chunked {
    my ($self, $path, $content, $params, $opts, $limit) = @_;

    $limit ||= 4 * 1024 * 1024; # A typical chunk is 4 MB

    my $upload;
    $upload = sub {
        my $data = shift;
        my $buf;
        my $total = $limit;
        my $chunk = 1024;
        my $tmp = File::Temp->new;
        while (my $read = read($content, $buf, $chunk)) {
            $tmp->print($buf);
            $total -= $read;
            if ($chunk > $total) {
                $chunk = $total;
            }
            last unless $chunk;
        }

        if ($total == $limit) {
            $data->{upload_id} or die 'read error.';
            return $self->commit_chunked_upload(
                $path, {
                    upload_id => $data->{upload_id},
                    ( $params ? %$params : () )
                }, $opts) || die $self->error;
        }

        $tmp->flush;
        $tmp->seek(0, 0);
        $data = $self->chunked_upload($tmp, {
            ( $data   ? %$data   : () ),
            ( $params ? %$params : () )
        }, $opts) or die $self->error;
        $upload->({
            upload_id => $data->{upload_id},
            offset    => $data->{offset}
        });
    };
    $upload->();
}

sub chunked_upload {
    my ($self, $content, $params, $opts) = @_;

    $opts ||= {};
    $self->api_json({
        method => 'PUT',
        url => $self->url('https://api-content.dropbox.com/1/chunked_upload', ''),
        content => $content,
        extra_params => $params,
        %$opts
    });
}

sub commit_chunked_upload {
    my ($self, $path, $params, $opts) = @_;

    $opts ||= {};
    $self->api_json({
        method => 'POST',
        url => $self->url('https://api-content.dropbox.com/1/commit_chunked_upload/' . $self->root, $path),
        extra_params => $params,
        %$opts
    });
}

sub metadata {
    my ($self, $path, $params) = @_;

    $self->api_json({
        url => $self->url('https://api.dropbox.com/1/metadata/' . $self->root, $path),
        extra_params => $params
    });
}

sub delta {
    my ($self, $params) = @_;

    $self->api_json({
        method => 'POST',
        url => $self->url('https://api.dropbox.com/1/delta', ''),
        extra_params => $params
    });
}

sub revisions {
    my ($self, $path, $params) = @_;

    $self->api_json({
        url => $self->url('https://api.dropbox.com/1/revisions/' . $self->root, $path),
        extra_params => $params
    });
}

sub restore {
    my ($self, $path, $params) = @_;

    $self->api_json({
        method => 'POST',
        url => $self->url('https://api.dropbox.com/1/restore/' . $self->root, $path),
        extra_params => $params
    });
}

sub search {
    my ($self, $path, $params) = @_;

    $self->api_json({
        url => $self->url('https://api.dropbox.com/1/search/' . $self->root, $path),
        extra_params => $params
    });
}

sub shares {
    my ($self, $path, $params) = @_;

    $self->api_json({
        method => 'POST',
        url => $self->url('https://api.dropbox.com/1/shares/' . $self->root, $path),
        extra_params => $params
    });
}

sub media {
    my ($self, $path, $params) = @_;

    $self->api_json({
        method => 'POST',
        url => $self->url('https://api.dropbox.com/1/media/' . $self->root, $path),
        extra_params => $params
    });
}

sub copy_ref {
    my ($self, $path, $params) = @_;

    $self->api_json({
        method => 'GET',
        url => $self->url('https://api.dropbox.com/1/copy_ref/' . $self->root, $path),
        extra_params => $params
    });
}

sub thumbnails {
    my ($self, $path, $output, $params, $opts) = @_;

    $opts ||= {};
    if (ref $output eq 'CODE') {
        $opts->{write_code} = $output; # code ref
    } elsif (ref $output) {
        $opts->{write_file} = $output; # file handle
        binmode $opts->{write_file};
    } else {
        open $opts->{write_file}, '>', $output; # file path
        Carp::croak("invalid output, output must be code ref or filehandle or filepath.")
            unless $opts->{write_file};
        binmode $opts->{write_file};
    }
    $opts->{extra_params} = $params if $params;
    $self->api({
        url => $self->url('https://api-content.dropbox.com/1/thumbnails/' . $self->root, $path),
        extra_params => $params,
        %$opts,
    });
    return if $self->error;
    return 1;
}

sub create_folder {
    my ($self, $path, $params) = @_;

    $params ||= {};
    $params->{root} ||= $self->root;
    $params->{path} = $self->path($path);

    $self->api_json({
        method => 'POST',
        url => $self->url('https://api.dropbox.com/1/fileops/create_folder', ''),
        extra_params => $params
    });
}

sub copy {
    my ($self, $from, $to_path, $params) = @_;

    $params ||= {};
    $params->{root} ||= $self->root;
    $params->{to_path} = $self->path($to_path);
    if (ref $from) {
        $params->{from_copy_ref} = $from->{copy_ref};
    } else {
        $params->{from_path} = $self->path($from);
    }

    $self->api_json({
        method => 'POST',
        url => $self->url('https://api.dropbox.com/1/fileops/copy', ''),
        extra_params => $params
    });
}

sub move {
    my ($self, $from_path, $to_path, $params) = @_;

    $params ||= {};
    $params->{root} ||= $self->root;
    $params->{from_path} = $self->path($from_path);
    $params->{to_path}   = $self->path($to_path);

    $self->api_json({
        method => 'POST',
        url => $self->url('https://api.dropbox.com/1/fileops/move', ''),
        extra_params => $params
    });
}

sub delete {
    my ($self, $path, $params) = @_;

    $params ||= {};
    $params->{root} ||= $self->root;
    $params->{path} ||= $self->path($path);
    $self->api_json({
        method => 'POST',
        url => $self->url('https://api.dropbox.com/1/fileops/delete', ''),
        extra_params => $params
    });
}

# private

sub parse_error ($) {
    eval { decode_json($_[0])->{error} } || $_[0];
}

sub api {
    my ($self, $args) = @_;

    $args->{method} ||= 'GET';
    $args->{url} = $self->oauth_request_url($args);

    $self->request_url($args->{url});
    $self->request_method($args->{method});

    return $self->api_lwp($args) if $WebService::Dropbox::USE_LWP;

    if (my $write_file = delete $args->{write_file}) {
        $args->{write_code} = sub {
            $write_file->print($_[3]);
        };
    }
    if (my $write_code = delete $args->{write_code}) {
        $args->{write_code} = sub {
            if ($_[0] =~ qr{ \A 2 }xms) {
                $write_code->(@_);
            } else {
                $self->error(parse_error($_[3]));
            }
        };
    }

    my ($minor_version, $code, $msg, $headers, $body) = $self->furl->request(%$args);
    $self->code($code);
    if ($code !~ qr{ \A 2 }xms) {
        unless ($self->error) {
            $self->error($body || $msg);
        }
        return;
    } else {
        $self->error(undef);
    }

    return $body;
}

sub api_lwp {
    my ($self, $args) = @_;

    my $headers = [];
    if ($args->{write_file}) {
        $args->{write_code} = sub {
            my $buf = shift;
            $args->{write_file}->print($buf);
        };
    }
    if ($args->{content}) {
        my $buf;
        my $content = delete $args->{content};
        $args->{content} = sub {
            read($content, $buf, 1024);
            return $buf;
        };
        my $assert = sub {
            $_[0] or Carp::croak(
                "Failed to $_[1] for Content-Length: $!",
            );
        };
        $assert->(defined(my $cur_pos = tell($content)), 'tell');
        $assert->(seek($content, 0, SEEK_END),           'seek');
        $assert->(defined(my $end_pos = tell($content)), 'tell');
        $assert->(seek($content, $cur_pos, SEEK_SET),    'seek');
        my $content_length = $end_pos - $cur_pos;
        push @$headers, 'Content-Length' => $content_length;
    }
    if ($args->{headers}) {
        push @$headers, @{ $args->{headers} };
    }
    my $req = HTTP::Request->new($args->{method}, $args->{url}, $headers, $args->{content});
    my $ua = LWP::UserAgent->new;
    $ua->timeout($self->timeout);
    $ua->env_proxy if $self->{env_proxy};
    my $res = $ua->request($req, $args->{write_code});
    $self->code($res->code);
    if ($res->is_success) {
        $self->error(undef);
    } else {
        $self->error(parse_error($res->decoded_content));
    }
    return $res->decoded_content;
}

sub api_json {
    my ($self, $args) = @_;

    my $body = $self->api($args) or return;
    return if $self->error;
    return $body if $self->no_decode_json;
    return decode_json($body);
}

sub oauth_request_url {
    my ($self, $args) = @_;

    Carp::croak("missing url.") unless $args->{url};
    Carp::croak("missing method.") unless $args->{method};

    my ($type, $token, $token_secret);
    if ($args->{url} eq $request_token_url) {
        $type = 'request token';
    } elsif ($args->{url} eq $access_token_url) {
        Carp::croak("missing request_token.") unless $self->request_token;
        Carp::croak("missing request_secret.") unless $self->request_secret;
        $type = 'access token';
        $token = $self->request_token;
        $token_secret = $self->request_secret;
    } else {
        Carp::croak("missing access_token, please `\$dropbox->auth;`.") unless $self->access_token;
        Carp::croak("missing access_secret, please `\$dropbox->auth;`.") unless $self->access_secret;
        $type = 'protected resource';
        $token = $self->access_token;
        $token_secret = $self->access_secret;
    }

    my $request = Net::OAuth->request($type)->new(
        consumer_key => $self->key,
        consumer_secret => $self->secret,
        request_url => $args->{url},
        request_method => uc($args->{method}),
        signature_method => 'PLAINTEXT', # HMAC-SHA1 can't delete %20.txt bug...
        timestamp => time,
        nonce => $self->nonce,
        token => $token,
        token_secret => $token_secret,
        extra_params => $args->{extra_params},
    );
    $request->sign;
    $request->to_url;
}

sub furl {
    my $self = shift;
    unless ($self->{furl}) {
        $self->{furl} = Furl::HTTP->new(
            timeout => $self->timeout,
            ssl_opts => {
                SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_PEER(),
            },
        );
        $self->{furl}->env_proxy if $self->{env_proxy};
    }
    $self->{furl};
}

sub url {
    my ($self, $base, $path, $params) = @_;
    my $url = URI->new($base . uri_escape_utf8($self->path($path), q{^a-zA-Z0-9_.~/-}));
    $url->query_form($params) if $params;
    $url->as_string;
}

sub path {
    my ($self, $path) = @_;
    return '' unless defined $path;
    return '' unless length $path;
    $path =~ s|^/||;
    return '/' . $path;
}

sub nonce {
    my $length = 16;
    my @chars = ( 'A'..'Z', 'a'..'z', '0'..'9' );
    my $ret;
    for (1..$length) {
        $ret .= $chars[int rand @chars];
    }
    return $ret;
}

sub mk_accessors {
    my $package = shift;
    no strict 'refs';
    foreach my $field ( @_ ) {
        *{ $package . '::' . $field } = sub {
            return $_[0]->{ $field } if scalar( @_ ) == 1;
            return $_[0]->{ $field }  = scalar( @_ ) == 2 ? $_[1] : [ @_[1..$#_] ];
        };
    }
}

sub env_proxy { $_[0]->{env_proxy} = defined $_[1] ? $_[1] : 1 }

# Backward Compatibility
sub lwp_env_proxy { shift->env_proxy(@_) }

1;
__END__

=head1 NAME

WebService::Dropbox - Perl interface to Dropbox API

=head1 SYNOPSIS

    use WebService::Dropbox;

    my $dropbox = WebService::Dropbox->new({
        key => '...', # App Key
        secret => '...' # App Secret
    });

    # get access token
    if (!$access_token or !$access_secret) {
        my $url = $dropbox->login or die $dropbox->error;
        warn "Please Access URL and press Enter: $url";
        <STDIN>;
        $dropbox->auth or die $dropbox->error;
        warn "access_token: " . $dropbox->access_token;
        warn "access_secret: " . $dropbox->access_secret;
    } else {
        $dropbox->access_token($access_token);
        $dropbox->access_secret($access_secret);
    }

    my $info = $dropbox->account_info or die $dropbox->error;

    # download
    # https://www.dropbox.com/developers/reference/api#files
    my $fh_get = IO::File->new('some file', '>');
    $dropbox->files('make_test_folder/test.txt', $fh_get) or die $dropbox->error;
    $fh_get->close;

    # upload
    # https://www.dropbox.com/developers/reference/api#files_put
    my $fh_put = IO::File->new('some file');
    $dropbox->files_put('make_test_folder/test.txt', $fh_put) or die $dropbox->error;
    $fh_put->close;

    # filelist(metadata)
    # https://www.dropbox.com/developers/reference/api#metadata
    my $data = $dropbox->metadata('folder_a');

=head1 DESCRIPTION

WebService::Dropbox is Perl interface to Dropbox API

- Support Dropbox v1 REST API

- Support Furl (Fast!!!)

- Streaming IO (Low Memory)

- Default URI Escape (The specified path is utf8 decoded string)

=head1 API

=head2 login(callback_url) - get request token and request secret

    my $callback_url = '...'; # optional
    my $url = $dropbox->login($callback_url) or die $dropbox->error;
    warn "Please Access URL and press Enter: $url";

=head2 auth - get access token and access secret

    $dropbox->auth or die $dropbox->error;
    warn "access_token: " . $dropbox->access_token;
    warn "access_secret: " . $dropbox->access_secret;

=head2 root - set access type

    # Access Type is App folder
    # Your app only needs access to a single folder within the user's Dropbox
    $dropbox->root('sandbox');

    # Access Type is Full Dropbox (default)
    # Your app needs access to the user's entire Dropbox
    $dropbox->root('dropbox');

L<https://www.dropbox.com/developers/start/core>

=head2 account_info

    my $info = $dropbox->account_info or die $dropbox->error;

    # {
    #     "referral_link": "https://www.dropbox.com/referrals/r1a2n3d4m5s6t7",
    #     "display_name": "John P. User",
    #     "uid": 12345678,
    #     "country": "US",
    #     "quota_info": {
    #         "shared": 253738410565,
    #         "quota": 107374182400000,
    #         "normal": 680031877871
    #     },
    #     "email": "john@example.com"
    # }

L<https://www.dropbox.com/developers/reference/api#account-info>

=head2 files(path, output, [params, opts]) - download (no file list, file list is metadata)

    # Current Rev
    my $fh_get = IO::File->new('some file', '>');
    $dropbox->files('folder/file.txt', $fh_get) or die $dropbox->error;
    $fh_get->close;

    # Specified Rev
    $dropbox->files('folder/file.txt', $fh_get, { rev => ... }) or die $dropbox->error;

    # Code ref
    $dropbox->files('folder/file.txt', sub {
        # compatible with LWP::UserAgent and Furl::HTTP
        my $chunk = @_ == 4 ? @_[3] : $_[0];
        print $chunk;
    }) or die $dropbox->error;

    # Range
    $dropbox->files('folder/file.txt', $fh_get) or die $dropbox->error;
    > "0123456789"
    $dropbox->files('folder/file.txt', $fh_get, undef, { headers => ['Range' => 'bytes=5-6'] }) or die $dropbox->error;
    > "56"

L<https://www.dropbox.com/developers/reference/api#files-GET>

=head2 files_put(path, input) - Uploads a files

    my $fh_put = IO::File->new('some file');
    $dropbox->files_put('folder/test.txt', $fh_put) or die $dropbox->error;
    $fh_put->close;

    # no overwrite (default true)
    $dropbox->files_put('folder/test.txt', $fh_put, { overwrite => 0 }) or die $dropbox->error;
    # create 'folder/test (1).txt'

    # Specified Parent Rev
    $dropbox->files_put('folder/test.txt', $fh_put, { parent_rev => ... }) or die $dropbox->error;
    # conflict prevention

L<https://www.dropbox.com/developers/reference/api#files_put>

=head2 files_put_chunked(path, input) - Uploads large files by chunked_upload and commit_chunked_upload.

    my $fh_put = IO::File->new('some large file');
    $dropbox->files_put('folder/test.txt', $fh_put) or die $dropbox->error;
    $fh_put->close;

L<https://www.dropbox.com/developers/reference/api#chunked_upload>

=head2 chunked_upload(input, [params]) - Uploads large files

    # large file 1/3
    my $fh_put = IO::File->new('large file part 1');
    my $data = $dropbox->chunked_upload($fh_put) or die $dropbox->error;
    $fh_put->close;

    # large file 2/3
    $fh_put = IO::File->new('large file part 2');
    $data = $dropbox->chunked_upload($fh_put, {
        upload_id => $data->{upload_id},
        offset => $data->{offset}
    }) or die $dropbox->error;
    $fh_put->close;

    # large file 3/3
    $fh_put = IO::File->new('large file part 3');
    $data = $dropbox->chunked_upload($fh_put, {
        upload_id => $data->{upload_id},
        offset => $data->{offset}
    }) or die $dropbox->error;
    $fh_put->close;

    # commit
    $dropbox->commit_chunked_upload('folder/test.txt', {
        upload_id => $data->{upload_id}
    }) or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#chunked_upload>

=head2 commit_chunked_upload(path, params) - Completes an upload initiated by the chunked_upload method.

    $dropbox->commit_chunked_upload('folder/test.txt', {
        upload_id => $data->{upload_id}
    }) or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#commit_chunked_upload>

=head2 copy(from_path or from_copy_ref, to_path)

    # from_path
    $dropbox->copy('folder/test.txt', 'folder/test_copy.txt') or die $dropbox->error;

    # from_copy_ref
    my $copy_ref = $dropbox->copy_ref('folder/test.txt') or die $dropbox->error;

    $dropbox->copy($copy_ref, 'folder/test_copy.txt') or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#fileops-copy>

=head2 move(from_path, to_path)

    $dropbox->move('folder/test.txt', 'folder/test_move.txt') or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#fileops-move>

=head2 delete(path)

    # folder delete
    $dropbox->delete('folder') or die $dropbox->error;

    # file delete
    $dropbox->delete('folder/test.txt') or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#fileops-delete>

=head2 create_folder(path)

    $dropbox->create_folder('some_folder') or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#fileops-create-folder>

=head2 metadata(path, [params]) - get file list

    my $data = $dropbox->metadata('some_folder') or die $dropbox->error;

    my $data = $dropbox->metadata('some_file') or die $dropbox->error;

    # 304
    my $data = $dropbox->metadata('some_folder', { hash => ... });
    return if $dropbox->code == 304; # not modified
    die $dropbox->error if $dropbox->error;
    return $data;

L<https://www.dropbox.com/developers/reference/api#metadata>

=head2 delta([params]) - get file list

    my $data = $dropbox->delta() or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#delta>

=head2 revisions(path, [params])

    my $data = $dropbox->revisions('some_file') or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#revisions>

=head2 restore(path, [params])

    # params rev is Required
    my $data = $dropbox->restore('some_file', { rev => $rev }) or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#restore>

=head2 search(path, [params])

    # query rev is Required
    my $data = $dropbox->search('some_file', { query => $query }) or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#search>

=head2 shares(path, [params])

    my $data = $dropbox->shares('some_file') or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#shares>

=head2 media(path, [params])

    my $data = $dropbox->media('some_file') or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#media>

=head2 copy_ref(path)

    my $copy_ref = $dropbox->copy_ref('folder/test.txt') or die $dropbox->error;

    $dropbox->copy($copy_ref, 'folder/test_copy.txt') or die $dropbox->error;

L<https://www.dropbox.com/developers/reference/api#copy_ref>

=head2 thumbnails(path, output)

    my $fh_get = File::Temp->new;
    $dropbox->thumbnails('folder/file.txt', $fh_get) or die $dropbox->error;
    $fh_get->flush;
    $fh_get->seek(0, 0);

L<https://www.dropbox.com/developers/reference/api#thumbnails>

=head2 env_proxy

enable HTTP_PROXY, NO_PROXY

    $dropbox->env_proxy;

=head1 AUTHOR

Shinichiro Aska

=head1 SEE ALSO

- L<https://www.dropbox.com/developers/reference/api>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
