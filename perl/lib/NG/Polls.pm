package NG::Polls;
use strict;
use NG::PageModule;
use Date::Simple;
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);
use NSecure;
use NGService;
our @ISA = qw(NG::PageModule);

sub moduleTabs {
    return [
        {HEADER=>"Опросы",URL=>"/"}
    ];
};

sub moduleBlocks {
    return [
        {BLOCK=>"NG::Polls::List" ,URL=>"/"}
    ];
};

sub pollsConfig {
    #Keys:
    # IMAGEFIELDS    - field configuration hash
    # IMAGEFORROTATE - Require image when 'rotate' set
    # DISABLE_HIDERESULT - Disable 'visible' field
    return {};
};

sub fields     { return []; };
sub formfields { return []; };
sub listfields { return []; };


sub voteHandlers {
    return [
        {CANVOTE=>'checkIP_vote',  DELETE=>'checkIP_delete', VOTE=>'checkIP_vote'},
        {CANVOTE=>'checkUID_vote', DELETE=>'checkUID_delete',VOTE=>'checkUID_vote'},
    ];
};

sub checkIP_vote {
    my ($self,$voting,$handler,$ctx) = (shift,shift,shift,shift);
    
    my $dbh  = $self->dbh();
    my $q  = $self->q();
    
    return unless $voting->{check_ip} && $voting->{can_vote};

    my $sth = $dbh->prepare("select count(*) from polls_ip where ip=? and polls_id=?") or return undef;
    $sth->execute($q->remote_addr(),$voting->{id}) or undef;
    my ($count) = $sth->fetchrow();
    $sth->finish();
    $voting->{can_vote} = 0 if $count>0;

#$voting->{can_vote} = 0;

    if ($handler eq 'VOTE' && $voting->{can_vote}) {
        $dbh->do("INSERT INTO polls_ip (polls_id,ip) values(?,?)",undef,$voting->{id},$self->q()->remote_addr()) or NG::DBIException->throw('checkIP_vote() error');
    };
};

sub checkIP_delete {
    my ($self,$voting,$handler,$ctx) = (shift,shift,shift,shift);
    $self->dbh()->do("DELETE FROM polls_ip WHERE polls_id=?",undef,$voting->{id}) or NG::DBIException->throw('checkIP_delete() error');
};

our $UID_COOKIENAME = 'uid';
our $UID_COOKIELIFE = '+3M';
our $UID_KEY        = 'maFaephe9Ezum7j';
our $UID_STATIC_SALT = 'eiLo3ohnoh';

sub checkUID_vote {
    my ($self,$voting,$handler,$ctx) = (shift,shift,shift,shift);
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    my $q   = $cms->q();
    
    return unless $voting->{can_vote};
    
    my ($time,$uid) = (undef,undef); #Составной идентификатор пользователя
    
    #Проверяем наличие куки.
    my $cid = $q->cookie($UID_COOKIENAME);
    if ($ctx->{new} || ($cid && $ctx->{cid} && $ctx->{cid} eq $cid)) {
        $time = $ctx->{time};
        $uid  = $ctx->{uid};
    }
    elsif ($cid && $cid =~ /(\d+)_(\S{8})_(\S{40})/) {
        #кука есть, проверим подпись
        $time = $1;
        $uid  = $2;
        my $hash = $3;
        
        my $myHash = hmac_sha1_hex($time.":".$uid.":".$UID_STATIC_SALT, pack('H*',$UID_KEY));
        
        if ($myHash eq $hash) {
            $ctx->{time} = $time;
            $ctx->{uid}  = $uid;
            $ctx->{cid}  = $cid;
            
            $cms->addCookie(-name=>$UID_COOKIENAME,-value=>$cid, -expires=>$UID_COOKIELIFE);
        }
        else {
            warn "checkUID_canvote(): $hash vs $myHash - mismatch for cookie $cid";
            $uid = undef;
            $time = undef;
        };
    };
    
    if ($time && $uid) {
        if ($handler eq 'VOTE' && $ctx->{new}) {
            $voting->{can_vote_errorCode} = 'missingUUIDCookie';
            $voting->{can_vote} = 0;
            return;
        };
        
        #Найдена валидная кука, ищем наличие голосования по кешу/БД.
        #Ищем в кеше
        my $cache = $cms->getCacheData($self,{key=>'hasvote',uid=>$uid,time=>$time,vote=>$voting->{id}});
        if (defined $cache && $cache) {
            $voting->{can_vote} = 0;
            return;
        };
        unless (defined $cache) {
            #Ищем в БД
            my $sth = $dbh->prepare("select count(*) from polls_uid_votes where polls_id=? and uid = ? and utime=?") or warn $DBI::errstr;
            $sth->execute($voting->{id},$uid,$time) or warn $DBI::errstr;
            my ($count) = $sth->fetchrow();
            $sth->finish();
            if ($count > 0) {
                $cms->setCacheData($self,{key=>'hasvote',uid=>$uid,time=>$time,vote=>$voting->{id}},1,3600);
                $voting->{can_vote} = 0;
                return;
            };
        };
        #Далее can_vote = 1; Можно голосовать.
        if ($handler eq 'VOTE') {
            $cms->setCacheData($self,{key=>'hasvote',uid=>$uid,time=>$time,vote=>$voting->{id}},1,3600);
            $dbh->do("INSERT INTO polls_uid_votes (polls_id,utime,uid,ip,atime) values (?,?,?,?,?)",undef,$voting->{id},$time,$uid,$self->q()->remote_addr(),time()) or NG::DBIException->throw('checkIP_vote() error'); 
        }
        else {
            $cms->setCacheData($self,{key=>'hasvote',uid=>$uid,time=>$time,vote=>$voting->{id}},0,3600) unless defined $cache;
        };
    }
    else {
        if ($handler eq 'VOTE') {
            $voting->{can_vote_errorCode} = 'missingUUIDCookie';
            $voting->{can_vote} = 0;
            return;
        };
        #Generate new.
        $uid = generate_session_id(8);
        $uid = substr( $uid, 0, 8 );
        $time = time();
        
        my $myHash = hmac_sha1_hex($time.":".$uid.":".$UID_STATIC_SALT, pack('H*',$UID_KEY));
        
        my $cid = $time."_".$uid."_".$myHash;
        $cms->addCookie(-name=>$UID_COOKIENAME,-value=>$cid, -expires=>$UID_COOKIELIFE);
        
        $cms->setCacheData($self,{key=>'hasvote',uid=>$uid,time=>$time,vote=>$voting->{id}},0,3600);
        #
        $ctx->{time} = $time;
        $ctx->{uid}  = $uid;
        $ctx->{cid}  = $cid;
        $ctx->{new}  = 1;
    };
};

sub checkUID_delete {
    my ($self,$voting,$handler,$ctx) = (shift,shift,shift,shift);
    $self->dbh()->do("DELETE FROM polls_uid_votes WHERE polls_id=?",undef,$voting->{id}) or NG::DBIException->throw('checkIP_delete() error');
};

#-----------

sub _runHandler {
    my ($self,$voting,$handler,$ctx) = (shift,shift,shift,shift);
    my $VH = $self->voteHandlers($handler);
    
    my $idx = 0;
    foreach my $h (@$VH) {
        $idx++;
        my $m = $h->{$handler} or next;
        $self->$m($voting,$handler,($ctx->[$idx]||={}));
    };
};

sub _get_poll_fields {
    my $self = shift;
    
    my $sql = "p.id,p.question,p.multichoice,p.vote_cnt,p.start_date,p.end_date,p.visible,p.check_ip";
    
    my $imageFields = $self->pollsConfig()->{IMAGEFIELDS};
    if ($imageFields) {
        $imageFields = [$imageFields] unless ref $imageFields eq 'ARRAY';
        foreach my $if (@$imageFields) {
            $sql.=",p.".$if->{FIELD};
        };
    };
    return $sql;
};

sub keys_SQLPOLLSLIST {
    my ($self,$keysParams) = (shift,shift);

    $keysParams or die 'Internal error';
    $keysParams->{sqlWhere} ||= '1=1';
    my $sqlWhere = $keysParams->{sqlWhere};
    
    my $cms = $self->cms();
    
    my $req = {};
    my $ctx = [];
    my $today = Date::Simple->new()->as_iso();
    
    my $items;
    my $versionKeys = [];
    
    my $anyPollVersion = $cms->getKeysVersion($self,{key=>'anyvoting'});
    if ($anyPollVersion && $anyPollVersion->[0]) {  #Кеширование включено
        $items = $cms->getCacheData($self,{where=> $sqlWhere, key=>'items_'.$anyPollVersion->[0], today=>$today});
        unless ($items) {
            my $fields = $self->_get_poll_fields();
            $items = $self->dbh()->selectall_arrayref("SELECT $fields FROM polls p WHERE $sqlWhere ORDER BY p.start_date DESC",{Slice => {}});
            foreach my $item (@$items) {
                $self->_isVotingActive($item,$today);
            };
            $cms->setCacheData($self,{where=>$sqlWhere, key=>'items_'.$anyPollVersion->[0], today=>$today}, $items);
        };
        
        $req->{anyvv} = $anyPollVersion->[0]; #Зависимость от ключа anyvoting
        $req->{today} = $today;
        $req->{showItems} = {};  #Перечень отображаемых элементов
        
        #TODO: Разбивка на страницы. Конфигурация разбивки задается в $keysParams
        
        foreach my $item (@$items) {
            my $voting = {
                id       => $item->{id},
                visible  => $item->{visible},
                check_ip => $item->{check_ip},
                active   => $item->{active},
                can_vote => 1,
            };
            
            $voting->{can_vote} = 0 unless $voting->{active};
            
            $self->_runHandler($voting,'CANVOTE',$ctx) if $voting->{can_vote};
            
            next unless $voting->{can_vote} || $voting->{visible};
            
            $req->{showItems}->{$voting->{id}} = {
                visible  => $voting->{visible},
                can_vote => $voting->{can_vote},
            };
            
            push @$versionKeys, {key=>'votingresult', id => $voting->{id}} if $voting->{visible};
        };
    };
    return {REQUEST=>$req, VERSION_KEYS => $versionKeys, HELPER=>{'polls:items'=> $items, 'polls:keysParams'=> $keysParams}};
};

sub block_SQLPOLLSLIST {
    my ($self,$action,$keys,$params) = (shift,shift,shift,shift);
    
    my $cms = $self->cms();
    my $dbh = $self->dbh();
    my $baseURL = $self->getBaseURL();
    
    my $items = $keys->{HELPER}->{'polls:items'};
    my $sqlWhere = $keys->{HELPER}->{'polls:keysParams'}->{sqlWhere} or die 'Internal error';
    $params->{template} or die 'Internal error: missing template';
    
    unless ($items) {
        my $fields = $self->_get_poll_fields();
        #TODO: Разбивка на страницы
        $items = $dbh->selectall_arrayref("SELECT $fields FROM polls p WHERE $sqlWhere ORDER BY p.start_date DESC",{Slice => {}});
        foreach my $item (@$items) {
            $self->_isVotingActive($item,undef);
        };
    };
    
    my @polls = ();
    my $ctx = [];
    
    foreach my $voting (@$items) {
        if ($keys->{REQUEST}->{showItems}) {
            #Кеш есть...
            next unless exists $keys->{REQUEST}->{showItems}->{$voting->{id}}; #..а элемента нет
        }
        else {
            #Кеша нет
            $voting->{can_vote} = 1;
            $voting->{can_vote} = 0 unless $voting->{active};
            
            $self->_runHandler($voting,'CANVOTE',$ctx) if $voting->{can_vote};
            
            next unless $voting->{can_vote} || $voting->{visible};
        };
        
        $self->_handleVoting($voting);
        $self->_loadAnswers($voting);
        next unless @{$voting->{answers}};
        
        push @polls,$voting;
    };
    
    return $cms->output('') unless @polls;
    
    my $template = $self->gettemplate($params->{template});
    $template->param(
        POLLS   => \@polls,
        BASEURL => $baseURL,
    );
    return $cms->output($template);
}

sub keys_SLIDER {
    my ($self,$action) = (shift,shift);
    return $self->keys_SQLPOLLSLIST({sqlWhere => 'rotate=1 AND (start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW()))'});
};

sub block_SLIDER {
    my ($self,$action,$keys) = (shift,shift,shift);
    
    return $self->block_SQLPOLLSLIST($action,$keys,{template=>"public/polls/slider.tmpl"});
};

sub _isVotingActive {
    my ($self, $voting, $today) = (shift,shift,shift);
    
    die '_isVotingActive: Internal error' unless exists $voting->{start_date};
    my ($sdate,$edate);
    $sdate = Date::Simple->new($voting->{start_date});
    $edate = Date::Simple->new($voting->{end_date}) if $voting->{end_date};
    $today ||= Date::Simple::today();
    $edate ||= $today;
    
    $voting->{active} = ($sdate<=$today && $edate>=$today)?1:0;
}

sub _handleVoting {
    my ($self,$voting) = (shift,shift);
    
    my $db = $self->db();
    
    my $imageFields = $self->pollsConfig()->{IMAGEFIELDS};
    if ($imageFields) {
        $imageFields = [$imageFields] unless ref $imageFields eq 'ARRAY';
        foreach my $if (@$imageFields) {
            $voting->{$if->{FIELD}} = $if->{UPLOADDIR}.$voting->{$if->{FIELD}} if $voting->{$if->{FIELD}};
        };
    };
    
    $voting->{db_start_date} = $voting->{start_date};
    $voting->{db_end_date}   = $voting->{end_date};
    $voting->{start_date}    = $db->date_from_db($voting->{start_date});
    $voting->{end_date}      = $db->date_from_db($voting->{end_date});
    
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
            vote_percent     => !$voting->{vote_cnt}?0:sprintf("%.2f",($_->{vote_cnt}/$voting->{vote_cnt})*100),
            vote_percent_int => !$voting->{vote_cnt}?0:sprintf("%d",  ($_->{vote_cnt}/$voting->{vote_cnt})*100),
        };
    };
};

=comment
sub block_ONMAIN {
    my $self = shift;
    my $cms = $self->cms();
    my $dbh = $self->dbh();
    my $db = $self->db();

    my $random_function = $db->isa('NG::DBI::Mysql')? 'rand' : 'random';

    my ($poll_id) = $dbh->selectrow_array("SELECT id FROM polls WHERE rotate=1 AND (start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW())) ORDER BY ".$random_function."() limit 1",undef);
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
    my $self = shift;
    my $id = shift;

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
                vote_percent     => !$poll->{vote_cnt}?0:sprintf("%.2f",($_->{vote_cnt}/$poll->{vote_cnt})*100),
                vote_percent_int => !$poll->{vote_cnt}?0:sprintf("%d",($_->{vote_cnt}/$poll->{vote_cnt})*100),
            };
        };
        my $sdate = Date::Simple->new($poll->{db_start_date});
        my $edate = Date::Simple::today();
        $edate = Date::Simple->new($poll->{db_end_date}) if $poll->{db_end_date};
        my $today = Date::Simple::today();

        $poll->{active} = ($sdate<=$today && $edate>=$today)?1:0;

        $poll->{canvote} = $poll->{active} eq "0"?0:1;
        if ($poll->{canvote} == 1 && $poll->{check_ip}) {
            my $sth = $dbh->prepare("select count(*) from polls_ip where ip=? and polls_id=?") or return undef;
            $sth->execute($q->remote_addr(),$poll->{id}) or undef;
            my ($count) = $sth->fetchrow();
            $sth->finish();
            $poll->{canvote} = 0 if $count>0;
        };
    }
    else {
        $poll = undef;
    };
    return $poll;
};
=cut


sub processModulePost{
    my $self = shift;
    
    my $q = $self->q();
    my $action = $q->param('action') || '';
    
    return $self->doVote($action) if $q->http('X-Requested-With') && $q->http('X-Requested-With') eq "XMLHttpRequest" && ($action eq 'vote' || $action eq 'voteajax');
    return 1;
};

sub _doVote {
    my $self = shift;
    
    my $q   = $self->q();
    my $dbh = $self->dbh();
    
    my $id = $q->param("id");
    my @answers = $q->param("answer");

    my $ret = {status=>'error'};
    
    unless (is_valid_id($id)) {
        $ret->{errorCode} = 'invalidId';
        return $ret;
    };
    
    my $voting = $dbh->selectrow_hashref("select p.id,p.question,p.multichoice,p.vote_cnt,p.start_date,p.end_date,p.visible,p.check_ip from polls p where p.id=?",undef,$id);
    unless ($voting) {
        $ret->{errorCode} = 'invalidId';
        return $ret;
    };
    $self->_isVotingActive($voting);
    $self->_handleVoting($voting);
    $self->_loadAnswers($voting);
    
    unless (@{$voting->{answers}}) {
        $ret->{errorCode} = 'invalidId';
        return $ret;
    };

    $ret->{status} = 'warning';
    $voting->{can_vote} = 1;
    
    my $allowVisible = 1;
    if (scalar @answers > 1 && !$voting->{multichoice}) {
        $ret->{errorCode} = 'noMultichoice';
        $allowVisible = 0;
    };
    unless (scalar @answers) {
        $ret->{errorCode} = 'noAnswers';
        $allowVisible = 0;
    };
    unless ($voting->{active}) {
        $voting->{can_vote} = 0;
        $ret->{errorCode} = 'inactive';
    };
    
    $ret->{voting} = {
        id          => $voting->{id},
        question    => $voting->{question},
        multichoice => $voting->{multichoice},
        active      => $voting->{active},
        visible     => $voting->{visible},
        can_vote    => $voting->{can_vote},
        start_date  => $voting->{start_date},
        end_date    => $voting->{end_date},
        answers     => [],
    };

    my $v_selected = {};
    unless ($ret->{errorCode}) {
        foreach (@answers) {
            $v_selected->{$_} = 1;
        };
        
        my $vote_found = 0; 
        foreach (@{$voting->{answers}}) {
            $vote_found = 1 if $v_selected->{$_->{id}}
        };
        if ($vote_found) {
            #Будем голосовать?
            $self->_runHandler($voting,'VOTE',[]);
            if ($voting->{can_vote}) {
                $voting->{vote_cnt}++;
            }
            else {
                $ret->{errorCode} = $voting->{can_vote_errorCode} || 'alreadyVoted';
            };
        }
        else {
            $ret->{errorCode} = 'noAnswers';
        };
    };
    
    if ($voting->{visible} && $allowVisible) {
        $ret->{voting}->{vote_cnt} = $voting->{vote_cnt};
    };
    
    my $updSth = $self->db()->dbh()->prepare("update polls_answers set vote_cnt=vote_cnt+1 where id=? and polls_id=?") ;
    foreach (@{$voting->{answers}}) {
        my $answer = {
            id       => $_->{id},
            answer   => $_->{answer},
            def      => $_->{def},
        };
        
        if ($v_selected->{$_->{id}} && !$ret->{errorCode}) {
            #Голосуем!
            $updSth->execute($_->{id},$voting->{id});
            $_->{vote_cnt}++;
        };
        
        if ($voting->{visible} && $allowVisible) {
            $answer->{vote_cnt}        = $_->{vote_cnt};
            $answer->{vote_percent}    = !$voting->{vote_cnt}?0:sprintf("%.2f",($_->{vote_cnt}/$voting->{vote_cnt})*100);
            $answer->{vote_percent_int}= !$voting->{vote_cnt}?0:sprintf("%d",  ($_->{vote_cnt}/$voting->{vote_cnt})*100);
        };
        push @{$ret->{voting}->{answers}}, $answer;
    };
    $updSth->finish();
    
    unless ($ret->{errorCode}) {
        $dbh->do("update polls set vote_cnt=vote_cnt+1 where id=?",undef,$voting->{id}) or die $DBI::errstr;
        $ret->{status} = 'ok';
        $ret->{voting}->{can_vote} = 0;
        
        if ($voting->{visible}) {
            $self->cms->updateKeysVersion($self,[
                {key=>'votingresult', id => $voting->{id}},
            ]);
        };
    };
    return $ret;
};

sub doVote {
    my ($self,$action) = (shift,shift);
    
    my $cms  = $self->cms();
    
    return $cms->outputJSON($self->_doVote()) if $action eq 'voteajax';
    
    my $vret = $self->_doVote();
    my $template = $self->gettemplate("public/polls/sliderItem.tmpl");
    $template->param(%$vret);
    return $cms->outputJSON({
        content   => $template->output(),
        status    => $vret->{status},
        errorCode => $vret->{errorCode},
    });
};

=comment
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
        foreach (@answers) {
            if(is_valid_id($_)) {
                $sth_insert->execute($_,$poll->{id});
                $poll->{vote_cnt} = $poll->{vote_cnt} + 1;
            };
        };
        $sth_insert->finish();
        $self->db()->dbh()->do("update polls set vote_cnt=? where id=?",undef,$poll->{vote_cnt},$poll->{id}) or die $DBI::errstr;
        $self->db()->dbh()->do("insert into polls_ip(polls_id,ip) values(?,?)",undef,$poll->{id},$self->q()->remote_addr()) or die $DBI::errstr; 
    };
    
    return wantarray?($ret,$errors):$ret;
};
=cut

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
    
    my $pollsConfig = $m->pollsConfig();
    my $imageFields = $pollsConfig->{IMAGEFIELDS};
    
    $self->fields(
        {FIELD=>'id',         TYPE=>'id',     NAME=>'Код записи'},
        {FIELD=>'question',   TYPE=>'text',   NAME=>'Текст вопроса', IS_NOTNULL=>1},
        {FIELD=>'start_date', TYPE=>'date',   NAME=>'Дата начала (дд.мм.гггг)',   IS_NOTNULL=>1,DEFAULT=>current_date()},
        {FIELD=>'end_date',   TYPE=>'date',   NAME=>'Дата окончания (дд.мм.гггг)'},
        {FIELD=>'rotate',     TYPE=>'checkbox', NAME=>'Ротировать',IS_NOTNULL=>0},
        {FIELD=>'check_ip',   TYPE=>'checkbox', NAME=>'Проверять IP',         IS_NOTNULL=>0},
        {FIELD=>'multichoice',TYPE=>'checkbox', NAME=>'Несколько вариантов',  IS_NOTNULL=>0},
        {FIELD=>'vote_cnt',   TYPE=>'number', NAME=>'Количество опрошенных',  IS_NOTNULL=>1,READONLY=>1,DEFAULT=>0},
        @$fields
    );
    $self->fields($imageFields) if $imageFields;
    if ($pollsConfig->{DISABLE_HIDERESULT}) {
        $self->fields(
            {FIELD=>'visible',    TYPE=>'hidden',   NAME=>'Показывать результаты', IS_NOTNULL=>0, DEFAULT=>1, HIDE=>1},
        );
    }
    else {
        $self->fields(
            {FIELD=>'visible',    TYPE=>'checkbox', NAME=>'Показывать результаты', IS_NOTNULL=>0},
        );
    };
    
    # Списковая
    $self->listfields(
        {FIELD=>'_counter_',NAME=>"№"},
        {FIELD=>'question',},
        {FIELD=>'start_date',},
        {FIELD=>'end_date',},
        {FIELD=>'rotate', CLICKABLE=>1},
        @$listfields
    );
    # Формовая часть
    $self->formfields(
        {FIELD=>'id'},
        {FIELD=>'question'},
    );
    $self->formfields($imageFields) if $imageFields;
    $self->formfields(
        {FIELD=>'start_date'},
        {FIELD=>'end_date'},
        {FIELD=>'visible'},
        {FIELD=>'rotate'},
        {FIELD=>'check_ip'},
        {FIELD=>'multichoice'},
        @$formfields
    );
    
    $self->filter (
        NAME   => "Фильтр:",
        TYPE   => "tabs",
        VALUES => [
            {NAME=>"Все опросы", WHERE=>""},
            {NAME=>"Ротируемые", WHERE=>"rotate=1 AND (start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW()))"},
        ],
    );
    
    $self->addRowLink({NAME=>'Варианты ответа',URL=>'?action=showanswers&poll_id={id}',AJAX=>1});
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

sub checkData {
    my ($self,$form,$action) = (shift,shift,shift);

    my $m = $self->getModuleObj();
    my $c = $m->pollsConfig();
    
    if ($c->{IMAGEFIELDS} && $c->{IMAGEFORROTATE}) {
        my $if = $c->{IMAGEFIELDS};
        $if = $if->[0] if ref $if eq 'ARRAY';
        
        my $cb = $form->getField('rotate');
        my $im = $form->getField($if->{FIELD});
        
        if ($cb->value() && is_empty($im->value())) {
            $cb->setError("Отсутствует файл изображения");
        };
        #Да, остается вариант "залить файл, выставить признак ротации, а потом удалить файл.
        #На данный момент нет варианта сделать проверку.
    };
    return NG::Block::M_OK;
};


sub beforeDelete {
    my ($self,$id)=(shift,shift);
    
    my $mObj = $self->getModuleObj();
    $mObj->_runHandler({id=>$id},'DELETE',[]);
    $self->dbh()->do("DELETE FROM polls_answers WHERE polls_id=?",undef,$id) or return $self->error("Ошибка удаления вопроса: ".$DBI::errstr);
    return NG::Block::M_OK;
};

sub deleteAnswer {
    my ($self,$action,$is_ajax) = (shift,shift,shift);
    
    my $cms   = $self->cms();
    my $dbh   = $self->dbh();
    my $q     = $self->q();
    my $myurl  = $q->url();
    my $confirmation = $q->param("confirmation")?1:0;
    
    my $ref    = $q->param('ref') || ""; #TODO: заменить на функцию
    my $answer_id = $q->param('answer_id') || 0;
    return $self->error('Не указан код варианта ответа') unless is_valid_id($answer_id);
    
    my $poll_id = $q->param('poll_id') || 0;
    return $self->error('Не указан код вопроса') unless is_valid_id($poll_id);
    if ($confirmation) {
        $dbh->do("update polls set vote_cnt=(vote_cnt - (select vote_cnt from polls_answers where id = ? and polls_id = ?)) where id=? and (multichoice = 0)",undef,$answer_id,$poll_id,$poll_id) or return $self->error("Ошибка удаления варианта ответа: ".$DBI::errstr);
        $dbh->do("delete from polls_answers where id = ? and polls_id = ?",undef,$answer_id,$poll_id) or return $self->error("Ошибка удаления варианта ответа: ".$DBI::errstr);
        
        my $mObj = $self->getModuleObj();
        $cms->updateKeysVersion($mObj,[
            {key=>'voting', id => $poll_id},
            {key=>'anyvoting'},
        ]);

        if ($is_ajax) {
            #TODO: отсутствует передача параметра ref
            return $self->output("<script type='text/javascript'>parent.ajax_url('$myurl?action=showanswers&poll_id=$poll_id&_ajax=1','formb_$poll_id');</script>"); 
        }
        else {
            return $self->redirect("$myurl?action=showanswers&poll_id=$poll_id&ref=".uri_escape($ref));
        };
    }
    else {
        $q->param("delete_answer_id",$answer_id);
        return $self->showOrUpdateAnswers("showanswers",0);
    };
};

sub showOrUpdateAnswers {
    my ($self,$action,$is_ajax) = (shift,shift,shift);
    
    my $cms   = $self->cms();
    my $dbh   = $self->dbh();
    my $q     = $self->q();
    my $myurl  = $q->url();
    my $method = $q->request_method();
    
    my $delete_answer_id = $q->param("delete_answer_id");
    my $ref    = $q->param('ref') || ""; #TODO: заменить на функцию
    
    my $is_update = 0;
    $is_update = 1 if (($method eq "POST") and ($action eq "updateanswers"));
    
    my $poll_id = $q->param('poll_id') || 0;
    return $self->error('Не указан код вопроса') unless is_valid_id($poll_id);

    # Загружаем вопрос
    my $sth=$dbh->prepare("select id,question,vote_cnt,multichoice from polls where id=? order by id") or return $self->error($DBI::errstr);
    $sth->execute($poll_id) or return $self->error($DBI::errstr);
    my $poll=$sth->fetchrow_hashref();
    $sth->finish();

    my $newAError = "";
    if (($method eq "POST") and ($action eq "addanswer")) {
        #validation
        my $answer = $q->param("question") || "";
        if (is_empty($answer)) {
            $newAError = "Не указан текст варианта ответа";
        };
        #my $def=(is_valid_id($q->param('def_$row->{id}')))?1:0;
        my $def=0;
        if ($newAError eq "") {
            my $id = $self->db()->get_id('polls_answers');
            return $self->error($self->db()->errstr()) unless $id;
            $dbh->do("insert into polls_answers (id,polls_id,answer,def,vote_cnt) values (?,?,?,?,?)",undef,$id,$poll_id,$answer,$def,0) or return $self->error("Insert:".$DBI::errstr); ##TODO: вывод ошибки будет в невидимую зону

            my $mObj = $self->getModuleObj();
            $cms->updateKeysVersion($mObj,[
                {key=>'voting', id => $poll_id},
                {key=>'anyvoting'},
            ]);

            if ($is_ajax) {
                #TODO: отсутствует передача параметра ref
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

    # Загружаем список вариантов ответа
    $sth=$dbh->prepare("select id,polls_id,answer,def,vote_cnt from polls_answers where polls_id=? order by id") or return $self->error($DBI::errstr);
    $sth->execute($poll_id) or return $self->error($DBI::errstr);
    my @answers     = ();
    my @new_answers = ();
    my $has_errors=0;
    while (my $row=$sth->fetchrow_hashref()) {
        $row->{vote_prc} = 0;
        $row->{vote_prc} = sprintf("%.2f",($row->{vote_cnt}*100/$poll->{vote_cnt})) if ($poll->{vote_cnt}>0);
        if ($is_update) {
            my $error="";
            #validation
            my $answer = $q->param("answer_$row->{id}") || "";
            if (is_empty($answer)) {
                $has_errors = 1;
                $error = "Не указан текст варианта ответа";
            };
            my $def=0;
            if ($poll->{multichoice}) {
                $def = (is_valid_id($q->param("def_$row->{id}")))?1:0;
            }
            else {
                $def = ($q->param("def") && $q->param("def") == $row->{id})?1:0;
            }
            push @new_answers, {
                id     => $row->{id},
                answer => $answer,
                def    => $def,
                error  => $error,
                vote_cnt => $row->{vote_cnt},
                vote_prc => $row->{vote_prc},
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

            # Делаем правильный редирект и выходим
            if ($is_ajax) {
                #TODO: отсутствует передача параметра ref
                #return $self->output("<script type='text/javascript'>parent.ajax_url('$myurl?action=showanswers&poll_id=$poll_id&_ajax=1','formb_$poll_id');</script>");
                return $self->output("<script type='text/javascript'>parent.clear_block('formb_$poll_id');</script>");
            }
            else {
                #return $self->redirect("$myurl?action=showanswers&poll_id=$poll_id&ref=".uri_escape($ref));
                return $self->redirect($ref);
            };
        }
        else {
            #надо показывать ошибки
            if ($is_ajax) {
                my $ajax_error = "<script type='text/javascript'>";
                foreach my $row (@new_answers) {
                        $ajax_error .= "parent.ge('error_name$row->{ID}').innerHTML='$row->{ERROR}';" if ($row->{ERROR});
                };
                $ajax_error .= "</script>";
                return $self->output($ajax_error);
            };
            #Если не AJAX - то вывод ошибок при обычном выводе формы.
            @answers = (@new_answers);
        };
    };

    #Выводим форму, в т.ч. сообщения об ошибках
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
        multichoice => $poll->{multichoice}
    );
    return $self->output($tmpl->output());
}

sub beforeInsertUpdate {
    my $self = shift;
    my $form = shift;
    my $action = shift;
    
    if ($action eq "update") {
        my $id = $form->getParam("id");
        my ($oldmultichoice) = $self->dbh()->selectrow_array("select multichoice from polls where id=?",undef,$id);
        my ($multichoice) = $form->getParam("multichoice");
        if ($oldmultichoice != $multichoice && !$multichoice) {
            $self->dbh()->do("update polls_answers set def=0 where polls_id=?",undef,$id) or return $self->error($DBI::errstr);
        };
    };
    return NG::Block::M_OK;
};

1;
