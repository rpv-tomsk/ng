package NG::Mailer::Mailgun;
use strict;
use Scalar::Util();
use LWP;
use HTTP::Request::Common;
require MIME::Base64;

=head
    WARNING! ATTENTION! This code is completely unchecked and untested on ng5/ng6 codebase.
                        It was used at ng4/NMailer code as hotfix and saved to ng6/ without
                        any (ever syntax) checks for future uses ! But it can work...
                        Please remove this warning when (if) this code works.
=cut

sub new {
    my $class = shift;
    my $self = {};
    bless $self,$class;
    $self->{Mailer} = shift;

    Scalar::Util::weaken($self->{Mailer});

    $self;
};

sub send {
    my ($self,$data,$opts) = (@_);

    my $cms = $self->cms();
    my $m   = $self->{Mailer};

    $opts->{From} or return $cms->error("MAILGUN: No 'From' option found.");
    ($opts->{To} && ref ($opts->{To}) eq "ARRAY" && @{$opts->{To}}) or return $cms->error("MAILGUN: No 'To' option found.");

    my $APIKey = $m->_mparam('APIKey');
    return $cms->error('MAILGUN: APIKey module parameter is missing') unless $APIKey;

    my $userAgent = LWP::UserAgent->new();
    $userAgent->default_header( Authorization => "Basic " . MIME::Base64::encode("api:$APIKey", ""));

    my $request = HTTP::Request::Common::POST(
        'https://api.mailgun.net/v3/86hm.ru/messages.mime',
        Content_Type => 'multipart/form-data',
        Content => [
            message => [undef, 'message.data', Content => $data->as_string],
            from => $opts->{From},
            to   => join ',', @{$opts->{To}},
        ],
    );

    my $response = $userAgent->request($request);
    return 1 if $response->code == 200;  #TODO: Need to check response content?
    return $cms->error("MAILGUN: MAIL failed: ".$response->status_line());
};

return 1;
