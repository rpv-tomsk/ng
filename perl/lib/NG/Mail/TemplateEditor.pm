####
#### TODO
####

=head
  * Реализовать проверку шаблонов при сохранении
  * Переделать отображение списка, за основу брать перечень шаблонов из модуля, а не из БД
    - Добавлять недостающие шаблоны в БД
    - Отображать лишние и дать возможность удалять из БД
  * Реализовать NG::Mail::TemplateEditor для редактирования шаблонов всех модулей.
=cut

package NG::Mail::TemplateEditor::Block;
use strict;

use NGService;
use NSecure;
use NG::Module::List;
use base qw(NG::Module::List);

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
    
    $self->disableAddlink();
    $self->disableDeletelink();
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

sub _prepareTemplate {
    my $field = shift;
    
    my $q     = $field->q();
    my $form  = $field->parent();
    my $mObj  = $form->owner()->getModuleObj();
    
    my $template = NG::Mail::Template->new();
    
    my $iface = $mObj->getInterface('NG::Interface::MailTemplates') or NG::Exception->throw('NG.INTERNALERROR','Module has no NG::Interface::MailTemplates interface.');
    my $labels   = $iface->try('mailLabels');
    my $metadata = $iface->getTemplateMetadata($q->param('code'));
    
    #Compose test data
    my $data = {};
    foreach my $var (keys %{$metadata->{VARIABLES}}) {
        $data->{$var} = $metadata->{VARIABLES}->{$var}->{EXAMPLE} || '[No EXAMPLE was configured]';
    };
    #
    $template->{_subjt} = NG::Mail::TemplateElement->new(_convert $q->param('subject'));
    $template->{_subjt}->param($data);
    #
    $template->{_htmlt} = NG::Mail::TemplateElement->new(_convert $q->param('html'));
    $template->{_htmlt}->param($data);
    #
    $template->setLabels($labels) if $labels;
    
    return $template;
};

sub sendTestMail {
    my ($field,$is_ajax) = (shift,shift);
    
    my $q     = $field->q();
    my $cms   = $field->cms();
    my $testaddr = $q->param('testaddr');
    return 'Указан неверный адрес' unless is_valid_email($testaddr);
    
    my $template = undef;
    my $ret = eval {
        $template = $field->_prepareTemplate();
        $template->check();
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            return $e->message();
        };
        return 'Internal error: '.$@;
    };
    
    my $nMailer = $template->getMailer();
    $nMailer->add('to',$testaddr);
    $nMailer->send($testaddr) or return $cms->getError();
    return 'Сообщение отправлено';
};

sub checkTemplate {
    my ($field,$is_ajax) = (shift,shift);
    
    my $ret = eval {
        my $template = $field->_prepareTemplate();
        $template->check();
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            return '<font color="red">'.$e->message().'</font>';
        };
        return '<font color="red">Internal error: '.$@.'</font>';
    };
    return $ret;
};

sub prepareOutput {
    my $field = shift;

    my $form  = $field->parent();
    my $code = $form->getParam('code');
    my $mObj  = $form->owner()->getModuleObj();
    my $iface = $mObj->getInterface('NG::Interface::MailTemplates') or NG::Exception->throw('NG.INTERNALERROR','Module has no NG::Interface::MailTemplates interface.');
    
    my $metadata = $iface->getTemplateMetadata($code);
    
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
