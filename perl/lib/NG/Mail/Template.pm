package NG::Mail::Template;
use strict;

use NG::Exception;

sub new {
    my ($class,$content) = (shift,shift);
    
    my $self = {};
    bless $self,$class;
    #Предобработка шаблона
    $content =~ s@\[\%(?:var\s+)?\s*(\S+?)\s*\%\]@\[\%var VARS\.$1\%\]@gm;
    $content =~ s@\[\%label\s+(\S+?)\s*\%\]@\[\%var LABELS\.$1\%\]@gm;
    #Заполнение данными
    $self->{_template} = $self->cms->gettemplate(undef,{tagstyle=>['tt'],scalarref=>\$content});
    $self->{_vars} = undef;
    $self->{_labels} = undef;
    $self;
};

sub param {
    my $self = shift;
    my $data = shift;
    $self->_setVariables($self->_createVariables($data));
};

sub labels {
    my $self = shift;
    my $data = shift;
    $self->_setLabels($self->_createLabels($data));
};

sub check {
    my $self = shift;
    my $unused = $self->{_template}->output();
    my $message = "";
    
    if ($self->{_vars}) {
        foreach my $var (keys %{$self->{_vars}->{_data}}) {
            next if exists $self->{_vars}->{_used}->{$var};
            $message.= "Переменная $var не использована\n";
        };
    };
    
    $message ||= "Шаблон абсолютно корректен";
    $message;
};

sub output {
    my $self = shift;
    $self->{_template}->output();
};

sub _createVariables {
    my ($unused,$data) = (shift,shift);
    my $variables = {};
    bless $variables, "NG::Mail::Template::Variables";
    $variables->{_data} = $data;
    $variables->{_used} = {};
    $variables;
};

sub _createLabels {
    my ($unused,$data) = (shift,shift);
    my $labels = {};
    bless $labels, "NG::Mail::Template::Labels";
    $labels->{_data} = $data;
    $labels->{_used} = {};
    $labels;
};

sub _setVariables {
    my ($self,$vars) = (shift,shift);
    $self->{_template}->param({VARS=>$vars});
    $self->{_vars} = $vars;
};

sub _setLabels {
    my ($self,$labels) = (shift,shift);
    $self->{_template}->param({LABELS=>$labels});
    $self->{_labels} = $labels;
};

package NG::Mail::Template::Variables;
use strict;
our $AUTOLOAD;

sub DESTROY {
    return "Запрещенное имя переменной";
};

sub AUTOLOAD {
    my $self=shift;
    my $pkg = ref $self;
    $AUTOLOAD =~ s/$pkg\:\://;
    $self->{_used}->{$AUTOLOAD} = 1;
    NG::Exception->throw('NG.INTERNALLERROR',"Шаблон: Переменная $AUTOLOAD не найдена") unless exists $self->{_data}->{$AUTOLOAD};
    return $self->{_data}->{$AUTOLOAD};
};

package NG::Mail::Template::Labels;
use strict;
our $AUTOLOAD;

sub DESTROY {
    return "Запрещенное имя метки";
};

sub AUTOLOAD {
    my $self=shift;
    my $pkg = ref $self;
    $AUTOLOAD =~ s/$pkg\:\://;
    $self->{_used}->{$AUTOLOAD} = 1;
    NG::Exception->throw('NG.INTERNALLERROR',"Шаблон: Метка $AUTOLOAD не найдена") unless exists $self->{_data}->{$AUTOLOAD};
    return $self->{_data}->{$AUTOLOAD};
};

1;
