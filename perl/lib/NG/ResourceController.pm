package NG::ResourceController;

our $AUTOLOAD;

sub new
{
    my $class = shift;
    my $obj = {};
    bless $obj,$class;
    $obj->init(@_);
    return $obj;
};

sub init
{
    my $self = shift;
    $self->{_parent} = shift || undef;
};

sub AUTOLOAD 
{
    my $self = shift;
    my $param = $AUTOLOAD;
    my $package = ref $self;
    $param =~ s/$package\:\://;
    return $self->{_parent}->getResource($param) if (defined $self->{_parent} && $self->{_parent}->can("getResource"));
    return undef;
};

1;