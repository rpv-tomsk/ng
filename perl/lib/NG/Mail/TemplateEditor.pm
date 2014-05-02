package NG::Mail::TemplateEditor::Block;
use strict;

use NGService;
use NSecure;
use NG::Module::List;
use base qw(NG::Module::List);

BEGIN {}

sub config {
    my $self = shift;
    $self->{'_table'} = 'mtemplates';
 
    my $mObj=$self->getModuleObj();
    my $callerCode = undef;
    if($mObj) {
        $callerCode = $mObj->getModuleCode();
    };

    $self->fields(
        {FIELD => 'id',         TYPE => 'id',        NAME => 'Код записи'},
        {FIELD => 'module',     TYPE => 'filter',    NAME => 'mcode',           IS_NOTNULL => 1, VALUE => $callerCode},
        {FIELD => 'name',       TYPE => 'text',      NAME => 'Название',      IS_NOTNULL => 1},
        {FIELD => 'subject',    TYPE => 'text',      NAME => 'Subject',       IS_NOTNULL => 1},
        {FIELD => 'html',       TYPE => 'rtf',       NAME => 'Текст',         IS_NOTNULL => 1,
            OPTIONS => {
                # CONFIG               => 'defaultConfig',
                IMG_TABLE            => 'mtemplatesrtfimages',
                IMG_UPLOADDIR        => '/upload/mtemplates/',
                IMG_TABLE_FIELDS_MAP => {id => 'parent_id'},
            },
        },
        {FIELD => 'code',      TYPE => 'hidden',      NAME => 'Код',           IS_NOTNULL => 1},
        {FIELD => 'legend',    TYPE => 'text', CLASS => 'NG::Mail::TemplateEditor::LegendField'},
    );
    $self->listfields([
        {FIELD => 'name'},
    ]);
    $self->formfields(
        {FIELD => 'id'},
        {FIELD => 'name'},
        {FIELD => 'subject'},
        {FIELD => 'html'},
        {FIELD => 'legend'},
        {FIELD => 'code'},
    );
};

package NG::Mail::TemplateEditor::LegendField;
use strict;
use NSecure;
use NGService;
use NG::Field;
use NG::Mail::Template;
our @ISA = qw(NG::Field);

sub init {
    my $field = shift;
    $field->SUPER::init(@_) or return undef;
    
    $field->{IS_FAKEFIELD} = 1;
    $field->{TEMPLATE} = 'admin-side/common/mail/templatelegend.tmpl';
    
    return 1;
};

sub getFieldActions {
    my $self = shift;
    return [
        {ACTION=>"checktemplate", METHOD=>"checkTemplate"},
        {ACTION=>"sendtestmail",  METHOD=>"sendTestMail"},
    ];
};

my $converter = undef;

sub _convert {
    $converter ||= $NG::Application::cms->getObject("Text::Iconv","utf-8","cp1251");
    $converter->convert($_[0]);
}; 

sub _getTemplateMetadata {
    my ($field,$iface,$code) = (shift,shift,shift);
    
    NG::Exception->throw('NG.INTERNALERROR','Template code not specified.') unless $code;
    
    my $cfg = $iface->mailTemplates();
    NG::Exception->throw('NG.INTERNALERROR',"mailTemplates(): incorrect value returned") unless $cfg && ref $cfg eq "HASH";
    NG::Exception->throw('NG.INTERNALERROR',"Module has no template $code") unless exists $cfg->{$code};
    $cfg->{$code};
};

sub _prepareTestData {
    my $field = shift;
    
    my $q     = $field->q();
    my $form  = $field->parent();
    my $mObj  = $form->owner()->getModuleObj();
    
    my $subjTemplate = undef;
    my $htmlTemplate = undef;
    
    eval {
        my $iface = $mObj->getInterface('TMAILER') or NG::Exception->throw('NG.INTERNALERROR','Module has no TMAILER interface.');
        my $metadata = $field->_getTemplateMetadata($iface,$q->param('code'));
        
        my $labels = undef;
        if ($iface->can('mailLabels')) {
            $labels = $iface->mailLabels();
            NG::Exception->throw('NG.INTERNALERROR',"mailLabels(): incorrect value returned") unless $labels && ref $labels eq "HASH";
        };
        
        #Compose test data
        my $data = {};
        foreach my $var (keys %{$metadata->{VARIABLES}}) {
            $data->{$var} = $metadata->{VARIABLES}->{$var}->{EXAMPLE} || '[No EXAMPLE was configured]';
        };
        #
        $subjTemplate = NG::Mail::Template->new(_convert $q->param('subject'));
        $subjTemplate->param($data);
        $subjTemplate->labels($labels) if $labels;
        #
        $htmlTemplate = NG::Mail::Template->new(_convert $q->param('html'));
        $htmlTemplate->param($data);
        $htmlTemplate->labels($labels) if $labels;
    };
    return ($subjTemplate,$htmlTemplate);
};

sub sendTestMail {
    my ($field,$is_ajax) = (shift,shift);
    
    my $q     = $field->q();
    my $cms   = $field->cms();
    my $testaddr = $q->param('testaddr');
    return 'Указан неверный адрес' unless is_valid_email($testaddr);
    
    my $subjT = undef;
    my $htmlT = undef;
    my $ret = eval {
        ($subjT,$htmlT) = $field->_prepareTestData();
        $field->_checkTemplate($subjT,$htmlT);
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            return $e->message();
        };
        return 'Internal error: '.$@;
    };
    
    my $nMailer = $cms->getModuleByCode('MAILER') or return 'Модуль MAILER не найден';
    $nMailer->add('Subject',$subjT->output()) if $subjT;
    #$nMailer->addPlainPart($plainT) if $plainT;
    
    if ($htmlT) {
        $nMailer->addHTMLPart(
            Data     => $htmlT->output(),
            BaseDir  => $cms->getDocRoot(),
            #Encoding => 'base64'
        );
    };
    $nMailer->send($testaddr) or return $cms->getError();
    return 'Сообщение отправлено';
};

sub checkTemplate {
    my ($field,$is_ajax) = (shift,shift);
    
    my $ret = eval {
        my ($subjT,$htmlT) = $field->_prepareTestData();
        $field->_checkTemplate($subjT,$htmlT);
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            return '<font color="red">'.$e->message().'</font>';
        };
        return '<font color="red">Internal error: '.$@.'</font>';
    };
    return $ret;
};

sub _checkTemplate {
    my ($field,$subjTemplate,$htmlTemplate) = (shift,shift,shift);
    
    #Check Subject
    my $ret = eval {
        my $unused = $subjTemplate->output();
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
    #Check HTML
    $ret = eval {
        $htmlTemplate->check();
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

sub prepareOutput {
    my $field = shift;

    my $form  = $field->parent();
    my $code = $form->getParam('code');
    my $mObj  = $form->owner()->getModuleObj();
    
    my $metadata = $field->_getTemplateMetadata($mObj,$code);
    
    my $legend = [];
    foreach my $var (keys %{$metadata->{VARIABLES}}) {
        push @$legend, {
            VAR => $var,
            NAME => $metadata->{VARIABLES}->{$var}->{NAME},
            EXAMPLE => $metadata->{VARIABLES}->{$var}->{EXAMPLE},
        };
    }
    $field->{LEGEND} = $legend;
    
    1;
};

1;
