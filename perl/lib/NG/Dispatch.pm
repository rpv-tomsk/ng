package NG::Dispatch;

use strict;
use NGService;
use NSecure;
use NG::Form;
use NHtml;
use NG::DBlist;
use NG::Module;
use NMailer;
use NG::Module::List;
use NG::DBlist;
use URI::Escape;
use Data::Dumper;

use vars qw(@ISA);


use constant DISPATCH_SEND_DESCRIBE_LETTER  => 0;
use constant DISPATCH_SEND_UNDESCRIBE_LETTER	=> 1;
use constant DISPATCH_DESCRIBE_APPLY => 3;
use constant DISPATCH_UNDESCRIBE_APPLY => 4;
use constant DISPATCH_NONE => 5;
use constant DISPATCH_ERROR_EMAIL => 6;
use constant DISPATCH_ERROR_SUBSCRIBE => 7;
use constant DISPATCH_ERROR_UNSUBSCRIBE => 8;

sub AdminMode {
    use NG::Module::List;
    @ISA = qw(NG::Module::List);
};

sub FaceMode {
    use NG::Face;
    @ISA = qw(NG::Face);
};

sub init {
	my $self = shift;
	$self->SUPER::init(@_);
	$self->{_subject} = "";
	$self->{_frommail} = "";
	$self->{_subscribe_apply_template} = "admin-side/dispatch/subscribe_apply_template.tmpl";
	$self->{_unsubscribe_apply_template} = "admin-side/dispatch/unsubscribe_apply_template.tmpl";
	$self->{_content_congif} = [];
	$self->configDispatch();
};

sub setSubscribeApplyTemplate {
	my $self = shift;
	$self->{_subscribe_apply_template} = shift;
};


sub setUnsubscribeApplyTemplate {
	my $self = shift;
	$self->{_unsubscribe_apply_template} = shift;
};

sub config {
	my $self = shift;
	
    $self->{_table} = "dispatches";
    $self->{_contentadmin_template} = "admin-side/dispatch/contentadmin.tmpl";
    $self->fields(
        {FIELD=>'id',  	     TYPE=>'id',   NAME=>'Код'},
        {FIELD=>'create_date',      TYPE=>'datetime', NAME=>'Дата создания'},
        {FIELD=>'last_send_date',      TYPE=>'datetime', NAME=>'Дата последней рассылки'},
        {FIELD=>'plain', TYPE=>'textarea',NAME=>'Текстовая часть письма'},
        {FIELD=>'html', TYPE=>'rtf', NAME=>'HTML часть письма',
			OPTIONS=>{
				IMG_TABLE=>"dispatch_images",
				IMG_UPLOADDIR => "upload/dispatch/rtf/",
				IMG_TABLE_FIELDS_MAP => {id=>"parent_id"}
			}                	
        }
      );
    
    # Списковая
    $self->listfields([
        {FIELD=>'_counter_',NAME=>"№"},
        {FIELD=>'create_date'},
        {FIELD=>'last_send_date'},
    ]);
    
    # Формовая часть
    $self->formfields(
        {FIELD=>'id'},
        {FIELD=>'plain'},
        {FIELD=>'html'},
    );
  
    $self->order({FIELD=>"create_date",DEFAULT=>1 ,DEFAULTBY=>"desc"});
	
    $self->setSubmodules(
        {URL=>"emails/",MODULE=>"NG::Dispatch::Emails"},
    );
    
    $self->register_action("send","Send");
    $self->add_links("Разослать",$self->getBaseURL()."?action=send&id={id}",0);
    $self->{_content_config} = $self->contentConfig();
    if (scalar @{$self->{_content_config}}) {
    	$self->add_links("Сформировать",$self->getBaseURL()."?action=content&dispatch_id={id}",1);
    	$self->register_action("content","Content");
    	$self->register_action("addtodispatch","addToDispatch");
    	$self->register_action("deletedispatch","deleteDispatch");
    	$self->register_action("movedispatch","moveDispatch");
    	$self->register_action("formatdispatch","formatDispatch");
    	$self->{_hash_content_config} = {};
    	foreach my $conf (@{$self->{_content_config}}) {
    		$self->{_hash_content_config}->{$conf->{CODE}} = $conf;	
    	};
    };
};


sub Content {
	my $self = shift;
	my $action = shift;
	my $is_ajax = shift;
	my $dispatch_id = $self->q()->param("dispatch_id");
    my $u = $self->q()->url(-query=>1); # для возврата в исходную страницу 
    $u =~ s/_ajax=1//;          # после действий со списком
	
	my $dlist = $self->_createDispatchList() or return $self->error("Cat create object NG::Module::List for dispatch list");
	$dlist->opentemplate($self->{_contentadmin_template});
	my $ret = $dlist->buildList();
	
	if ($ret != NG::Module::M_OK) {
		return $self->error($dlist->getError());
	};
	
	if (ref $dlist->tmpl()->param("DATA") eq "ARRAY") {
		foreach my $item (@{$dlist->tmpl()->param("DATA")}) {
			$item->{DISPATCHID} = $dispatch_id;
		};
	};
	
	my $sth = $self->db()->dbh()->prepare("select needupdate from dispatches where id=?") or return $self->error($DBI::errstr);
	$sth->execute($dispatch_id) or return $self->error($DBI::errstr);
	my ($needupdate) = $sth->fetchrow();
	$sth->finish();

	my @clists = $self->_createDispatchContentList();
	
    $dlist->tmpl()->param(
        DISPATCHID  => $dispatch_id,
        CONTENTDATA => \@clists,
        SELF_URL    => $u,
        IS_AJAX     => $is_ajax,
        BASEURL     => $self->getBaseURL(),
        NEEDUPDATE  => $needupdate,
        REF         => scalar $self->q->param('ref') || $self->getBaseURL(),
    );
	
	$self->output($dlist->tmpl()->output());
};


sub _createDispatchList {
	my $self = shift;
	my $dispatchlist = NG::Module::List->new($self->app());
	my $dispatch_id = $self->q()->param("dispatch_id");
	return undef if (!is_valid_id($dispatch_id));
	
	$dispatchlist->tablename("dispatch_content");
	$dispatchlist->fields(
		{FIELD=>'id',  	     TYPE=>'id',   NAME=>'Код'},
		{FIELD=>'name',  	 TYPE=>'text',   NAME=>'Тип'},
		{FIELD=>'header',  	 TYPE=>'text',   NAME=>'Заголовок'},
		{FIELD=>"dispatch_id", TYPE=>"fkparent", VALUE=>$dispatch_id},
		{FIELD=>"content_id", TYPE=>"hidden"},
		{FIELD=>"position", TYPE=>"posorder",NAME=>"Позиция", WIDTH=>"80px;"},
		{FIELD=>"code", TYPE=>"text",NAME=>"Код"},
	);
	$dispatchlist->listfields({FIELD=>"id"},{FIELD=>"name"},{FIELD=>"header"},);
	$dispatchlist->formfields({FIELD=>"id"},{FIELD=>"name"},{FIELD=>"header"},{FIELD=>"content_id"},{FIELD=>"code"},);
    $dispatchlist->disablePages();
 	$dispatchlist->_analyseFieldTypes();
	return $dispatchlist;
};

sub _createDispatchContentList {
	my $self = shift;
	my $q = $self->q();
	my $myurl = $q->url();
	my $dispatch_id = $q->param("dispatch_id");
	return undef if (!is_valid_id($dispatch_id));
    my $u = $self->q()->url(-query=>1); # для возврата в исходную страницу 
    $u =~ s/_ajax=1//;          # после действий со списком
    $u = uri_escape($u);	
	my @dblists = ();
	foreach my $conf (@{$self->{_content_config}}){
	    my $dblist = NG::DBlist->new(
	        db     => $self->db(),
	        table  => $conf->{TABLE}." t left join dispatch_content c on (t.".$conf->{IDFIELD}."=c.content_id and c.code=? and c.dispatch_id=?)",
	        fields => "c.content_id as hasin,t.".$conf->{NAMEFIELD}." as name,t.".$conf->{IDFIELD}." as id",
	        where  => $conf->{WHERE},
	        order  => $conf->{ORDER},
	        pagename=>"page".$conf->{CODE},
	        page   => is_valid_id($q->param("page".$conf->{CODE}))?$q->param("page".$conf->{CODE}):1,
	        onpage => $conf->{ONPAGE},
	        onlist => $conf->{ONLIST},
	        url    => getURLWithParams($myurl,$self->getDispatchContentPagesParam($conf->{CODE}),"dispatch_id=".$dispatch_id,"action=content","ref=".$u),
	    );
	    $dblist->open($conf->{CODE},$dispatch_id,@{$conf->{PARAMS}});
	    my $data = $dblist->data();
	    my $pages = $dblist->pages();
	    push @dblists, {DATA=>$data,PAGES=>$pages,LISTNAME=>$conf->{LISTNAME},CODE=>$conf->{CODE}} if (scalar @{$data});
	};	
	return @dblists;
};

sub getDispatchContentPagesParam {
	my $self = shift;
	my $q = $self->q();
	my $code = shift;
	my @params = ();
	foreach my $conf (@{$self->{_content_config}}){
		if ($conf->{CODE} ne $code) {
			push @params, "page".$conf->{CODE}."=".(is_valid_id($q->param("page".$conf->{CODE}))?$q->param("page".$conf->{CODE}):1);
		};
	};
	return @params;
};

sub contentConfig {
	return [];
};

sub getModuleTabs {
	my $self = shift;
	my $header = [
		{HEADER=>"Рассылка",URL=>"/"},
		{HEADER=>"Список подписчиков",URL=>"/emails/"},
	];
	return $header;
};


sub sendSubscribeApplyLetter {
	my $self = shift;
	my $q = $self->q();
	my $email = shift;
	my $session = shift;
	my $site = "http://".$q->virtual_host();
	
	my $template = $self->{_template};

	$self->opentemplate($self->{_subscribe_apply_template});
	$self->tmpl()->param(site=>$site,session=>$session,email=>$email);
	
	my $mailer = NMailer->mynew();
	$mailer->add("subject","Подтверждение подписки ".$email." на сайте ".$site);
	$mailer->add("from",$self->frommail());
	$mailer->add("to",$email);
	$mailer->set_plain_part($self->tmpl()->output());
	$mailer->send_to_list($email);
	
	$self->{_template} = $template;
};

sub sendUnsubscribeApplyLetter {
	my $self = shift;
	my $q = $self->q();
	my $email = shift;
	my $session = shift;
	my $site = "http://".$q->virtual_host();
	
	my $template = $self->{_template};	

	$self->opentemplate($self->{_unsubscribe_apply_template});
	$self->tmpl()->param(site=>$site,session=>$session,email=>$email);
	
	my $mailer = NMailer->mynew();
	$mailer->add("subject","Подтверждение прекращения рассылки на адрес ".$email." на сайте ".$site);
	$mailer->add("from",$self->frommail());
	$mailer->add("to",$email);
	$mailer->set_plain_part($self->tmpl()->output());
	$mailer->send_to_list($email);
	
	$self->{_template} = $template;
};

# Подписка отписка принимает параметры code и email
sub subscribeEmail {
	my $self = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my $email = $q->param("email");
	my $code = $q->param("code");
	my $sth = undef;
	my $emailrecord = undef;
	return DISPATCH_ERROR_EMAIL if ((!is_valid_email($email)) && is_empty($code));
	if (!is_empty($email) && is_empty($code)) {
		
		$sth = $dbh->prepare("select id,email,subscribe_apply,unsubscribe_question,key from dispatch_emails where email=?") or die $DBI::errstr;
		$sth->execute($email) or die $DBI::errstr;
		$emailrecord  = $sth->fetchrow_hashref();
		$sth->finish();
		
		if (!$emailrecord) { #Если новый емаил на подписку
			my $id = $self->db()->get_id("dispatch_emails");
			die $self->db()->errstr() unless $id;
			my $session = generate_session_id();
			$dbh->do("insert into dispatch_emails (id,email,key) values(?,?,?)",undef,$id,$email,$session) or die $DBI::errstr;
			$self->sendSubscribeApplyLetter($email,$session);
			return DISPATCH_SEND_DESCRIBE_LETTER;
		} elsif ($emailrecord->{subscribe_apply}==1 && $emailrecord->{unsubscribe_question} == 0) { #Если емаил на отписку
			my $session = generate_session_id();
			$dbh->do("update dispatch_emails set unsubscribe_question=1,key=? where id=?",undef,$session,$emailrecord->{id}) or die $DBI::errstr;
			$self->sendUnsubscribeApplyLetter($email,$session);
			return DISPATCH_SEND_UNDESCRIBE_LETTER;
		} elsif($emailrecord->{subscribe_apply}==0) {
			return DISPATCH_ERROR_SUBSCRIBE;
		} elsif($emailrecord->{unsubscribe_question}==1) {
			return DISPATCH_ERROR_UNSUBSCRIBE;
		};
	} elsif (is_valid_email($email) && !is_empty($code)) {
		$sth = $dbh->prepare("select id,email,subscribe_apply,unsubscribe_question,key from dispatch_emails where key=? and email=?") or die $DBI::errstr;
		$sth->execute($code,$email) or die $DBI::errstr;
		$emailrecord  = $sth->fetchrow_hashref();
		$sth->finish();
		if ($emailrecord) { #пришло подтверждение отписки емайла
			if ($emailrecord->{unsubscribe_question} == 1) {
				$dbh->do("delete from dispatch_emails where id=?",undef,$emailrecord->{id}) or die $DBI::errstr;
				return DISPATCH_UNDESCRIBE_APPLY;
			} else {#пришло подтверждение подписки емайла
				$dbh->do("update dispatch_emails set subscribe_apply=1,key='' where id=?",undef,$emailrecord->{id}) or die $DBI::errstr;
				return DISPATCH_DESCRIBE_APPLY;
			};
		};
	};
	return DISPATCH_NONE;
};

sub Send {
	my $self = shift;
	my $action = shift;
	my $is_ajax = shift;
	my $q = $self->q();
	my $dbh = $self->dbh();
	my $sth = undef;
	my $ref = $q->param("ref");
	
	my $id = $q->param("id");
	if (is_valid_id($id)) {
		$sth = $dbh->prepare("select * from dispatches where id=?") or return $self->error($DBI::errstr);
		$sth->execute($id) or return $self->error($DBI::errstr);
		my ($dispatch) = $sth->fetchrow_hashref();
		$sth->finish();
		if ($dispatch) {
			my @emails = $self->_getSubscribersEmails();
			foreach my $email (@emails) {
				my $mailer = NMailer->mynew();
				$mailer->add("subject",$self->subject());
				$mailer->add("from",$self->frommail());				
				$mailer->add("to",$email);
				$mailer->set_plain_part($self->prepareMessageBeforeSend(message=>$dispatch->{plain},mode=>"text",email=>$email));
				$mailer->set_html_part($self->prepareMessageBeforeSend(message=>$dispatch->{html},mode=>"html",email=>$email),$self->getDocRoot());
				$mailer->send_to_list($email);
			};
			$dbh->do("update dispatches set last_send_date=now() where id=?",undef,$id) or return $self->error($DBI::errstr);
		};
	};
	return $self->redirect($ref);
};

sub prepareMessageBeforeSend {
	my $self = shift;
	my %args = (@_);
	my $message = $args{message};
	my $mode = $args{mode} || "text";
	return $message;
};

sub _getSubscribersEmails {
	my $self = shift;
	my $dbh = $self->db()->dbh();
	my $sth = $dbh->prepare("select email from dispatch_emails where subscribe_apply=1 order by id") or die $DBI::errstr;
	$sth->execute() or die $DBI::errstr;
	my @result = ();
	while (my ($row) = $sth->fetchrow()) {
		push @result, $row;
	};
	$sth->finish();
	return wantarray ? @result: \@result;
};

sub subject {
	my $self = shift;
	my $subject = shift;
	if (!is_empty ($subject)) {
		$self->{_subject} = $subject;
	};
	$self->{_subject};
};

sub frommail {
	my $self = shift;
	my $frommail = shift;
	if (is_valid_email ($frommail)) {
		$self->{_frommail} = $frommail;
	};
	$self->{_frommail};
};

sub addToDispatch {
	my $self = shift;
	my $action = shift;
	my $is_ajax = shift;
	my $q = $self->q();
	my $dispatch_id = $q->param("dispatch_id");
	my $dbh = $self->dbh();
	my $conf = $self->{_hash_content_config}->{$q->param("content")};
	my $container = $q->param("_container");
	my $ref = $q->param("ref");
	$ref = getURLWithParams($ref,"_ajax=1");		
	
	my $id = $self->db()->get_id("dispatch_content");
	die $self->db()->errstr() unless $id;
	$q->param("id",$id);
	$q->param("name",$conf->{NAME});
	$q->param("code",$q->param("content"));
	
	if (is_valid_id($q->param("content_id"))) {
		my $sth = $dbh->prepare("select ".$conf->{NAMEFIELD}." from ".$conf->{TABLE}." where ".$conf->{IDFIELD}."=?") or retunr $self->error($DBI::errstr);
		$sth->execute($q->param("content_id")) or retunr $self->error($DBI::errstr);
		my ($header) = $sth->fetchrow();
		$sth->finish();
		$q->param("header",$header);
	};
	
	$q->param("formaction","insert");
	my $dlist = $self->_createDispatchList();
	my $ret = $dlist->processForm("formaction",$is_ajax);
	$dbh->do("update dispatches set needupdate=1 where id=?",undef,$dispatch_id) or return $self->error($DBI::errstr);
	
	if (!is_empty($container)) {
		if ($ret == NG::Module::M_ERROR) {
			return $self->error($dlist->getError());
		} else {
			return $self->output("<script>parent.ajax_url('$ref','$container');</script>");
		};
	} else {
		if ($ret == NG::Module::M_ERROR) {
			return $self->error($dlist->getError());
		} elsif ($ret == NG::Module::M_OK) {
			return $self->output($dlist->getOutput());
		} elsif ($ret == NG::Module::M_REDIRECT) {
			$self->redirect($dlist->getRedirectUrl());
		};		
	};
};


sub deleteDispatch {
	my $self = shift;
	my $action = shift;
	my $is_ajax = shift;
	my $q = $self->q();
	my $dispatch_id = $q->param("dispatch_id");
	my $dbh = $self->dbh();
	my $conf = $self->{_hash_content_config}->{$q->param("content")||""};
	my $container = $q->param("_container");
	my $ref = $q->param("ref");
	$ref = getURLWithParams($ref,"_ajax=1");	

	my $dlist = $self->_createDispatchList();
	my $ret = $dlist->Delete("deletefull",$is_ajax);
	$dbh->do("update dispatches set needupdate=1 where id=?",undef,$dispatch_id) or return $self->error($DBI::errstr);
	
	if (!is_empty($container)) {
		if ($ret == NG::Module::M_ERROR) {
			return $self->error($dlist->getError());
		} else {
			return $self->output("<script>parent.ajax_url('$ref','$container');</script>");
		};
	} else {
		if ($ret == NG::Module::M_ERROR) {
			return $self->error($dlist->getError());
		} elsif ($ret == NG::Module::M_OK) {
			return $self->output($dlist->getOutput());
		} elsif ($ret == NG::Module::M_REDIRECT) {
			$self->redirect($dlist->getRedirectUrl());
		};		
	};
};

sub moveDispatch {
	my $self = shift;
	my $action = shift;
	my $is_ajax = shift;
	my $q = $self->q();
	my $dbh = $self->dbh();
	my $dispatch_id = $q->param("dispatch_id");
	my $conf = $self->{_hash_content_config}->{$q->param("content")};
	my $container = $q->param("_container");
	my $ref = $q->param("ref");
	$ref = getURLWithParams($ref,"_ajax=1");
	
	
	my $dlist = $self->_createDispatchList();
	my $ret = $dlist->Move($is_ajax);
	$dbh->do("update dispatches set needupdate=1 where id=?",undef,$dispatch_id) or return $self->error($DBI::errstr);
	
	if (!is_empty($container)) {
		if ($ret == NG::Module::M_ERROR) {
			return $self->error($dlist->getError());
		} else {
			return $self->output("<script>parent.ajax_url('$ref','$container');</script>");
		};
	} else {
		if ($ret == NG::Module::M_ERROR) {
			return $self->error($dlist->getError());
		} elsif ($ret == NG::Module::M_OK) {
			return $self->output($dlist->getOutput());
		} elsif ($ret == NG::Module::M_REDIRECT) {
			$self->redirect($dlist->getRedirectUrl());
		};		
	};
};

sub formatDispatch {
	my $self = shift;
	my $q = $self->q();
	my $container = $q->param("_container");
	my $ref = $q->param("ref");
	
	my $dbh = $self->db()->dbh();
	my $dispatch_id = $q->param("dispatch_id");
	my $sth = undef;

	my %data = ();
	my $tdata = [];
	if (is_valid_id($dispatch_id)) {
		foreach my $conf (@{$self->{_content_config}}) {
			$sth = $dbh->prepare("select ".$conf->{CONTENTFIELDS}." from ".$conf->{TABLE}." where ".$conf->{IDFIELD}." in (select content_id from dispatch_content where dispatch_id=? and code=?)") or return $self->error($DBI::errstr);
			$sth->execute($dispatch_id,$conf->{CODE}) or return $self->error($DBI::errstr);
			while (my $row = $sth->fetchrow_hashref()) {
				$row->{"TYPE".$conf->{CODE}} = 1;
				$data{$conf->{CODE}.$row->{$conf->{IDFIELD}}} = $row;
			};
			$sth->finish();
		};
	
		$sth = $dbh->prepare("select code,content_id from dispatch_content where dispatch_id=? order by position") or return $self->error($DBI::errstr);		
		$sth->execute($dispatch_id) or return $self->error($DBI::errstr);
		while (my $row = $sth->fetchrow_hashref()) {
			push @{$tdata}, $data{$row->{code}.$row->{content_id}};
		};
		$sth->finish();
		my ($text,$html) = $self->createDispatchText($tdata); # Передаем структуру данных по которой будет формироваться выходной текст
		
		$dbh->do("update dispatches set needupdate=0,plain=?,html=? where id=?",undef,$text,$html,$dispatch_id) or return $self->error($DBI::errstr);
	} else {
		retunr $self->error("Ошибка: нет такой рассылки");
	};
	
	if (!is_empty($container)) {
		$ref = getURLWithParams($ref,"_ajax=1");
		return $self->output("<script>parent.ajax_url('$ref','$container');</script>");
	} else {
		return $self->redirect($ref);	
	};	
};


sub createDispatchText { #ovveride by user
};

sub configDispatch { #ovveride by user
};





return 1;