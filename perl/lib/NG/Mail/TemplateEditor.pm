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
    ];
};

sub _getTemplateMetadata {
    my ($field,$iface,$code) = (shift,shift,shift);
    
    NG::Exception->throw('NG.INTERNALERROR','Template code not specified.') unless $code;
    
    my $cfg = $iface->mailTemplates();
    NG::Exception->throw('NG.INTERNALERROR',"mailTemplates(): incorrect value returned") unless $cfg && ref $cfg eq "HASH";
    NG::Exception->throw('NG.INTERNALERROR',"Module has no template $code") unless exists $cfg->{$code};
    $cfg->{$code};
};

sub checkTemplate {
    my ($field,$is_ajax) = (shift,shift);
    
    my $q     = $field->q();
    my $form  = $field->parent();
    my $mObj  = $form->owner()->getModuleObj();
    
    my $data = {};
    my $labels   = undef;
    
    eval {
        my $iface = $mObj->getInterface('TMAILER') or NG::Exception->throw('NG.INTERNALERROR','Module has no TMAILER interface.');
        my $metadata = $field->_getTemplateMetadata($iface,$q->param('code'));
        
        if ($iface->can('mailLabels')) {
            $labels = $iface->mailLabels();
            NG::Exception->throw('NG.INTERNALERROR',"mailLabels(): incorrect value returned") unless $labels && ref $labels eq "HASH";
        };
        
        #Compose test data
        foreach my $var (keys %{$metadata->{VARIABLES}}) {
            $data->{$var} = $metadata->{VARIABLES}->{$var}->{EXAMPLE} || '[No EXAMPLE was configured]';
        };
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            return '<font color="red">'.$e->message().'</font>';
        };
        return '<font color="red">Internal error: '.$@.'</font>';
    };

    #Check Subject
    my $ret = eval {
        my $subjTemplate = NG::Mail::Template->new($q->param('subject'));
        $subjTemplate->param($data);
        $subjTemplate->labels($labels) if $labels;
        my $unused = $subjTemplate->output();
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            return '<font color="red">Subject: '.$e->message().'</font>';
        };
        return '<font color="red">Internal error: '.$@.'</font>';
    };
    unless ($ret) {
        return '<font color="red">Ошибка проверки шаблона</font>';
    };
    #Check HTML
    $ret = eval {
        my $htmlTemplate = NG::Mail::Template->new($q->param('html'));
        $htmlTemplate->param($data);
        $htmlTemplate->labels($labels) if $labels;
        $htmlTemplate->check();
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            return '<font color="red">HTML: '.$e->message().'</font>';
        };
        return '<font color="red">Internal error: '.$@.'</font>';
    };
    unless ($ret) {
        return '<font color="red">Ошибка проверки шаблона</font>';
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
