package NG::Exception;
use strict;
use Scalar::Util 'blessed';

our @specificators;
our $specificatorProcessors = {};

sub new {
    my $class = shift;
    
    my $self = {};
    bless $self,$class;
    
    $self->{code} = shift;
    $self->{message} = shift;
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
    return $e if $code eq $e->{code};
    return undef;
}

sub message  { my $self = shift; return $self->{message}; };
sub code     { my $self = shift; return $self->{code};    };

sub getText {
    my $exc = shift;
    
    return $exc->{carpmessage} if $exc->{carpmessage};
    $exc->code.": ".$exc->message."\n";
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
