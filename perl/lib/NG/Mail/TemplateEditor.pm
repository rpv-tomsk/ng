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
    $field->{NAME} =  "Добавление трейлера";
    
    return 1;
};

sub getFieldActions {
    my $self = shift;
    return [
        {ACTION=>"checktemplate", METHOD=>"checkTemplate"},
    ];
};

sub _getTemplateMetadata {
    my ($field,$mObj,$code) = (shift,shift,shift);
    
    NG::Exception->throw('NG.INTERNALERROR','Template code not specified.') unless $code;
    my $iface = $mObj->getInterface('TMAILER') or NG::Exception->throw('NG.INTERNALERROR','Module has no TMAILER interface.');
    
    my $cfg = $iface->configTMAILER();
    NG::Exception->throw('NG.INTERNALERROR',"Module has no template $code") unless exists $cfg->{$code};
    $cfg->{$code};
}

sub checkTemplate {
    my ($field,$is_ajax) = (shift,shift);
    
    my $q     = $field->q();
    my $form  = $field->parent();
    my $mObj  = $form->owner()->getModuleObj();
    
    my $metadata = $field->_getTemplateMetadata($mObj,$q->param('code'));
    
##TODO: add labels

    #Compose test data
    my $data = {};
    foreach my $var (keys %{$metadata->{VARIABLES}}) {
        $data->{$var} = $metadata->{VARIABLES}->{$var}->{EXAMPLE} || '[No EXAMPLE was configured]';
    };
    #Check Subject
    my $ret = eval {
        my $subjTemplate = NG::Mail::Template->new($q->param('subject'));
        $subjTemplate->param($data);
        my $unused = $subjTemplate->output();
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            return '<font color="red">Subject:'.$e->message().'</font>';
        };
        return '<font color="red">Internal error: '.$@.'</font>';
    };
    unless ($ret) {
        return '<font color="red">Ошибка проверки</font>';
    };
    #Check HTML
    my $ret = eval {
        my $htmlTemplate = NG::Mail::Template->new($q->param('html'));
        $htmlTemplate->param($data);
        $htmlTemplate->check();
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            return '<font color="red">HTML:'.$e->message().'</font>';
        };
        return '<font color="red">Internal error: '.$@.'</font>';
    };
    unless ($ret) {
        return '<font color="red">Ошибка проверки</font>';
    };
    return '<font color="green">'.$ret.'</font>';
}

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
} 

1;
