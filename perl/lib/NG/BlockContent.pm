package NG::BlockContent;
use strict;

use constant M_ERROR    => 0;  # крайне не рекомендуется менять эту критично важную константу
use constant M_OK       => 1;
use constant M_REDIRECT => 2;
use constant M_404      => 3;
use constant M_EXIT     => 4;


=head
    Переменные:
    
    _type
    _error          (_type == 0)
    _output_data    (_type == 1/4)
    _redirect_url   (_type == 2)
    
    _headers
    _cookies
    _headkeys
=cut

## Setters: error
## Getters: getError
## Checker: is_error

sub error {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->_error(@_);
};

sub getError {
    my $self = shift;
    return $self->{_error};
}

sub is_error {
    my $self = shift;
    return $self->{_type} == M_ERROR;
};

## Setters: exit, output, header(exit)
## Getters: getOutput
## Checker: is_exit is_output

sub _setOutput {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    
    my $retCode = shift;
    
    my $data = shift;
    
    if (ref $data) {
        return $self->_error("Ссылка на данные не является объектом") unless UNIVERSAL::can($data, 'can');
        return $self->_error("Объект данных не содержит метода output") unless UNIVERSAL::can($data, 'output');
    };
    
    $self->{_output_data} = $data;
    $self->_setheaders('-type',@_) or return $self;
    $self->{_type} = $retCode;
    $self;
};

=head
    $HEADKEYS = {
        csslist => '' || ['','','']
        jslist  => '' || ['','','']
        title   => ''
        meta => {
            keywords => ''
            description => ''
        }
    };

return $cms->output($tmplObj->output());
return $cms->output($tmplObj, "text/plain");
return $cms->output($tmplObj, "text/plain", $HEADKEYS);
return $cms->output($tmplObj, undef, $HEADKEYS);
return $cms->output($tmplObj, {}, $HEADKEYS);
return $cms->output($tmplObj, -type=>"text/xml", -charset=>"utf-8", -status=>"200");
return $cms->output($tmplObj, {-type=>"text/xml", -charset=>"utf-8", -status=>"200"}, $HEADKEYS);

return $cms->exit($tmplObj->output());
return $cms->exit($tmplObj, "text/plain");
return $cms->exit($tmplObj, "text/plain", $HEADKEYS);
return $cms->exit($tmplObj, undef, $HEADKEYS);
return $cms->exit($tmplObj, {}, $HEADKEYS);
return $cms->exit($tmplObj, -type=>"text/xml", -charset=>"utf-8", -status=>"200");
return $cms->exit($tmplObj, {-type=>"text/xml", -charset=>"utf-8", -status=>"200"}, $HEADKEYS);

return $cms->header(-status=>"416 Invalid Range");

=cut

sub exit {
    my $self = shift;
    return $self->_setOutput(M_EXIT,@_);
};

sub output {
    my $self = shift;
    return $self->_setOutput(M_OK,@_);
};

sub header {
    my $class = shift;
    my $self = {};
    bless $self, $class;

    $self->_setheaders('',@_) or return $self;
    $self->{_type} = M_EXIT;
    $self->{_type} = M_404 if $self->{_headers}->{-status} =~ /^404/;
    $self;
};

sub getOutput {
    my $self = shift;
    $self->{_output_data} = $self->{_output_data}->output() if ref $self->{_output_data};
    return $self->{_output_data};
};

sub is_output {
    my $self = shift;
    return $self->{_type} == M_OK;
};

sub is_exit {
    my $self = shift;
    return $self->{_type} == M_EXIT;
};

## Setters: redirect
## Getters: getRedirectUrl
## Checker: is_redirect

=head
	return $cms->redirect($url);
	return $cms->redirect($url, -status=>"301");
	return $cms->redirect($url, -status=>"302");
	return $cms->redirect($url, -status=>"303");
	return $cms->redirect(-uri=>$url, -status=>"303");
=cut

sub redirect {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    
    $self->_setheaders('-uri',@_) or return $self;
    return $self->_error("NG::BlockContent->redirect(): missing uri key") unless exists $self->{_headers}->{-uri};
    my $st = $self->{_headers}->{-status}  || "302";
    return $self->_error("NG::BlockContent->redirect(): status is not 3xx code")  if $st !~ /^3/;
    $self->{_redirect_url} = delete $self->{_headers}->{-uri};
    $self->{_type}  = M_REDIRECT;
    $self;
};

sub getRedirectUrl {
    my $self = shift;
    return $self->{_redirect_url};
};

sub is_redirect {
    my $self = shift;
    return $self->{_type} == M_REDIRECT;
};

## Setters: notFound
## Checker: is_404

sub notFound {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    
    $self->_setheaders('',@_) or return $self;
    $self->{_headers}->{-status} = "404 Not Found";
    $self->{_output_data} = "Страница не найдена";
    $self->{_type} = M_404;
    $self;
};

sub is_404 {
    my $self = shift;
    return $self->{_type} == M_404;
};

## headers and cookies

sub headers {
    my $self = shift;
    return $self->{_headers};
};

sub cookies {
    my $self = shift;
    return $self->{_cookies};
};

sub headkeys {
    my $self = shift;
    return $self->{_headkeys};
};

##
## Internal functions
##

sub _error {
    my $self = shift;
    my $error = shift;

    $self->{_error} = $error if $error;
#carp ts($error) if $error;
    $self->{_type}  = M_ERROR;
    $self;
};

sub _error0 {
    _error(@_);
    0;
};

sub _caller {
    my $self = shift;
    my @call  = caller(3);
    
    return $call[3];
};

sub _setheaders {
    my $self = shift;
    my $singleKey = shift;
    my $param = {};
    
    while (1) {
        last unless scalar @_;
        my $v = shift;
        
        if (!defined $v) {
            #Do nothing, skip
        }
        elsif (ref $v eq "HASH") {
            $param = $v;
        }
        elsif ($v =~ m/^-/) {
            unshift @_, $v;
            last;
        }
        elsif ($singleKey) {
            $param->{$singleKey} = $v;
        }
        else {
            return $self->_error0("NG::BlockContent->".$self->_caller()."(): invalid parameters count");
        };
        return $self->_error0("NG::BlockContent->".$self->_caller()."(): invalid parameters count") if scalar @_ > 1;
        last unless scalar @_;
        $v = shift;
        return $self->_error0("NG::BlockContent->".$self->_caller()."(): KEY parameter is not hashref") if ref $v ne "HASH";
        $self->{_headkeys} = $v;
    };
    
    return $self->_error0("NG::BlockContent->".$self->_caller()."(): invalid parameters count") if scalar @_ % 2;
    
    $param = {@_} if scalar @_;
    if (exists $param->{-cookie}) {
        if (ref $param->{-cookie} eq "ARRAY") {
            push @{$self->{_cookies}}, @{$param->{-cookie}};
        }
        else {
            push @{$self->{_cookies}}, $param->{-cookie};
        };
        delete $param->{-cookie};
    };
    $self->{_headers} = $param;
    1;
};


1;
