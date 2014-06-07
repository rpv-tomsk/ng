package NG::Exception;
use strict;
use Scalar::Util 'blessed';

our @specificators;
our $specificatorProcessors = {};
our $notificationPrefix = "";
our $notificationGroupCode = "";
our $notificationRecipients = undef;

sub defaultCode {
    return 'NG.INTERNALERROR';
};

sub new {
    my $class = shift;
    
    my $self = {};
    bless $self,$class;
    
    unless (scalar @_ == 2) {
        $self->{code} = $class->defaultCode();
        $self->{message} = 'Incorrect '.$class.'->throw() call';
    }
    else {
        $self->{code} = shift;
        $self->{message} = shift;
    };
    
    $self->{carpmessage} = "";
    
    if ($NG::Application::DEBUG) {
        local($@, $!);
        eval { require Carp::Heavy; };
        unless ($@) {
            $Carp::Internal{'NG::Exception'}++;
            $self->{carpmessage} = Carp::longmess_heavy($self->getText());
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

sub message  { my $self = shift; return $self->{message}; };
sub code     { my $self = shift; return $self->{code};    };

sub getText {
    my $exc = shift;
    
    return $exc->{carpmessage} if $exc->{carpmessage};
    $exc->code.": ".$exc->message."\n";
};

sub notify {
    my ($class, $exc,$opName) = (shift,shift,shift);
    
    my $excCode = $class->defaultCode();
    my $excMsg  = '';
    my $subj = '';
    
    if (NG::Exception->caught($exc)) {
        $excCode = $exc->code();
        $excMsg  = $exc->message();
    }
    elsif (ref $exc){
        $excMsg = "Неизвестное исключение класса ".(ref $exc);
    }
    else {
        $excMsg = $exc;
    };
    
    foreach my $spec (@NG::Exception::specificators) {
        my $v = {};
        my $ref = ref $spec;
        my $parentRef = undef;

        if ($ref eq 'HASH') {
            $parentRef = $ref;
            $ref = $spec->{type};
            $spec = $spec->{spec};

            $v->{text} = 'HASH Specificator: "type" or "spec" is missing' unless $ref && $spec;
            $v->{text} = 'HASH Specificator: "type" has forbidden value '.$ref if $ref eq 'HASH' || $ref eq 'CODE';
        };

        if ($ref eq 'CODE') {
            $v = eval {$spec->($exc)};
        }
        else {
            my $code = $NG::Exception::specificatorProcessors->{$ref};
            if ($code) {
                $v = eval {$code->($spec,$exc)};
            }
            else {
                $v->{text} = "Not found CODE for specificator type $ref";
                $@ = "";
            };
        };
        if (my $ee = $@) {
            my $eeText = "";
            if (NG::Exception->caught($ee)) {
                $eeText = $ee->getText();
            }
            else {
                $eeText = $ee;
            };
            $excMsg .= "EXCEPTION $eeText WHILE GETTING VALUE FROM EXCEPTION SPECIFICATOR '$ref'\n";
            next;
        };
        $excMsg .= "\n".$v->{text};
        $subj .= " ".$v->{subj} if exists $v->{subj};
    };
    $excMsg=~s/\r?\n$//;
    
    my $notifyText .= "Во время обработки операции \"$opName\" произошла ошибка:\n\n$excMsg\n\n";
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
    $code = $params->{exceptionCode} if ($params && $params->{exceptionCode});
    
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
    $Carp::Internal{'NG::DBIException'}++;
    $class->SUPER::throw($code,$prefix.$message);
};

1;
