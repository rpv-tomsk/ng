package NG::Module::NotifyEmails;
use strict;

=head
Модуль вкладки администрирования списка емайл-адресов общего назначения.
=cut

$NG::Module::NotifyEmails::VERSION=0.5;

use NG::Module 0.5;
use vars qw(@ISA);
@ISA = qw(NG::Module);

sub loadEmails {
    my ($class,$module,$subcode) = (shift,shift,shift);
    my $cms = $class->cms();
    if (ref $module) {
        NG::InternalError->throw("Missing moduleObj/moduleObj->getModuleCode") unless UNIVERSAL::can($module,"getModuleCode");
        $module = $module->getModuleCode() or NG::InternalError->throw('Не могу определить код модуля '.(ref $module));
    }
    NG::InternalError->throw('Missing moduleobj/modulecode') unless $module;
    NG::InternalError->throw('Missing subcode') unless $subcode;
    my $mails = $cms->dbh->selectall_arrayref('SELECT email FROM ng_emails WHERE mcode =? AND subcode = ?', {Slice=>{}},$module,$subcode) or NG::DBIException->throw();
    my @mails = map {$_->{email}} @$mails;
    return \@mails;
};

package NG::Module::NotifyEmails::Block;
use strict;
use NG::Module::List;
use vars qw(@ISA);

BEGIN {
    @ISA = qw(NG::Module::List);
}

sub config {
    my $self = shift;
    
    my $mObj = $self->getModuleObj();  ## NB: Это не NG::Module::NotifyEmails,
                                       ## а тот модуль, который вызывает вкладку
    my $opts = $self->opts();

#opts:
#  - subcode - дополнительный фильтр
    
    $self->{_table} = $self->opts('table') || 'ng_emails';
    my $subCode     = $self->opts('subcode');
    
    my @fields = ();
    push @fields, {FIELD=>'id',    TYPE=>'id',     NAME=>'Код',IS_NOTNULL=>1};
    push @fields, {FIELD=>'email', TYPE=>'email',   NAME=>'E-Mail',IS_NOTNULL=>1,WIDTH=>"100%"};
    push @fields, {FIELD=>'mcode',  TYPE=>'filter', NAME=>'Filter',IS_NOTNULL=>1,WIDTH=>"100%",VALUE=>$mObj->getModuleCode()};
    #
    my @formfields = ();
    push @formfields, {FIELD=>'id'};
    push @formfields, {FIELD=>'email'};
    
    if ($subCode) {
        push @fields, {FIELD=>'subcode',  TYPE=>'filter', NAME=>'Filter',IS_NOTNULL=>1,WIDTH=>"100%",VALUE=>$subCode};
    }
    else {
        push @fields, {FIELD=>'subcode',  TYPE=>'select', NAME=>'Категория',IS_NOTNULL=>1,WIDTH=>"100%",
            OPTIONS => {
                TABLE => 'ng_emails_subcodes',
                ORDER => 'id',
                ID_FIELD=>'subcode',
                WHERE => 'mcode = ?',
                PARAMS => [$mObj->getModuleCode()],
            },
        };
        $self->filter(
            NAME => 'Группа',
            TYPE => 'select',
            LINKEDFIELD => 'subcode',
        );
        push @formfields, {FIELD=>'subcode',TYPE=>'hidden'};
    };
    $self->fields( @fields );
    $self->listfields([
        {FIELD=>'id'},
        {FIELD=>'email'},
    ]);
    $self->formfields( \@formfields );
    $self->{_onpage} = 20;
    $self->{_onlist} = 20;
    $self->order(
        {FIELD=>"email",DEFAULT=>0,ORDER_ASC=>"email",ORDER_DESC=>"email desc",DEFAULTBY=>'DESC'},
        {FIELD=>"id",DEFAULT=>0,ORDER_ASC=>"id",ORDER_DESC=>"id desc",DEFAULTBY=>'DESC'},
    );
#    $self->{_pageBlockMode}=1;
};

=comment

USAGE:

sub moduleTabs {
    return [
        ...
        {HEADER=>"Получатели уведомлений А",URL=>"/emailA/"},
        {HEADER=>"Получатели уведомлений Б",URL=>"/emailB/"},
        ...
    ];
};

sub moduleBlocks {
    return [
        ...
        #Все адреса модуля с фильтром по группам
        {URL=>"/emailA/", BLOCK=>"NG::Module::NotifyEmails::Block",USE=>'NG::Module::NotifyEmails'},
        ...
        #Определенный сабкод (группа) адресов 
        {URL=>"/emailB/", BLOCK=>"NG::Module::NotifyEmails::Block",USE=>'NG::Module::NotifyEmails',OPTS=>{subcode=>'ANOTIFY'}},
        ...
    ];
};

Использование списка адресов (Рассылка мессаг):

    #Внимание! loadEmails() может выдать Exception.
    #my $mails = $cms->getObject({CLASS=>"NG::Module::NotifyEmails",METHOD=>"loadEmails"},'MODULECODE','ANOTIFY');
    my $mails = $cms->getObject({CLASS=>"NG::Module::NotifyEmails",METHOD=>"loadEmails"},$self,'ANOTIFY');
    
    if (scalar @$mails) {
        ...
        #Вариант 1 - Общий заголовок To:
        $nmailer->send(@$mails) or return $cms->error();
        ...
        #Вариант 2 - Публичный список получателей 
        my $To = ''; $To .= '<'.$_ . '>,' foreach @$mails; $To =~ s/,$//;
        $nmailer->add('To',$To);
        $nmailer->send();
        
        #Вариант 3 - Формируем каждому отдельное письмо
    };
    
    
CREATE TABLE ng_emails (
  id SERIAL,
  email VARCHAR(50) NOT NULL,
  mcode VARCHAR(25) NOT NULL,
  subcode VARCHAR(25) NOT NULL,
  CONSTRAINT ng_emails_idx UNIQUE(email, mcode, subcode),
  CONSTRAINT ng_emails_pkey PRIMARY KEY(id)
) 
WITH (oids = false);

CREATE TABLE IF NOT EXISTS `ng_emails` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `email` varchar(50) NOT NULL,
  `mcode` varchar(25) NOT NULL,
  `subcode` varchar(25) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `mcode` (`mcode`,`subcode`,`email`)
) ENGINE=MyISAM DEFAULT CHARSET=cp1251 AUTO_INCREMENT=1;
=cut

1;
