package NG::Mail::Template;
use strict;

use NG::Exception;

sub new {
    my ($class,$opts) = (shift,shift);
    
    my $template = {};
    bless $template,$class;
    
    $opts ||= {};
    $template->{_caller} = $opts->{CALLER}   if $opts->{CALLER};
    $template->{_code}   = $opts->{TEMPLATE} if $opts->{TEMPLATE};

    $template->_load() if $template->{_caller} && $template->{_code};
    $template;
};

sub _load {
    my $template = shift;
    
    my $templateCode = $template->{_code};
    my $callerCode   = $template->{_caller}->getModuleCode();
    
    my $sql = 'select id, name, subject, html, plain from mtemplates where module = ? and code=?';
    my $sth = $template->dbh()->prepare($sql) or NG::DBIException->throw();
    $sth->execute($callerCode,$templateCode) or NG::DBIException->throw();
    my $tmplRow = $sth->fetchrow_hashref() or NG::Exception->throw("Запись шаблона $templateCode модуля $callerCode не найдена");
    $sth->finish();
    
    $template->{_plaint} = NG::Mail::TemplateElement->new($tmplRow->{plain},'PLAIN')   if $tmplRow->{plain};
    $template->{_subjt}  = NG::Mail::TemplateElement->new($tmplRow->{subject},'SUBJECT') if $tmplRow->{subject};
    $template->{_htmlt}  = NG::Mail::TemplateElement->new($tmplRow->{html},'HTML')    if $tmplRow->{html};
    $template;
};

sub param {
    my ($template,$data) = (shift,shift);
    
    my $vars = NG::Mail::TemplateElement->_createVariables($data);
    
    $template->{_subjt}->_setVariables($vars)  if $template->{_subjt};
    $template->{_htmlt}->_setVariables($vars)  if $template->{_htmlt};
    $template->{_plaint}->_setVariables($vars) if $template->{_plaint};
    $template;
};

sub setLabelsFromInterface {
    my $template = shift;
    
    my $iface = $template->{_caller}->getInterface('NG::Interface::MailTemplates');
    return unless $iface;
    return unless $iface->can('mailLabels');
    my $labels = $iface->mailLabels();
    NG::Exception->throw('NG.INTERNALERROR',"mailLabels(): incorrect value returned") unless $labels && ref $labels eq "HASH";
    
    return $template->setLabels($labels); 
};

sub setLabels {
    my ($template,$labels) = (shift,shift);
    
    my $labelsObj = NG::Mail::TemplateElement->_createLabels($labels);
    
    $template->{_subjt}->_setLabels($labelsObj) if $template->{_subjt};
    $template->{_htmlt}->_setLabels($labelsObj) if $template->{_htmlt};
    $template->{_plaint}->_setLabels($labelsObj) if $template->{_plaint};
    $template;
}

sub check {
    my $template = shift;
    
    my $ret = "";
    $template->_checkSubjectTemplate()      if $template->{_subjt};
    $ret .= $template->_checkHTMLTemplate() if $template->{_htmlt};
    
    $ret;
};

sub _checkSubjectTemplate {
    my $template = shift;
    
    NG::Exception->throw('NG.INTERNALERROR','No subject template') unless $template->{_subjt};
    #Check Subject
    my $ret = eval {
        my $unused = $template->{_subjt}->output();
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            NG::Exception->throw('NG.INTERNALERROR','Subject: '.$e->message());
        };
        NG::Exception->throw('NG.INTERNALERROR','Internal error: '.$@);
    };
    unless ($ret) {
        NG::Exception->throw('NG.INTERNALERROR','Ошибка проверки шаблона');
    };
    return "";
};

sub _checkHTMLTemplate {
    my $template = shift;
    
    NG::Exception->throw('NG.INTERNALERROR','No HTML template') unless $template->{_htmlt};
    #Check HTML
    my $ret = eval {
        $template->{_htmlt}->check();
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            NG::Exception->throw('NG.INTERNALERROR','HTML: '.$e->message());
        };
        NG::Exception->throw('NG.INTERNALERROR','Internal error: '.$@);
    };
    unless ($ret) {
        NG::Exception->throw('NG.INTERNALERROR','Ошибка проверки шаблона');
    };
    return $ret;
};

sub getMailer {
    my $template = shift;
    
    NG::Exception->throw('NG.INTERNALERROR','No HTML or PLAIN part') unless $template->{_htmlt} or $template->{_plaint};
    my $cms = $template->cms();
    my $nMailer = $cms->getModuleByCode('MAILER') or NG::Exception->throw('NG.INTERNALERROR','Модуль MAILER не найден');
    $nMailer->add('Subject',$template->{_subjt}->output()) if $template->{_subjt};
    $nMailer->addPlainPart($template->{_plaint}->output()) if $template->{_plaint};
    
    if ($template->{_htmlt}) {
        $nMailer->addHTMLPart(
            Data     => $template->{_htmlt}->output(),
            BaseDir  => $cms->getDocRoot(),
            Encoding => 'base64'
        );
    };
    $nMailer;
};

package NG::Mail::TemplateElement;
use strict;

sub new {
    my ($class,$content,$type) = (shift,shift,shift);
    
    my $self = {};
    bless $self,$class;
    #Предобработка шаблона
    $content =~ s@\[\%(?:var\s+)?\s*(\S+?)\s*\%\]@\[\%var VARS\.$1\%\]@gm;
    $content =~ s@\[\%label\s+(\S+?)\s*\%\]@\[\%var LABELS\.$1\%\]@gm;
    
    if ($type eq 'HTML') {
        $content = '<html>'.$content.'</html>' unless ($content =~ /^\s*<html>/im) || ($content =~ /<\/html>\s*$/im);
    };
    
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
    if ($message) {
        $message = '<font color="red">'.$message.'</font>';
    };
    
    $message ||= '<font color="green">Шаблон абсолютно корректен</font>';
    $message;
};

sub output {
    my $self = shift;
    $self->{_template}->output();
};

sub _createVariables {
    my ($unused,$data) = (shift,shift);
    my $variables = {};
    bless $variables, "NG::Mail::TemplateElement::Variables";
    $variables->{_data} = $data;
    $variables->{_used} = {};
    $variables;
};

sub _createLabels {
    my ($unused,$data) = (shift,shift);
    my $labels = {};
    bless $labels, "NG::Mail::TemplateElement::Labels";
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

package NG::Mail::TemplateElement::Variables;
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
    NG::Exception->throw('NG.INTERNALLERROR',"Переменная $AUTOLOAD не найдена") unless exists $self->{_data}->{$AUTOLOAD};
    return $self->{_data}->{$AUTOLOAD};
};

package NG::Mail::TemplateElement::Labels;
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
    NG::Exception->throw('NG.INTERNALLERROR',"Метка $AUTOLOAD не найдена") unless exists $self->{_data}->{$AUTOLOAD};
    return $self->{_data}->{$AUTOLOAD};
};

1;
