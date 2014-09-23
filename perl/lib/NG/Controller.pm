package NG::Controller;

use strict;

=head
    $pCtrl = $cms->new("NG::Controller",{
        PCLASS  => 'NG::ImageProcessor',
        STEPS   => [
            {METHOD=>"towidth",     PARAMS=>{width=>"100",toid=>"small"}},
            {METHOD=>"toGray",      PARAMS=>{id=>"small"}},
            {METHOD=>"saveToField", PARAMS=>{id=>"small", field=>"small"}},
            {METHOD=>"saveToFile",  PARAMS=>{id=>"small", dir=>"{siteroot}/htdocs/images", mask=>""}},
        ],
        FORM => $form,
        FIELD => $field,
    });
    
    PCLASS  = FIELD.PROCESSOR
    STEPS   = FIELD.OPTIONS.STEPS
    
    $pCtrl->processField($field);
    
    ...
        Файловое поле, класс NG::Field:
        my $pCtrl = ....
        
        $source = $field->value();
        $dest   = $field->dbValue();
        
        $pCtrl->processFile($source,$dest) or return $cms->error();
        
        
        Не файловое поле.
        
        my $value = $field->value()
        $pCtrl->process($value) or return $cms->error();
        my $result = $pCtrl->getResult();
        $field->setValue($result);
        
    ...
=cut

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);    
    $self; 
};

sub init {
    my $self = shift;
    my $args = shift;
    
    $self->{_pclass} = $args->{PCLASS} or NG::Exception->throw('NG.INTERNALERROR',"NG::Controller->new(): PCLASS argument is missing");
    $self->{_steps}  = $args->{STEPS}  or NG::Exception->throw('NG.INTERNALERROR',"NG::Controller->new(): STEPS argument is missing");

    NG::Exception->throw('NG.INTERNALERROR',"NG::Controller->new(): STEPS is not ARRAYREF") unless ref $self->{_steps} eq "ARRAY";

    $self->{_pObj}  = undef;
    $self->{_form}  = $args->{FORM};
    $self->{_field} = $args->{FIELD};
    
    $self->_fillStepsFromConfig() if (scalar @{$self->{_steps}} == 1) && !exists $self->{_steps}[0]->{PARAMS};
    $self;
};

sub _fillStepsFromConfig {
    my $self = shift;
    
    my $cms = $self->cms();
    my $cobj = $cms->{_confObj} or NG::Exception->throw('NG.INTERNALERROR','NG::Controller->_fillStepsFromConfig(): No cms config object exists');
    my $method = $self->{_steps}[0]->{METHOD} or NG::Exception->throw('NG.INTERNALERROR',"NG::Controller->_fillStepsFromConfig(): Unable to get METHOD (OPTIONS.METHOD)");
    
    #Site::Field::Processor_OptionsMethod.stepX_yyy 
    
    #[Site::Field::Processor_OptionsMethod]
    #step0=torectangle
    #step0_width=100
    #step0_height=200
    #
    my $hash = $cobj->get_block($self->{_pclass}."_".$method);
    
    my $steps = {}; 
    foreach my $key (keys %$hash) {
        if ($key =~ /^step(\d+)$/) {
            $steps->{$1}->{METHOD} = $hash->{$key};
        };
        if ($key =~ /^step(\d+)_(\S+)/) {
            $steps->{$1}->{PARAMS}->{$2} = $hash->{$key};
        };
    };
    
    $self->{_steps} = [];
    my $step = 0;
    while (exists $steps->{$step}) {
        push @{$self->{_steps}}, $steps->{$step};
        $step++;
    };
};

sub param { # getStepParam
    my $self = shift;
    return $self->{_stepParams} unless scalar @_;
    my $param = shift;
    return $self->{_stepParams}->{$param};
};

sub doStep {
    my $self = shift;
    my $method = shift;
    my $params = shift;
    
    my $cms = $self->cms();
    my $pObj = $self->{_pObj};
    
    return $cms->error("Class ".$self->{_pclass}." has no method $method") unless ($pObj->can($method));
    
    $self->{_stepParams} = $params;
    
    $pObj->$method() or return $cms->error("Step method $method failed: ".$self->{_error});
    
    1;
};

sub process {
    my $self = shift;
    my $value = shift;
    my $dest  = shift;
    
    my $cms = $self->cms();
    my $pObj = $self->{_pObj} = $cms->getObject($self->{_pclass},$self);
    
    $pObj->setValue($value) or return $cms->error($self->{_pclass}."->setValue() failed:".$self->{_error});
    
    foreach my $step (@{$self->{_steps}}) {
        my $method = $step->{METHOD} or return $cms->error("No METHOD configured");
        return $cms->error("Class ".$self->{_pclass}." has no method $method") unless ($pObj->can($method));
        
        $self->doStep($method,$step->{PARAMS}) or return $cms->error($self->{_error});
    };
    $self->{_stepParams} = undef;
    $pObj->afterProcess($dest) or return $cms->error($self->{_pclass}."->afterProcess() failed: ".$self->{_error});
    1;
};

sub getResult {
    my $self = shift;
    return $self->{_pObj}->getResult();
};

=head
sub processFile { # SourceFile, DestFile
    my $self = shift;
    $self->{_value} = shift;
    

    return $self->process();
};
sub processField {
    my $self = shift;
    $self->{_field} = shift;
    $self->{_value} = $self->{_field}->value();
    return $self->process();
};
=cut

sub getField {
    my $self = shift;
    my $fName = shift;
    return undef unless $self->{_form};
    my $f = $self->{_form}->getField($fName);
    unless ($f) {
        $self->error("Field '$fName' not found");
        return undef;
    }
    return $f;
};

sub getCurrentField {
    my $self = shift;
    return $self->{_field};
};

sub error {
    my $self = shift;
    $self->{_error} ||= shift;
    0;
};

sub getSourceValue {
    my $self = shift;
    return $self->{_value};
};

1;
