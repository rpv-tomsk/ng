package NG::Exception;
use strict;
use Scalar::Util 'blessed';
use POSIX qw(strftime);

our @specificators;
our $specificatorProcessors = {};
our $notificationPrefix = "";
our $notificationGroupCode = "";
our $notificationRecipients = undef;
our @messagePrepend;

sub defaultCode {
    return 'NG.INTERNALERROR';
};

=head
# NG::Exception->new(MESSAGE)
# NG::Exception->new(CODE,MESSAGE[,DETAILS])
# NG::Exception->new({CODE=>CODE,PARAMS=>PARAMS},MESSAGE[,DETAILS])

Pay::Exception->throw('PAY.INTERNALERROR', "������ ���� �������� ����������. ���������� ������ ���������.", {DUMP=>$result})

=cut

sub new {
    my $class = shift;
    
    my $self = {};
    bless $self,$class;
    
    if (scalar @_ == 1) {
        $self->{message} = shift;
    }
    elsif (scalar @_ == 2 || scalar @_ == 3) {
        my $code = shift;
        if (ref $code eq 'HASH') {
            $self->{code}   = $code->{CODE};
            $self->{params} = $code->{PARAMS};
        }
        else {
            $self->{code} = $code;
        }
        $self->{message} = shift;
        $self->{details} = shift;
    }
    else {
        $self->{message} = 'Incorrect '.$class.'->throw() call';
    };
    $self->{code} ||= $class->defaultCode();
    
    $self->{message} = join(': ',@messagePrepend, $self->{message});
    $self->{carpmessage} = "";
    
    if ($NG::Application::DEBUG) {
        local($@, $!);
        eval { require Carp::Heavy; };
        unless ($@) {
            $Carp::Internal{'NG::Exception'}++;
            $self->{carpmessage} .= $self->getText();
            $self->{carpmessage} .= $class->processSpecificator($self->{details},$self)->{text} if $self->{details};
            $self->{carpmessage} .= Carp::longmess_heavy('');
        };
    };
    $self;
};

sub throw {
    my $self = shift->new(@_);
    warn $self->getText();
    die $self;
};

sub caught {
    my ($class,$e,$code) = (shift,shift,shift);
    
    #Treat all 'die' exceptions as NG.INTERNALERROR
    #Using this method does not provide correct backtraces.
    #unless (blessed($e)) {
    #    $e = NG::Exception->new('NG.INTERNALERROR',$e);
    #};
    
    return undef unless blessed($e) && $e->isa( $class );
    return $e unless $code;
    if (ref $code eq 'ARRAY') {
        foreach (@$code) {
            return $e if $e->{code} eq $_;
        };
    }
    else {
        return $e if $code eq $e->{code};
    };
    return undef;
}

sub message  { $_[0]->{message}; };
sub code     { $_[0]->{code};    };
sub params   { $_[0]->{params};  };

sub getText {
    my $exc = shift;
    
    if (ref $exc) { #Object method
        return $exc->{carpmessage} if $exc->{carpmessage};
        $exc->code.": ".$exc->message."\n";
    }
    else {          #Class method
        my $e = shift;
        if (NG::Exception->caught($e)) {
            return $e->getText();
        }
        else {
            return $e;
        };
    };
};

sub getShortText {
    my $exc = shift;
    
    if (ref $exc) { #Object method
        $exc->code.": ".$exc->message."\n";
    }
    else {          #Class method
        my $e = shift;
        if (NG::Exception->caught($e)) {
            return $e->getShortText();
        }
        else {
            return $e;
        };
    };
};

sub processSpecificator {
    my ($class,$spec,$exc) = (shift,shift,shift);
    
    my $v = {};
    my $ref = ref $spec;

    if ($ref eq 'HASH') {
        if (exists $spec->{DUMP}) {
            $ref  = 'DUMP';
            $spec = $spec->{DUMP};
        }
        else {
            $ref = $spec->{type};
            $spec = $spec->{spec};
            
            $v->{text} = 'HASH Specificator: "type" or "spec" is missing' unless $ref && $spec;
            $v->{text} = 'HASH Specificator: "type" has forbidden value '.$ref if $ref eq 'HASH' || $ref eq 'CODE';
        };
    };

    if ($ref eq 'CODE') {
        $v = eval {$spec->($exc)};
    }
    else {
        my $code = $NG::Exception::specificatorProcessors->{$ref};
        if ($code) {
            $v = eval {$code->($spec,$exc)};
        }
        elsif ($ref eq '') {
            $v->{text} = $spec."\n";
            $@ = '';
        }
        else {
            $v->{text} = "Not found CODE for specificator type $ref";
            $@ = '';
        };
    };
    if (my $ee = $@ || ref $v ne 'HASH') {
        my $eeText = "";
        if (NG::Exception->caught($ee)) {
            $eeText = $ee->getText();
        }
        else {
            $eeText = $ee;
        };
        return {text => "EXCEPTION $eeText WHILE GETTING VALUE FROM EXCEPTION SPECIFICATOR '$ref'"};
    };
    $v;
};

sub notify {
    my ($class, $exc,$opName) = (shift,shift,shift);
    
    my $excCode = $class->defaultCode();
    my $excMsg  = '';
    my $subj = '';
    
    my $details = undef;
    if (NG::Exception->caught($exc)) {
        $excCode = $exc->code();
        $excMsg  = $exc->message();
        $details = $exc->{details};
    }
    elsif (ref $exc){
        $excMsg = "����������� ���������� ������ ".(ref $exc);
    }
    else {
        $excMsg = $exc;
    };
    $excMsg.="\n";
    foreach my $spec ($details, @NG::Exception::specificators) {
        next unless defined $spec;
        my $v = $class->processSpecificator($spec,$exc);
        
        $excMsg .= "\n".$v->{text};
        $subj .= " ".$v->{subj} if exists $v->{subj};
    };
    $excMsg=~s/\r?\n$//;
    
    my $notifyText = "";
    $notifyText .= strftime("[%a %b %d %T %Y %z]",localtime())."\n\n";
    $notifyText .= "�� ����� ��������� �������� \"$opName\" ��������� ������:\n\n$excMsg\n\n";
    $subj = "$notificationPrefix $excCode $opName" . $subj;
    
    while (1) {
        my $cms = $NG::Application::cms;
        last unless $cms;
        last unless $notificationRecipients;
        last if (ref $notificationRecipients) && (ref $notificationRecipients ne 'ARRAY');
        
        my $To = ''; 
        if (ref $notificationRecipients) {
            $To .= '<'.$_ . '>,' foreach @$notificationRecipients; $To =~ s/,$//;
        }
        else {
            $To = $notificationRecipients;
        };
        
        my $nmailer = $cms->getModuleByCode('MAILER') or last;
        $nmailer->setGroupCode($notificationGroupCode) if $notificationGroupCode;
        $nmailer->addPlainPart(Data=>$notifyText);
        $nmailer->add(Subject=> $subj);
        $nmailer->add(To=>$To);
        $nmailer->send() or last;
        return 1;
    };
    warn "Unable to notify about exception $notifyText";
    return 0;
};

package NG::DBIException;
use strict;

our @ISA = qw(NG::Exception);

=head
NG::DBIException->throw();
NG::DBIException->throw(MESSAGEPREFIX);
NG::DBIException->throw(MESSAGEPREFIX, PARAMS);

Default exception code: NG.DBIEXCEPTION. May be overrided by PARAMS->{exceptionCode}

Example:

NG::DBIException->throw('Order lock failed',{rollback=>$dbh, exceptionCode=>'ORDER.LOCK'});
=cut

sub throw {
    my ($class,$prefix, $params) = (shift,shift,shift);
    my $message = $DBI::errstr;
    $prefix .= ': ' if $prefix;
    $params ||= {};
    
    if (ref $params ne 'HASH') {
        warn 'Incorrect params passed to '.__PACKAGE__.'->throw()';
        $message .= "\nIncorrect parameters passed to ".__PACKAGE__."->throw()";
    };
    my $code = "NG.DBIEXCEPTION";
    $code = $params->{exceptionCode} if $params->{exceptionCode};
    
    if ($params->{rollback}) {
        eval {
            $params->{rollback}->rollback();
        } or do {
            my $rm  = "Rollback failed:";
            if ($@) {
                $rm .= ' '.$@ if $@;
            }
            else {
                $rm .= ' '.$DBI::errstr if $DBI::errstr;
            };
            warn __PACKAGE__.'->throw(): '.$rm;
            $message.= "\n".$rm;
        };
    };
    $prefix||='';
    $Carp::Internal{'NG::DBIException'}++;
    $class->SUPER::throw($code,$prefix.$message);
};

package NG::InternalError;
use strict;
our @ISA = qw(NG::Exception);

sub throw {
    my ($class,$text) = (shift,shift);
    $text = $NG::Application::cms->{_error} . ($text?" ($text)":"") if $NG::Application::cms->{_error};
    $Carp::Internal{'NG::InternalError'}++;
    $class->SUPER::throw('NG.INTERNALERROR', $text);
};

1;
