package NG::SiteModule::Faq;
use strict;
use NGService;
use NSecure;
use NHtml;
use NG::PageModule;
use NG::Form;

use vars qw(@ISA);
sub BEGIN
{
    @ISA = qw(NG::PageModule);
};
    
sub moduleTabs {
	return [
		{'HEADER'=>'Вопрос-ответ', 'URL'=>'/'},
		{'HEADER'=>'E-mail', 'URL'=>'/emails/'},
    ];
}

sub moduleBlocks {
	return [
		{'URL'=>'/', 'BLOCK'=>'NG::SiteModule::Faq::List'},
		{'URL'=>'/emails/', 'BLOCK'=>'NG::SiteModule::Faq::Emails'}
	]
};


sub getActiveBlock {
    return {'BLOCK'=>'FAQ'};
};

sub block_FAQ {
    my $self = shift;
    my $cms = $self->cms();
    my $q = $self->q();
    my $db = $self->db();

    my $template = $self->gettemplate('public/faq/faq.tmpl') or return $cms->error();
    my $form = $self->getStash('form') || $self->_get_form();
    $form->print($template);
    
    my $messageok = $q->param('ok')?'Ваш вопрос принят к рассмотрению':'';
    $template->param(
        'MESSAGEOK' => $messageok,
        'ERROR' => $form->has_err_msgs()
    );
    
    my $page = $q->param('page');
    $page = 1 unless is_valid_id($page);
    
	my $dblist = NG::DBlist->new(
		'db' => $db,
		'table' => 'faq',
		'fields' => 'q_name,q_date,q_text,a_text,a_date,a_name',
		'order' => 'order by q_date desc',
		'page' => $page,
		'onpage' => 5,
        'onlist' => 5,
		'where' => 'page_id=? and is_show=1',
	);    	

	$dblist->rowfunction(
	    sub 
	    {
	        my $dblist = shift;
	        my $row = shift;
	        $row->{'q_date'} = $db->date_from_db($row->{'q_date'});
	        $row->{'a_date'} = $db->date_from_db($row->{'a_date'});
            $row->{'q_text'} = nl2br($row->{'q_text'});
            $row->{'a_text'} = nl2br($row->{'a_text'});
	    }
	);
	$dblist->open($self->getPageId());
	my $data = $dblist->data();
	my $pages = $dblist->pages();
    
    $template->param(
        'DATA' => $data,
        'PAGES' => $pages
    );
    return $cms->output($template);        
};

sub _get_form {
    my $self = shift;
    my $cms = $self->cms();
    my $page_row = $self->getPageRow();
    
	my $form = NG::Form->new(
		'DB' => $self->db(),
		'FORM_URL'  => getURLWithParams($page_row->{'url'}),
		'KEY_FIELD' => 'id',
		'DOCROOT'   => $cms->getDocRoot(),
		'SITEROOT'  => $cms->getSiteRoot(),
		'CGIObject' => $self->q(),
		'DEFFIELDTEMPLATE' => '../common/fields.tmpl'
	);
    $form->{'_table'} = 'faq';
    
    $form->addfields([
		{'FIELD'=>'id','TYPE'=>'id','IS_NOTNULL'=>1,'VALUE'=>1},        
        {'FIELD'=>'page_id','TYPE'=>'filter','VALUE'=>$page_row->{'id'}},
        {'FIELD'=>'q_name', 'TYPE'=>'text', 'IS_NOTNULL'=>1, 'NAME'=>'Ф.И.О. контактного лица'},
        {'FIELD'=>'q_mail', 'TYPE'=>'email', 'IS_NOTNULL'=>0, 'NAME'=>'E-mail контактного лица'},
        {'FIELD'=>'q_text', 'TYPE'=>'textarea', 'IS_NOTNULL'=>1, 'NAME'=>'Сообщение'},
        {'FIELD'=>'number','TYPE'=>'turing','IS_NOTNULL'=>1,'IS_FAKEFIELD'=>1,'IMAGEURL'=>'/turing/', 'NAME'=>'Код защиты'}
    ]);                                                                                                         
    $form->modeInsert(); 
    return $form;    
};

sub processModulePost {
    my $self = shift;
    my $q = $self->q();
    my $db = $self->db();
    my $cms = $self->cms();
    my $page_row = $self->getPageRow();
    
    my $form = $self->_get_form();
    $form->setFormValues();
    $form->StandartCheck();
    unless ($form->has_err_msgs()) {
        foreach my $key (qw(q_name q_mail q_text)) {
            $form->param($key,htmlspecialchars($form->getValue($key)));                
        };        
        $form->param('id',$db->get_id($form->{'_table'}));
        $form->insertData();
        #$self->_send_notify();
        return $cms->redirect(getURLWithParams($page_row->{'url'},'ok=1'));
    };
    $self->setStash('form',$form);
    
    return 1; 
};

=comment
sub _send_notify {
    my $self = shift;
    my $dbh = $self->dbh();
    my $q = $self->q();
    my $vhost = $self->cms()->confParam('CMS.FromMailHost') || $q->virtual_host();
    my $page_row = $self->getPageRow();
    my $mails = $dbh->selectall_arrayref('select mail from faq_emails where page_id=?',{'Slice'=>{}},$page_row->{'id'});
    if (scalar @$mails) {
        my @mails = (); map {push @mails,$_->{'mail'}} @$mails;
        my $nmailer = NMailer->mynew();
        $nmailer->add('from','no-reply@'.$vhost);
        $nmailer->add('to',$mails[0]);
        $nmailer->add('subject','Поступил новый вопрос');
        $nmailer->set_plain_part(
            'Поступил новый вопрос в раздел '.$page_row->{'name'}.'.'."\n".'Для просмотра сообщения вы можете перейти по ссылке http://'.$vhost.'/admin-side/pages/'.$page_row->{'id'}.'/ .'
        );
        $nmailer->send_to_list(@mails);
    };
};
=cut


package NG::SiteModule::Faq::List;
use strict;
use NGService;
use NSecure;
use NG::Module::List;
use vars qw(@ISA);
@ISA = qw(NG::Module::List);

sub config  {
    my $self = shift;
    $self->{'_table'} = 'faq';
    
    $self->fields(
        {'FIELD'=>'id', 'TYPE'=>'id', 'NAME'=>'Код записи'},
        {'FIELD'=>'page_id', 'TYPE'=>'pageId', 'NAME'=>'Код', 'IS_NOTNULL'=>1},        
        {'FIELD'=>'q_name', 'TYPE'=>'text', 'NAME'=>'Автор вопроса', 'IS_NOTNULL'=>1},
        {'FIELD'=>'q_mail', 'TYPE'=>'email', 'NAME'=>'E-mail', 'IS_NOTNULL'=>0},
        {'FIELD'=>'q_text', 'TYPE'=>'textarea', 'NAME'=>'Вопрос', 'IS_NOTNULL'=>1},
        {'FIELD'=>'q_date', 'TYPE'=>'datetime', 'NAME'=>'Дата вопроса', 'IS_NOTNULL'=>1, 'DEFAULT'=>current_datetime()},
        {'FIELD'=>'a_name', 'TYPE'=>'text', 'NAME'=>'Автор ответа', 'IS_NOTNULL'=>1},
        {'FIELD'=>'a_text', 'TYPE'=>'textarea', 'NAME'=>'Ответ'},        
        {'FIELD'=>'a_date', 'TYPE'=>'datetime', 'NAME'=>'Дата ответа', 'IS_NOTNULL'=>1, 'DEFAULT'=>current_datetime()},
        {'FIELD'=>'is_show', 'TYPE'=>'checkbox', 'NAME'=>'Отображать на сайте'}
    );
    # Списковая
    $self->listfields([
        {'FIELD'=>'q_date',},
        {'FIELD'=>'q_name',},
        {'FIELD'=>'q_text',}, 
        {'FIELD'=>'is_show',},
    ]);
    # Формовая часть
    $self->formfields(
        {'FIELD'=>'id'},
        {'FIELD'=>'q_name'},
        {'FIELD'=>'q_date'},
        {'FIELD'=>'q_mail'},        
        {'FIELD'=>'q_text'},
        {'FIELD'=>'a_name'},
        {'FIELD'=>'a_date'},
        {'FIELD'=>'a_text'},
        {'FIELD'=>'is_show'}
    );
    $self->filter(
  		'NAME'=>'Отобразить',
  		'TYPE'=>'select',
  		'VALUES'=>[
  			  { 'NAME'=>'Все записи', 'WHERE'=>'', },
  			  { 'NAME'=>'Не отвеченые', 'WHERE'=>'is_show<>1', },
  		],
  	);
	
	$self->order({'DEFAULT'=>'DESC', 'DEFAULTBY'=>'DESC', 'FIELD'=>'q_date', 'ORDER_DESC'=>'q_date desc,id desc', 'ORDER_ASC'=>'q_date asc,id asc'});
};

sub checkData {
    my $self = shift;
    my $form = shift;
    my $fa = shift;
    
    $form->pusherror('a_text','Поле "Ответ" должно быть заполнено перед публикацией вопроса на сайте') if ($form->getValue('is_show') && is_empty($form->getValue('a_text')));
     
    return NG::Block::M_OK; 
};

sub afterFormLoadData {
	my $self = shift;
	my $form = shift;
	my $action = shift;
	my $field = $form->_getfieldhash('a_date');
	if(is_empty($field->{'VALUE'}) || $field->{'VALUE'} eq '00.00.0000 00:00:00')	{
		$field->{'VALUE'} = current_datetime();
	};
	$field = $form->_getfieldhash('a_name');
	if(is_empty($field->{'VALUE'}))	{
		$field->{'VALUE'} = 'Администратор';
	};	
	return 1;
};

sub getSenderEmail {
    my $self = shift;
    my $vhost = $self->cms()->confParam('CMS.MailFromHost') || $self->q()->virtual_host();
    return 'faq@'.$vhost;
};

sub afterInsertUpdate {
    my $self = shift;
    my $form = shift;
    my $action = shift;
    my $dbh = $self->dbh();
    
    if ($action eq 'update') {
        my $is_show = $form->getField('is_show');
        my $mail = $form->getValue('q_mail');
        if ($is_show->{DBVALUE} == 1 && $is_show->{OLDDBVALUE}==0 && is_valid_email($mail)) {
            my $q = $self->q();
            my $page_row = $self->getPageRow();
            my $vhost = $q->virtual_host();
            my $sendmail = $self->getSenderEmail();
            my $nmailer = NMailer->mynew();
            $nmailer->add('from',$sendmail);
            $nmailer->add('to',$mail);
            $nmailer->add('subject','На Ваш вопрос поступил ответ.');
    
   
            $nmailer->set_plain_part(
                'На размещенный Вами вопрос на сайте http://'.$vhost.' поступил ответ.'."\n".'Для просмотра ответа можете перейти по ссылке http://'.$vhost.$page_row->{'url'}.' .'
            );
    
            $nmailer->send_to_list($mail);	
        };
    };
    return NG::Block::M_OK;
}; 

1;

package NG::SiteModule::Faq::Emails;
use strict;
use NGService;
use NSecure;
use NG::Module::List;
use vars qw(@ISA);
@ISA = qw(NG::Module::List);


sub config {
	my $self = shift;
	$self->tablename('faq_emails');
	$self->fields(
		{'FIELD'=>'id', 'TYPE'=>'id', 'IS_NOTNULL'=>1},
		{'FIELD'=>'page_id', 'TYPE'=>'pageId', 'IS_NOTNULL'=>1 },
		{'FIELD'=>'mail', 'TYPE'=>'email', 'NAME'=>'E-mail', 'IS_NOTNULL'=>1},
	);
	
	$self->listfields([
		{'FIELD'=>'mail'},
	]);
	
	$self->formfields(
		{'FIELD'=>'id'},
		{'FIELD'=>'mail'},
	);
};
	
1;

=comment
mysql
create table faq (
	id int not null primary key auto_increment,
	page_id int not null,
	q_name varchar(255) not null,
	q_mail varchar(255) not null,
	q_text text not null,
	q_date timestamp not null default CURRENT_TIMESTAMP,
	a_name varchar(255),
	a_text text,
	a_date timestamp,
	is_show tinyint not null default 0
);

create table faq_emails (
	id int not null primary key auto_increment,
	page_id int not null,
	mail varchar(255)
);

pgsql
create table faq (
	id serial not null primary key,
	page_id int not null,
	q_name varchar(255) not null,
	q_mail varchar(255) not null,
	q_text text not null,
	q_date timestamp with time zone not null default CURRENT_TIMESTAMP,
	a_name varchar(255),
	a_text text,
	a_date timestamp  with time zone,
	is_show smallint not null default 0
);

create table faq_emails (
	id  serial not null primary key,
	page_id int not null,
	mail varchar(255)
);
=cut