package NG::Polls;
use strict;
use NG::PageModule;
use Date::Simple;
use NSecure;
use NGService;
our @ISA = qw(NG::PageModule);

use Data::Dumper;

sub getActiveBlock {
	my $self = shift;
	my $q = $self->q();
	return {BLOCK=>"FULL"} if $q->param("id");
	return {BLOCK=>"LIST"};
};

sub moduleTabs {
    return [
        {HEADER=>"������",URL=>"/"}
    ];
};

sub moduleBlocks {
    return [
        {BLOCK=>"NG::Polls::List" ,URL=>"/"}
    ];
};

sub fields {
    return [];
}; 

sub formfields {
    return [];
};

sub listfields {
    return [];
};

sub voteHandlers {
    return [
        {CANVOTE=>'checkIP_check'},
    ];
};

sub checkIP_check {
    my ($self,$voting) = (shift,shift);
    
    my $dbh  = $self->dbh();
    my $q  = $self->q();
    
    return unless $voting->{check_ip} && $voting->{active} && $voting->{can_vote};

    my $sth = $dbh->prepare("select count(*) from polls_ip where ip=? and polls_id=?") or return undef;
    $sth->execute($q->remote_host(),$voting->{id}) or undef;
    my ($count) = $sth->fetchrow();
    $sth->finish();
    $voting->{can_vote} = 0 if $count>0;
};

sub _runHandler {
    my ($self,$voting,$handler) = (shift,shift,shift);
    my $VH = $self->voteHandlers($handler);
    
    foreach my $h (@$VH) {
        my $m = $h->{$handler} or next;
        $self->$m($voting);
    };
};

sub keys_SLIDER {
    my $self = shift;
    
    my $cms = $self->cms();
    my $q  = $self->q();
    my $req = {};
    
    my $anyPollVersion = $cms->getKeysVersion($self,{key=>'anyvoting'});
    if ($anyPollVersion && $anyPollVersion->[0]) {  #����������� ��������
        my $sliderItems = $cms->getCacheData($self,{key=>'sliderItems_'.$anyPollVersion->[0]});
        unless ($sliderItems) {
            $sliderItems = $self->dbh()->selectall_arrayref("SELECT id,visible,check_ip FROM polls WHERE rotate=1 AND (start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW()))",{Slice => {}});
            $cms->setCacheData($self,{key=>'sliderItems_'.$anyPollVersion->[0]},$sliderItems);
        };
        
        $req->{today} = Date::Simple->new()->as_iso();
        $req->{items} = {};  #�������� ������������ ���������
        
        foreach my $si (@$sliderItems) {
            my $voting = {
                id       => $si->{id},
                visible  => $si->{visible},
                check_ip => $si->{check_ip},
                can_vote => 1,
                active   => 1,
            };
            
            $self->_runHandler($voting,'CANVOTE');
            
            next unless $voting->{can_vote} || $voting->{visible};
            
            $req->{items}->{$voting->{id}} = {
                visible  => $voting->{visible},
                can_vote => $voting->{can_vote},
            };
        };
    };
    return {REQUEST=>$req};
};

sub block_SLIDER {
    my ($self,$action,$keys) = (shift,shift,shift);
    
    my $cms = $self->cms();
    my $dbh = $self->dbh();
    #my $baseURL = $self->getBaseURL();
    
    
    my $sql = "select p.id,p.question,p.multichoice,p.vote_cnt,p.start_date,p.end_date,p.visible,p.check_ip FROM polls p WHERE rotate=1 AND (start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW())) ORDER BY start_date DESC";
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    
    my @polls = ();
    while (my $voting = $sth->fetchrow_hashref()) {
        $voting->{active}   = 1;
        
        if ($keys->{REQUEST}->{items}) {
            #��� ����.
            next unless exists $keys->{REQUEST}->{items}->{$voting->{id}};
        }
        else {
            #���� ���
            $voting->{can_vote} = 1;
            $self->_runHandler($voting,'CANVOTE');
            
            next unless $voting->{can_vote} || $voting->{visible};
        };
        
        $self->_loadVoting($voting);
        $self->_loadAnswers($voting);
        next unless @{$voting->{answers}};
        
        push @polls,$voting;
    };
    
    return $cms->output('') unless @polls;
    
	my $template = $self->gettemplate("public/polls/slider.tmpl");
	$template->param(
        SLIDER=>\@polls,
	);
	return $cms->output($template);
};

sub _loadVoting {
    my ($self,$voting) = (shift,shift);
    
    my $db = $self->db();
    
    $voting->{db_start_date} = $voting->{start_date};
    $voting->{db_end_date}   = $voting->{end_date};
    $voting->{start_date}    = $db->date_from_db($voting->{start_date});
    $voting->{end_date}      = $db->date_from_db($voting->{end_date});
    
    my ($sdate,$edate);
    $sdate = Date::Simple->new($voting->{db_start_date});
    $edate = Date::Simple->new($voting->{db_end_date}) if $voting->{db_end_date};
    my $today = Date::Simple::today();
    $edate ||= $today;
    
    $voting->{active} = ($sdate<=$today && $edate>=$today)?1:0;
    $voting;
};

sub _loadAnswers {
    my ($self,$voting) = (shift,shift);
    
	my $answers = $self->dbh->selectall_arrayref("SELECT a.id,a.polls_id,a.answer,a.def,a.vote_cnt FROM polls_answers a WHERE a.polls_id=? ORDER BY a.id",{Slice=>{}},$voting->{id});
    die $DBI::errstr unless defined $answers;
    
    $voting->{answers} = [];
    
    foreach (@$answers) {
        push @{$voting->{answers}}, {
            id       => $_->{id},
            answer   => $_->{answer},
            def      => $_->{def},
            vote_cnt => $_->{vote_cnt},
            vote_cnt_percent      => !$voting->{vote_cnt}?0:sprintf("%.2f",($_->{vote_cnt}/$voting->{vote_cnt})*100),
            vote_cnt_percent_show => !$voting->{vote_cnt}?0:sprintf("%d",  ($_->{vote_cnt}/$voting->{vote_cnt})*100),
        };
    };
};

sub block_ONMAIN {
	my $self = shift;
	my $cms = $self->cms();
	my $dbh = $self->dbh();
	my $db = $self->db();

    my $random_function = $db->isa('NG::DBI::Mysql')? 'rand' : 'random';

	my ($poll_id) = $dbh->selectrow_array("select id from polls WHERE rotate=1 AND (start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW())) ORDER BY ".$random_function."() limit 1",undef);
	my $poll = undef;
	$poll = $self->_loadPoll($poll_id) if (is_valid_id($poll_id));
	my $template = $self->gettemplate("public/polls/onmain.tmpl") or return $cms->error();
	$template->param(
		POLL => $poll,
		URL => $self->getBaseURL(),
	);
	return $cms->output($template);
};

sub _loadPoll {
	my ($self,$id) = (shift,shift);
	
	my $dbh = $self->dbh();
	my $db = $self->db();
	my $q = $self->q();
	
	my $answers = $dbh->selectall_arrayref("select a.id,a.polls_id,a.answer,a.def,a.vote_cnt,p.question,p.multichoice,p.vote_cnt as total_vote_cnt,p.start_date,p.end_date,p.visible,p.check_ip from polls_answers a,polls p where p.id=? and a.polls_id=p.id order by a.id",{Slice=>{}},$id);
	my $poll = undef;
	if (defined $answers and ref $answers eq 'ARRAY' && scalar @$answers) {
		$poll = {
			id => ${$answers}[0]->{polls_id},
			question => ${$answers}[0]->{question},
			vote_cnt => ${$answers}[0]->{total_vote_cnt},
			visible => ${$answers}[0]->{visible},
			check_ip => ${$answers}[0]->{check_ip},
			multichoice => ${$answers}[0]->{multichoice},
			db_start_date => ${$answers}[0]->{start_date},
			db_end_date => ${$answers}[0]->{end_date},
			start_date => $db->date_from_db(${$answers}[0]->{start_date}),
			end_date => $db->date_from_db(${$answers}[0]->{end_date}),
			active => 0,
			canvote => 0,
			answers => []
		};
		foreach (@$answers) {
			push @{$poll->{answers}},{
				id => $_->{id},
				answer => $_->{answer},
				def => $_->{def},
				vote_cnt => $_->{vote_cnt},
				vote_cnt_percent => !$poll->{vote_cnt}?0:sprintf("%.2f",($_->{vote_cnt}/$poll->{vote_cnt})*100),
				vote_cnt_percent_show => !$poll->{vote_cnt}?0:sprintf("%d",($_->{vote_cnt}/$poll->{vote_cnt})*100),
			};
		};
		my $sdate = Date::Simple->new($poll->{db_start_date});
		my $edate = Date::Simple::today();
		$edate = Date::Simple->new($poll->{db_end_date}) if $poll->{db_end_date};
		my $today = Date::Simple::today();
		
		$poll->{active} = ($sdate<=$today && $edate>=$today)?1:0;
		
		$poll->{canvote} = $poll->{active} eq "0"?0:1;
		if($poll->{canvote} == 1 && $poll->{check_ip}) {
			my $sth = $dbh->prepare("select count(*) from polls_ip where ip=? and polls_id=?") or return undef;
			$sth->execute($q->remote_host(),$poll->{id}) or undef;
			my ($count) = $sth->fetchrow();
			$sth->finish();
			$poll->{canvote}=0 if $count>0;
		};
	}
	else {
		$poll = undef;
	};
	
	return $poll;
};

sub processModulePost {
	1;
};

sub _vote {
	my $self = shift;
	my $poll = shift;
	my $q = $self->q();

	my @answers = $q->param("answer");
	
	my $errors = {};
	my $ret = 1;

	unless ($poll->{active}) {
		$ret = 0;
		$errors->{no_active} = 1;
	};
	
	unless (scalar @answers) {
		$ret = 0;
		$errors->{no_answers} = 1;
	};
	
	if ($poll->{active} && $poll->{check_ip} && !$poll->{canvote}) {
		$ret = 0;
		$errors->{same_ip} = 1;		
	};
	
	if (!scalar keys %$errors && scalar @answers) {
		my $sth_insert = $self->db()->dbh()->prepare("update polls_answers set vote_cnt=vote_cnt+1 where id=? and polls_id=?") ;
		foreach (@answers)
		{
			if(is_valid_id($_)) 
			{
				$sth_insert->execute($_,$poll->{id});
				$poll->{vote_cnt} = $poll->{vote_cnt} + 1;
			};
		};
		$sth_insert->finish();
		$self->db()->dbh()->do("update polls set vote_cnt=? where id=?",undef,$poll->{vote_cnt},$poll->{id}) or die $DBI::errstr;
		$self->db()->dbh()->do("insert into polls_ip(polls_id,ip) values(?,?)",undef,$poll->{id},$self->q()->remote_host()) or die $DBI::errstr; 
	};
	
	return wantarray?($ret,$errors):$ret;
};

package NG::Polls::List;
use strict;
use NGService;
use NSecure;
use NG::DBlist;
use URI::Escape;
use POSIX;

use NG::Module::List;
our @ISA = qw(NG::Module::List);

sub config  {
    my $self = shift;
    $self->{_table} = "polls";
    $self->{_pageBlockMode} = 1;
    
    my $m = $self->getModuleObj();
    
    my $fields     = $m->fields();
    my $formfields = $m->formfields();
    my $listfields = $m->listfields();
    
    $self->fields(
        {FIELD=>'id',         TYPE=>'id',     NAME=>'��� ������'},
        {FIELD=>'question',   TYPE=>'text',   NAME=>'����� �������', IS_NOTNULL=>1},
        {FIELD=>'start_date', TYPE=>'date',   NAME=>'���� ������ (��.��.����)',   IS_NOTNULL=>1,DEFAULT=>current_date()},
        {FIELD=>'end_date',   TYPE=>'date',   NAME=>'���� ��������� (��.��.����)'},
        {FIELD=>'visible',    TYPE=>'checkbox', NAME=>'���������� ����������', IS_NOTNULL=>0,},
        {FIELD=>'rotate',     TYPE=>'checkbox', NAME=>'����������',IS_NOTNULL=>0},
        {FIELD=>'check_ip',   TYPE=>'checkbox', NAME=>'��������� IP',         IS_NOTNULL=>0},
        {FIELD=>'multichoice',TYPE=>'checkbox', NAME=>'��������� ���������',  IS_NOTNULL=>0},
        {FIELD=>'vote_cnt',   TYPE=>'number', NAME=>'���������� ����������',  IS_NOTNULL=>1,READONLY=>1,DEFAULT=>0},
        @$fields
    );
    # ���������
    $self->listfields([
        {FIELD=>'_counter_',NAME=>"�"},
        {FIELD=>'question',},
        {FIELD=>'start_date',},
        {FIELD=>'end_date',},
        {FIELD=>'rotate', CLICKABLE=>1},
        @$listfields
    ]);
    # �������� �����
    $self->formfields(
        {FIELD=>'id'},
        {FIELD=>'question'},
        {FIELD=>'start_date'},
        {FIELD=>'end_date'},
        {FIELD=>'visible'},
        {FIELD=>'rotate'},
        {FIELD=>'check_ip'},
        {FIELD=>'multichoice'},
        @$formfields
    );
    
	$self->filter(
		NAME  => "������:",
		TYPE  => "tabs",
		VALUES=> [
            {NAME=>"��� ������", WHERE=>""},
			{NAME=>"����������", WHERE=>"rotate=1 AND (start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW()))"},
		],
	);
    
	$self->addRowLink({NAME=>'�������� ������',URL=>'?action=showanswers&poll_id={id}',AJAX=>1});
	$self->register_action('showanswers',"showOrUpdateAnswers");
	$self->register_action('updateanswers',"showOrUpdateAnswers");
	$self->register_action('addanswer',"showOrUpdateAnswers");
    $self->register_action('deleteanswer',"deleteAnswer");
    $self->order({FIELD=>"start_date",DEFAULT=>1,DEFAULTBY=>"DESC",ORDER_ASC=>"start_date asc,id desc",ORDER_DESC=>"start_date desc,id desc"});
    
    $self->updateKeysVersion([
        {key=>'voting', id => '{id}'},
        {key=>'anyvoting'},
    ]);
    
    $m->configList($self) if $m->can('configList');
};

sub beforeDelete {
    my ($self,$id)=(shift,shift);
    
    my $dbh=$self->dbh();
    my $sql="delete from polls_ip where polls_id=?";
    $dbh->do($sql,undef,$id) or return $self->error("������ �������� �������: ".$DBI::errstr);
    $sql="delete from polls_answers where polls_id=?";
    $dbh->do($sql,undef,$id) or return $self->error("������ �������� �������: ".$DBI::errstr);
    $sql="delete from polls_ip where polls_id=?";
    $dbh->do($sql,undef,$id) or return $self->error("������ �������� �������: ".$DBI::errstr);
    return NG::Block::M_OK;
};


sub deleteAnswer {
	my $self = shift;
	my $action = shift;
    my $is_ajax = shift;

    my $cms   = $self->cms();
	my $dbh   = $self->dbh();
	my $q     = $self->q();	
	my $myurl  = $q->url();
	my $confirmation = $q->param("confirmation")?1:0;

    my $ref    = $q->param('ref') || ""; #TODO: �������� �� �������
	my $answer_id = $q->param('answer_id') || 0;
	return $self->error('�� ������ ��� �������� ������') unless is_valid_id($answer_id);
    
	my $poll_id = $q->param('poll_id') || 0;
	return $self->error('�� ������ ��� �������') unless is_valid_id($poll_id);
	if ($confirmation) {
		
		$dbh->do("update polls set vote_cnt=(vote_cnt - (select vote_cnt from polls_answers where id = ? and polls_id = ?)) where id=? and (multichoice = 0)",undef,$answer_id,$poll_id,$poll_id) or return $self->error("������ �������� �������� ������: ".$DBI::errstr);
		$dbh->do("delete from polls_answers where id = ? and polls_id = ?",undef,$answer_id,$poll_id) or return $self->error("������ �������� �������� ������: ".$DBI::errstr);
		
        my $mObj = $self->getModuleObj();
        $cms->updateKeysVersion($mObj,[
            {key=>'voting', id => $poll_id},
            {key=>'anyvoting'},
        ]);
        
		if ($is_ajax) {
			#TODO: ����������� �������� ��������� ref
			return $self->output("<script type='text/javascript'>parent.ajax_url('$myurl?action=showanswers&poll_id=$poll_id&_ajax=1','formb_$poll_id');</script>"); 
		}
		else {
			return $self->redirect("$myurl?action=showanswers&poll_id=$poll_id&ref=".uri_escape($ref));
		};
	}
	else {
		if ($is_ajax) {
			return $self->output("<script>parent.document.getElementById('deleteform1_".$answer_id."').style.display='';parent.document.getElementById('deleteform2_".$answer_id."').style.display='';</script>");
		}
		else {
			$q->param("delete_answer_id",$answer_id);
			return $self->showOrUpdateAnswers("showanswers",0);
		};
	};
};

sub showOrUpdateAnswers {
	my $self = shift;
	my $action = shift;
    my $is_ajax = shift;	
	
    my $cms   = $self->cms();
	my $dbh   = $cms->dbh();
	my $q     = $cms->q();	
	my $myurl  = $q->url();
	my $method = $q->request_method();
	
	my $delete_answer_id = $q->param("delete_answer_id");
	my $ref    = $q->param('ref') || ""; #TODO: �������� �� �������
	
	my $is_update = 0;
	$is_update = 1 if (($method eq "POST") and ($action eq "updateanswers"));
	
	my $poll_id = $q->param('poll_id') || 0;
	return $self->error('�� ������ ��� �������') unless is_valid_id($poll_id);

	# ��������� ������
    my $sth=$dbh->prepare("select id,question,vote_cnt,multichoice from polls where id=? order by id") or return $self->error($DBI::errstr);
    $sth->execute($poll_id) or return $self->error($DBI::errstr);
    my $poll=$sth->fetchrow_hashref();
    $sth->finish();

	my $newAError = "";
	if (($method eq "POST") and ($action eq "addanswer")) {
		#validation
		my $answer = $q->param("question") || "";
		if (is_empty($answer)) {
			$newAError = "�� ������ ����� �������� ������";
		};
		#my $def=(is_valid_id($q->param('def_$row->{id}')))?1:0;
		my $def=0;
		if ($newAError eq "") {
			my $id = $self->db()->get_id('polls_answers');
			return $self->error($self->db()->errstr()) unless $id;
			$dbh->do("insert into polls_answers (id,polls_id,answer,def,vote_cnt) values (?,?,?,?,?)",undef,$id,$poll_id,$answer,$def,0) or return $self->error("Insert:".$DBI::errstr); ##TODO: ����� ������ ����� � ��������� ����
            
            my $mObj = $self->getModuleObj();
            $cms->updateKeysVersion($mObj,[
                {key=>'voting', id => $poll_id},
                {key=>'anyvoting'},
            ]);
            
			if ($is_ajax) {
				#TODO: ����������� �������� ��������� ref
				#return $self->output("<script type='text/javascript'>parent.ajax_url('$myurl?action=showanswers&poll_id=$poll_id&_ajax=1','formb_$poll_id');</script>");
				return $self->output("<script type='text/javascript'>parent.ajax_url('$myurl?action=showanswers&poll_id=$poll_id&_ajax=1','formb_$poll_id');</script>"); 
			}
			else {
				return $self->redirect("$myurl?action=showanswers&poll_id=$poll_id&ref=".uri_escape($ref));
			};
		}
        elsif ($is_ajax) {
            return $self->output("<script type='text/javascript'>parent.ge('new_answer$poll_id').innerHTML='$newAError';</script>");
        };
	};

	# ��������� ������ ��������� ������
    $sth=$dbh->prepare("select id,polls_id,answer,def,vote_cnt from polls_answers where polls_id=? order by id") or return $self->error($DBI::errstr);
    $sth->execute($poll_id) or return $self->error($DBI::errstr);
    my @answers     = ();
	my @new_answers = ();
	my $has_errors=0;
    while (my $row=$sth->fetchrow_hashref()) {
		$row->{VOTE_PRC} = 0;
        $row->{VOTE_PRC} = sprintf("%.2f",($row->{vote_cnt}*100/$poll->{vote_cnt})) if ($poll->{vote_cnt}>0);
		if ($is_update) {
            my $error="";
			#validation
			my $answer = $q->param("answer_$row->{id}") || "";
			if (is_empty($answer)) {
				$has_errors = 1;
				$error = "�� ������ ����� �������� ������";
			};
			my $def=0;
			if ($poll->{multichoice}) {
				$def = (is_valid_id($q->param("def_$row->{id}")))?1:0;
			}
			else {
				$def = ($q->param("def") && $q->param("def") == $row->{id})?1:0;
			}
			push @new_answers, {
				ID     => $row->{id},
				ANSWER => $answer,
				DEF    => $def,
                ERROR  => $error,
                VOTE_CNT => $row->{vote_cnt},
                VOTE_PRC => $row->{VOTE_PRC},
			};
		};
		$row->{for_delete} = ($delete_answer_id == $row->{id})?1:0;
        push @answers,$row;		
    };
    $sth->finish();
	
	if ($is_update) {
		if ($has_errors==0) {
			foreach my $row (@new_answers) {
				$dbh->do("update polls_answers set answer=?,def=? where id=?",undef,$row->{ANSWER},$row->{DEF},$row->{ID}) or die $DBI::errstr;
			};
            
            my $mObj = $self->getModuleObj();
            $cms->updateKeysVersion($mObj,[
                {key=>'voting', id => $poll_id},
                {key=>'anyvoting'},
            ]);
            
			# ������ ���������� �������� � �������
			if ($is_ajax) {
				#TODO: ����������� �������� ��������� ref
				#return $self->output("<script type='text/javascript'>parent.ajax_url('$myurl?action=showanswers&poll_id=$poll_id&_ajax=1','formb_$poll_id');</script>");
                return $self->output("<script type='text/javascript'>parent.clear_block('formb_$poll_id');</script>");
			}
			else {
                #return $self->redirect("$myurl?action=showanswers&poll_id=$poll_id&ref=".uri_escape($ref));
                return $self->redirect($ref);
			};
		}
		else {
			#���� ���������� ������
			if ($is_ajax) {
				my $ajax_error = "<script type='text/javascript'>";
				foreach my $row (@new_answers) {
					$ajax_error .= "parent.ge('error_name$row->{ID}').innerHTML='$row->{ERROR}';" if ($row->{ERROR});
				};
				$ajax_error .= "</script>";
				return $self->output($ajax_error);
			};
			#���� �� AJAX - �� ����� ������ ��� ������� ������ �����.
            @answers = (@new_answers);
        };
	};

	#������� �����, � �.�. ��������� �� �������	

	$self->opentemplate("admin-side/polls/questions_admin.tmpl") || return $self->showError();
	my $tmpl = $self->template();
	$tmpl->param(
		ANSWERS_LIST => \@answers,
		POLL_ID      => $poll_id,
        QUESTION     => $poll->{question},
		URL          => $myurl,
		IS_AJAX      => $is_ajax,
		REF          => $ref,
        NEW_A_ERROR  => $newAError,
		MULTICHOICE => $poll->{multichoice}
    );
	return $self->output($tmpl->output());
}

sub beforeInsertUpdate {
	my $self = shift;
	my $form = shift;
	my $action = shift;
	
	if ($action eq "update") {
		my $id = $form->getParam("id");
		my ($oldmultichoice) = $self->db()->dbh()->selectrow_array("select multichoice from polls where id=?",undef,$id);
		my ($multichoice) = $form->getParam("multichoice");
		if ($oldmultichoice != $multichoice && !$multichoice) {
			$self->db()->dbh()->do("update polls_answers set def=0 where polls_id=?",undef,$id) or return $self->error($DBI::errstr);
		};
	};
	return NG::Block::M_OK;
};

1;
