package NG::Controller;

use strict;

=head
    $pCtrl = $cms->new("NG::Controller",{
        STEPS   => [
            {METHOD=>"towidth",     PARAMS=>{width=>"100",toid=>"small"}},
            {METHOD=>"toGray",      PARAMS=>{id=>"small"}},
            {METHOD=>"saveToField", PARAMS=>{id=>"small", field=>"small"}},
            {METHOD=>"saveToFile",  PARAMS=>{id=>"small", dir=>"{siteroot}/htdocs/images", mask=>""}},
        ],
        PCLASS  =>
        OPTIONS =>
        
        OPTIONS => {
            METHOD=> "",
        },
        
        FORM => $form,
        FIELD => $field,
    });
    
    PCLASS  = FIELD.PROCESSOR
    OPTIONS = FIELD.OPTIONS
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
    
    $self->{_steps} = undef;
    $self->{_steps} = $args->{STEPS} if exists $args->{STEPS};
    $self->{_pclass} = $args->{PCLASS};
    $self->{_pObj}  = undef;
    $self->{_options} = $args->{OPTIONS};
    $self->{_form} = $args->{FORM};
    $self->{_field} = $args->{FIELD};
    
    $self;
};

sub _fillStepsFromConfig {
    my $self = shift;
    
    my $cms = $self->cms();
    my $cobj = $cms->{_confObj};
    return $cms->error("No config object exists") unless $cobj;
    return $cms->error("No OPTIONS.METHOD") unless $self->{_options} && $self->{_options}->{METHOD};
    
    #Site::Field::Processor_OptionsMethod.stepX_yyy 
    my $hash = $cobj->get_block($self->{_pclass}."_".$self->{_options}->{METHOD});
    
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
    1;
};

sub param { # getStepParam
    my $self = shift;
    my $param = shift;
    
    return $self->{_stepParams} unless $param;
    return $self->{_stepParams}->{$param};
};

sub paramOrOption {
    my $self = shift;
    my $param = shift;
    my $option = shift;
    my $o = $self->{_options} || {};
    return $self->param($param) || $o->{$option};
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
    
    return $cms->error("PCLASS is not configured") unless $self->{_pclass};
    my $pObj = $self->{_pObj} = $cms->getObject($self->{_pclass},$self) or return $cms->error();
    
    return $cms->error("STEPS is not ARRAYREF") if $self->{_steps} && ref $self->{_steps} ne "ARRAY";
    return $cms->error("OPTIONS is not HASHREF") if $self->{_options} && ref $self->{_options} ne "HASH";
    return $cms->error("No STEPS or OPTIONS.METHOD") unless $self->{_steps} || ($self->{_options} && $self->{_options}->{METHOD});
    
    $pObj->setValue($value) or return $cms->error($self->{_pclass}."->setValue() failed:".$self->{_error});
    
    unless ($self->{_steps}) {
        $self->_fillStepsFromConfig() or return $cms->error();
    };
    
    push @{$self->{_steps}}, {METHOD=>$self->{_options}->{METHOD}, PARAMS=>{}} unless (scalar @{$self->{_steps}});
    
    foreach my $step (@{$self->{_steps}}) {
        my $method = $step->{METHOD};
        $method or return $cms->error("No METHOD configured");
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
