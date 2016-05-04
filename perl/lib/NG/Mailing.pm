package NG::Mailing;
use strict;
use base qw(NG::Module);

sub moduleTabs{
	return [
		{HEADER => "Рассылки", URL => "/"},
	];
}

sub moduleBlocks{
	return [
		{URL => "/", BLOCK => "NG::Mailing::List", TYPE => "moduleBlock"},
	]
};

sub createMailing {
    my ($self,$params) = (shift,shift);
    
    #Параметры createMailing()
    #      TYPE        - тип рассылки, опционально. Если тип не задан, берется тип по-умолчанию.
    #  *   MODULE      - ссылка на объект модуля
    # (*)  MODULECODE  - код модуля.    MODULE или MODULECODE - обязательны
    # TODO MAILINGID   - идентификатор рассылки внутри модуля. Могло бы быть полезным
    #                  - для конфигурирующих классов, если рассылок от модуля несколько.
    #  *   CONTENTID   - строка, идентификатор контента. Если контент не был задан
    #                    при создании рассылки, то модуль может его сам запросить
    #                    у модуля, создавшего рассылку
    #  *   SUBJECT      - Заголовок рассылки. До 512 символов
    #      HTMLCONTENT  - HTML-контент рассылки
    #      PLAINCONTENT - TEXT-контент рассылки
    #      RECIPIENTS   - массив получателей. Либо массив емейлов, либо массив хешей:
    #                   - *email, fio (до 150 символов), любые другие ключи (JSON до 1000 символов)
    
    my $moduleCode = $params->{MODULECODE};
    unless ($moduleCode) {
        return NG::Mailing::Mailing->error('No MODULECODE or MODULE') unless $params->{MODULE};
        $moduleCode = $params->{MODULE}->getModuleCode();
        return NG::Mailing::Mailing->error('getModuleCode() не вернул значения') unless $moduleCode;
    };
    
    my $mailing = NG::Mailing::Mailing->_load("module=? AND contentid = ?",$moduleCode,$params->{CONTENTID});
    return $mailing if $mailing;
    
    $params->{TYPE} = 1 unless exists $params->{TYPE};
    
    $mailing = NG::Mailing::Mailing->create({
        subject   => $params->{SUBJECT},
        module    => $moduleCode,
        contentid => $params->{CONTENTID},
        type      => $params->{TYPE},
        htmlcontent  => $params->{HTMLCONTENT},
        plaincontent => $params->{PLAINCONTENT},
    });
    $mailing->saveRecipients($params->{RECIPIENTS}) if $params->{RECIPIENTS};
    return $mailing;
};

sub moduleInterfaces{
    my $self = shift;
    return {
        "NG::Cron::Interface" => $self,
    };
};

sub configCRON{
    return [{
        TASK=>'send',
        METHOD=>"processQueue",
        DESCRIPTION=>"Отправка писем из очереди",
        FREQ_STR=>["* * * * *"],
    }];
};

sub processQueue {
    my $self = shift;
    
    my $mailing = NG::Mailing::Mailing->_load("status=3 ORDER BY date_add LIMIT 1");
    
    unless ($mailing) {
        $mailing = NG::Mailing::Mailing->_load("status=2 AND send_after <= now() ORDER BY date_add LIMIT 1");
        return unless ($mailing);
        $mailing->begin();
        return ; # Мы никуда не торопимся...
    };
    $mailing->deliverSegment();
};

package NG::Mailing::Mailing;
use strict;

use JSON::XS qw(decode_json encode_json);

# Statuses:

# 0 - Ошибка
# 1 - Новая
# 2 - Поставлена в очередь на рассылку
# 3 - Рассылается
# 4 - Приостановлена
# 5 - Ошибка рассылки / операций над рассылкой
# 6 - Ошибка рассылки - нет получателей
# 7 - Отменена
# 8 - Завершена

sub create {
    my ($class,$param) = (shift,shift);
    
    my $mailing = $class->new($param);
    $mailing->save() if $mailing->status() == 1;
    $mailing->updateLetterSize();
    $mailing;
};

sub new {
    my ($class,$param) = (shift,shift);
    
    $param->{status} = 1 unless exists $param->{status};
    
    return $class->error('wrong status')      if $param->{status} < 1 || $param->{status} > 8;
    return $class->error('contentid missing') unless $param->{contentid};
    return $class->error('subject missing')   unless $param->{subject};
    return $class->error('module missing')    unless $param->{module};
    
    return $class->error('contentid is too long') if length($param->{contentid}) >= 50;
    return $class->error('subject is too long')   if length($param->{subject}) >= 512;
    
    return $class->error('error param not supported') if $param->{error};
    
    #Load mailing_type
    $param->{type} = 1 unless exists $param->{type};
    my $mailingType = $class->dbh->selectrow_hashref("SELECT type_id, type_name, subject_prefix, subscribers_module, subscribers_id, segment_size, layout, plain_layout, mailer_group_code, mail_from, test_rcpt_data, lettersize_limit FROM ng_mailing_types WHERE type_id = ?",undef,$param->{type});
    NG::DBIException->throw() if $DBI::errstr;
    return $class->error('mailing_type (id '.$param->{type} . ') not found') unless $mailingType->{type_id};
    
    my $mailing = {};
    bless $mailing, $class;
    
    $mailing->{status} = delete $param->{status};
    $mailing->{_param} = $param;
    $mailing->{_mtype} = $mailingType;
    
    if ($param->{id}) {
        $mailing->{_id} = delete $param->{id};
    }
    else {
        #Новая
        return $class->error('wrong status for new record') if $mailing->{status} != 1;
        $mailing->{_new} = 1;
    };
    
#warn 'Mailing result: '.$param->{error} if $param->{error};
    
    return $mailing;
};

sub error {
    my ($class,$error) = (shift,shift);
warn $error;
    my $mailing = {};
    bless $mailing, $class;
    $mailing->_error($error);
    $mailing;
};

sub _error {
    my ($mailing,$error) = (shift,shift);
    $mailing->{_error} = $error;
    $mailing->{status} = 0;
    $mailing;
};

sub load {
    my ($class,$id) = (shift,shift);
    return $class->_load("id=?",$id);
};

sub _load {
    my ($class,$where) = (shift,shift);
    
    my $mailing = $class->dbh->selectrow_hashref("SELECT id,status,total,progress,module,contentid,subject,type FROM ng_mailing WHERE $where",undef,@_);
    NG::DBIException->throw() if $DBI::errstr;
    return undef unless $mailing->{id};
    return $class->new($mailing);
};

sub save {
    my ($mailing) = (shift);
    
    my $dbh = $mailing->dbh();
    
    if ($mailing->{_new}) {
        $mailing->{_id}= $mailing->db()->get_id('ng_mailing');
        my $param = $mailing->{_param};
        $param->{htmlcontent}  ||= '';
        $param->{plaincontent} ||= '';
        $dbh->do("INSERT INTO ng_mailing "
                ."(id, type, module, contentid, subject, html_content,plain_content)"
                ." VALUES (?,?,?,?,?,?,?)",
                undef,
                $mailing->{_id}, $param->{type}, $param->{module},$param->{contentid},
                $param->{subject},$param->{htmlcontent},$param->{plaincontent}
        );
    }
    else {
        die "Not implemented!";
    };
    return NG::Mailing::Mailing->error($DBI::errstr) if $DBI::errstr;
};

sub status {
    my $self = shift;
    return $self->{status};
};

sub isNew {
    my $self = shift;
    return $self->{_new};
};

sub saveRecipients {
    my ($mailing,$recipients) = (shift,shift);
    
    NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Missing id")    unless $mailing->{_id};
    NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Wrong status")  unless $mailing->{status} == 1 || $mailing->{status} == 2;
    NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Already has recipients") if $mailing->{_param}->{total};
    
    my $dbh = $mailing->dbh();
    my $insSth = $dbh->prepare("INSERT INTO ng_mailing_recipients (mailing_id,segment,email,fio,data) VALUES (?,?,?,?,?)") or NG::DBIException->throw('Error');
    
    my $total = 0;
    my $segment = 1;
    my $n = $mailing->{_mtype}->{segment_size};
    
    NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Wrong mailing type segment_size") unless $n;
    
    my $sub = sub {
        my $rec = shift;
        
        my $ref = ref $rec;
        if ($ref eq 'HASH') {
            NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Email is missing")  unless $rec->{email};
            NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Email is too long") if length($rec->{email}) >= 150;
            NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): FIO is too long")   if $rec->{fio} && length($rec->{fio}) >= 150;
            
            my @data = (delete $rec->{email}, delete $rec->{fio});
            my $databytes = '';
            if (scalar keys %$rec) {
                $databytes = encode_json($rec);
                NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Data too long") if length($databytes) >= 1000;
            };
            $insSth->execute($mailing->{_id},$segment,@data,$databytes) or NG::DBIException->throw('Insert failed');
        }
        elsif ($ref) {
            NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Unsupported recipients type");
        }
        else {
            NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Email is missing")  unless $rec;
            NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Email is too long") if length($rec) >= 150;
            $insSth->execute($mailing->{_id},$segment,$rec,undef,undef) or NG::DBIException->throw('Insert failed');
        };
        
        if(++$total % $n == 0){
            $dbh->commit() or NG::DBIException->throw('Transaction commit error');
            $dbh->begin_work() or NG::DBIException->throw('Transaction start error');
            $segment++;
        };
    };
    
    my $ret = eval {
        $dbh->begin_work() or NG::DBIException->throw('Transaction start error');
        
        if ($recipients) {
            NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Invalid usage") if ref $recipients ne 'ARRAY';
        }
        else {
            if ($mailing->{_mtype}->{subscribers_module}) {
                my $sModule = $mailing->cms->getModuleByCode($mailing->{_mtype}->{subscribers_module});
                NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Subscribers module has no getMailingRecipients()") unless $sModule->can('getMailingRecipients');
                $recipients = $sModule->getMailingRecipients($mailing, $sub);
            }
            else {
                NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Missing mailing initiator module") unless $mailing->{_param}->{module};
                my $initiator  = $mailing->cms->getModuleByCode($mailing->{_param}->{module});
                NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Mailing initiator module has no getMailingRecipients()") unless $initiator->can('getMailingRecipients');
                
                $recipients = $initiator->getMailingRecipients($mailing, $sub);
            };
            return 1 if $total;
            NG::Exception->throw('NG.INTERNALERROR', "Mailing->saveRecipients(): Invalid result from getMailingRecipients()") if ref $recipients ne 'ARRAY';
        };
        
        foreach my $rec (@$recipients) {
            &$sub($rec);
        };
        return 1;
    };
    
    $insSth->finish();
    
    unless ($ret) {
        $dbh->rollback() or NG::DBIException->throw('Transaction rollback error');
        $dbh->do("DELETE FROM ng_mailing_recipients WHERE mailing_id = ?",undef, $mailing->{_id}) or warn $DBI::errstr;
        $dbh->do("UPDATE ng_mailing SET status = 5 WHERE id = ?",undef,$mailing->{_id}) or warn $DBI::errstr;
        $mailing->{status} = 5;
        die $@;
    };
    
    $dbh->commit() or NG::DBIException->throw('Transaction commit error');
    
    unless ($total) {
        $dbh->do("UPDATE ng_mailing SET status = 6 WHERE id = ?",undef,$mailing->{_id}) or warn $DBI::errstr;
        $mailing->{status} = 6;
        return $mailing;
    };
    
    $dbh->do("UPDATE ng_mailing SET total = ? WHERE id = ?",undef,$total,$mailing->{_id}) or warn $DBI::errstr;
    $mailing->{_param}->{total} = $total;
    return $mailing;
};

sub updateLetterSize {
    my ($mailing) = (shift);
    
    my $cms = $mailing->cms();
    my $dbh = $cms->dbh();
    
    my $param = $mailing->{_param};
    my $mtype = $mailing->{_mtype};
    
    my $nmailer = $cms->getModuleByCode('MAILER') or return $cms->error();
    $nmailer->setGroupCode($mtype->{mailer_group_code}) if $mtype->{mailer_group_code};
    
    my $ret = $mailing->_fillNMailer($nmailer, {
        email => 'test.recipient@domain.tld',
        fio   => 'Тестов Тест Тестович',
        data  => $mtype->{test_rcpt_data},
    });
    
    my $letterSize = 0;
    if ($ret) {
        $letterSize = length ($nmailer->_getDataObj()->as_string());
    };
    
    $dbh->do("UPDATE ng_mailing SET lettersize = ? WHERE id = ?",undef,$letterSize,$mailing->{_id}) or warn $DBI::errstr;
    return 1;
};

sub _fillNMailer {
    my ($mailing,$nmailer,$rcpt) = (shift,shift,shift);
    
    my $cms = $mailing->cms();
    my $dbh = $cms->dbh();
    my $param = $mailing->{_param};
    my $mtype = $mailing->{_mtype};
    
    unless (exists $param->{htmlcontent} && exists $param->{plaincontent}) {
        #Загрузим контент
        my $row = $dbh->selectrow_hashref("SELECT html_content,plain_content FROM ng_mailing WHERE id = ?",undef, $mailing->{_id});
        unless ($row && ($row->{html_content} || $row->{plain_content})) {
            $mailing->_terminate({reason=>'Content missing', oldstatus=>3});
            return 0;
        };
        $param->{htmlcontent} = $row->{html_content};
        $param->{plaincontent} = $row->{plain_content};
    };
    
    my $userdata = {};
    if ($mtype->{layout} || $mtype->{plain_layout}) {
        $userdata = decode_json($rcpt->{data}) if $rcpt->{data};
    };
    
    my $mailingHTMLContent;
    if ($mtype->{layout} && $param->{htmlcontent}) {
        my $tmpl = $mtype->{layout};
        my $layout = $cms->gettemplate(undef,{tagstyle=>['tt'],scalarref=>\$tmpl,debug_file=>0});
        $layout->param(
            RCPT     => $rcpt,
            USERDATA => $userdata,
            CONTENT  => $param->{htmlcontent},
        );
        $mailingHTMLContent = $layout->output();
    }
    elsif ($param->{htmlcontent}) {
        $mailingHTMLContent = $param->{htmlcontent};
        $mailingHTMLContent = '<html><body>'.$mailingHTMLContent.'</body></html>';
    };
    
    my $mailingPLAINContent;
    if ($mtype->{plain_layout} && $param->{plaincontent}) {
        my $tmpl = $mtype->{plain_layout};
        my $layout = $cms->gettemplate(undef,{tagstyle=>['tt'],scalarref=>\$tmpl,debug_file=>0});
        $layout->param(
            RCPT     => $rcpt,
            USERDATA => $userdata,
            CONTENT  => $param->{plaincontent},
        );
        $mailingPLAINContent = $layout->output();
    }
    elsif ($param->{plaincontent}) {
        $mailingPLAINContent = $param->{plaincontent};
    };
    
    my $subj = $mailing->{_param}->{subject};
    $subj = $mtype->{subject_prefix}.$subj if $subj && $mtype->{subject_prefix};
    
    $nmailer->add("from",$mtype->{mail_from}) if $mtype->{mail_from};
    $nmailer->add("subject", $subj) if $subj;
    $nmailer->add("to", ($rcpt->{fio}||'').'<'.$rcpt->{email}.'>');
    $nmailer->add("Precedence","bulk");
    $nmailer->add("Auto-Submitted", "auto-generated");
    $nmailer->addHTMLPart(Data=>$mailingHTMLContent, BaseDir=>$cms->getDocRoot()) if $mailingHTMLContent;
    $nmailer->addPlainPart(Data=>$mailingPLAINContent) if $mailingPLAINContent;
    1;
};


sub deliverSegment {
    my ($mailing) = (shift);
    
    NG::Exception->throw('NG.INTERNALERROR', "Mailing->deliverSegment(): Wrong status")  if $mailing->{status} != 3;
    
    #Нашли рассылку в статусе 3 - "Рассылается". Приведем реальность в соответствие статусу.
    my $cms = $mailing->cms();
    my $dbh = $cms->dbh();
    
    my $segmentId = $dbh->selectrow_array("SELECT MIN(segment) FROM ng_mailing_recipients WHERE mailing_id = ?",undef, $mailing->{_id});
    unless ($segmentId) {
        $mailing->_terminate({reason=>'Unable to find next segment', oldstatus=>3});
        return;
    };
    
    my $param = $mailing->{_param};
    my $mtype = $mailing->{_mtype};
    
    
    my $nmailer = $cms->getModuleByCode('MAILER') or return $cms->error();
    $nmailer->setGroupCode($mtype->{mailer_group_code}) if $mtype->{mailer_group_code};
    
#my $i = 0;
#while ($i < 1) {
#    $nmailer->add("from",'noreply@tdsk.tomsk.ru');
#    $nmailer->add("subject",'Test');
#    $nmailer->add("to",'rpv@nikolas.ru');
#    $nmailer->addHTMLPart(Data=>$htmlContent, BaseDir=>$cms->getDocRoot());
#    $nmailer->send('rpv@nikolas.ru');
#    $nmailer->rset();
#    #sleep(1);
#    $i++;
#};
#$nmailer = undef;
#undef($nmailer);

#warn "Go to sleep!";
#sleep(100);
    
    #$nmailer->add("from",'noreply@tdsk.tomsk.ru');
    #$nmailer->add("subject",'Test');
    #$nmailer->add("to",'rpv@nikolas.ru');
    #$nmailer->addHTMLPart(Data=>$htmlContent, BaseDir=>$cms->getDocRoot());
    #$nmailer->send('rpv@nikolas.ru');
    #
    #$nmailer->rset();
    ##sleep(1);
    #
    #$nmailer->add("from",'noreply@tdsk.tomsk.ru');
    #$nmailer->add("subject",'Test');
    #$nmailer->add("to",'rpv@nikolas.ru');
    #$nmailer->addHTMLPart(Data=>$htmlContent, BaseDir=>$cms->getDocRoot());
    #$nmailer->send('rpv@nikolas.ru');
    
#use Data::Dumper;
#warn Dumper($mailing);
    
    #Определили сегмент. Получаем список получателей.
    my $dbc = $dbh->prepare("SELECT email, fio, data FROM ng_mailing_recipients WHERE mailing_id = ? AND segment = ?")  or die $DBI::errstr;
    $dbc->execute($mailing->{_id}, $segmentId) or die $DBI::errstr;
    
    my $i = 0;
    while(my $rcpt = $dbc->fetchrow_hashref()){
        $mailing->_fillNMailer($nmailer,$rcpt);
        $nmailer->send($rcpt->{email});
        $nmailer->rset();
        $i++;
    };
    $dbc->finish();
    
    #Delete segment
    my $ret = $dbh->do("DELETE FROM ng_mailing_recipients WHERE mailing_id = ? AND segment = ?",undef,$mailing->{_id}, $segmentId) or warn $DBI::errstr;
    unless (defined $ret && $ret == $i) {
        $mailing->_terminate({reason=>"Unable to delete processed segment / row count mismatch: processed $ret expected $i", oldstatus=>3});
        return;
    };
    
    #Increment progressbar
    $ret = $dbh->do("UPDATE ng_mailing SET progress = progress + ? WHERE id = ? AND status = 3",undef,$i,$mailing->{_id}) or warn $DBI::errstr;
    unless (defined $ret && $ret == 1) {
        $mailing->_terminate({reason=>'Progress update failed', oldstatus=>3});
        return;
    };
    
    if ($mailing->{_param}->{progress} + $i == $mailing->{_param}->{total}) {
        #Wow!
        $ret = $dbh->do("UPDATE ng_mailing SET status = 8 WHERE id = ? AND status = 3",undef,$mailing->{_id}) or warn $DBI::errstr;
        warn "Mailing ".$mailing->{_id}." finished but status update failed." unless defined $ret && $ret == 1;
    };
};

sub testDeilver {
    my ($mailing,$rcptlist) = (shift,shift);
    
    my $cms = $mailing->cms();
    my $dbh = $cms->dbh();
    
    my $mtype = $mailing->{_mtype};
    
    my $nmailer = $cms->getModuleByCode('MAILER') or return $cms->error();
    $nmailer->setGroupCode($mtype->{mailer_group_code}) if $mtype->{mailer_group_code};
    
    foreach my $rcpt (@$rcptlist) {
        $mailing->_fillNMailer($nmailer, {
            email => $rcpt,
            fio   => $rcpt,
            data  => $mtype->{test_rcpt_data},
        });
        warn $rcpt;
        $nmailer->send($rcpt);
        $nmailer->rset();
    };
    return 1;
};

sub begin {
    my ($mailing) = (shift);
    
    NG::Exception->throw('NG.INTERNALERROR', "Mailing->begin(): Wrong status")  if $mailing->{status} != 2;

    my $ret = eval {
        if ($mailing->{_param}->{total} == 0) {
            $mailing->saveRecipients();
        };
        if ($mailing->{status} == 2) {
            my $ret = $mailing->dbh->do("UPDATE ng_mailing SET status = 3, date_begin = now() WHERE id = ? AND status = 2",undef,$mailing->{_id}) or warn $DBI::errstr;
            $mailing->{status} = 3 if defined $ret && $ret == 1;
        };
        return 1;
    };
    unless ($ret) {
        $mailing->_terminate({reason=>'Begin failed: '.NG::Exception->getText($@), oldstatus=>2});
        die $@;
    };
};

sub _terminate {
    my ($mailing,$reason) = (shift,shift);
    warn "Mailing ".$mailing->{_id}." terminated: ".$reason->{reason};
    
    my $ret = $mailing->dbh->do("UPDATE ng_mailing SET status = 5 WHERE id = ? AND status = ?",undef,$mailing->{_id},$reason->{oldstatus}) or warn $DBI::errstr;
    warn "Mailing ".$mailing->{_id}." terminated, status update failed too." unless defined $ret && $ret == 1;
    $mailing->{status} = 5;
};

sub start {
    my ($mailing) = (shift);
    
    if ($mailing->{status} == 1) {
        my $ret = $mailing->dbh->do("UPDATE ng_mailing SET status = 2 WHERE id = ? AND status = 1",undef,$mailing->{_id}) or warn $DBI::errstr;
        $mailing->{status} = 2 if defined $ret && $ret == 1;
    };
    return $mailing;
};

sub pause {
    my ($mailing) = (shift);
    
    if ($mailing->{status} == 2 || $mailing->{status} == 3) {
        my $ret = $mailing->dbh->do("UPDATE ng_mailing SET status = 4 WHERE id = ? AND (status = 2 OR status = 3)",undef,$mailing->{_id}) or warn $DBI::errstr;
        $mailing->{status} = 4 if defined $ret && $ret == 1;
    };
    return $mailing;
};

sub unpause {
    my ($mailing) = (shift);
    
    if ($mailing->{status} == 4) {
        my $ret = $mailing->dbh->do("UPDATE ng_mailing SET status = 2 WHERE id = ? AND status = 4",undef,$mailing->{_id}) or warn $DBI::errstr;
        $mailing->{status} = 2 if defined $ret && $ret == 1;
    };
    return $mailing;
};

sub cancel {
    my ($mailing) = (shift);
    
    if ($mailing->{status} == 2 || $mailing->{status} == 3 || $mailing->{status} == 4) {
        my $ret = $mailing->dbh()->do("UPDATE ng_mailing SET status = 7 WHERE id = ? AND (status = 2 OR status = 3 OR status = 4)",undef,$mailing->{_id}) or warn $DBI::errstr;
        $mailing->{status} = 7 if defined $ret && $ret == 1;
    };
    $mailing->dbh()->do("DELETE FROM ng_mailing_recipients WHERE mailing_id = ?",undef,$mailing->{_id}) or warn $DBI::errstr;
    return $mailing;
};

sub retry0 { #Специальное действие
    my ($mailing) = (shift);
    
    if ($mailing->{status} == 6 && $mailing->{_param}->{total} == 0) {
        my $ret = $mailing->dbh->do("UPDATE ng_mailing SET status = 2 WHERE id = ? AND status = 6 AND total = 0",undef,$mailing->{_id}) or warn $DBI::errstr;
        $mailing->{status} = 2 if defined $ret && $ret == 1;
    };
    return $mailing;
};

return 1;

=comment

sub getMailingRecipients {
    my ($self,$mailing,$sub) = (shift,shift,shift);

    my $dbc = $self->dbh->prepare("SELECT email,name as fio, hash FROM subscribers WHERE is_active");
    $dbc->execute();
    while($_ = $dbc->fetchrow_hashref()){
        &$sub($_);
    };
    $dbc->finish();
};

=cut
